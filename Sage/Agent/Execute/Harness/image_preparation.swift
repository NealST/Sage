//
//  image_preparation.swift
//  CodexCore
//
//  Port of codex-rs/core/src/image_preparation.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  AttachmentStore is a local protocol (codex_attachment_store waits).
//  AnnotatedContent from context-fragments is inlined as direct
//  ResponseItem walks. Image resize uses CodexUtils loadDataURLForPrompt.
//

import CodexProtocol
import CodexUtils
import Foundation

public let imageProcessingErrorPlaceholder =
    "image content omitted because it could not be processed"
let imageTooLargePlaceholder =
    "image content omitted because it exceeded the supported size limit; use a smaller image"
let unsupportedLowDetailPlaceholder =
    "image content omitted because detail 'low' is not supported; use 'high', 'original', or 'auto'"
let remoteImageURLPlaceholder =
    "image content omitted because remote image URLs are not supported"

public enum ImagePreparationMode: Equatable, Sendable {
    case detailBased
    case unifiedBudget
}

public enum ImageDetailSetting: String, Equatable, Sendable {
    case high
    case original
}

public struct ImagePreparationMetadata: Equatable, Sendable {
    public var messageRole: String?
    public var itemId: String?
    public var effectiveDetail: ImageDetailSetting
    public var sourceWidth: UInt32
    public var sourceHeight: UInt32
    public var preparedWidth: UInt32
    public var preparedHeight: UInt32
}

public enum ImageResizeNoticeMode: Equatable, Sendable {
    case disabled
    case enabled
}

public struct UploadRequest: Sendable {
    public var threadId: String
    public var fileName: String?
    public var data: Data

    public init(threadId: String, fileName: String? = nil, data: Data) {
        self.threadId = threadId
        self.fileName = fileName
        self.data = data
    }
}

public enum UploadResult: Sendable {
    case inline(bytes: Data)
    case file(fileId: String)
}

public protocol AttachmentStore: Sendable {
    func upload(_ request: UploadRequest) async throws -> UploadResult
}

public struct InlineAttachmentStore: AttachmentStore {
    public init() {}

    public func upload(_ request: UploadRequest) async throws -> UploadResult {
        .inline(bytes: request.data)
    }
}

public func unifiedImageBudgetEnabled(featureEnabled: Bool, modelInfo: ModelInfo) -> Bool {
    featureEnabled && (modelInfo.useResponsesLite || canRequestOriginalImageDetail(modelInfo))
}

public enum ImagePreparationError: Error, CustomStringConvertible, Sendable {
    case remoteUrlUnsupported
    case unsupportedLowDetail
    case processing(ImageProcessingError)

    public var description: String {
        switch self {
        case .remoteUrlUnsupported: return "remote image URLs are not supported"
        case .unsupportedLowDetail: return "image detail `low` is not supported"
        case .processing(let error): return error.description
        }
    }

    func placeholder() -> String {
        switch self {
        case .remoteUrlUnsupported: return remoteImageURLPlaceholder
        case .unsupportedLowDetail: return unsupportedLowDetailPlaceholder
        case .processing(.imageTooLarge): return imageTooLargePlaceholder
        case .processing: return imageProcessingErrorPlaceholder
        }
    }
}

struct PreparedImageResize: Equatable {
    var sourceWidth: UInt32
    var sourceHeight: UInt32
    var preparedWidth: UInt32
    var preparedHeight: UInt32
}

public struct PreparedInlineImage: Sendable {
    public var encoded: EncodedImage
    public var effectiveDetail: ImageDetailSetting
    var resize: PreparedImageResize?

    public func intoDataURL() -> String {
        encoded.intoDataURL()
    }
}

public func prepareResponseItems(
    threadId: String,
    items: inout [ResponseItem],
    mode: ImagePreparationMode,
    resizeNoticeMode: ImageResizeNoticeMode,
    imageStore: any AttachmentStore
) async -> [ImagePreparationMetadata] {
    var metadata: [ImagePreparationMetadata] = []
    var prepared: [ResponseItem] = []
    prepared.reserveCapacity(items.count)
    for var item in items {
        var resizeNotice: ImageResizeNotice?
        switch item {
        case .message(_, let role, var content, _, _):
            let resized = await prepareMessageContent(
                &content,
                threadId: threadId,
                messageRole: role,
                resizeNoticeMode: role == "user" ? resizeNoticeMode : .disabled,
                metadata: &metadata,
                mode: mode,
                imageStore: imageStore
            )
            replaceMessageContent(&item, content: content)
            if !resized.isEmpty {
                resizeNotice = ImageResizeNotice(source: .user, images: resized)
            }
        case .functionCallOutput(_, let callId, _, _, var output, _):
            resizeNotice = await prepareToolOutput(
                threadId: threadId,
                output: &output,
                itemId: callId,
                resizeNoticeMode: resizeNoticeMode,
                metadata: &metadata,
                mode: mode,
                imageStore: imageStore
            )
            replaceFunctionOutput(&item, output: output)
        case .customToolCallOutput(_, let callId, _, var output, _):
            resizeNotice = await prepareToolOutput(
                threadId: threadId,
                output: &output,
                itemId: callId,
                resizeNoticeMode: resizeNoticeMode,
                metadata: &metadata,
                mode: mode,
                imageStore: imageStore
            )
            replaceCustomToolOutput(&item, output: output)
        default:
            break
        }
        prepared.append(item)
        if let resizeNotice {
            prepared.append(resizeNotice.asResponseItem())
        }
    }
    items = prepared
    return metadata
}

func prepareToolOutput(
    threadId: String,
    output: inout FunctionCallOutputPayload,
    itemId: String?,
    resizeNoticeMode: ImageResizeNoticeMode,
    metadata: inout [ImagePreparationMetadata],
    mode: ImagePreparationMode,
    imageStore: any AttachmentStore
) async -> ImageResizeNotice? {
    guard case .contentItems(var content) = output.body else { return nil }
    let resized = await prepareToolOutputContent(
        &content,
        threadId: threadId,
        itemId: itemId,
        resizeNoticeMode: resizeNoticeMode,
        metadata: &metadata,
        mode: mode,
        imageStore: imageStore
    )
    output.body = .contentItems(content)
    if resized.isEmpty { return nil }
    return ImageResizeNotice(source: .tool, images: resized)
}

func prepareMessageContent(
    _ items: inout [ContentItem],
    threadId: String,
    messageRole: String,
    resizeNoticeMode: ImageResizeNoticeMode,
    metadata: inout [ImagePreparationMetadata],
    mode: ImagePreparationMode,
    imageStore: any AttachmentStore
) async -> [ResizedImage] {
    let imageCount = items.filter {
        if case .inputImage = $0 { return true }
        return false
    }.count
    var imageNumber = 0
    var resizedImages: [ResizedImage] = []
    for index in items.indices {
        guard case .inputImage(var image, var detail) = items[index] else { continue }
        imageNumber += 1
        do {
            if let resize = try await prepareImage(
                &image, detail: &detail, threadId: threadId, messageRole: messageRole,
                itemId: nil, metadata: &metadata, mode: mode, imageStore: imageStore
            ), resizeNoticeMode == .enabled {
                resizedImages.append(ResizedImage(
                    originalBytes: Int(resize.sourceWidth) * Int(resize.sourceHeight),
                    resizedBytes: Int(resize.preparedWidth) * Int(resize.preparedHeight),
                    width: Int(resize.preparedWidth),
                    height: Int(resize.preparedHeight)
                ))
            }
            items[index] = .inputImage(image: image, detail: detail)
        } catch let error as ImagePreparationError {
            items[index] = .inputText(text: error.placeholder())
        } catch {
            items[index] = .inputText(text: imageProcessingErrorPlaceholder)
        }
        _ = imageNumber
        _ = imageCount
    }
    return resizedImages
}

func prepareToolOutputContent(
    _ items: inout [FunctionCallOutputContentItem],
    threadId: String,
    itemId: String?,
    resizeNoticeMode: ImageResizeNoticeMode,
    metadata: inout [ImagePreparationMetadata],
    mode: ImagePreparationMode,
    imageStore: any AttachmentStore
) async -> [ResizedImage] {
    var resizedImages: [ResizedImage] = []
    for index in items.indices {
        guard case .inputImage(var image, var detail) = items[index] else { continue }
        do {
            if let resize = try await prepareImage(
                &image, detail: &detail, threadId: threadId, messageRole: nil,
                itemId: itemId, metadata: &metadata, mode: mode, imageStore: imageStore
            ), resizeNoticeMode == .enabled {
                resizedImages.append(ResizedImage(
                    originalBytes: Int(resize.sourceWidth) * Int(resize.sourceHeight),
                    resizedBytes: Int(resize.preparedWidth) * Int(resize.preparedHeight),
                    width: Int(resize.preparedWidth),
                    height: Int(resize.preparedHeight)
                ))
            }
            items[index] = .inputImage(image: image, detail: detail)
        } catch let error as ImagePreparationError {
            items[index] = .inputText(text: error.placeholder())
        } catch {
            items[index] = .inputText(text: imageProcessingErrorPlaceholder)
        }
    }
    return resizedImages
}

func isRemoteImageURL(_ imageURL: String) -> Bool {
    guard let scheme = imageURL.split(separator: ":", maxSplits: 1).first else { return false }
    return scheme.lowercased() == "http" || scheme.lowercased() == "https"
}

func isDataURL(_ imageURL: String) -> Bool {
    imageURL.prefix("data:".count).lowercased() == "data:"
}

func prepareImage(
    _ image: inout ImageReference,
    detail: inout ImageDetail?,
    threadId: String,
    messageRole: String?,
    itemId: String?,
    metadata: inout [ImagePreparationMetadata],
    mode: ImagePreparationMode,
    imageStore: any AttachmentStore
) async throws -> PreparedImageResize? {
    guard case .inline(let imageURL) = image else { return nil }
    guard let prepared = try resizeImage(imageURL, detail: &detail, mode: mode) else {
        return nil
    }
    metadata.append(ImagePreparationMetadata(
        messageRole: messageRole,
        itemId: itemId,
        effectiveDetail: prepared.effectiveDetail,
        sourceWidth: prepared.encoded.sourceWidth,
        sourceHeight: prepared.encoded.sourceHeight,
        preparedWidth: prepared.encoded.width,
        preparedHeight: prepared.encoded.height
    ))
    let resize = prepared.resize
    let request = UploadRequest(threadId: threadId, data: prepared.encoded.bytes)
    do {
        switch try await imageStore.upload(request) {
        case .inline(let bytes):
            image = .inline(imageUrl: dataURLFromBytes(mime: prepared.encoded.mime, bytes: bytes))
        case .file(let fileId):
            image = .file(fileId: fileId)
        }
    } catch {
        image = .inline(imageUrl: prepared.intoDataURL())
    }
    return resize
}

public func resizeImage(
    _ imageURL: String,
    detail: inout ImageDetail?,
    mode: ImagePreparationMode
) throws -> PreparedInlineImage? {
    if isRemoteImageURL(imageURL) {
        throw ImagePreparationError.remoteUrlUnsupported
    }
    if !isDataURL(imageURL) {
        return nil
    }
    let effectiveDetail: ImageDetailSetting
    let imageMode: PromptImageMode
    switch mode {
    case .unifiedBudget:
        effectiveDetail = .original
        imageMode = .originalDetail
    case .detailBased:
        switch detail {
        case nil, .auto, .high:
            effectiveDetail = .high
            imageMode = .highDetail
        case .original:
            effectiveDetail = .original
            imageMode = .originalDetail
        case .low:
            throw ImagePreparationError.unsupportedLowDetail
        }
    }
    let encoded = try loadDataURLForPrompt(imageURL: imageURL, mode: imageMode)
    let resize = (encoded.sourceWidth, encoded.sourceHeight) != (encoded.width, encoded.height)
        ? PreparedImageResize(
            sourceWidth: encoded.sourceWidth,
            sourceHeight: encoded.sourceHeight,
            preparedWidth: encoded.width,
            preparedHeight: encoded.height)
        : nil
    if mode == .unifiedBudget {
        detail = .original
    }
    return PreparedInlineImage(encoded: encoded, effectiveDetail: effectiveDetail, resize: resize)
}

func replaceMessageContent(_ item: inout ResponseItem, content: [ContentItem]) {
    if case .message(let id, let role, _, let phase, let meta) = item {
        item = .message(
            id: id, role: role, content: content, phase: phase,
            internalChatMessageMetadataPassthrough: meta)
    }
}

func replaceFunctionOutput(_ item: inout ResponseItem, output: FunctionCallOutputPayload) {
    if case .functionCallOutput(let id, let callId, let name, let namespace, _, let meta) = item {
        item = .functionCallOutput(
            id: id, callId: callId, name: name, namespace: namespace,
            output: output, internalChatMessageMetadataPassthrough: meta)
    }
}

func replaceCustomToolOutput(_ item: inout ResponseItem, output: FunctionCallOutputPayload) {
    if case .customToolCallOutput(let id, let callId, let name, _, let meta) = item {
        item = .customToolCallOutput(
            id: id, callId: callId, name: name, output: output,
            internalChatMessageMetadataPassthrough: meta)
    }
}
