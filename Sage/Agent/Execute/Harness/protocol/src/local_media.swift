//
//  local_media.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/local_media.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Snapshots local image and audio input into portable, validated data URLs.
//  `std::path::Path` maps to String paths; `io::Result` maps to `throws` with
//  CodexUtils' `IOError`. Image loading/encoding comes from CodexUtils
//  (`utils/image`), which the protocol crate links upstream.
//

import CodexUtils
import Foundation

/// Maximum accepted decoded byte length for prompt audio inputs.
///
/// This matches the Responses API audio input limit.
public let maxPromptAudioInputBytes = 50 * 1024 * 1024

/// `snapshot_local_user_input` — snapshots local image and audio input into
/// portable, validated data URLs.
public func snapshotLocalUserInput(_ input: inout UserInput) throws {
    switch input {
    case .localImage(let path, let detail):
        let mode: PromptImageMode
        switch detail {
        case .original:
            mode = .original
        case .auto, .low, .high, nil:
            mode = .resizeToFit
        }
        let fileBytes = try readBoundedLocalMedia(
            path: path, maxBytes: maxPromptImageInputBytes, kind: "image")
        let image: EncodedImage
        do {
            image = try loadForPromptBytes(path: path, fileBytes: fileBytes, mode: mode)
        } catch {
            // `io::Error::other`
            throw IOError(kind: .other, "\(error)")
        }
        input = .image(
            image: .inline(imageUrl: image.intoDataURL()),
            detail: detail
        )
    case .localAudio(let path):
        guard let mime = audioMimeForPath(path: path) else {
            throw IOError.invalidData("unsupported audio format")
        }
        let fileBytes = try readBoundedLocalMedia(
            path: path, maxBytes: maxPromptAudioInputBytes, kind: "audio")
        input = .audio(audioUrl: dataURLFromBytes(mime: mime, bytes: fileBytes))
    case .text, .image, .audio, .skill, .mention:
        break
    }
}

private func readBoundedLocalMedia(path: String, maxBytes: Int, kind: String) throws -> Data {
    let url = URL(fileURLWithPath: path)
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    if let size = attributes[.size] as? UInt64, size > UInt64(maxBytes) {
        throw IOError.invalidData("\(kind) input exceeds \(maxBytes) bytes")
    }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let bytes = handle.readData(ofLength: maxBytes + 1)
    if bytes.count > maxBytes {
        throw IOError.invalidData("\(kind) input exceeds \(maxBytes) bytes")
    }
    return bytes
}

/// `audio_mime_for_path` (`pub(crate)` upstream).
func audioMimeForPath(path: String) -> String? {
    let ext = URL(fileURLWithPath: path).pathExtension
    guard !ext.isEmpty else { return nil }
    if ext.caseInsensitiveCompare("wav") == .orderedSame { return "audio/wav" }
    if ext.caseInsensitiveCompare("mp3") == .orderedSame { return "audio/mpeg" }
    if ext.caseInsensitiveCompare("m4a") == .orderedSame { return "audio/mp4" }
    if ext.caseInsensitiveCompare("webm") == .orderedSame { return "audio/webm" }
    if ext.caseInsensitiveCompare("ogg") == .orderedSame { return "audio/ogg" }
    return nil
}
