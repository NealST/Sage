//
//  images.swift
//  CodexAPI
//
//  Port of codex-rs/codex-api/src/images.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Image generation / edit request and response DTOs.
//

import CodexProtocol
import Foundation

public struct ImageGenerationRequest: Equatable, Sendable {
    public var prompt: String
    public var background: ImageBackground?
    public var model: String
    public var n: UInt64?
    public var quality: ImageQuality?
    public var size: String?

    public init(
        prompt: String,
        background: ImageBackground? = nil,
        model: String,
        n: UInt64? = nil,
        quality: ImageQuality? = nil,
        size: String? = nil
    ) {
        self.prompt = prompt
        self.background = background
        self.model = model
        self.n = n
        self.quality = quality
        self.size = size
    }
}

extension ImageGenerationRequest: Encodable {
    private enum CodingKeys: String, CodingKey {
        case prompt, background, model, n, quality, size
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(prompt, forKey: .prompt)
        try container.encodeIfPresent(background, forKey: .background)
        try container.encode(model, forKey: .model)
        try container.encodeIfPresent(n, forKey: .n)
        try container.encodeIfPresent(quality, forKey: .quality)
        try container.encodeIfPresent(size, forKey: .size)
    }
}

public struct ImageEditRequest: Equatable, Sendable {
    public var images: [ImageReference]
    public var prompt: String
    public var background: ImageBackground?
    public var model: String
    public var n: UInt64?
    public var quality: ImageQuality?
    public var size: String?

    public init(
        images: [ImageReference],
        prompt: String,
        background: ImageBackground? = nil,
        model: String,
        n: UInt64? = nil,
        quality: ImageQuality? = nil,
        size: String? = nil
    ) {
        self.images = images
        self.prompt = prompt
        self.background = background
        self.model = model
        self.n = n
        self.quality = quality
        self.size = size
    }
}

extension ImageEditRequest: Encodable {
    private enum CodingKeys: String, CodingKey {
        case images, prompt, background, model, n, quality, size
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(images, forKey: .images)
        try container.encode(prompt, forKey: .prompt)
        try container.encodeIfPresent(background, forKey: .background)
        try container.encode(model, forKey: .model)
        try container.encodeIfPresent(n, forKey: .n)
        try container.encodeIfPresent(quality, forKey: .quality)
        try container.encodeIfPresent(size, forKey: .size)
    }
}

public enum ImageBackground: String, Codable, Equatable, Sendable {
    case transparent
    case opaque
    case auto
}

public enum ImageQuality: String, Codable, Equatable, Sendable {
    case low
    case medium
    case high
    case auto
}

public struct ImageResponse: Equatable, Sendable {
    public var created: UInt64
    public var data: [ImageData]
    public var background: ImageBackground?
    public var quality: ImageQuality?
    public var size: String?

    public init(
        created: UInt64,
        data: [ImageData],
        background: ImageBackground? = nil,
        quality: ImageQuality? = nil,
        size: String? = nil
    ) {
        self.created = created
        self.data = data
        self.background = background
        self.quality = quality
        self.size = size
    }
}

extension ImageResponse: Decodable {
    private enum CodingKeys: String, CodingKey {
        case created, data, background, quality, size
    }
}

public struct ImageData: Equatable, Sendable {
    public var b64Json: String
    public var generationId: String?

    public init(b64Json: String, generationId: String? = nil) {
        self.b64Json = b64Json
        self.generationId = generationId
    }
}

extension ImageData: Decodable {
    private enum CodingKeys: String, CodingKey {
        case b64Json = "b64_json"
        case generationId = "generation_id"
    }
}
