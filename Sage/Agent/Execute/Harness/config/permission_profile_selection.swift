//
//  permission_profile_selection.swift
//  Sage
//
//  Port of codex-rs/core/src/config/permission_profile_selection.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

func selectPermissionProfile(
    id: String?,
    catalog: [PermissionProfileCatalogEntry],
    fallback: PermissionProfile
) -> PermissionProfile {
    guard let id, let entry = catalog.first(where: { $0.id == id }) else {
        return fallback
    }
    return entry.profile
}
