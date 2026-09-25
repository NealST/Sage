//
//  models.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/models.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: partial
//
//  Core model types shared across the harness. FileSystemPermissions,
//  ManagedFileSystemPermissions, and PermissionProfile now use the full
//  permissions.swift types. ResponseItem is a partial port of the main
//  tagged variants so turn_input.swift can compile.
//
//  Sub-modules `configuration_update`, `executed_tool_calls`, and
//  `item_metadata` are ported in their own files.
//

import CodexUtils
import Foundation

// MARK: - SandboxPermissions

public enum SandboxPermissions: String, Codable, Equatable, Hashable, Sendable {
    case useDefault = "use_default"
    case requireEscalated = "require_escalated"
    case withAdditionalPermissions = "with_additional_permissions"

    public var requiresEscalatedPermissions: Bool {
        self == .requireEscalated
    }

    public var requestsSandboxOverride: Bool {
        self != .useDefault
    }

    public var usesAdditionalPermissions: Bool {
        self == .withAdditionalPermissions
    }
}

// MARK: - NetworkPermissions

public struct NetworkPermissions: Codable, Equatable, Hashable, Sendable {
    public var enabled: Bool?

    public var isEmpty: Bool { enabled == nil }

    public init(enabled: Bool? = nil) { self.enabled = enabled }
}

// MARK: - AdditionalPermissionProfile

public struct AdditionalPermissionProfile: Codable, Equatable, Hashable, Sendable {
    public var network: NetworkPermissions?
    public var fileSystem: FileSystemPermissions?

    enum CodingKeys: String, CodingKey {
        case network
        case fileSystem = "file_system"
    }

    public var isEmpty: Bool {
        network == nil && fileSystem == nil
    }

    public init(network: NetworkPermissions? = nil, fileSystem: FileSystemPermissions? = nil) {
        self.network = network; self.fileSystem = fileSystem
    }
}

// MARK: - FileSystemPermissions

public struct FileSystemPermissions: Equatable, Hashable, Sendable {
    public var entries: [FileSystemSandboxEntry]
    public var globScanMaxDepth: Int?

    public var isEmpty: Bool { entries.isEmpty }

    public init(entries: [FileSystemSandboxEntry] = [], globScanMaxDepth: Int? = nil) {
        self.entries = entries
        self.globScanMaxDepth = globScanMaxDepth.flatMap { $0 > 0 ? $0 : nil }
    }

    public static func fromReadWriteRoots(
        read: [AbsolutePathBuf]?,
        write: [AbsolutePathBuf]?
    ) -> FileSystemPermissions {
        fromPaths(read: read?.map(FileSystemPath.init), write: write?.map(FileSystemPath.init))
    }

    public static func fromReadWritePathUris(
        read: [PathUri]?,
        write: [PathUri]?
    ) -> FileSystemPermissions {
        fromPaths(read: read?.map(FileSystemPath.init), write: write?.map(FileSystemPath.init))
    }

    private static func fromPaths(
        read: [FileSystemPath]?,
        write: [FileSystemPath]?
    ) -> FileSystemPermissions {
        var entries: [FileSystemSandboxEntry] = []
        if let read {
            entries.append(contentsOf: read.map { FileSystemSandboxEntry.new($0, .read) })
        }
        if let write {
            entries.append(contentsOf: write.map { FileSystemSandboxEntry.new($0, .write) })
        }
        return FileSystemPermissions(entries: entries, globScanMaxDepth: nil)
    }

    public func legacyReadWriteRoots() -> LegacyReadWriteRoots? {
        asLegacyPermissions()
    }

    func asLegacyPermissions() -> LegacyReadWriteRoots? {
        if globScanMaxDepth != nil { return nil }
        var read: [AbsolutePathBuf] = []
        var write: [AbsolutePathBuf] = []
        for entry in entries {
            guard case .path(let path) = entry.path, let abs = try? path.toAbsPath() else {
                return nil
            }
            switch entry.access {
            case .read: read.append(abs)
            case .write: write.append(abs)
            case .deny: return nil
            }
        }
        return LegacyReadWriteRoots(
            read: read.isEmpty ? nil : read,
            write: write.isEmpty ? nil : write
        )
    }
}

public struct LegacyReadWriteRoots: Codable, Equatable, Hashable, Sendable {
    public var read: [AbsolutePathBuf]?
    public var write: [AbsolutePathBuf]?

    enum CodingKeys: String, CodingKey, CaseIterable { case read, write }

    public init(read: [AbsolutePathBuf]? = nil, write: [AbsolutePathBuf]? = nil) {
        self.read = read
        self.write = write
    }

    public init(from decoder: any Decoder) throws {
        try rejectUnknownFields(in: decoder, keys: CodingKeys.self, type: "LegacyReadWriteRoots")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        read = try container.decodeIfPresent([AbsolutePathBuf].self, forKey: .read)
        write = try container.decodeIfPresent([AbsolutePathBuf].self, forKey: .write)
    }
}

private struct CanonicalFileSystemPermissions: Codable {
    var entries: [RawFileSystemSandboxEntry]
    var globScanMaxDepth: Int?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case entries
        case globScanMaxDepth = "glob_scan_max_depth"
    }

    init(entries: [RawFileSystemSandboxEntry] = [], globScanMaxDepth: Int? = nil) {
        self.entries = entries
        self.globScanMaxDepth = globScanMaxDepth
    }

    init(from decoder: any Decoder) throws {
        try rejectUnknownFields(
            in: decoder, keys: CodingKeys.self, type: "CanonicalFileSystemPermissions")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = try container.decodeIfPresent([RawFileSystemSandboxEntry].self, forKey: .entries) ?? []
        globScanMaxDepth = try container.decodeIfPresent(Int.self, forKey: .globScanMaxDepth)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !entries.isEmpty { try container.encode(entries, forKey: .entries) }
        try container.encodeIfPresent(globScanMaxDepth, forKey: .globScanMaxDepth)
    }
}

extension FileSystemPermissions: Codable {
    public init(from decoder: any Decoder) throws {
        let value = try JSONValue(from: decoder)
        if let canonical = try? value.decoded(as: CanonicalFileSystemPermissions.self) {
            self.entries = try canonical.entries.map { try FileSystemSandboxEntry($0) }
            self.globScanMaxDepth = canonical.globScanMaxDepth.flatMap { $0 > 0 ? $0 : nil }
            return
        }
        let legacy = try value.decoded(as: LegacyReadWriteRoots.self)
        self = .fromReadWriteRoots(read: legacy.read, write: legacy.write)
    }

    public func encode(to encoder: any Encoder) throws {
        if let legacy = asLegacyPermissions() {
            try legacy.encode(to: encoder)
            return
        }
        try CanonicalFileSystemPermissions(
            entries: try entries.map { try RawFileSystemSandboxEntry($0) },
            globScanMaxDepth: globScanMaxDepth
        ).encode(to: encoder)
    }
}

// MARK: - SandboxEnforcement

public enum SandboxEnforcement: String, Codable, Equatable, Hashable, Sendable {
    case managed
    case disabled
    case external

    public static func fromLegacySandboxPolicy(_ sandboxPolicy: SandboxPolicy) -> SandboxEnforcement {
        switch sandboxPolicy {
        case .dangerFullAccess: return .disabled
        case .externalSandbox: return .external
        case .readOnly, .workspaceWrite: return .managed
        }
    }
}

// MARK: - ActivePermissionProfile

public struct ActivePermissionProfile: Codable, Equatable, Sendable {
    public var id: String
    public var extends: String?

    public init(id: String, extends: String? = nil) {
        self.id = id; self.extends = extends
    }

    public static func readOnly() -> ActivePermissionProfile {
        ActivePermissionProfile(id: builtInPermissionProfileReadOnly)
    }
}

public let builtInPermissionProfileReadOnly = ":read-only"
public let builtInPermissionProfileWorkspace = ":workspace"
public let builtInPermissionProfileDangerFullAccess = ":danger-full-access"

// MARK: - ManagedFileSystemPermissions

public enum ManagedFileSystemPermissions: Equatable, Hashable, Sendable {
    case restricted(entries: [FileSystemSandboxEntry], globScanMaxDepth: Int?)
    case unrestricted

    static func fromSandboxPolicy(_ fileSystemSandboxPolicy: FileSystemSandboxPolicy) -> ManagedFileSystemPermissions {
        switch fileSystemSandboxPolicy.kind {
        case .restricted:
            return .restricted(
                entries: fileSystemSandboxPolicy.entries,
                globScanMaxDepth: fileSystemSandboxPolicy.globScanMaxDepth.flatMap { $0 > 0 ? $0 : nil })
        case .unrestricted:
            return .unrestricted
        case .externalSandbox:
            return .unrestricted
        }
    }

    public func toSandboxPolicy() -> FileSystemSandboxPolicy {
        switch self {
        case .restricted(let entries, let globScanMaxDepth):
            return FileSystemSandboxPolicy(
                kind: .restricted,
                globScanMaxDepth: globScanMaxDepth,
                entries: entries)
        case .unrestricted:
            return .unrestricted()
        }
    }
}

extension ManagedFileSystemPermissions: Codable {
    private enum TypeKey: String, CodingKey { case type_ = "type" }
    private enum Keys: String, CodingKey {
        case type_ = "type"
        case entries
        case globScanMaxDepth = "glob_scan_max_depth"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decode(String.self, forKey: .type_)
        let keys = try decoder.container(keyedBy: Keys.self)
        switch type_ {
        case "restricted":
            let raw = try keys.decode([RawFileSystemSandboxEntry].self, forKey: .entries)
            self = .restricted(
                entries: try raw.map { try FileSystemSandboxEntry($0) },
                globScanMaxDepth: try keys.decodeIfPresent(Int.self, forKey: .globScanMaxDepth)
                    .flatMap { $0 > 0 ? $0 : nil })
        case "unrestricted":
            self = .unrestricted
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type_, in: container,
                debugDescription: "Unknown ManagedFileSystemPermissions: \(type_)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        switch self {
        case .restricted(let entries, let globScanMaxDepth):
            try container.encode("restricted", forKey: .type_)
            try container.encode(entries.map { try RawFileSystemSandboxEntry($0) }, forKey: .entries)
            try container.encodeIfPresent(globScanMaxDepth, forKey: .globScanMaxDepth)
        case .unrestricted:
            try container.encode("unrestricted", forKey: .type_)
        }
    }
}

// MARK: - PermissionProfile

public enum PermissionProfile: Equatable, Sendable {
    case managed(fileSystem: ManagedFileSystemPermissions, network: NetworkSandboxPolicy)
    case disabled
    case external(network: NetworkSandboxPolicy)

    public static func readOnly() -> PermissionProfile {
        let fileSystem = FileSystemSandboxPolicy.readOnly()
        return .managed(
            fileSystem: .fromSandboxPolicy(fileSystem),
            network: .restricted)
    }

    public func intersectWithReadOnly() -> PermissionProfile? {
        var fileSystem = fileSystemSandboxPolicy()
        switch fileSystem.kind {
        case .restricted:
            for index in fileSystem.entries.indices {
                switch fileSystem.entries[index].access {
                case .read, .write:
                    fileSystem.entries[index].access = .read
                case .deny:
                    break
                }
            }
        case .unrestricted:
            fileSystem = .readOnly()
        case .externalSandbox:
            return nil
        }
        return .fromRuntimePermissions(fileSystem, .restricted)
    }

    public static func workspaceWrite() -> PermissionProfile {
        workspaceWriteWith(
            [],
            network: .restricted,
            excludeTmpdirEnvVar: false,
            excludeSlashTmp: false)
    }

    public static func workspaceWriteWith(
        _ writableRoots: [AbsolutePathBuf],
        network: NetworkSandboxPolicy,
        excludeTmpdirEnvVar: Bool,
        excludeSlashTmp: Bool
    ) -> PermissionProfile {
        let fileSystem = FileSystemSandboxPolicy.workspaceWrite(
            writableRoots,
            excludeTmpdirEnvVar: excludeTmpdirEnvVar,
            excludeSlashTmp: excludeSlashTmp)
        return .managed(fileSystem: .fromSandboxPolicy(fileSystem), network: network)
    }

    public static func workspaceWriteWithPathUris(
        _ writableRoots: [PathUri],
        network: NetworkSandboxPolicy,
        excludeTmpdirEnvVar: Bool,
        excludeSlashTmp: Bool
    ) -> PermissionProfile {
        let fileSystem = FileSystemSandboxPolicy.workspaceWriteWithPathUris(
            writableRoots,
            excludeTmpdirEnvVar: excludeTmpdirEnvVar,
            excludeSlashTmp: excludeSlashTmp)
        return .managed(fileSystem: .fromSandboxPolicy(fileSystem), network: network)
    }

    public func materializeProjectRootsWithWorkspaceRoots(
        _ workspaceRoots: [AbsolutePathBuf]
    ) -> PermissionProfile {
        materializeProjectRootsWith { $0.materializeProjectRootsWithWorkspaceRoots(workspaceRoots) }
    }

    public func materializeProjectRootsWithPathUris(
        _ workspaceRoots: [PathUri]
    ) -> PermissionProfile {
        materializeProjectRootsWith { $0.materializeProjectRootsWithPathUris(workspaceRoots) }
    }

    private func materializeProjectRootsWith(
        _ materialize: (FileSystemSandboxPolicy) -> FileSystemSandboxPolicy
    ) -> PermissionProfile {
        switch self {
        case .managed(let fileSystem, let network):
            let fileSystem = materialize(fileSystem.toSandboxPolicy())
            return .managed(fileSystem: .fromSandboxPolicy(fileSystem), network: network)
        case .disabled:
            return .disabled
        case .external(let network):
            return .external(network: network)
        }
    }

    public static func fromRuntimePermissions(
        _ fileSystemSandboxPolicy: FileSystemSandboxPolicy,
        _ networkSandboxPolicy: NetworkSandboxPolicy
    ) -> PermissionProfile {
        let enforcement: SandboxEnforcement
        switch fileSystemSandboxPolicy.kind {
        case .restricted, .unrestricted:
            enforcement = .managed
        case .externalSandbox:
            enforcement = .external
        }
        return fromRuntimePermissionsWithEnforcement(
            enforcement,
            fileSystemSandboxPolicy,
            networkSandboxPolicy)
    }

    public static func fromRuntimePermissionsWithEnforcement(
        _ enforcement: SandboxEnforcement,
        _ fileSystemSandboxPolicy: FileSystemSandboxPolicy,
        _ networkSandboxPolicy: NetworkSandboxPolicy
    ) -> PermissionProfile {
        switch fileSystemSandboxPolicy.kind {
        case .externalSandbox:
            return .external(network: networkSandboxPolicy)
        case .unrestricted where enforcement == .disabled:
            return .disabled
        case .restricted, .unrestricted:
            return .managed(
                fileSystem: .fromSandboxPolicy(fileSystemSandboxPolicy),
                network: networkSandboxPolicy)
        }
    }

    public static func fromLegacySandboxPolicy(_ sandboxPolicy: SandboxPolicy) -> PermissionProfile {
        fromRuntimePermissionsWithEnforcement(
            .fromLegacySandboxPolicy(sandboxPolicy),
            FileSystemSandboxPolicy(sandboxPolicy),
            NetworkSandboxPolicy(sandboxPolicy))
    }

    public static func fromLegacySandboxPolicyForCwd(
        _ sandboxPolicy: SandboxPolicy,
        cwd: String
    ) -> PermissionProfile {
        fromRuntimePermissionsWithEnforcement(
            .fromLegacySandboxPolicy(sandboxPolicy),
            .fromLegacySandboxPolicyForCwd(sandboxPolicy, cwd: cwd),
            NetworkSandboxPolicy(sandboxPolicy))
    }

    public func enforcement() -> SandboxEnforcement {
        switch self {
        case .managed: return .managed
        case .disabled: return .disabled
        case .external: return .external
        }
    }

    public func fileSystemSandboxPolicy() -> FileSystemSandboxPolicy {
        switch self {
        case .managed(let fileSystem, _): return fileSystem.toSandboxPolicy()
        case .disabled: return .unrestricted()
        case .external: return .externalSandbox()
        }
    }

    public func networkSandboxPolicy() -> NetworkSandboxPolicy {
        switch self {
        case .managed(_, let network), .external(let network): return network
        case .disabled: return .enabled
        }
    }

    public func toLegacySandboxPolicy(cwd: String) throws -> SandboxPolicy {
        switch self {
        case .managed(let fileSystem, let network):
            return try fileSystem.toSandboxPolicy().toLegacySandboxPolicy(network, cwd: cwd)
        case .disabled:
            return .dangerFullAccess
        case .external(let network):
            return .externalSandbox(networkAccess: network.isEnabled ? .enabled : .restricted)
        }
    }

    public func toRuntimePermissions() -> (FileSystemSandboxPolicy, NetworkSandboxPolicy) {
        (fileSystemSandboxPolicy(), networkSandboxPolicy())
    }
}

extension PermissionProfile: Codable {
    private enum TypeKey: String, CodingKey { case type_ = "type" }
    private enum Keys: String, CodingKey {
        case type_ = "type"
        case fileSystem = "file_system"
        case network
    }
    private enum LegacyKeys: String, CodingKey, CaseIterable {
        case network
        case fileSystem = "file_system"
    }

    public init(from decoder: any Decoder) throws {
        let value = try JSONValue(from: decoder)
        if let tagged = try? value.decoded(as: TaggedPermissionProfile.self) {
            self = tagged.asProfile()
            return
        }
        let legacy = try value.decoded(as: LegacyPermissionProfile.self)
        self = legacy.asProfile()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        switch self {
        case .managed(let fileSystem, let network):
            try container.encode("managed", forKey: .type_)
            try container.encode(fileSystem, forKey: .fileSystem)
            try container.encode(network, forKey: .network)
        case .disabled:
            try container.encode("disabled", forKey: .type_)
        case .external(let network):
            try container.encode("external", forKey: .type_)
            try container.encode(network, forKey: .network)
        }
    }
}

private struct TaggedPermissionProfile: Codable {
    var type_: String
    var fileSystem: ManagedFileSystemPermissions?
    var network: NetworkSandboxPolicy?

    enum CodingKeys: String, CodingKey {
        case type_ = "type"
        case fileSystem = "file_system"
        case network
    }

    func asProfile() -> PermissionProfile {
        switch type_ {
        case "managed":
            return .managed(
                fileSystem: fileSystem ?? .restricted(entries: [], globScanMaxDepth: nil),
                network: network ?? .restricted)
        case "disabled":
            return .disabled
        case "external":
            return .external(network: network ?? .restricted)
        default:
            return .managed(
                fileSystem: .restricted(entries: [], globScanMaxDepth: nil),
                network: .restricted)
        }
    }
}

private struct LegacyPermissionProfile: Codable {
    var network: NetworkPermissions?
    var fileSystem: FileSystemPermissions?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case network
        case fileSystem = "file_system"
    }

    init(from decoder: any Decoder) throws {
        try rejectUnknownFields(in: decoder, keys: CodingKeys.self, type: "LegacyPermissionProfile")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        network = try container.decodeIfPresent(NetworkPermissions.self, forKey: .network)
        fileSystem = try container.decodeIfPresent(FileSystemPermissions.self, forKey: .fileSystem)
    }

    func asProfile() -> PermissionProfile {
        let fileSystem: ManagedFileSystemPermissions
        if let permissions = self.fileSystem {
            fileSystem = .restricted(
                entries: permissions.entries,
                globScanMaxDepth: permissions.globScanMaxDepth)
        } else {
            fileSystem = .restricted(entries: [], globScanMaxDepth: nil)
        }
        let network: NetworkSandboxPolicy =
            self.network?.enabled == true ? .enabled : .restricted
        return .managed(fileSystem: fileSystem, network: network)
    }
}

extension PermissionProfile {
    public static let `default` = PermissionProfile.managed(
        fileSystem: .restricted(entries: [], globScanMaxDepth: nil),
        network: .restricted)
}

extension NetworkPermissions {
    public init(_ value: NetworkSandboxPolicy) {
        self.init(enabled: value.isEnabled)
    }
}

extension FileSystemPermissions {
    public init(_ value: FileSystemSandboxPolicy) {
        let entries: [FileSystemSandboxEntry]
        switch value.kind {
        case .restricted:
            entries = value.entries
        case .unrestricted, .externalSandbox:
            entries = [FileSystemSandboxEntry.new(.special(value: .root), .write)]
        }
        self.init(
            entries: entries,
            globScanMaxDepth: value.globScanMaxDepth.flatMap { $0 > 0 ? $0 : nil })
    }
}

extension FileSystemSandboxPolicy {
    public init(_ value: FileSystemPermissions) {
        var policy = FileSystemSandboxPolicy.restricted(value.entries)
        policy.globScanMaxDepth = value.globScanMaxDepth
        self = policy
    }
}

// MARK: - ImageReference

public enum ImageReference: Codable, Equatable, Sendable {
    case inline(imageUrl: String)
    case file(fileId: String)

    private enum InlineCodingKeys: String, CodingKey { case imageUrl = "image_url" }
    private enum FileCodingKeys: String, CodingKey { case fileId = "file_id" }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: InlineCodingKeys.self)
        if let url = try container.decodeIfPresent(String.self, forKey: .imageUrl) {
            self = .inline(imageUrl: url)
            return
        }
        let fileContainer = try decoder.container(keyedBy: FileCodingKeys.self)
        let fileId = try fileContainer.decode(String.self, forKey: .fileId)
        self = .file(fileId: fileId)
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .inline(let url):
            var container = encoder.container(keyedBy: InlineCodingKeys.self)
            try container.encode(url, forKey: .imageUrl)
        case .file(let fileId):
            var container = encoder.container(keyedBy: FileCodingKeys.self)
            try container.encode(fileId, forKey: .fileId)
        }
    }
}

// MARK: - ImageDetail

public enum ImageDetail: String, Codable, Equatable, Sendable {
    case auto
    case low
    case high
    case original
}

public let defaultImageDetail: ImageDetail = .high

// MARK: - MessagePhase

public enum MessagePhase: String, Codable, Equatable, Sendable {
    case commentary
    case finalAnswer = "final_answer"
}

// MARK: - ContentItem

public enum ContentItem: Codable, Equatable, Sendable {
    case inputText(text: String)
    case inputImage(image: ImageReference, detail: ImageDetail?)
    case inputAudio(audioUrl: String)
    case outputText(text: String)

    private enum TypeKey: String, CodingKey { case type_ = "type" }
    private enum Keys: String, CodingKey {
        case text
        case imageUrl = "image_url"
        case fileId = "file_id"
        case detail
        case audioUrl = "audio_url"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decode(String.self, forKey: .type_)
        let keys = try decoder.container(keyedBy: Keys.self)
        switch type_ {
        case "input_text":
            self = .inputText(text: try keys.decode(String.self, forKey: .text))
        case "input_image":
            let image = try ImageReference(from: decoder)
            let detail = try keys.decodeIfPresent(ImageDetail.self, forKey: .detail)
            self = .inputImage(image: image, detail: detail)
        case "input_audio":
            self = .inputAudio(audioUrl: try keys.decode(String.self, forKey: .audioUrl))
        case "output_text":
            self = .outputText(text: try keys.decode(String.self, forKey: .text))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type_, in: container,
                debugDescription: "Unknown ContentItem type: \(type_)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        var keys = encoder.container(keyedBy: Keys.self)
        switch self {
        case .inputText(let text):
            try container.encode("input_text", forKey: .type_)
            try keys.encode(text, forKey: .text)
        case .inputImage(let image, let detail):
            try container.encode("input_image", forKey: .type_)
            try image.encode(to: encoder)
            try keys.encodeIfPresent(detail, forKey: .detail)
        case .inputAudio(let audioUrl):
            try container.encode("input_audio", forKey: .type_)
            try keys.encode(audioUrl, forKey: .audioUrl)
        case .outputText(let text):
            try container.encode("output_text", forKey: .type_)
            try keys.encode(text, forKey: .text)
        }
    }
}

// MARK: - AgentMessageInputContent

public enum AgentMessageInputContent: Codable, Equatable, Sendable {
    case inputText(text: String)
    case encryptedContent(encryptedContent: String)

    private enum TypeKey: String, CodingKey { case type_ = "type" }
    private enum Keys: String, CodingKey {
        case text
        case encryptedContent = "encrypted_content"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decode(String.self, forKey: .type_)
        let keys = try decoder.container(keyedBy: Keys.self)
        switch type_ {
        case "input_text":
            self = .inputText(text: try keys.decode(String.self, forKey: .text))
        case "encrypted_content":
            self = .encryptedContent(
                encryptedContent: try keys.decode(String.self, forKey: .encryptedContent))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type_, in: container,
                debugDescription: "Unknown AgentMessageInputContent: \(type_)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        var keys = encoder.container(keyedBy: Keys.self)
        switch self {
        case .inputText(let text):
            try container.encode("input_text", forKey: .type_)
            try keys.encode(text, forKey: .text)
        case .encryptedContent(let enc):
            try container.encode("encrypted_content", forKey: .type_)
            try keys.encode(enc, forKey: .encryptedContent)
        }
    }
}

public func plaintextAgentMessageContent(_ content: [AgentMessageInputContent]) -> String? {
    var parts: [String] = []
    for part in content {
        switch part {
        case .inputText(let text): parts.append(text)
        case .encryptedContent: return nil
        }
    }
    let text = parts.joined(separator: "\n")
    return text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : text
}

// MARK: - FunctionCallOutputContentItem

public enum FunctionCallOutputContentItem: Codable, Equatable, Sendable {
    case inputText(text: String)
    case inputImage(image: ImageReference, detail: ImageDetail?)
    case inputAudio(audioUrl: String)
    case encryptedContent(encryptedContent: String)

    private enum TypeKey: String, CodingKey { case type_ = "type" }
    private enum Keys: String, CodingKey {
        case text
        case detail
        case audioUrl = "audio_url"
        case encryptedContent = "encrypted_content"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decode(String.self, forKey: .type_)
        let keys = try decoder.container(keyedBy: Keys.self)
        switch type_ {
        case "input_text":
            self = .inputText(text: try keys.decode(String.self, forKey: .text))
        case "input_image":
            let image = try ImageReference(from: decoder)
            let detail = try keys.decodeIfPresent(ImageDetail.self, forKey: .detail)
            self = .inputImage(image: image, detail: detail)
        case "input_audio":
            self = .inputAudio(audioUrl: try keys.decode(String.self, forKey: .audioUrl))
        case "encrypted_content":
            self = .encryptedContent(
                encryptedContent: try keys.decode(String.self, forKey: .encryptedContent))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type_, in: container,
                debugDescription: "Unknown FunctionCallOutputContentItem: \(type_)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        var keys = encoder.container(keyedBy: Keys.self)
        switch self {
        case .inputText(let text):
            try container.encode("input_text", forKey: .type_)
            try keys.encode(text, forKey: .text)
        case .inputImage(let image, let detail):
            try container.encode("input_image", forKey: .type_)
            try image.encode(to: encoder)
            try keys.encodeIfPresent(detail, forKey: .detail)
        case .inputAudio(let audioUrl):
            try container.encode("input_audio", forKey: .type_)
            try keys.encode(audioUrl, forKey: .audioUrl)
        case .encryptedContent(let enc):
            try container.encode("encrypted_content", forKey: .type_)
            try keys.encode(enc, forKey: .encryptedContent)
        }
    }
}

public func functionCallOutputContentItemsToText(
    _ contentItems: [FunctionCallOutputContentItem]
) -> String? {
    let segments = contentItems.compactMap { item -> String? in
        guard case .inputText(let text) = item, !text.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        return text
    }
    return segments.isEmpty ? nil : segments.joined(separator: "\n")
}

extension FunctionCallOutputContentItem {
    public init(from dynamicItem: DynamicToolCallOutputContentItem) {
        switch dynamicItem {
        case .inputText(let text):
            self = .inputText(text: text)
        case .inputImage(let imageUrl):
            self = .inputImage(
                image: .inline(imageUrl: imageUrl),
                detail: defaultImageDetail)
        case .inputAudio(let audioUrl):
            self = .inputAudio(audioUrl: audioUrl)
        }
    }
}

// MARK: - FunctionCallOutputBody

public enum FunctionCallOutputBody: Codable, Equatable, Sendable {
    case text(String)
    case contentItems([FunctionCallOutputContentItem])

    public func toText() -> String? {
        switch self {
        case .text(let content): return content
        case .contentItems(let items): return functionCallOutputContentItemsToText(items)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
        } else {
            self = .contentItems(try container.decode([FunctionCallOutputContentItem].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let s): try container.encode(s)
        case .contentItems(let items): try container.encode(items)
        }
    }
}

// MARK: - FunctionCallOutputPayload

public struct FunctionCallOutputPayload: Equatable, Sendable, CustomStringConvertible {
    public var body: FunctionCallOutputBody
    public var success: Bool?

    public init(body: FunctionCallOutputBody = .text(""), success: Bool? = nil) {
        self.body = body; self.success = success
    }

    public static func fromText(_ content: String) -> FunctionCallOutputPayload {
        FunctionCallOutputPayload(body: .text(content))
    }

    public static func fromContentItems(
        _ items: [FunctionCallOutputContentItem]
    ) -> FunctionCallOutputPayload {
        FunctionCallOutputPayload(body: .contentItems(items))
    }

    public var textContent: String? {
        if case .text(let c) = body { return c }
        return nil
    }

    public var contentItems: [FunctionCallOutputContentItem]? {
        if case .contentItems(let items) = body { return items }
        return nil
    }

    public var description: String {
        switch body {
        case .text(let content): return content
        case .contentItems(let items):
            let data = try? JSONEncoder().encode(items)
            return data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
    }
}

extension FunctionCallOutputPayload: Codable {
    public init(from decoder: any Decoder) throws {
        body = try FunctionCallOutputBody(from: decoder)
        success = nil
    }

    public func encode(to encoder: any Encoder) throws {
        try body.encode(to: encoder)
    }
}

// MARK: - SearchToolCallParams

public struct SearchToolCallParams: Codable, Equatable, Sendable {
    public var query: String
    public var limit: Int?
}

// MARK: - ReasoningItemReasoningSummary

public enum ReasoningItemReasoningSummary: Codable, Equatable, Sendable {
    case summaryText(text: String)

    private enum TypeKey: String, CodingKey { case type_ = "type" }
    private enum Keys: String, CodingKey { case text }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decode(String.self, forKey: .type_)
        let keys = try decoder.container(keyedBy: Keys.self)
        switch type_ {
        case "summary_text":
            self = .summaryText(text: try keys.decode(String.self, forKey: .text))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type_, in: container,
                debugDescription: "Unknown ReasoningItemReasoningSummary: \(type_)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        var keys = encoder.container(keyedBy: Keys.self)
        switch self {
        case .summaryText(let text):
            try container.encode("summary_text", forKey: .type_)
            try keys.encode(text, forKey: .text)
        }
    }
}

// MARK: - ReasoningItemContent

public enum ReasoningItemContent: Codable, Equatable, Sendable {
    case reasoningText(text: String)
    case text(text: String)

    private enum TypeKey: String, CodingKey { case type_ = "type" }
    private enum Keys: String, CodingKey { case text }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decode(String.self, forKey: .type_)
        let keys = try decoder.container(keyedBy: Keys.self)
        switch type_ {
        case "reasoning_text":
            self = .reasoningText(text: try keys.decode(String.self, forKey: .text))
        case "text":
            self = .text(text: try keys.decode(String.self, forKey: .text))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type_, in: container,
                debugDescription: "Unknown ReasoningItemContent: \(type_)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        var keys = encoder.container(keyedBy: Keys.self)
        switch self {
        case .reasoningText(let text):
            try container.encode("reasoning_text", forKey: .type_)
            try keys.encode(text, forKey: .text)
        case .text(let text):
            try container.encode("text", forKey: .type_)
            try keys.encode(text, forKey: .text)
        }
    }
}

// MARK: - LocalShellStatus

public enum LocalShellStatus: String, Codable, Equatable, Sendable {
    case completed
    case inProgress = "in_progress"
    case incomplete
}

// MARK: - LocalShellAction

public enum LocalShellAction: Codable, Equatable, Sendable {
    case exec(LocalShellExecAction)

    private enum TypeKey: String, CodingKey { case type_ = "type" }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decode(String.self, forKey: .type_)
        switch type_ {
        case "exec":
            self = .exec(try LocalShellExecAction(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type_, in: container,
                debugDescription: "Unknown LocalShellAction: \(type_)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        switch self {
        case .exec(let action):
            try container.encode("exec", forKey: .type_)
            try action.encode(to: encoder)
        }
    }
}

// MARK: - LocalShellExecAction

public struct LocalShellExecAction: Codable, Equatable, Sendable {
    public var command: [String]
    public var timeoutMs: UInt64?
    public var workingDirectory: String?
    public var env: [String: String]?
    public var user: String?

    enum CodingKeys: String, CodingKey {
        case command
        case timeoutMs = "timeout_ms"
        case workingDirectory = "working_directory"
        case env, user
    }
}

// MARK: - WebSearchAction

public enum WebSearchAction: Codable, Equatable, Sendable {
    case search(query: String?, queries: [String]?)
    case openPage(url: String?)
    case findInPage(url: String?, pattern: String?)
    case other

    private enum TypeKey: String, CodingKey { case type_ = "type" }
    private enum Keys: String, CodingKey { case query, queries, url, pattern }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let keys = try decoder.container(keyedBy: Keys.self)
        let type_ = try container.decode(String.self, forKey: .type_)
        switch type_ {
        case "search":
            self = .search(
                query: try keys.decodeIfPresent(String.self, forKey: .query),
                queries: try keys.decodeIfPresent([String].self, forKey: .queries))
        case "open_page":
            self = .openPage(url: try keys.decodeIfPresent(String.self, forKey: .url))
        case "find_in_page":
            self = .findInPage(
                url: try keys.decodeIfPresent(String.self, forKey: .url),
                pattern: try keys.decodeIfPresent(String.self, forKey: .pattern))
        default:
            self = .other
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        var keys = encoder.container(keyedBy: Keys.self)
        switch self {
        case .search(let query, let queries):
            try container.encode("search", forKey: .type_)
            try keys.encodeIfPresent(query, forKey: .query)
            try keys.encodeIfPresent(queries, forKey: .queries)
        case .openPage(let url):
            try container.encode("open_page", forKey: .type_)
            try keys.encodeIfPresent(url, forKey: .url)
        case .findInPage(let url, let pattern):
            try container.encode("find_in_page", forKey: .type_)
            try keys.encodeIfPresent(url, forKey: .url)
            try keys.encodeIfPresent(pattern, forKey: .pattern)
        case .other:
            try container.encode("other", forKey: .type_)
        }
    }
}

// MARK: - BaseInstructionsProvenance

public enum BaseInstructionsProvenance: Codable, Equatable, Sendable {
    case custom
    case model(model: String)

    private enum TypeKey: String, CodingKey { case type_ = "type" }
    private enum Keys: String, CodingKey { case model }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decode(String.self, forKey: .type_)
        switch type_ {
        case "custom":
            self = .custom
        case "model":
            let keys = try decoder.container(keyedBy: Keys.self)
            self = .model(model: try keys.decode(String.self, forKey: .model))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type_, in: container,
                debugDescription: "Unknown BaseInstructionsProvenance: \(type_)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        switch self {
        case .custom:
            try container.encode("custom", forKey: .type_)
        case .model(let model):
            try container.encode("model", forKey: .type_)
            var keys = encoder.container(keyedBy: Keys.self)
            try keys.encode(model, forKey: .model)
        }
    }
}

// MARK: - BaseInstructions

public let baseInstructionsDefault = ""

public struct BaseInstructions: Codable, Equatable, Sendable {
    public var text: String
    public var provenance: BaseInstructionsProvenance?

    public init(text: String = baseInstructionsDefault, provenance: BaseInstructionsProvenance? = nil) {
        self.text = text; self.provenance = provenance
    }
}

// MARK: - ResponseInputItem

public enum ResponseInputItem: Codable, Equatable, Sendable {
    case message(role: String, content: [ContentItem], phase: MessagePhase?)
    case functionCallOutput(callId: String, output: FunctionCallOutputPayload)
    case mcpToolCallOutput(callId: String, output: CallToolResult)
    case customToolCallOutput(callId: String, name: String?, output: FunctionCallOutputPayload)
    case toolSearchOutput(callId: String, status: String, execution: String, tools: [JSONValue])

    private enum TypeKey: String, CodingKey { case type_ = "type" }
    private enum Keys: String, CodingKey {
        case role, content, phase
        case callId = "call_id"
        case output, name, status, execution, tools
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decode(String.self, forKey: .type_)
        let keys = try decoder.container(keyedBy: Keys.self)
        switch type_ {
        case "message":
            self = .message(
                role: try keys.decode(String.self, forKey: .role),
                content: try keys.decode([ContentItem].self, forKey: .content),
                phase: try keys.decodeIfPresent(MessagePhase.self, forKey: .phase))
        case "function_call_output":
            self = .functionCallOutput(
                callId: try keys.decode(String.self, forKey: .callId),
                output: try keys.decode(FunctionCallOutputPayload.self, forKey: .output))
        case "mcp_tool_call_output":
            self = .mcpToolCallOutput(
                callId: try keys.decode(String.self, forKey: .callId),
                output: try keys.decode(CallToolResult.self, forKey: .output))
        case "custom_tool_call_output":
            self = .customToolCallOutput(
                callId: try keys.decode(String.self, forKey: .callId),
                name: try keys.decodeIfPresent(String.self, forKey: .name),
                output: try keys.decode(FunctionCallOutputPayload.self, forKey: .output))
        case "tool_search_output":
            self = .toolSearchOutput(
                callId: try keys.decode(String.self, forKey: .callId),
                status: try keys.decode(String.self, forKey: .status),
                execution: try keys.decode(String.self, forKey: .execution),
                tools: try keys.decode([JSONValue].self, forKey: .tools))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type_, in: container,
                debugDescription: "Unknown ResponseInputItem: \(type_)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        var keys = encoder.container(keyedBy: Keys.self)
        switch self {
        case .message(let role, let content, let phase):
            try container.encode("message", forKey: .type_)
            try keys.encode(role, forKey: .role)
            try keys.encode(content, forKey: .content)
            try keys.encodeIfPresent(phase, forKey: .phase)
        case .functionCallOutput(let callId, let output):
            try container.encode("function_call_output", forKey: .type_)
            try keys.encode(callId, forKey: .callId)
            try keys.encode(output, forKey: .output)
        case .mcpToolCallOutput(let callId, let output):
            try container.encode("mcp_tool_call_output", forKey: .type_)
            try keys.encode(callId, forKey: .callId)
            try keys.encode(output, forKey: .output)
        case .customToolCallOutput(let callId, let name, let output):
            try container.encode("custom_tool_call_output", forKey: .type_)
            try keys.encode(callId, forKey: .callId)
            try keys.encodeIfPresent(name, forKey: .name)
            try keys.encode(output, forKey: .output)
        case .toolSearchOutput(let callId, let status, let execution, let tools):
            try container.encode("tool_search_output", forKey: .type_)
            try keys.encode(callId, forKey: .callId)
            try keys.encode(status, forKey: .status)
            try keys.encode(execution, forKey: .execution)
            try keys.encode(tools, forKey: .tools)
        }
    }

    public static func userMessage(_ content: [ContentItem]) -> ResponseInputItem {
        .message(role: "user", content: content, phase: nil)
    }
}

// MARK: - ResponseItem (partial)

public enum ResponseItem: Equatable, Sendable {
    case additionalTools(id: ResponseItemId?, role: String, tools: [JSONValue])
    case message(
        id: ResponseItemId?, role: String, content: [ContentItem],
        phase: MessagePhase?,
        internalChatMessageMetadataPassthrough: InternalChatMessageMetadataPassthrough?)
    case agentMessage(
        id: ResponseItemId?, author: String, recipient: String,
        content: [AgentMessageInputContent],
        internalChatMessageMetadataPassthrough: InternalChatMessageMetadataPassthrough?)
    case reasoning(
        id: ResponseItemId?, summary: [ReasoningItemReasoningSummary],
        content: [ReasoningItemContent]?, encryptedContent: String?,
        internalChatMessageMetadataPassthrough: InternalChatMessageMetadataPassthrough?)
    case localShellCall(
        id: ResponseItemId?, callId: String?, status: LocalShellStatus,
        action: LocalShellAction,
        internalChatMessageMetadataPassthrough: InternalChatMessageMetadataPassthrough?)
    case functionCall(
        id: ResponseItemId?, name: String, namespace: String?, arguments: String,
        encryptedFunctionArgs: [String]?, callId: String,
        internalChatMessageMetadataPassthrough: InternalChatMessageMetadataPassthrough?)
    case toolSearchCall(
        id: ResponseItemId?, callId: String?, status: String?, execution: String,
        arguments: JSONValue,
        internalChatMessageMetadataPassthrough: InternalChatMessageMetadataPassthrough?)
    case functionCallOutput(
        id: ResponseItemId?, callId: String?, name: String?, namespace: String?,
        output: FunctionCallOutputPayload,
        internalChatMessageMetadataPassthrough: InternalChatMessageMetadataPassthrough?)
    case customToolCall(
        id: ResponseItemId?, status: String?, callId: String, name: String,
        namespace: String?, input: String,
        internalChatMessageMetadataPassthrough: InternalChatMessageMetadataPassthrough?)
    case customToolCallOutput(
        id: ResponseItemId?, callId: String, name: String?,
        output: FunctionCallOutputPayload,
        internalChatMessageMetadataPassthrough: InternalChatMessageMetadataPassthrough?)
    case toolSearchOutput(
        id: ResponseItemId?, callId: String?, status: String, execution: String,
        tools: [JSONValue],
        internalChatMessageMetadataPassthrough: InternalChatMessageMetadataPassthrough?)
    case webSearchCall(
        id: ResponseItemId?, status: String?, action: WebSearchAction?,
        internalChatMessageMetadataPassthrough: InternalChatMessageMetadataPassthrough?)
    case imageGenerationCall(
        id: ResponseItemId?, status: String, revisedPrompt: String?, result: String,
        internalChatMessageMetadataPassthrough: InternalChatMessageMetadataPassthrough?)
    case compaction(
        id: ResponseItemId?, encryptedContent: String,
        internalChatMessageMetadataPassthrough: InternalChatMessageMetadataPassthrough?)
    case configurationUpdate(reasoning: ConfigurationReasoning)
    case compactionTrigger
    case contextCompaction(
        id: ResponseItemId?, encryptedContent: String?,
        internalChatMessageMetadataPassthrough: InternalChatMessageMetadataPassthrough?)
    case other

    public func isUserMessage() -> Bool {
        if case .message(_, let role, _, _, _) = self { return role == "user" }
        return false
    }

    public func id() -> ResponseItemId? {
        switch self {
        case .additionalTools(let id, _, _),
             .message(let id, _, _, _, _),
             .agentMessage(let id, _, _, _, _),
             .localShellCall(let id, _, _, _, _),
             .functionCall(let id, _, _, _, _, _, _),
             .toolSearchCall(let id, _, _, _, _, _),
             .functionCallOutput(let id, _, _, _, _, _),
             .customToolCall(let id, _, _, _, _, _, _),
             .customToolCallOutput(let id, _, _, _, _),
             .toolSearchOutput(let id, _, _, _, _, _),
             .webSearchCall(let id, _, _, _),
             .reasoning(let id, _, _, _, _),
             .imageGenerationCall(let id, _, _, _, _),
             .compaction(let id, _, _),
             .contextCompaction(let id, _, _):
            return id
        case .configurationUpdate, .compactionTrigger, .other:
            return nil
        }
    }

    public func internalChatMessageMetadataPassthrough() -> InternalChatMessageMetadataPassthrough? {
        switch self {
        case .additionalTools, .configurationUpdate, .compactionTrigger, .other:
            return nil
        case .message(_, _, _, _, let meta),
             .agentMessage(_, _, _, _, let meta),
             .reasoning(_, _, _, _, let meta),
             .localShellCall(_, _, _, _, let meta),
             .functionCall(_, _, _, _, _, _, let meta),
             .toolSearchCall(_, _, _, _, _, let meta),
             .functionCallOutput(_, _, _, _, _, let meta),
             .customToolCall(_, _, _, _, _, _, let meta),
             .customToolCallOutput(_, _, _, _, let meta),
             .toolSearchOutput(_, _, _, _, _, let meta),
             .webSearchCall(_, _, _, let meta),
             .imageGenerationCall(_, _, _, _, let meta),
             .compaction(_, _, let meta),
             .contextCompaction(_, _, let meta):
            return meta
        }
    }

    public mutating func modifyInternalChatMessageMetadata(
        _ body: (inout InternalChatMessageMetadataPassthrough?) -> Void
    ) -> Bool {
        switch self {
        case .message(let id, let role, let content, let phase, var metadata):
            body(&metadata)
            self = .message(
                id: id, role: role, content: content, phase: phase,
                internalChatMessageMetadataPassthrough: metadata)
            return true
        default:
            return false
        }
    }
}

extension ResponseItem: Codable {
    private enum TypeKey: String, CodingKey { case type_ = "type" }
    private enum Keys: String, CodingKey {
        case type_ = "type"
        case id, role, tools, content, phase
        case author, recipient
        case summary
        case encryptedContent = "encrypted_content"
        case callId = "call_id"
        case status, action, name, namespace, arguments
        case encryptedFunctionArgs = "encrypted_function_args"
        case output, input, execution
        case revisedPrompt = "revised_prompt"
        case result, reasoning
        case internalChatMessageMetadataPassthrough = "internal_chat_message_metadata_passthrough"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decode(String.self, forKey: .type_)
        let keys = try decoder.container(keyedBy: Keys.self)
        let id = try keys.decodeIfPresent(ResponseItemId.self, forKey: .id)
        let meta = try keys.decodeIfPresent(
            InternalChatMessageMetadataPassthrough.self,
            forKey: .internalChatMessageMetadataPassthrough)
        switch type_ {
        case "additional_tools":
            self = .additionalTools(
                id: id,
                role: try keys.decode(String.self, forKey: .role),
                tools: try keys.decode([JSONValue].self, forKey: .tools))
        case "message":
            self = .message(
                id: id,
                role: try keys.decode(String.self, forKey: .role),
                content: try keys.decode([ContentItem].self, forKey: .content),
                phase: try keys.decodeIfPresent(MessagePhase.self, forKey: .phase),
                internalChatMessageMetadataPassthrough: meta)
        case "agent_message":
            self = .agentMessage(
                id: id,
                author: try keys.decode(String.self, forKey: .author),
                recipient: try keys.decode(String.self, forKey: .recipient),
                content: try keys.decode([AgentMessageInputContent].self, forKey: .content),
                internalChatMessageMetadataPassthrough: meta)
        case "reasoning":
            self = .reasoning(
                id: id,
                summary: try keys.decode([ReasoningItemReasoningSummary].self, forKey: .summary),
                content: try keys.decodeIfPresent([ReasoningItemContent].self, forKey: .content),
                encryptedContent: try keys.decodeIfPresent(String.self, forKey: .encryptedContent),
                internalChatMessageMetadataPassthrough: meta)
        case "local_shell_call":
            self = .localShellCall(
                id: id,
                callId: try keys.decodeIfPresent(String.self, forKey: .callId),
                status: try keys.decode(LocalShellStatus.self, forKey: .status),
                action: try keys.decode(LocalShellAction.self, forKey: .action),
                internalChatMessageMetadataPassthrough: meta)
        case "function_call":
            self = .functionCall(
                id: id,
                name: try keys.decode(String.self, forKey: .name),
                namespace: try keys.decodeIfPresent(String.self, forKey: .namespace),
                arguments: try keys.decode(String.self, forKey: .arguments),
                encryptedFunctionArgs: try keys.decodeIfPresent([String].self, forKey: .encryptedFunctionArgs),
                callId: try keys.decode(String.self, forKey: .callId),
                internalChatMessageMetadataPassthrough: meta)
        case "tool_search_call":
            self = .toolSearchCall(
                id: id,
                callId: try keys.decodeIfPresent(String.self, forKey: .callId),
                status: try keys.decodeIfPresent(String.self, forKey: .status),
                execution: try keys.decode(String.self, forKey: .execution),
                arguments: try keys.decode(JSONValue.self, forKey: .arguments),
                internalChatMessageMetadataPassthrough: meta)
        case "function_call_output":
            self = .functionCallOutput(
                id: id,
                callId: try keys.decodeIfPresent(String.self, forKey: .callId),
                name: try keys.decodeIfPresent(String.self, forKey: .name),
                namespace: try keys.decodeIfPresent(String.self, forKey: .namespace),
                output: try keys.decode(FunctionCallOutputPayload.self, forKey: .output),
                internalChatMessageMetadataPassthrough: meta)
        case "custom_tool_call":
            self = .customToolCall(
                id: id,
                status: try keys.decodeIfPresent(String.self, forKey: .status),
                callId: try keys.decode(String.self, forKey: .callId),
                name: try keys.decode(String.self, forKey: .name),
                namespace: try keys.decodeIfPresent(String.self, forKey: .namespace),
                input: try keys.decode(String.self, forKey: .input),
                internalChatMessageMetadataPassthrough: meta)
        case "custom_tool_call_output":
            self = .customToolCallOutput(
                id: id,
                callId: try keys.decode(String.self, forKey: .callId),
                name: try keys.decodeIfPresent(String.self, forKey: .name),
                output: try keys.decode(FunctionCallOutputPayload.self, forKey: .output),
                internalChatMessageMetadataPassthrough: meta)
        case "tool_search_output":
            self = .toolSearchOutput(
                id: id,
                callId: try keys.decodeIfPresent(String.self, forKey: .callId),
                status: try keys.decode(String.self, forKey: .status),
                execution: try keys.decode(String.self, forKey: .execution),
                tools: try keys.decode([JSONValue].self, forKey: .tools),
                internalChatMessageMetadataPassthrough: meta)
        case "web_search_call":
            self = .webSearchCall(
                id: id,
                status: try keys.decodeIfPresent(String.self, forKey: .status),
                action: try keys.decodeIfPresent(WebSearchAction.self, forKey: .action),
                internalChatMessageMetadataPassthrough: meta)
        case "image_generation_call":
            self = .imageGenerationCall(
                id: id,
                status: try keys.decode(String.self, forKey: .status),
                revisedPrompt: try keys.decodeIfPresent(String.self, forKey: .revisedPrompt),
                result: try keys.decode(String.self, forKey: .result),
                internalChatMessageMetadataPassthrough: meta)
        case "compaction", "compaction_summary":
            self = .compaction(
                id: id,
                encryptedContent: try keys.decode(String.self, forKey: .encryptedContent),
                internalChatMessageMetadataPassthrough: meta)
        case "configuration_update":
            self = .configurationUpdate(
                reasoning: try keys.decode(ConfigurationReasoning.self, forKey: .reasoning))
        case "compaction_trigger":
            self = .compactionTrigger
        case "context_compaction":
            self = .contextCompaction(
                id: id,
                encryptedContent: try keys.decodeIfPresent(String.self, forKey: .encryptedContent),
                internalChatMessageMetadataPassthrough: meta)
        default:
            self = .other
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        func encodeMeta(_ meta: InternalChatMessageMetadataPassthrough?) throws {
            try container.encodeIfPresent(meta, forKey: .internalChatMessageMetadataPassthrough)
        }
        switch self {
        case .additionalTools(let id, let role, let tools):
            try container.encode("additional_tools", forKey: .type_)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encode(role, forKey: .role)
            try container.encode(tools, forKey: .tools)
        case .message(let id, let role, let content, let phase, let meta):
            try container.encode("message", forKey: .type_)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encode(role, forKey: .role)
            try container.encode(content, forKey: .content)
            try container.encodeIfPresent(phase, forKey: .phase)
            try encodeMeta(meta)
        case .agentMessage(let id, let author, let recipient, let content, let meta):
            try container.encode("agent_message", forKey: .type_)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encode(author, forKey: .author)
            try container.encode(recipient, forKey: .recipient)
            try container.encode(content, forKey: .content)
            try encodeMeta(meta)
        case .reasoning(let id, let summary, let content, let enc, let meta):
            try container.encode("reasoning", forKey: .type_)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encode(summary, forKey: .summary)
            if let content, !content.contains(where: {
                if case .reasoningText = $0 { return true }; return false
            }) {
                // skip_serializing_if should_serialize_reasoning_content
            } else {
                try container.encodeIfPresent(content, forKey: .content)
            }
            try container.encodeIfPresent(enc, forKey: .encryptedContent)
            try encodeMeta(meta)
        case .localShellCall(let id, let callId, let status, let action, let meta):
            try container.encode("local_shell_call", forKey: .type_)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encodeIfPresent(callId, forKey: .callId)
            try container.encode(status, forKey: .status)
            try container.encode(action, forKey: .action)
            try encodeMeta(meta)
        case .functionCall(let id, let name, let namespace, let arguments, let enc, let callId, let meta):
            try container.encode("function_call", forKey: .type_)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(namespace, forKey: .namespace)
            try container.encode(arguments, forKey: .arguments)
            try container.encodeIfPresent(enc, forKey: .encryptedFunctionArgs)
            try container.encode(callId, forKey: .callId)
            try encodeMeta(meta)
        case .toolSearchCall(let id, let callId, let status, let execution, let arguments, let meta):
            try container.encode("tool_search_call", forKey: .type_)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encodeIfPresent(callId, forKey: .callId)
            try container.encodeIfPresent(status, forKey: .status)
            try container.encode(execution, forKey: .execution)
            try container.encode(arguments, forKey: .arguments)
            try encodeMeta(meta)
        case .functionCallOutput(let id, let callId, let name, let namespace, let output, let meta):
            try container.encode("function_call_output", forKey: .type_)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encodeIfPresent(callId, forKey: .callId)
            try container.encodeIfPresent(name, forKey: .name)
            try container.encodeIfPresent(namespace, forKey: .namespace)
            try container.encode(output, forKey: .output)
            try encodeMeta(meta)
        case .customToolCall(let id, let status, let callId, let name, let namespace, let input, let meta):
            try container.encode("custom_tool_call", forKey: .type_)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encodeIfPresent(status, forKey: .status)
            try container.encode(callId, forKey: .callId)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(namespace, forKey: .namespace)
            try container.encode(input, forKey: .input)
            try encodeMeta(meta)
        case .customToolCallOutput(let id, let callId, let name, let output, let meta):
            try container.encode("custom_tool_call_output", forKey: .type_)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encode(callId, forKey: .callId)
            try container.encodeIfPresent(name, forKey: .name)
            try container.encode(output, forKey: .output)
            try encodeMeta(meta)
        case .toolSearchOutput(let id, let callId, let status, let execution, let tools, let meta):
            try container.encode("tool_search_output", forKey: .type_)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encodeIfPresent(callId, forKey: .callId)
            try container.encode(status, forKey: .status)
            try container.encode(execution, forKey: .execution)
            try container.encode(tools, forKey: .tools)
            try encodeMeta(meta)
        case .webSearchCall(let id, let status, let action, let meta):
            try container.encode("web_search_call", forKey: .type_)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encodeIfPresent(status, forKey: .status)
            try container.encodeIfPresent(action, forKey: .action)
            try encodeMeta(meta)
        case .imageGenerationCall(let id, let status, let prompt, let result, let meta):
            try container.encode("image_generation_call", forKey: .type_)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encode(status, forKey: .status)
            try container.encodeIfPresent(prompt, forKey: .revisedPrompt)
            try container.encode(result, forKey: .result)
            try encodeMeta(meta)
        case .compaction(let id, let enc, let meta):
            try container.encode("compaction", forKey: .type_)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encode(enc, forKey: .encryptedContent)
            try encodeMeta(meta)
        case .configurationUpdate(let reasoning):
            try container.encode("configuration_update", forKey: .type_)
            try container.encode(reasoning, forKey: .reasoning)
        case .compactionTrigger:
            try container.encode("compaction_trigger", forKey: .type_)
        case .contextCompaction(let id, let enc, let meta):
            try container.encode("context_compaction", forKey: .type_)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encodeIfPresent(enc, forKey: .encryptedContent)
            try encodeMeta(meta)
        case .other:
            try container.encode("other", forKey: .type_)
        }
    }
}

// MARK: - InternalChatMessageMetadataPassthrough

public struct InternalChatMessageMetadataPassthrough: Codable, Equatable, Sendable {
    public var turnId: String?
    public var createTime: JSONValue?
    public var contentItemKinds: [ContentItemKind]?
    /// Host-owned; ignored on decode so requests cannot fake tool-call records.
    public var cellId: String?
    /// Warehouse-only; ignored on decode.
    public var executedToolCalls: [ExecutedToolCall]?
    /// Warehouse-only; ignored on decode.
    public var toolCallsComplete: Bool?

    enum CodingKeys: String, CodingKey {
        case turnId = "turn_id"
        case createTime = "create_time"
        case contentItemKinds = "content_item_kinds"
        case cellId = "cell_id"
        case executedToolCalls = "executed_tool_calls"
        case toolCallsComplete = "tool_calls_complete"
    }

    public init(
        turnId: String? = nil,
        createTime: JSONValue? = nil,
        contentItemKinds: [ContentItemKind]? = nil,
        cellId: String? = nil,
        executedToolCalls: [ExecutedToolCall]? = nil,
        toolCallsComplete: Bool? = nil
    ) {
        self.turnId = turnId; self.createTime = createTime
        self.contentItemKinds = contentItemKinds; self.cellId = cellId
        self.executedToolCalls = executedToolCalls
        self.toolCallsComplete = toolCallsComplete
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        turnId = try container.decodeIfPresent(String.self, forKey: .turnId)
        createTime = try container.decodeIfPresent(JSONValue.self, forKey: .createTime)
        contentItemKinds = try container.decodeIfPresent([ContentItemKind].self, forKey: .contentItemKinds)
        // skip_deserializing: cell_id, executed_tool_calls, tool_calls_complete
        cellId = nil
        executedToolCalls = nil
        toolCallsComplete = nil
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(turnId, forKey: .turnId)
        try container.encodeIfPresent(createTime, forKey: .createTime)
        try container.encodeIfPresent(contentItemKinds, forKey: .contentItemKinds)
        try container.encodeIfPresent(cellId, forKey: .cellId)
        try container.encodeIfPresent(executedToolCalls, forKey: .executedToolCalls)
        try container.encodeIfPresent(toolCallsComplete, forKey: .toolCallsComplete)
    }

    public static func setTurnIdIfMissing(
        _ metadata: inout InternalChatMessageMetadataPassthrough?,
        turnId: String
    ) {
        if turnId.isEmpty { return }
        if let existing = metadata?.turnId, !existing.isEmpty { return }
        if metadata == nil { metadata = InternalChatMessageMetadataPassthrough() }
        metadata?.turnId = turnId
    }
}

// MARK: - Image/Audio tag helpers

public let viewImageToolName = "view_image"

public func imageOpenTagText() -> String { "<image>" }
public func imageCloseTagText() -> String { "</image>" }

public func localImageLabelText(_ labelNumber: Int) -> String {
    "[Image #\(labelNumber)]"
}

public func localImageOpenTagTextWithPath(_ labelNumber: Int, path: String) -> String {
    let label = localImageLabelText(labelNumber)
    return "<image name=\(label) path=\"\(path)\">"
}

public func isLocalImageOpenTagText(_ text: String) -> Bool {
    text.hasPrefix("<image name=") && text.hasSuffix(">")
}

public func isImageCloseTagText(_ text: String) -> Bool { text == "</image>" }
public func isLocalImageCloseTagText(_ text: String) -> Bool { isImageCloseTagText(text) }
public func isImageOpenTagText(_ text: String) -> Bool { text == "<image>" }

public func audioOpenTagText() -> String { "<audio>" }
public func audioCloseTagText() -> String { "</audio>" }

public func localAudioLabelText(_ labelNumber: Int) -> String {
    "[Audio #\(labelNumber)]"
}

public func localAudioOpenTagTextWithPath(_ labelNumber: Int, path: String) -> String {
    let label = localAudioLabelText(labelNumber)
    return "<audio name=\(label) path=\"\(path)\">"
}

public func isLocalAudioOpenTagText(_ text: String) -> Bool {
    text.hasPrefix("<audio name=") && text.hasSuffix(">")
}

public func isAudioCloseTagText(_ text: String) -> Bool { text == "</audio>" }
public func isLocalAudioCloseTagText(_ text: String) -> Bool { isAudioCloseTagText(text) }
public func isAudioOpenTagText(_ text: String) -> Bool { text == "<audio>" }

// MARK: - CallToolResult extensions

extension CallToolResult {
    public static func fromResult(_ result: Result<CallToolResult, any Error>) -> CallToolResult {
        switch result {
        case .success(let r): return r
        case .failure(let error): return .fromErrorText(error.localizedDescription)
        }
    }

    public static func fromStringResult(_ ok: CallToolResult?, error: String?) -> CallToolResult {
        if let ok { return ok }
        return .fromErrorText(error ?? "unknown error")
    }

    public static func fromErrorText(_ text: String) -> CallToolResult {
        CallToolResult(
            content: [.object(["type": .string("text"), "text": .string(text)])],
            structuredContent: nil,
            isError: true,
            meta: nil)
    }

    public var isSuccess: Bool {
        isError != true
    }

    public func asFunctionCallOutputPayload() -> FunctionCallOutputPayload {
        let contentItems = convertMcpContentToItems(content)
        if contentItems.contains(where: {
            if case .encryptedContent = $0 { return true }; return false
        }) {
            return FunctionCallOutputPayload(
                body: .contentItems(contentItems), success: isSuccess)
        }
        if let sc = structuredContent, sc != .null {
            let data = try? JSONEncoder().encode(sc)
            if let data, let str = String(data: data, encoding: .utf8) {
                return FunctionCallOutputPayload(body: .text(str), success: isSuccess)
            }
            return FunctionCallOutputPayload(body: .text("serialization error"), success: false)
        }
        return FunctionCallOutputPayload(body: .contentItems(contentItems), success: isSuccess)
    }
}

// MARK: - MCP content → FunctionCallOutputContentItem

private let codexEncryptedContentMetaKey = "codex/encryptedContent"
private let codexImageDetailMetaKey = "codex/imageDetail"

private func convertMcpContentToItems(_ contents: [JSONValue]) -> [FunctionCallOutputContentItem] {
    var items: [FunctionCallOutputContentItem] = []
    for content in contents {
        guard case .object(let obj) = content else {
            items.append(.inputText(text: "<content>"))
            continue
        }
        guard case .string(let type_)? = obj["type"] else {
            items.append(.inputText(text: "<content>"))
            continue
        }
        let item: FunctionCallOutputContentItem
        switch type_ {
        case "text":
            if case .string(let text)? = obj["text"] {
                if let meta = obj["_meta"],
                   case .object(let metaObj) = meta,
                   case .string(let enc)? = metaObj[codexEncryptedContentMetaKey] {
                    item = .encryptedContent(encryptedContent: enc)
                } else {
                    item = .inputText(text: text)
                }
            } else {
                item = .inputText(text: "<content>")
            }
        case "image":
            if case .string(let data)? = obj["data"] {
                let mimeType: String
                if case .string(let m)? = obj["mimeType"] ?? obj["mime_type"] {
                    mimeType = m
                } else {
                    mimeType = "application/octet-stream"
                }
                let imageUrl = data.hasPrefix("data:")
                    ? data : "data:\(mimeType);base64,\(data)"
                var detail: ImageDetail? = defaultImageDetail
                if let meta = obj["_meta"],
                   case .object(let metaObj) = meta,
                   case .string(let d)? = metaObj[codexImageDetailMetaKey] {
                    switch d {
                    case "auto": detail = .auto
                    case "low": detail = .low
                    case "high": detail = .high
                    case "original": detail = .original
                    default: break
                    }
                }
                item = .inputImage(image: .inline(imageUrl: imageUrl), detail: detail)
            } else {
                item = .inputText(text: "<content>")
            }
        case "audio":
            if case .string(let data)? = obj["data"] {
                let mimeType: String
                if case .string(let m)? = obj["mimeType"] ?? obj["mime_type"] {
                    mimeType = m
                } else {
                    mimeType = "application/octet-stream"
                }
                let audioUrl = data.hasPrefix("data:")
                    ? data : "data:\(mimeType);base64,\(data)"
                item = .inputAudio(audioUrl: audioUrl)
            } else {
                item = .inputText(text: "<content>")
            }
        default:
            let data = try? JSONEncoder().encode(content)
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<content>"
            item = .inputText(text: text)
        }
        items.append(item)
    }
    return items
}
