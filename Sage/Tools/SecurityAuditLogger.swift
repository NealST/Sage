//
//  SecurityAuditLogger.swift
//  Sage
//
//  Structured, privacy-preserving security events in the macOS unified log.
//

import Foundation
import OSLog

nonisolated enum SecurityAuditLogger {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.sage.app",
        category: "SecurityAudit"
    )

    static func sandboxLaunch(
        component: String,
        allowsNetwork: Bool,
        protectedMetadataWritable: Bool
    ) {
        logger.notice(
            """
            sandbox_launch component=\(component, privacy: .public) \
            network=\(allowsNetwork, privacy: .public) \
            protected_metadata_write=\(protectedMetadataWritable, privacy: .public)
            """
        )
    }

    static func sandboxDenied(executable: String, exitCode: Int32) {
        logger.warning(
            """
            sandbox_denied executable=\(executable, privacy: .public) \
            exit_code=\(exitCode, privacy: .public)
            """
        )
    }

    static func approval(toolName: String, scope: SessionToolApprovalScope, key: String) {
        logger.notice(
            """
            tool_approval tool=\(toolName, privacy: .public) \
            scope=\(scope.auditLabel, privacy: .public) \
            key_prefix=\(String(key.prefix(12)), privacy: .public)
            """
        )
    }

    static func approvalDenied(toolName: String, key: String) {
        logger.notice(
            """
            tool_approval_denied tool=\(toolName, privacy: .public) \
            key_prefix=\(String(key.prefix(12)), privacy: .public)
            """
        )
    }
}

private extension SessionToolApprovalScope {
    var auditLabel: String {
        switch self {
        case .once:
            return "once"

        case .task:
            return "task"

        case .always:
            return "always"
        }
    }
}
