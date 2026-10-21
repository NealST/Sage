//
//  permission_path.swift
//  Sage
//
//  Port of codex-rs/core/src/config/permission_path.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

func normalizePermissionPath(_ path: String) -> String {
    (path as NSString).standardizingPath
}
