//
//  session_rollout_init_error.swift
//  CodexCore
//
//  Port of codex-rs/core/src/session_rollout_init_error.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Rust walks `anyhow::Error` cause chains. Swift takes the leaf error
//  (`ThreadStoreError` or `NSError` POSIX).
//

import CodexProtocol
import CodexThreadStore
import Foundation

public let sessionsSubdirName = "sessions"

public func mapSessionInitError(_ error: any Error, codexHome: String) -> CodexErr {
    if let storeError = error as? ThreadStoreError {
        switch storeError {
        case .unsupported(let operation):
            return .unsupportedOperation("\(operation) is not supported yet")
        case .conflict(let message):
            return .invalidRequest(message)
        case .threadNotFound, .invalidRequest, .internal:
            break
        }
    }
    if let mapped = mapRolloutIoError(error, codexHome: codexHome) {
        return mapped
    }
    return .fatal("Failed to initialize session: \(error)")
}

func mapRolloutIoError(_ error: any Error, codexHome: String) -> CodexErr? {
    let nsError = error as NSError
    guard nsError.domain == NSPOSIXErrorDomain || nsError.domain == NSCocoaErrorDomain else {
        return nil
    }
    let sessionsDir = (codexHome as NSString).appendingPathComponent(sessionsSubdirName)
    let hint: String
    switch nsError.code {
    case Int(EACCES), Int(EPERM), NSFileWriteNoPermissionError, NSFileReadNoPermissionError:
        hint = "Codex cannot access session files at \(sessionsDir) (permission denied). If sessions were created using sudo, fix ownership: sudo chown -R $(whoami) \(codexHome)"
    case Int(ENOENT), NSFileNoSuchFileError:
        hint = "Session storage missing at \(sessionsDir). Create the directory or choose a different Codex home."
    case Int(EEXIST), NSFileWriteFileExistsError:
        hint = "Session storage path \(sessionsDir) is blocked by an existing file. Remove or rename it so Codex can create sessions."
    case NSFileReadCorruptFileError:
        hint = "Session data under \(sessionsDir) looks corrupt or unreadable. Clearing the sessions directory may help (this will remove saved threads)."
    case NSFileReadUnknownError:
        hint = "Session storage path \(sessionsDir) has an unexpected type. Ensure it is a directory Codex can use for session files."
    default:
        return nil
    }
    return .fatal("\(hint) (underlying error: \(error))")
}
