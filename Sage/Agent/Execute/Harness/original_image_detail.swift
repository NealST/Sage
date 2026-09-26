//
//  original_image_detail.swift
//  CodexCore
//
//  Port of codex-rs/core/src/original_image_detail.rs and
//  codex-rs/tools/src/image_detail.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol

public func canRequestOriginalImageDetail(_ modelInfo: ModelInfo) -> Bool {
    modelInfo.supportsImageDetailOriginal
}

public func normalizeOutputImageDetail(
    modelInfo: ModelInfo,
    detail: ImageDetail?
) -> ImageDetail? {
    switch detail {
    case .original where canRequestOriginalImageDetail(modelInfo):
        return .original
    case .original, nil:
        return nil
    case .auto, .low, .high:
        return detail
    }
}

public func sanitizeOriginalImageDetail(
    canRequestOriginalImageDetail: Bool,
    items: inout [FunctionCallOutputContentItem]
) {
    guard !canRequestOriginalImageDetail else { return }
    for index in items.indices {
        if case .inputImage(let image, let detail) = items[index],
           detail == .original
        {
            items[index] = .inputImage(image: image, detail: defaultImageDetail)
        }
    }
}
