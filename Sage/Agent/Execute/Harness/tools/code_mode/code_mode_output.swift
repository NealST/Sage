//
//  code_mode_output.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/code_mode/output.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Header insertion and host-overhead rewrite are faithful. R4a: basename
//  `output.swift` is reserved for tools/output.swift if added later.
//

import CodexProtocol
import Foundation

struct CodeModeToolOutput: ToolOutput, Sendable {
    var output: FunctionToolOutput
    var status: String
    var hostDuration: Duration?

    init(
        output: FunctionToolOutput,
        status: String,
        wallTime: Duration,
        hostDuration: Duration? = nil
    ) {
        var output = output
        let seconds = durationSeconds(wallTime)
        let rounded = (seconds * 10.0).rounded() / 10.0
        output.body.insert(
            .inputText(text: "\(status)\nWall time \(String(format: "%.1f", rounded)) seconds\nOutput:\n"),
            at: 0
        )
        self.output = output
        self.status = status
        self.hostDuration = hostDuration
    }

    func logOutput() -> String { output.logOutput() }
    func successForLogging() -> Bool { output.successForLogging() }
    func toResponseItem(callId: String, payload: ToolPayload) -> ResponseInputItem {
        output.toResponseItem(callId: callId, payload: payload)
    }

    mutating func setHandlerDurationMs(_ handlerDurationMs: UInt64) {
        guard let hostDuration else { return }
        let totalSeconds = Double(handlerDurationMs) / 1_000.0
        let hostSeconds = durationSeconds(hostDuration)
        let overheadSeconds = totalSeconds - hostSeconds
        output.body[0] = .inputText(
            text:
                "\(status)\nWall time \(String(format: "%.3f", totalSeconds)) seconds (code-mode \(String(format: "%.3f", hostSeconds)) seconds; overhead \(String(format: "%.3f", overheadSeconds)) seconds)\nOutput:\n"
        )
    }
}

func durationSeconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) + Double(components.attoseconds) / 1e18
}
