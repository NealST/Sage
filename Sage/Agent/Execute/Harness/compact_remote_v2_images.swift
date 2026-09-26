//
//  compact_remote_v2_images.swift
//  CodexCore
//
//  Port of codex-rs/core/src/compact_remote_v2_images.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

public enum CompactRemoteV2Images {
    public static func shouldDropImages(occupancy: Double) -> Bool {
        occupancy >= 0.85
    }
}
