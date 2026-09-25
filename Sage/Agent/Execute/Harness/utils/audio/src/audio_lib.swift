//
//  audio_lib.swift
//  CodexUtils
//
//  Port of codex-rs/utils/audio/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Audio preparation and duration-based token estimates for model inputs.
//  Upstream uses `symphonia` for codec probing and duration extraction. Sage
//  uses AVFoundation's `AVAudioFile` / `AVURLAsset` for the same purpose.
//  The data-URL parsing, canonicalization, and placeholder logic are faithful;
//  the audio decoding path is macOS-native.
//
//  R4a: upstream `lib.rs` → `audio_lib.swift` (basename dedup).
//

import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif
import CryptoKit

// MARK: - Constants

private let audioProcessingErrorPlaceholder =
    "audio content omitted because it could not be processed"
private let audioTooLargePlaceholder =
    "audio content omitted because it exceeded the supported size limit; use a smaller audio file"
private let unsupportedAudioFormatPlaceholder =
    "audio content omitted because its format is not supported; use wav, mp3, m4a, webm, or ogg"

/// Maximum accepted decoded byte length for prompt audio inputs.
public let maxPromptAudioInputBytes = 50 * 1024 * 1024
private let maxPromptAudioBase64Bytes = (maxPromptAudioInputBytes + 2) / 3 * 4
private let audioTokenEstimateCacheSize = 32
private let audioTokensPerSecond: Double = 10.0

// MARK: - Error types

private enum AudioPreparationError: Error {
    case invalidDataUrl(reason: String)
    case unsupportedFormat
    case audioTooLarge(size: Int)

    var placeholder: String {
        switch self {
        case .invalidDataUrl: audioProcessingErrorPlaceholder
        case .unsupportedFormat: unsupportedAudioFormatPlaceholder
        case .audioTooLarge: audioTooLargePlaceholder
        }
    }
}

// MARK: - MIME canonicalization

private func isDataURL(_ audioURL: String) -> Bool {
    audioURL.prefix("data:".count).lowercased() == "data:"
}

func canonicalAudioMime(_ mime: String) -> String? {
    let lower = mime.lowercased()
    switch lower {
    case "audio/wav", "audio/x-wav", "audio/wave", "audio/vnd.wave":
        return "audio/wav"
    case "audio/mpeg", "audio/mp3":
        return "audio/mpeg"
    case "audio/mp4", "audio/m4a", "audio/x-m4a":
        return "audio/mp4"
    case "audio/webm":
        return "audio/webm"
    case "audio/ogg":
        return "audio/ogg"
    default:
        return nil
    }
}

// MARK: - Token estimation cache

private let tokenEstimateCacheLock = NSLock()
private var tokenEstimateCache: [(key: Data, value: Int)] = []

/// Estimates audio tokens from decoded duration, falling back to the data URL size.
public func estimateAudioTokenCount(_ audioURL: String) -> Int {
    let key = Data(Insecure.SHA1.hash(data: Data(audioURL.utf8)))

    tokenEstimateCacheLock.lock()
    if let cached = tokenEstimateCache.first(where: { $0.key == key }) {
        tokenEstimateCacheLock.unlock()
        return cached.value
    }
    tokenEstimateCacheLock.unlock()

    let result: Int
    if let duration = audioDurationSeconds(audioURL) {
        let tokenCount = (duration * audioTokensPerSecond).rounded(.up)
        result = tokenCount >= Double(Int.max) ? Int.max : Int(tokenCount)
    } else {
        result = approxTokenCount(audioURL)
    }

    tokenEstimateCacheLock.lock()
    tokenEstimateCache.append((key: key, value: result))
    if tokenEstimateCache.count > audioTokenEstimateCacheSize {
        tokenEstimateCache.removeFirst()
    }
    tokenEstimateCacheLock.unlock()

    return result
}

private func audioDurationSeconds(_ audioURL: String) -> Double? {
    guard let commaIndex = audioURL.firstIndex(of: ",") else { return nil }
    let prefix = audioURL[audioURL.startIndex..<commaIndex]
    guard prefix.lowercased().hasPrefix("data:") else { return nil }
    let metadata = prefix.dropFirst("data:".count)
    let parts = metadata.split(separator: ";")
    guard let mimePart = parts.first,
          let _ = canonicalAudioMime(String(mimePart)),
          parts.contains(where: { $0.lowercased() == "base64" })
    else { return nil }

    let payload = audioURL[audioURL.index(after: commaIndex)...]
    guard let bytes = Data(base64Encoded: String(payload)), !bytes.isEmpty else { return nil }

    #if canImport(AVFoundation)
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("tmp")
    do {
        try bytes.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let audioFile = try? AVAudioFile(forReading: tempURL)
        guard let audioFile else { return nil }
        let sampleRate = audioFile.processingFormat.sampleRate
        guard sampleRate > 0 else { return nil }
        let duration = Double(audioFile.length) / sampleRate
        return duration.isFinite ? duration : nil
    } catch {
        return nil
    }
    #else
    return nil
    #endif
}

// MARK: - Audio MIME for path

/// Returns the canonical audio MIME type for a file extension.
public func audioMimeForPath(_ path: String) -> String? {
    let ext = (path as NSString).pathExtension.lowercased()
    switch ext {
    case "wav": return "audio/wav"
    case "mp3": return "audio/mpeg"
    case "m4a": return "audio/mp4"
    case "webm": return "audio/webm"
    case "ogg": return "audio/ogg"
    default: return nil
    }
}
