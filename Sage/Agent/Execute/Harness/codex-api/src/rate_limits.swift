//
//  rate_limits.swift
//  CodexAPI
//
//  Port of codex-rs/codex-api/src/rate_limits.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `http::HeaderMap` maps to `[String: String]` (lowercase names).
//  `account::PlanType` maps to `AuthPlanType` on `RateLimitSnapshot`.
//

import CodexProtocol
import Foundation

public struct RateLimitError: Error, Equatable, Sendable, CustomStringConvertible {
    public var message: String

    public init(message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// Parses the default Codex rate-limit header family into a `RateLimitSnapshot`.
public func parseDefaultRateLimit(_ headers: [String: String]) -> RateLimitSnapshot? {
    parseRateLimitForLimit(headers, limitId: nil)
}

/// Parses all known rate-limit header families into update records keyed by limit id.
public func parseAllRateLimits(_ headers: [String: String]) -> [RateLimitSnapshot] {
    var snapshots: [RateLimitSnapshot] = []
    if let snapshot = parseDefaultRateLimit(headers) {
        snapshots.append(snapshot)
    }

    var limitIds = Set<String>()
    for name in headers.keys {
        let headerName = name.lowercased()
        if let limitId = headerNameToLimitId(headerName), limitId != "codex" {
            limitIds.insert(limitId)
        }
    }

    for limitId in limitIds.sorted() {
        guard let snapshot = parseRateLimitForLimit(headers, limitId: limitId),
              hasRateLimitData(snapshot)
        else { continue }
        snapshots.append(snapshot)
    }
    return snapshots
}

/// Parses rate-limit headers for the provided limit id.
///
/// `limitId` should match the server-provided metered limit id (e.g. `codex`,
/// `codex_other`). When omitted, this defaults to the legacy `codex` header family.
public func parseRateLimitForLimit(
    _ headers: [String: String],
    limitId: String?
) -> RateLimitSnapshot? {
    let normalizedLimit = (limitId?.trimmingCharacters(in: .whitespacesAndNewlines))
        .flatMap { $0.isEmpty ? nil : $0 }
        .map { $0.lowercased().replacingOccurrences(of: "_", with: "-") }
        ?? "codex"
    let prefix = "x-\(normalizedLimit)"
    let primary = parseRateLimitWindow(
        headers,
        usedPercentHeader: "\(prefix)-primary-used-percent",
        windowMinutesHeader: "\(prefix)-primary-window-minutes",
        resetsAtHeader: "\(prefix)-primary-reset-at"
    )
    let secondary = parseRateLimitWindow(
        headers,
        usedPercentHeader: "\(prefix)-secondary-used-percent",
        windowMinutesHeader: "\(prefix)-secondary-window-minutes",
        resetsAtHeader: "\(prefix)-secondary-reset-at"
    )
    let normalizedLimitId = normalizeLimitId(normalizedLimit)
    let credits = parseCreditsSnapshot(headers)
    let limitNameHeader = "\(prefix)-limit-name"
    let parsedLimitName = parseHeaderStr(headers, limitNameHeader)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let limitName = (parsedLimitName?.isEmpty == false) ? parsedLimitName : nil

    return RateLimitSnapshot(
        limitId: normalizedLimitId,
        limitName: limitName,
        normalModelSlug: nil,
        primary: primary,
        secondary: secondary,
        credits: credits,
        individualLimit: nil,
        spendControlReached: nil,
        planType: nil,
        rateLimitReachedType: nil
    )
}

private struct RateLimitEventWindow: Decodable {
    var usedPercent: Double
    var windowMinutes: Int64?
    var resetAt: Int64?

    private enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetAt = "reset_at"
    }
}

private struct RateLimitEventDetails: Decodable {
    var primary: RateLimitEventWindow?
    var secondary: RateLimitEventWindow?
}

private struct RateLimitEventCredits: Decodable {
    var hasCredits: Bool
    var unlimited: Bool
    var balance: String?

    private enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited, balance
    }
}

private struct RateLimitEvent: Decodable {
    var kind: String
    var planType: AuthPlanType?
    var rateLimits: RateLimitEventDetails?
    var credits: RateLimitEventCredits?
    var meteredLimitName: String?
    var limitName: String?

    private enum CodingKeys: String, CodingKey {
        case kind = "type"
        case planType = "plan_type"
        case rateLimits = "rate_limits"
        case credits
        case meteredLimitName = "metered_limit_name"
        case limitName = "limit_name"
    }
}

public func parseRateLimitEvent(_ payload: String) -> RateLimitSnapshot? {
    guard let data = payload.data(using: .utf8),
          let event = try? JSONDecoder().decode(RateLimitEvent.self, from: data),
          event.kind == "codex.rate_limits"
    else { return nil }

    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
    if let details = event.rateLimits {
        primary = mapEventWindow(details.primary)
        secondary = mapEventWindow(details.secondary)
    } else {
        primary = nil
        secondary = nil
    }
    let credits = event.credits.map {
        CreditsSnapshot(hasCredits: $0.hasCredits, unlimited: $0.unlimited, balance: $0.balance)
    }
    let limitId = (event.meteredLimitName ?? event.limitName).map(normalizeLimitId)
    return RateLimitSnapshot(
        limitId: limitId ?? "codex",
        limitName: nil,
        normalModelSlug: nil,
        primary: primary,
        secondary: secondary,
        credits: credits,
        individualLimit: nil,
        spendControlReached: nil,
        planType: event.planType,
        rateLimitReachedType: nil
    )
}

private func mapEventWindow(_ window: RateLimitEventWindow?) -> RateLimitWindow? {
    guard let window else { return nil }
    return RateLimitWindow(
        usedPercent: window.usedPercent,
        windowMinutes: window.windowMinutes,
        resetsAt: window.resetAt
    )
}

/// Parses the bespoke Codex promo-message header.
public func parsePromoMessage(_ headers: [String: String]) -> String? {
    parseHeaderStr(headers, "x-codex-promo-message")?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .nilIfEmpty
}

func parseRateLimitReachedType(_ headers: [String: String]) -> RateLimitReachedType? {
    guard let raw = parseHeaderStr(headers, "x-codex-rate-limit-reached-type")?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    else { return nil }
    return RateLimitReachedType(rawValue: raw)
}

func parseRateLimitWindow(
    _ headers: [String: String],
    usedPercentHeader: String,
    windowMinutesHeader: String,
    resetsAtHeader: String
) -> RateLimitWindow? {
    guard let usedPercent = parseHeaderF64(headers, usedPercentHeader) else {
        return nil
    }
    let windowMinutes = parseHeaderI64(headers, windowMinutesHeader)
    let resetsAt = parseHeaderI64(headers, resetsAtHeader)
    let hasData = usedPercent != 0.0
        || (windowMinutes.map { $0 != 0 } ?? false)
        || resetsAt != nil
    guard hasData else { return nil }
    return RateLimitWindow(
        usedPercent: usedPercent,
        windowMinutes: windowMinutes,
        resetsAt: resetsAt
    )
}

func parseCreditsSnapshot(_ headers: [String: String]) -> CreditsSnapshot? {
    guard let hasCredits = parseHeaderBool(headers, "x-codex-credits-has-credits"),
          let unlimited = parseHeaderBool(headers, "x-codex-credits-unlimited")
    else { return nil }
    let balance = parseHeaderStr(headers, "x-codex-credits-balance")?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .nilIfEmpty
    return CreditsSnapshot(hasCredits: hasCredits, unlimited: unlimited, balance: balance)
}

func parseHeaderF64(_ headers: [String: String], _ name: String) -> Double? {
    guard let raw = parseHeaderStr(headers, name),
          let value = Double(raw),
          value.isFinite
    else { return nil }
    return value
}

func parseHeaderI64(_ headers: [String: String], _ name: String) -> Int64? {
    guard let raw = parseHeaderStr(headers, name) else { return nil }
    return Int64(raw)
}

func parseHeaderBool(_ headers: [String: String], _ name: String) -> Bool? {
    guard let raw = parseHeaderStr(headers, name) else { return nil }
    if raw.caseInsensitiveCompare("true") == .orderedSame || raw == "1" {
        return true
    }
    if raw.caseInsensitiveCompare("false") == .orderedSame || raw == "0" {
        return false
    }
    return nil
}

func parseHeaderStr(_ headers: [String: String], _ name: String) -> String? {
    let needle = name.lowercased()
    if let value = headers[needle] {
        return value
    }
    return headers.first { $0.key.lowercased() == needle }?.value
}

func hasRateLimitData(_ snapshot: RateLimitSnapshot) -> Bool {
    snapshot.primary != nil || snapshot.secondary != nil || snapshot.credits != nil
}

func headerNameToLimitId(_ headerName: String) -> String? {
    let suffix = "-primary-used-percent"
    guard headerName.hasSuffix(suffix) else { return nil }
    let prefix = String(headerName.dropLast(suffix.count))
    guard prefix.hasPrefix("x-") else { return nil }
    return normalizeLimitId(String(prefix.dropFirst(2)))
}

func normalizeLimitId(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "-", with: "_")
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
