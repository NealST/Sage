//
//  permission_profile_catalog.swift
//  Sage
//
//  Port of codex-rs/core/src/config/permission_profile_catalog.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

struct PermissionProfileCatalogEntry: Equatable, Sendable {
    var id: String
    var profile: PermissionProfile

    init(id: String, profile: PermissionProfile) {
        self.id = id
        self.profile = profile
    }
}
