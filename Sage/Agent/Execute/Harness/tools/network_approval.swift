//
//  network_approval.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/network_approval.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  A blocked request is recorded, then either denied outright or turned
//  into one escalation approval. Already-allowed network does not ask.
//

import Foundation

enum NetworkApproval {
    struct BlockedRequest: Equatable {
        var host: String?
        var output: String
    }

    private static var blocked: [BlockedRequest] = []

    static func recordBlocked(_ request: BlockedRequest) {
        blocked.append(request)
    }

    static func takeBlocked() -> [BlockedRequest] {
        let copy = blocked
        blocked.removeAll()
        return copy
    }

    /// Codex `begin_network_approval` returns nothing when managed network
    /// is off. Seatbelt is that managed network on Mac.
    static func begin(networkManaged: Bool, spec: NetworkProxySpec) -> NetworkProxySpec? {
        guard networkManaged, spec.enabled else { return nil }
        return spec
    }

    static func retryReason(
        sandboxOutput: String,
        bits: SandboxPermissionBits = [],
        spec: NetworkProxySpec = .seatbelt
    ) -> String {
        let decision = spec.decide(
            output: sandboxOutput,
            networkAlreadyAllowed: bits.contains(.network)
        )
        switch decision {
        case .allow:
            return "command failed; retry without sandbox?"

        case .deny(let host):
            recordBlocked(BlockedRequest(host: host, output: sandboxOutput))
            if let host {
                return "Network access to \"\(host)\" is blocked by policy."
            }
            return "Network access is blocked by policy."

        case .ask(let host):
            recordBlocked(BlockedRequest(host: host, output: sandboxOutput))
            if let host {
                return "Network access to \"\(host)\" is blocked by policy."
            }
            if sandboxOutput.lowercased().contains("network") {
                return "Network access is blocked by policy."
            }
            return "command failed; retry without sandbox?"
        }
    }
}
