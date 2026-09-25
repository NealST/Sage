//
//  user_input.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/user_input.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  User input types. `LocalImage` and `LocalAudio` variants use String paths
//  instead of `std::path::PathBuf`. `TextElement` and `ByteRange` are ported
//  faithfully.
//

import Foundation

// MARK: - Constants

public let maxUserInputTextChars = 1 << 20

// MARK: - UserInput

public enum UserInput: Codable, Equatable, Sendable {
    case text(text: String, textElements: [TextElement])
    case image(image: ImageReference, detail: ImageDetail?)
    case localImage(path: String, detail: ImageDetail?)
    case audio(audioUrl: String)
    case localAudio(path: String)
    case skill(name: String, path: String)
    case mention(name: String, path: String)

    private enum TypeKey: String, CodingKey { case type_ = "type" }
    private enum Keys: String, CodingKey {
        case text
        case textElements = "text_elements"
        case detail
        case audioUrl = "audio_url"
        case path, name
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decode(String.self, forKey: .type_)
        let keys = try decoder.container(keyedBy: Keys.self)
        switch type_ {
        case "text":
            self = .text(
                text: try keys.decode(String.self, forKey: .text),
                textElements: try keys.decodeIfPresent([TextElement].self, forKey: .textElements) ?? [])
        case "image":
            let image = try ImageReference(from: decoder)
            let detail = try keys.decodeIfPresent(ImageDetail.self, forKey: .detail)
            self = .image(image: image, detail: detail)
        case "local_image":
            self = .localImage(
                path: try keys.decode(String.self, forKey: .path),
                detail: try keys.decodeIfPresent(ImageDetail.self, forKey: .detail))
        case "audio":
            self = .audio(audioUrl: try keys.decode(String.self, forKey: .audioUrl))
        case "local_audio":
            self = .localAudio(path: try keys.decode(String.self, forKey: .path))
        case "skill":
            self = .skill(
                name: try keys.decode(String.self, forKey: .name),
                path: try keys.decode(String.self, forKey: .path))
        case "mention":
            self = .mention(
                name: try keys.decode(String.self, forKey: .name),
                path: try keys.decode(String.self, forKey: .path))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type_, in: container,
                debugDescription: "Unknown UserInput type: \(type_)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        var keys = encoder.container(keyedBy: Keys.self)
        switch self {
        case .text(let text, let textElements):
            try container.encode("text", forKey: .type_)
            try keys.encode(text, forKey: .text)
            if !textElements.isEmpty {
                try keys.encode(textElements, forKey: .textElements)
            }
        case .image(let image, let detail):
            try container.encode("image", forKey: .type_)
            try image.encode(to: encoder)
            try keys.encodeIfPresent(detail, forKey: .detail)
        case .localImage(let path, let detail):
            try container.encode("local_image", forKey: .type_)
            try keys.encode(path, forKey: .path)
            try keys.encodeIfPresent(detail, forKey: .detail)
        case .audio(let audioUrl):
            try container.encode("audio", forKey: .type_)
            try keys.encode(audioUrl, forKey: .audioUrl)
        case .localAudio(let path):
            try container.encode("local_audio", forKey: .type_)
            try keys.encode(path, forKey: .path)
        case .skill(let name, let path):
            try container.encode("skill", forKey: .type_)
            try keys.encode(name, forKey: .name)
            try keys.encode(path, forKey: .path)
        case .mention(let name, let path):
            try container.encode("mention", forKey: .type_)
            try keys.encode(name, forKey: .name)
            try keys.encode(path, forKey: .path)
        }
    }
}

// MARK: - TextElement

public struct TextElement: Codable, Equatable, Sendable {
    public var byteRange: ByteRange
    public var placeholder: String?

    enum CodingKeys: String, CodingKey {
        case byteRange = "byte_range"
        case placeholder
    }

    public init(byteRange: ByteRange, placeholder: String? = nil) {
        self.byteRange = byteRange; self.placeholder = placeholder
    }

    public func mapRange(_ transform: (ByteRange) -> ByteRange) -> TextElement {
        TextElement(byteRange: transform(byteRange), placeholder: placeholder)
    }

    public mutating func setPlaceholder(_ placeholder: String?) {
        self.placeholder = placeholder
    }

    /// Returns the placeholder text, falling back to slicing the parent text.
    public func placeholder(in text: String) -> String? {
        if let placeholder { return placeholder }
        let utf8 = text.utf8
        guard byteRange.start < utf8.count, byteRange.end <= utf8.count,
              byteRange.start <= byteRange.end,
              let startIdx = utf8.index(utf8.startIndex, offsetBy: byteRange.start, limitedBy: utf8.endIndex),
              let endIdx = utf8.index(utf8.startIndex, offsetBy: byteRange.end, limitedBy: utf8.endIndex)
        else { return nil }
        return String(utf8[startIdx..<endIdx])
    }
}

// MARK: - ByteRange

public struct ByteRange: Codable, Equatable, Sendable {
    public var start: Int
    public var end: Int

    public init(start: Int, end: Int) {
        self.start = start; self.end = end
    }

    public init(from range: Range<Int>) {
        self.start = range.lowerBound; self.end = range.upperBound
    }
}
