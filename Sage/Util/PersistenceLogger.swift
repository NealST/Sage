//
//  PersistenceLogger.swift
//  Sage
//
//  Unified-log channel for silent-by-design persistence paths. These writes
//  must not fail a user-visible turn, but they must not vanish either —
//  Console.app is the diagnostic trail for "why did my data not survive".
//

import Foundation
import OSLog

nonisolated enum PersistenceLogger {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.sage.app",
        category: "Persistence"
    )

    static func warn(_ context: String, error: Error) {
        logger.warning(
            "\(context, privacy: .public) error=\(String(describing: error), privacy: .public)"
        )
    }

    static func notice(_ context: String) {
        logger.notice("\(context, privacy: .public)")
    }
}
