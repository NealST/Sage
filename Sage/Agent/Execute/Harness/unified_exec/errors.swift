//
//  errors.swift
//  Sage
//
//  Port of codex-rs/core/src/unified_exec/errors.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `StdinApproval` wraps a string until tools/sandboxing ToolError is ported.
//

import CodexProtocol
import CodexUtils
import Foundation

enum UnifiedExecError: Error, CustomStringConvertible {
    case createProcess(message: String)
    case processFailed(message: String)
    case unknownProcessId(processId: Int32)
    case stdinApproval(String)
    case writeToStdin
    case stdinClosed
    case missingCommandLine
    case sandboxDenied(
        message: String,
        output: ExecToolCallOutput,
        originalTokenCount: Int?,
        outputOmittedBytes: Int?
    )
    case foreignPath(path: PathUri)

    var description: String {
        switch self {
        case .createProcess(let message):
            return "Failed to create unified exec process: \(message)"
        case .processFailed(let message):
            return "Unified exec process failed: \(message)"
        case .unknownProcessId(let processId):
            return "Unknown process id \(processId)"
        case .stdinApproval(let message):
            return "stdin approval failed: \(message)"
        case .writeToStdin:
            return "failed to write to stdin"
        case .stdinClosed:
            return "stdin is closed for this session; rerun exec_command with tty=true to keep stdin open"
        case .missingCommandLine:
            return "missing command line for unified exec request"
        case .sandboxDenied(let message, _, _, _):
            return "Command denied by sandbox: \(message)"
        case .foreignPath(let path):
            return "\(path) is not valid on macOS"
        }
    }

    static func createProcess(_ message: String) -> UnifiedExecError {
        .createProcess(message: message)
    }

    static func processFailed(_ message: String) -> UnifiedExecError {
        .processFailed(message: message)
    }

    static func sandboxDenied(_ message: String, output: ExecToolCallOutput) -> UnifiedExecError {
        .sandboxDenied(
            message: message,
            output: output,
            originalTokenCount: nil,
            outputOmittedBytes: nil
        )
    }

    func withOutputCollectionMetadata(
        originalTokenCount: Int,
        outputOmittedBytes: Int?
    ) -> UnifiedExecError {
        switch self {
        case .sandboxDenied(let message, let output, _, _):
            return .sandboxDenied(
                message: message,
                output: output,
                originalTokenCount: originalTokenCount,
                outputOmittedBytes: outputOmittedBytes
            )
        default:
            return self
        }
    }
}
