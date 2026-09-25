//
//  exec_permission_profile_serde.swift
//  FileSystem
//
//  Port of codex-rs/file-system/src/exec_permission_profile_serde.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Uses executor file URIs for sandbox permissions instead of the profile's
//  legacy native paths.
//

import CodexProtocol

enum ExecPermissionProfileSerde {
    static func decode<K: CodingKey>(
        from decoder: any Decoder,
        container: KeyedDecodingContainer<K>,
        key: K
    ) throws -> PermissionProfile {
        _ = decoder
        return PermissionProfile(try container.decode(ExecPermissionProfile.self, forKey: key))
    }

    static func encode<K: CodingKey>(
        _ value: PermissionProfile,
        to container: inout KeyedEncodingContainer<K>,
        key: K
    ) throws {
        try container.encode(ExecPermissionProfile(value), forKey: key)
    }
}
