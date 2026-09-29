//
//  metrics_mod.swift
//  CodexOtel
//
//  Port of codex-rs/otel/src/metrics/mod.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  R4a: basename collides with events/mod.swift. OnceLock →
//  OSAllocatedUnfairLock. Global install/redirect is faithful.
//

import Foundation
import os

private let globalMetrics = OSAllocatedUnfairLock<MetricsClient?>(initialState: nil)
private let globalStatsigSettingsLock = OSAllocatedUnfairLock<StatsigMetricsSettings?>(initialState: nil)
private let globalActiveSlot = OSAllocatedUnfairLock<MetricsClientInner?>(initialState: nil)

func installGlobal(_ metrics: MetricsClient) -> MetricsClient {
    let slotInner = globalActiveSlot.withLock { current -> MetricsClientInner in
        if let current { return current }
        current = metrics.inner
        return metrics.inner
    }
    let slot = OSAllocatedUnfairLock(initialState: slotInner)
    slot.withLock { $0 = metrics.inner }
    let installed = metrics.withActiveSlot(slot)
    globalMetrics.withLock { current in
        if current == nil {
            current = installed
        }
    }
    bufferedMetricsGlobal.enable(installed)
    return installed
}

public func globalMetricsClient() -> MetricsClient? {
    globalMetrics.withLock { $0 }
}

func installGlobalStatsigSettings(_ settings: StatsigMetricsSettings) {
    globalStatsigSettingsLock.withLock { current in
        if current == nil {
            current = settings
        }
    }
}

func globalStatsigSettings() -> StatsigMetricsSettings? {
    if globalMetrics.withLock({ $0?.activeInner().networkPolicyIsManaged == true }) {
        return nil
    }
    return globalStatsigSettingsLock.withLock { $0 }
}
