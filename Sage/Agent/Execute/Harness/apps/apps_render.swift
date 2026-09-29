//
//  apps_render.swift
//  CodexCore
//
//  Port of codex-rs/core/src/apps/render.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  R4a: basename `render.swift` would collide with `plugins/plugins_render.swift`.
//

import Foundation

public func renderAppsSection(_ connectors: [AppInfo]) -> String? {
    connectors.contains { $0.isAccessible && $0.isEnabled }
        ? AppsInstructions().renderedText()
        : nil
}
