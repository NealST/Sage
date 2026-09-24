//
//  io_error.swift
//  CodexUtils
//
//  Sage addition (no codex counterpart).
//
//  Stands in for `std::io::Error`: Rust harness APIs return `io::Result`;
//  Swift maps that to `throws` with this error type carrying the matching
//  `ErrorKind`.
//

import Foundation

public struct IOError: Error, Equatable, CustomStringConvertible {
    /// `std::io::ErrorKind` (subset; extend as ports need more kinds).
    public enum Kind: String, Equatable, Sendable {
        case notFound = "NotFound"
        case invalidInput = "InvalidInput"
        case permissionDenied = "PermissionDenied"
        case other = "Other"
    }

    public let kind: Kind
    public let message: String

    public init(kind: Kind, _ message: String) {
        self.kind = kind
        self.message = message
    }

    public static func invalidInput(_ message: String) -> IOError {
        IOError(kind: .invalidInput, message)
    }

    public static func notFound(_ message: String) -> IOError {
        IOError(kind: .notFound, message)
    }

    /// Map an errno value to the matching `ErrorKind`.
    public static func fromErrno(_ errno: Int32, context: String) -> IOError {
        switch errno {
        case ENOENT:
            return .notFound(context)
        case EACCES, EPERM:
            return IOError(kind: .permissionDenied, context)
        default:
            return IOError(kind: .other, "\(context) (errno \(errno))")
        }
    }

    /// `std::io::Error`'s `Display` is the wrapped error/message text (the
    /// kind is not printed), so `description` is just the message.
    public var description: String {
        message
    }
}
