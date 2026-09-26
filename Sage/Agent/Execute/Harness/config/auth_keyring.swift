//
//  auth_keyring.swift
//  Sage
//
//  Port of codex-rs/core/src/config/auth_keyring.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  macOS Keychain is the store. This file only names the service.
//

import Foundation

enum AuthKeyring {
    static let serviceName = "com.sage.codex-auth"
}
