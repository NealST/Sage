//
//  lib.swift
//  FileSystem
//
//  Port of codex-rs/file-system/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Faithful port of the Rust `FileSystemSandboxContext` (PermissionProfile +
//  PathUri) plus ExecutorFileSystem / walk / exec-permission types.
//  The URL-based initializer, `followSymlinks`, `denyProtectedWrites`, and
//  `assertAllowed` are a Sage compatibility layer so ApplyPatch callers
//  (`SandboxedApplyPatchFileSystem`, tools/handlers/apply_patch.swift) still
//  compile. `shouldReadFromSandbox` / `shouldWriteIntoSandbox` derive from
//  PermissionProfile, not the old bool flags. `FileSystemReadStream` is an
//  `AsyncThrowingStream` stand-in for the Rust `Stream` wrapper.
//

import CodexProtocol
@preconcurrency import CodexUtils
import Foundation

/// Maximum chunk size returned by `ExecutorFileSystem.readFileStream`.
public let FILE_READ_CHUNK_SIZE: Int = 1024 * 1024
/// Maximum accepted directory depth for a filesystem walk.
public let MAX_WALK_DEPTH: Int = 64
/// Maximum accepted directory count, including the walk root.
public let MAX_WALK_DIRECTORIES: Int = 10_000
/// Maximum accepted number of directory entries to examine.
public let MAX_WALK_ENTRIES: Int = 50_000
/// Maximum estimated size of a walk response.
public let MAX_WALK_RESPONSE_BYTES: Int = 4 * 1024 * 1024
/// Per-entry or per-error overhead charged to the walk response budget.
public let WALK_RESPONSE_ITEM_OVERHEAD_BYTES: Int = 64

public struct ReadFileOptions: Equatable, Sendable {
    public var followSymlinks: Bool

    public init(followSymlinks: Bool = true) {
        self.followSymlinks = followSymlinks
    }

    public static let `default` = ReadFileOptions()
}

public struct WriteFileOptions: Equatable, Sendable {
    public var followSymlinks: Bool

    public init(followSymlinks: Bool = true) {
        self.followSymlinks = followSymlinks
    }

    public static let `default` = WriteFileOptions()
}

public struct GetMetadataOptions: Equatable, Sendable {
    public var followSymlinks: Bool

    public init(followSymlinks: Bool = true) {
        self.followSymlinks = followSymlinks
    }

    public static let `default` = GetMetadataOptions()
}

public struct CreateDirectoryOptions: Equatable, Sendable {
    public var recursive: Bool
    public var followSymlinks: Bool

    public init(recursive: Bool, followSymlinks: Bool) {
        self.recursive = recursive
        self.followSymlinks = followSymlinks
    }
}

public struct RemoveOptions: Equatable, Sendable {
    public var recursive: Bool
    public var force: Bool
    public var followSymlinks: Bool

    public init(recursive: Bool, force: Bool, followSymlinks: Bool) {
        self.recursive = recursive
        self.force = force
        self.followSymlinks = followSymlinks
    }
}

public struct CopyOptions: Equatable, Sendable {
    public var recursive: Bool

    public init(recursive: Bool) {
        self.recursive = recursive
    }
}

public struct FileMetadata: Equatable, Sendable {
    public var isDirectory: Bool
    public var isFile: Bool
    public var isSymlink: Bool
    /// Size in bytes.
    public var size: UInt64
    public var createdAtMs: Int64
    public var modifiedAtMs: Int64

    public init(
        isDirectory: Bool,
        isFile: Bool,
        isSymlink: Bool,
        size: UInt64,
        createdAtMs: Int64,
        modifiedAtMs: Int64
    ) {
        self.isDirectory = isDirectory
        self.isFile = isFile
        self.isSymlink = isSymlink
        self.size = size
        self.createdAtMs = createdAtMs
        self.modifiedAtMs = modifiedAtMs
    }
}

public struct ReadDirectoryEntry: Equatable, Sendable {
    public var fileName: String
    public var isDirectory: Bool
    public var isFile: Bool

    public init(fileName: String, isDirectory: Bool, isFile: Bool) {
        self.fileName = fileName
        self.isDirectory = isDirectory
        self.isFile = isFile
    }
}

/// Bounds for a recursive filesystem walk.
public struct WalkOptions: Equatable, Sendable {
    /// Maximum directory depth below the root that may be traversed.
    public var maxDepth: Int
    /// Maximum number of directories that may be traversed, including the root.
    public var maxDirectories: Int
    /// Maximum number of directory entries that may be examined.
    public var maxEntries: Int
    /// Whether directory symlinks should be followed.
    public var followDirectorySymlinks: Bool
    /// Whether directories whose names start with `.` should be returned but not traversed.
    public var pruneHiddenDirectories: Bool

    public init(
        maxDepth: Int,
        maxDirectories: Int,
        maxEntries: Int,
        followDirectorySymlinks: Bool,
        pruneHiddenDirectories: Bool = false
    ) {
        self.maxDepth = maxDepth
        self.maxDirectories = maxDirectories
        self.maxEntries = maxEntries
        self.followDirectorySymlinks = followDirectorySymlinks
        self.pruneHiddenDirectories = pruneHiddenDirectories
    }
}

extension WalkOptions: Codable {
    enum CodingKeys: String, CodingKey {
        case maxDepth
        case maxDirectories
        case maxEntries
        case followDirectorySymlinks
        case pruneHiddenDirectories
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maxDepth = try container.decode(Int.self, forKey: .maxDepth)
        maxDirectories = try container.decode(Int.self, forKey: .maxDirectories)
        maxEntries = try container.decode(Int.self, forKey: .maxEntries)
        followDirectorySymlinks = try container.decode(Bool.self, forKey: .followDirectorySymlinks)
        pruneHiddenDirectories = try container.decodeIfPresent(Bool.self, forKey: .pruneHiddenDirectories) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(maxDepth, forKey: .maxDepth)
        try container.encode(maxDirectories, forKey: .maxDirectories)
        try container.encode(maxEntries, forKey: .maxEntries)
        try container.encode(followDirectorySymlinks, forKey: .followDirectorySymlinks)
        if pruneHiddenDirectories {
            try container.encode(pruneHiddenDirectories, forKey: .pruneHiddenDirectories)
        }
    }
}

/// Type of a filesystem entry returned by a walk.
public enum WalkEntryKind: String, Codable, Equatable, Sendable {
    case directory
    case file
}

/// One entry returned by a walk.
public struct WalkEntry: Codable, Equatable, Sendable {
    public var path: PathUri
    public var kind: WalkEntryKind

    public init(path: PathUri, kind: WalkEntryKind) {
        self.path = path
        self.kind = kind
    }
}

/// A descendant that could not be inspected during a walk.
public struct WalkError: Codable, Equatable, Sendable {
    public var path: PathUri
    public var message: String

    public init(path: PathUri, message: String) {
        self.path = path
        self.message = message
    }
}

/// Entries and recoverable errors collected by a bounded walk.
public struct WalkOutcome: Codable, Equatable, Sendable {
    public var entries: [WalkEntry]
    public var errors: [WalkError]
    public var truncated: Bool

    public init(entries: [WalkEntry] = [], errors: [WalkError] = [], truncated: Bool = false) {
        self.entries = entries
        self.errors = errors
        self.truncated = truncated
    }
}

public enum ExecFileSystemPath: Equatable, Hashable, Sendable {
    case path(path: PathUri)
    case globPattern(pattern: String)
    case special(value: FileSystemSpecialPath)
}

extension ExecFileSystemPath {
    public init(_ value: FileSystemPath) {
        switch value {
        case .path(let path):
            self = .path(path: path)
        case .globPattern(let pattern):
            self = .globPattern(pattern: pattern)
        case .special(let value):
            self = .special(value: value)
        }
    }
}

extension FileSystemPath {
    public init(_ value: ExecFileSystemPath) {
        switch value {
        case .path(let path):
            self = .path(path: path)
        case .globPattern(let pattern):
            self = .globPattern(pattern: pattern)
        case .special(let value):
            self = .special(value: value)
        }
    }
}

extension ExecFileSystemPath: Codable {
    private enum TypeKey: String, CodingKey { case type_ = "type" }
    private enum Keys: String, CodingKey { case type_ = "type", path, pattern, value }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decode(String.self, forKey: .type_)
        let keys = try decoder.container(keyedBy: Keys.self)
        switch type_ {
        case "path":
            self = .path(path: try keys.decode(PathUri.self, forKey: .path))
        case "glob_pattern":
            self = .globPattern(pattern: try keys.decode(String.self, forKey: .pattern))
        case "special":
            self = .special(value: try keys.decode(FileSystemSpecialPath.self, forKey: .value))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type_, in: container,
                debugDescription: "Unknown ExecFileSystemPath: \(type_)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        switch self {
        case .path(let path):
            try container.encode("path", forKey: .type_)
            try container.encode(path, forKey: .path)
        case .globPattern(let pattern):
            try container.encode("glob_pattern", forKey: .type_)
            try container.encode(pattern, forKey: .pattern)
        case .special(let value):
            try container.encode("special", forKey: .type_)
            try container.encode(value, forKey: .value)
        }
    }
}

public struct ExecFileSystemSandboxEntry: Equatable, Hashable, Sendable {
    public var path: ExecFileSystemPath
    public var access: FileSystemAccessMode
    public var missingPathBehavior: FileSystemSandboxEntryMissingPathBehavior?

    public init(
        path: ExecFileSystemPath,
        access: FileSystemAccessMode,
        missingPathBehavior: FileSystemSandboxEntryMissingPathBehavior? = nil
    ) {
        self.path = path
        self.access = access
        self.missingPathBehavior = missingPathBehavior
    }

    public init(_ value: FileSystemSandboxEntry) {
        self.init(
            path: ExecFileSystemPath(value.path),
            access: value.access,
            missingPathBehavior: value.missingPathBehavior
        )
    }
}

extension FileSystemSandboxEntry {
    public init(_ value: ExecFileSystemSandboxEntry) {
        self.init(
            path: FileSystemPath(value.path),
            access: value.access,
            missingPathBehavior: value.missingPathBehavior
        )
    }
}

extension ExecFileSystemSandboxEntry: Codable {
    enum CodingKeys: String, CodingKey {
        case path
        case access
        case missingPathBehavior = "missing_path_behavior"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(ExecFileSystemPath.self, forKey: .path)
        access = try container.decode(FileSystemAccessMode.self, forKey: .access)
        missingPathBehavior = try container.decodeIfPresent(
            FileSystemSandboxEntryMissingPathBehavior.self,
            forKey: .missingPathBehavior
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(access, forKey: .access)
        try container.encodeIfPresent(missingPathBehavior, forKey: .missingPathBehavior)
    }
}

public enum ExecManagedFileSystemPermissions: Equatable, Hashable, Sendable {
    case restricted(entries: [ExecFileSystemSandboxEntry], globScanMaxDepth: Int?)
    case unrestricted

    public init(_ value: ManagedFileSystemPermissions) {
        switch value {
        case .restricted(let entries, let globScanMaxDepth):
            self = .restricted(
                entries: entries.map(ExecFileSystemSandboxEntry.init),
                globScanMaxDepth: globScanMaxDepth
            )
        case .unrestricted:
            self = .unrestricted
        }
    }
}

extension ManagedFileSystemPermissions {
    public init(_ value: ExecManagedFileSystemPermissions) {
        switch value {
        case .restricted(let entries, let globScanMaxDepth):
            self = .restricted(
                entries: entries.map(FileSystemSandboxEntry.init),
                globScanMaxDepth: globScanMaxDepth
            )
        case .unrestricted:
            self = .unrestricted
        }
    }
}

extension ExecManagedFileSystemPermissions: Codable {
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
            let depth = try keys.decodeIfPresent(Int.self, forKey: .globScanMaxDepth)
            self = .restricted(
                entries: try keys.decode([ExecFileSystemSandboxEntry].self, forKey: .entries),
                globScanMaxDepth: depth.flatMap { $0 > 0 ? $0 : nil }
            )
        case "unrestricted":
            self = .unrestricted
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type_, in: container,
                debugDescription: "Unknown ExecManagedFileSystemPermissions: \(type_)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        switch self {
        case .restricted(let entries, let globScanMaxDepth):
            try container.encode("restricted", forKey: .type_)
            try container.encode(entries, forKey: .entries)
            try container.encodeIfPresent(globScanMaxDepth, forKey: .globScanMaxDepth)
        case .unrestricted:
            try container.encode("unrestricted", forKey: .type_)
        }
    }
}

/// Executor permission profile whose explicit filesystem paths serialize as file URIs.
public enum ExecPermissionProfile: Equatable, Sendable {
    case managed(fileSystem: ExecManagedFileSystemPermissions, network: NetworkSandboxPolicy)
    case disabled
    case external(network: NetworkSandboxPolicy)

    public init(_ value: PermissionProfile) {
        switch value {
        case .managed(let fileSystem, let network):
            self = .managed(fileSystem: ExecManagedFileSystemPermissions(fileSystem), network: network)
        case .disabled:
            self = .disabled
        case .external(let network):
            self = .external(network: network)
        }
    }
}

extension PermissionProfile {
    public init(_ value: ExecPermissionProfile) {
        switch value {
        case .managed(let fileSystem, let network):
            self = .managed(fileSystem: ManagedFileSystemPermissions(fileSystem), network: network)
        case .disabled:
            self = .disabled
        case .external(let network):
            self = .external(network: network)
        }
    }
}

extension ExecPermissionProfile: Codable {
    private enum TypeKey: String, CodingKey { case type_ = "type" }
    private enum Keys: String, CodingKey {
        case type_ = "type"
        case fileSystem = "file_system"
        case network
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decode(String.self, forKey: .type_)
        let keys = try decoder.container(keyedBy: Keys.self)
        switch type_ {
        case "managed":
            self = .managed(
                fileSystem: try keys.decode(ExecManagedFileSystemPermissions.self, forKey: .fileSystem),
                network: try keys.decode(NetworkSandboxPolicy.self, forKey: .network)
            )
        case "disabled":
            self = .disabled
        case "external":
            self = .external(network: try keys.decode(NetworkSandboxPolicy.self, forKey: .network))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type_, in: container,
                debugDescription: "Unknown ExecPermissionProfile: \(type_)")
        }
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

/// Windows sandbox choice encoded in executor RPCs.
///
/// The serialized field retains its legacy `windowsSandboxLevel` name for compatibility, but MXC
/// is a sandbox implementation rather than a RestrictedToken level.
public enum WindowsSandboxSelection: String, Codable, Equatable, Hashable, Sendable {
    case disabled
    case restrictedToken = "restricted-token"
    case elevated
    case mxc

    public init(_ level: WindowsSandboxLevel) {
        switch level {
        case .disabled: self = .disabled
        case .restrictedToken: self = .restrictedToken
        case .elevated: self = .elevated
        }
    }
}

/// Filesystem sandbox policy and the selected executor paths needed to interpret it.
public struct FileSystemSandboxContext: Equatable, Sendable {
    /// Serializes paths as executor file URIs instead of the profile's default native paths.
    public var permissions: PermissionProfile
    /// Working directory on the selected executor used to interpret sandbox permissions.
    /// Required even for absolute permissions; a process may use a different working directory.
    public var cwd: PathUri
    public var workspaceRoots: [PathUri]
    /// Executor-local user home used to resolve home-relative policy paths.
    public var userHomeDir: PathUri?
    /// Executor-local default directories used to resolve `:tmpdir` policy entries.
    public var temporaryDirectories: [PathUri]?
    public var windowsSandboxSelection: WindowsSandboxSelection
    public var windowsSandboxProxySettingsMode: WindowsSandboxProxySettingsMode?
    public var useLegacyLandlock: Bool

    /// Sage ApplyPatch compatibility: not present on the Rust type.
    /// Used by `ApplyPatchOptions.followSymlinks` and `assertAllowed`.
    public var followSymlinks: Bool
    /// Sage ApplyPatch compatibility: blocks writes under `.git` / `.sage` / `.agents`.
    public var denyProtectedWrites: Bool

    public init(
        permissions: PermissionProfile,
        cwd: PathUri,
        workspaceRoots: [PathUri] = [],
        userHomeDir: PathUri? = nil,
        temporaryDirectories: [PathUri]? = nil,
        windowsSandboxSelection: WindowsSandboxSelection = .disabled,
        windowsSandboxProxySettingsMode: WindowsSandboxProxySettingsMode? = nil,
        useLegacyLandlock: Bool = false,
        followSymlinks: Bool = true,
        denyProtectedWrites: Bool = false
    ) {
        self.permissions = permissions
        self.cwd = cwd
        self.workspaceRoots = workspaceRoots
        self.userHomeDir = userHomeDir
        self.temporaryDirectories = temporaryDirectories
        self.windowsSandboxSelection = windowsSandboxSelection
        self.windowsSandboxProxySettingsMode = windowsSandboxProxySettingsMode
        self.useLegacyLandlock = useLegacyLandlock
        self.followSymlinks = followSymlinks
        self.denyProtectedWrites = denyProtectedWrites
    }

    public static func fromLegacySandboxPolicy(
        _ sandboxPolicy: SandboxPolicy,
        cwd: PathUri
    ) throws -> FileSystemSandboxContext {
        // Legacy policy projection materializes native roots, so convert at the receiving-host
        // boundary while retaining the URI in the resulting sandbox context.
        let nativeCwd = try cwd.toAbsPath()
        let fileSystemSandboxPolicy = FileSystemSandboxPolicy.fromLegacySandboxPolicyForCwd(
            sandboxPolicy,
            cwd: nativeCwd.asPath
        )
        let permissions = PermissionProfile.fromRuntimePermissionsWithEnforcement(
            .fromLegacySandboxPolicy(sandboxPolicy),
            fileSystemSandboxPolicy,
            NetworkSandboxPolicy(sandboxPolicy)
        )
        return fromPermissionProfile(permissions, cwd: cwd)
    }

    public static func fromPermissionProfile(
        _ permissions: PermissionProfile,
        cwd: PathUri
    ) -> FileSystemSandboxContext {
        FileSystemSandboxContext(
            permissions: permissions,
            cwd: cwd,
            workspaceRoots: [cwd],
            userHomeDir: nil,
            temporaryDirectories: nil,
            windowsSandboxSelection: .disabled,
            windowsSandboxProxySettingsMode: nil,
            useLegacyLandlock: false
        )
    }

    /// Whether filesystem reads need a platform sandbox on the selected executor.
    public var shouldReadFromSandbox: Bool {
        !permissions
            .fileSystemSandboxPolicy()
            .hasFullDiskReadAccess(for: cwd.inferPathConvention())
    }

    /// Whether filesystem writes need a platform sandbox on the selected executor.
    public var shouldWriteIntoSandbox: Bool {
        !permissions
            .fileSystemSandboxPolicy()
            .hasFullDiskWriteAccess(for: cwd.inferPathConvention())
    }

    /// Whether this context selects either supported Windows sandbox implementation.
    public var windowsSandboxIsRequested: Bool {
        windowsSandboxSelection != .disabled
    }

    /// Checks that explicit permission paths can be enforced by the current host. An
    /// orchestrator can still construct this context with paths belonging to another executor.
    public func validateFileSystemPathsForCurrentHost() throws {
        if case .managed(let fileSystem, _) = permissions,
           case .restricted(let entries, _) = fileSystem
        {
            for entry in entries {
                if case .path(let path) = entry.path {
                    do {
                        _ = try path.toAbsPath()
                    } catch {
                        throw IOError.invalidInput("invalid sandbox permission path URI: \(error)")
                    }
                }
            }
        }
    }

    /// Borrows the executor-owned paths needed to interpret filesystem policy entries.
    public func policyContext() -> FileSystemSandboxPolicyContext {
        FileSystemSandboxPolicyContext(
            cwd: cwd,
            workspaceRoots: workspaceRoots,
            userHomeDir: userHomeDir,
            temporaryDirectories: temporaryDirectories
        )
    }
}

extension FileSystemSandboxContext: Codable {
    enum CodingKeys: String, CodingKey {
        case permissions
        case cwd
        case workspaceRoots
        case userHomeDir
        case temporaryDirectories
        case windowsSandboxSelection = "windowsSandboxLevel"
        case windowsSandboxProxySettingsMode
        case useLegacyLandlock
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        permissions = try ExecPermissionProfileSerde.decode(from: decoder, container: container, key: .permissions)
        cwd = try container.decode(PathUri.self, forKey: .cwd)
        workspaceRoots = try container.decodeIfPresent([PathUri].self, forKey: .workspaceRoots) ?? []
        userHomeDir = try container.decodeIfPresent(PathUri.self, forKey: .userHomeDir)
        temporaryDirectories = try container.decodeIfPresent([PathUri].self, forKey: .temporaryDirectories)
        windowsSandboxSelection = try container.decode(WindowsSandboxSelection.self, forKey: .windowsSandboxSelection)
        windowsSandboxProxySettingsMode = try container.decodeIfPresent(
            WindowsSandboxProxySettingsMode.self,
            forKey: .windowsSandboxProxySettingsMode
        )
        useLegacyLandlock = try container.decodeIfPresent(Bool.self, forKey: .useLegacyLandlock) ?? false
        followSymlinks = true
        denyProtectedWrites = false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try ExecPermissionProfileSerde.encode(permissions, to: &container, key: .permissions)
        try container.encode(cwd, forKey: .cwd)
        if !workspaceRoots.isEmpty {
            try container.encode(workspaceRoots, forKey: .workspaceRoots)
        }
        try container.encodeIfPresent(userHomeDir, forKey: .userHomeDir)
        try container.encodeIfPresent(temporaryDirectories, forKey: .temporaryDirectories)
        try container.encode(windowsSandboxSelection, forKey: .windowsSandboxSelection)
        try container.encodeIfPresent(windowsSandboxProxySettingsMode, forKey: .windowsSandboxProxySettingsMode)
        if useLegacyLandlock {
            try container.encode(useLegacyLandlock, forKey: .useLegacyLandlock)
        }
    }
}

/// Filesystem RPC wire context; older clients can omit the policy cwd before executor resolution.
public struct WireFileSystemSandboxContext: Codable {
    public var permissions: ExecPermissionProfile
    public var cwd: PathUri?
    public var policyContext: WireFileSystemPolicyContext?
    public var workspaceRoots: [PathUri]
    public var userHomeDir: PathUri?
    public var temporaryDirectories: [PathUri]?
    public var windowsSandboxSelection: WindowsSandboxSelection
    public var windowsSandboxProxySettingsMode: WindowsSandboxProxySettingsMode?
    public var useLegacyLandlock: Bool

    enum CodingKeys: String, CodingKey {
        case permissions
        case cwd
        case policyContext
        case workspaceRoots
        case userHomeDir
        case temporaryDirectories
        case windowsSandboxSelection = "windowsSandboxLevel"
        case windowsSandboxProxySettingsMode
        case useLegacyLandlock
    }

    public init(
        permissions: ExecPermissionProfile,
        cwd: PathUri? = nil,
        policyContext: WireFileSystemPolicyContext? = nil,
        workspaceRoots: [PathUri] = [],
        userHomeDir: PathUri? = nil,
        temporaryDirectories: [PathUri]? = nil,
        windowsSandboxSelection: WindowsSandboxSelection = .disabled,
        windowsSandboxProxySettingsMode: WindowsSandboxProxySettingsMode? = nil,
        useLegacyLandlock: Bool = false
    ) {
        self.permissions = permissions
        self.cwd = cwd
        self.policyContext = policyContext
        self.workspaceRoots = workspaceRoots
        self.userHomeDir = userHomeDir
        self.temporaryDirectories = temporaryDirectories
        self.windowsSandboxSelection = windowsSandboxSelection
        self.windowsSandboxProxySettingsMode = windowsSandboxProxySettingsMode
        self.useLegacyLandlock = useLegacyLandlock
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        permissions = try container.decode(ExecPermissionProfile.self, forKey: .permissions)
        cwd = try container.decodeIfPresent(PathUri.self, forKey: .cwd)
        policyContext = try container.decodeIfPresent(WireFileSystemPolicyContext.self, forKey: .policyContext)
        workspaceRoots = try container.decodeIfPresent([PathUri].self, forKey: .workspaceRoots) ?? []
        userHomeDir = try container.decodeIfPresent(PathUri.self, forKey: .userHomeDir)
        temporaryDirectories = try container.decodeIfPresent([PathUri].self, forKey: .temporaryDirectories)
        windowsSandboxSelection = try container.decode(WindowsSandboxSelection.self, forKey: .windowsSandboxSelection)
        windowsSandboxProxySettingsMode = try container.decodeIfPresent(
            WindowsSandboxProxySettingsMode.self,
            forKey: .windowsSandboxProxySettingsMode
        )
        useLegacyLandlock = try container.decodeIfPresent(Bool.self, forKey: .useLegacyLandlock) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(permissions, forKey: .permissions)
        try container.encodeIfPresent(cwd, forKey: .cwd)
        try container.encodeIfPresent(policyContext, forKey: .policyContext)
        if !workspaceRoots.isEmpty {
            try container.encode(workspaceRoots, forKey: .workspaceRoots)
        }
        try container.encodeIfPresent(userHomeDir, forKey: .userHomeDir)
        try container.encodeIfPresent(temporaryDirectories, forKey: .temporaryDirectories)
        try container.encode(windowsSandboxSelection, forKey: .windowsSandboxSelection)
        try container.encodeIfPresent(windowsSandboxProxySettingsMode, forKey: .windowsSandboxProxySettingsMode)
        if useLegacyLandlock {
            try container.encode(useLegacyLandlock, forKey: .useLegacyLandlock)
        }
    }

    /// Returns the policy cwd supplied by the client, falling back to the legacy cwd field.
    public func resolvedCwd() -> PathUri? {
        if let policyContext {
            return policyContext.cwd ?? cwd
        }
        return cwd
    }

    /// Returns whether a legacy filesystem policy needs the client's cwd to be interpreted.
    public func requiresCwd() -> Bool {
        guard case .managed(let fileSystem, _) = permissions,
              case .restricted(let entries, _) = fileSystem
        else {
            return false
        }
        return entries.contains { entry in
            switch entry.path {
            case .globPattern(let pattern):
                return !pattern.hasPrefix("/")
            case .special(value: .projectRoots):
                return true
            case .path, .special:
                return false
            }
        }
    }

    /// Constructs the strict context after executor ingress has resolved the policy cwd.
    public func intoContext(_ cwd: PathUri) -> FileSystemSandboxContext {
        FileSystemSandboxContext(
            permissions: PermissionProfile(permissions),
            cwd: cwd,
            workspaceRoots: policyContext?.workspaceRoots ?? workspaceRoots,
            userHomeDir: userHomeDir,
            temporaryDirectories: temporaryDirectories,
            windowsSandboxSelection: windowsSandboxSelection,
            windowsSandboxProxySettingsMode: windowsSandboxProxySettingsMode,
            useLegacyLandlock: useLegacyLandlock
        )
    }
}

/// New filesystem clients provide these paths independently of the legacy helper launch cwd.
public struct WireFileSystemPolicyContext: Codable {
    public var cwd: PathUri?
    public var workspaceRoots: [PathUri]

    public init(cwd: PathUri? = nil, workspaceRoots: [PathUri] = []) {
        self.cwd = cwd
        self.workspaceRoots = workspaceRoots
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cwd = try container.decodeIfPresent(PathUri.self, forKey: .cwd)
        workspaceRoots = try container.decodeIfPresent([PathUri].self, forKey: .workspaceRoots) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(cwd, forKey: .cwd)
        if !workspaceRoots.isEmpty {
            try container.encode(workspaceRoots, forKey: .workspaceRoots)
        }
    }

    enum CodingKeys: String, CodingKey {
        case cwd
        case workspaceRoots
    }
}

extension WireFileSystemSandboxContext {
    public init(_ sandbox: FileSystemSandboxContext) {
        let permissions = ExecPermissionProfile(sandbox.permissions)
        let cwd = sandbox.cwd
        let workspaceRoots = sandbox.workspaceRoots
        let legacyNeedsCwd: Bool
        switch permissions {
        case .managed(let fileSystem, _):
            switch fileSystem {
            case .restricted(let entries, _):
                legacyNeedsCwd = entries.contains { entry in
                    switch entry.path {
                    case .globPattern(let pattern):
                        if let convention = cwd.inferPathConvention() {
                            return (try? LegacyAppPathString.fromString(pattern).toPathUri(convention)) == nil
                        }
                        return true
                    case .special(value: .projectRoots):
                        return true
                    case .path, .special:
                        return false
                    }
                }
            case .unrestricted:
                legacyNeedsCwd = false
            }
        case .disabled, .external:
            legacyNeedsCwd = false
        }
        self.init(
            permissions: permissions,
            cwd: legacyNeedsCwd ? cwd : nil,
            policyContext: WireFileSystemPolicyContext(cwd: cwd, workspaceRoots: workspaceRoots),
            workspaceRoots: legacyNeedsCwd ? workspaceRoots : [],
            userHomeDir: sandbox.userHomeDir,
            temporaryDirectories: sandbox.temporaryDirectories,
            windowsSandboxSelection: sandbox.windowsSandboxSelection,
            windowsSandboxProxySettingsMode: sandbox.windowsSandboxProxySettingsMode,
            useLegacyLandlock: sandbox.useLegacyLandlock
        )
    }
}

/// Stream of immutable chunks read from an `ExecutorFileSystem`.
public struct FileSystemReadStream: Sendable {
    public let stream: AsyncThrowingStream<Data, Error>

    public init(_ stream: AsyncThrowingStream<Data, Error>) {
        self.stream = stream
    }
}

/// Abstract filesystem access used by components that may operate locally or via
/// a remote environment.
///
/// Constrained to `AnyObject` so `EnvironmentAccessKey` can identify the
/// filesystem by object identity (Rust `Weak<dyn ExecutorFileSystem>`).
public protocol ExecutorFileSystem: AnyObject, Sendable {
    func canonicalize(
        _ path: PathUri,
        sandbox: FileSystemSandboxContext?
    ) async throws -> PathUri

    func readFile(
        _ path: PathUri,
        options: ReadFileOptions,
        sandbox: FileSystemSandboxContext?
    ) async throws -> [UInt8]

    /// Reads a file as a stream of chunks no larger than `FILE_READ_CHUNK_SIZE`.
    func readFileStream(
        _ path: PathUri,
        sandbox: FileSystemSandboxContext?
    ) async throws -> FileSystemReadStream

    func writeFile(
        _ path: PathUri,
        contents: [UInt8],
        options: WriteFileOptions,
        sandbox: FileSystemSandboxContext?
    ) async throws

    func createDirectory(
        _ path: PathUri,
        options: CreateDirectoryOptions,
        sandbox: FileSystemSandboxContext?
    ) async throws

    func getMetadata(
        _ path: PathUri,
        options: GetMetadataOptions,
        sandbox: FileSystemSandboxContext?
    ) async throws -> FileMetadata

    func readDirectory(
        _ path: PathUri,
        sandbox: FileSystemSandboxContext?
    ) async throws -> [ReadDirectoryEntry]

    /// Recursively lists descendants, optionally following directory symlinks.
    func walk(
        _ path: PathUri,
        options: WalkOptions,
        sandbox: FileSystemSandboxContext?
    ) async throws -> WalkOutcome

    func remove(
        _ path: PathUri,
        options: RemoveOptions,
        sandbox: FileSystemSandboxContext?
    ) async throws

    func copy(
        sourcePath: PathUri,
        destinationPath: PathUri,
        options: CopyOptions,
        sandbox: FileSystemSandboxContext?
    ) async throws
}

extension ExecutorFileSystem {
    /// Reads a file and decodes it as UTF-8 text.
    public func readFileText(
        _ path: PathUri,
        options: ReadFileOptions,
        sandbox: FileSystemSandboxContext?
    ) async throws -> String {
        let bytes = try await readFile(path, options: options, sandbox: sandbox)
        guard let text = String(bytes: bytes, encoding: .utf8) else {
            throw IOError.invalidData("file is not valid UTF-8: \(path)")
        }
        return text
    }
}

public enum FileSystemSandboxError: Error, Equatable, Sendable {
    case notPermitted(path: String, write: Bool)
}

// MARK: - ApplyPatch URL compatibility (adapted)

extension FileSystemSandboxContext {
    /// Sage-adapted initializer used by ApplyPatch. Builds a `PermissionProfile`
    /// from the legacy bool flags so `shouldReadFromSandbox` /
    /// `shouldWriteIntoSandbox` still derive from the profile.
    public init(
        cwd: URL,
        workspaceRoots: [URL],
        userHomeDir: URL? = nil,
        temporaryDirectories: [URL] = [],
        denyProtectedWrites: Bool,
        followSymlinks: Bool,
        fullDiskRead: Bool = false,
        fullDiskWrite: Bool = false
    ) {
        let cwdUri = pathUriFromFileURL(cwd)
        let rootUris = workspaceRoots.map(pathUriFromFileURL)
        let homeUri = userHomeDir.map(pathUriFromFileURL)
        let tempUris = temporaryDirectories.map(pathUriFromFileURL)
        let permissions: PermissionProfile
        if fullDiskWrite {
            permissions = .disabled
        } else if fullDiskRead {
            permissions = .readOnly()
        } else {
            let entries = (rootUris + [cwdUri]).map {
                FileSystemSandboxEntry.new(.path(path: $0), .write)
            }
            permissions = .managed(
                fileSystem: .restricted(entries: entries, globScanMaxDepth: nil),
                network: .restricted
            )
        }
        self.init(
            permissions: permissions,
            cwd: cwdUri,
            workspaceRoots: rootUris,
            userHomeDir: homeUri,
            temporaryDirectories: tempUris.isEmpty ? nil : tempUris,
            followSymlinks: followSymlinks,
            denyProtectedWrites: denyProtectedWrites
        )
    }

    public func assertAllowed(_ url: URL, write: Bool) throws {
        let standardized = url.standardizedFileURL
        if write, denyProtectedWrites, isProtected(standardized) {
            throw FileSystemSandboxError.notPermitted(path: standardized.path, write: true)
        }
        if !followSymlinks, isSymlink(standardized) {
            throw FileSystemSandboxError.notPermitted(path: standardized.path, write: write)
        }
        if write, !shouldWriteIntoSandbox { return }
        if !write, !shouldReadFromSandbox { return }
        guard isInsideWorkspace(standardized) else {
            throw FileSystemSandboxError.notPermitted(path: standardized.path, write: write)
        }
    }

    public func isProtected(_ url: URL) -> Bool {
        url.standardizedFileURL.pathComponents.contains { component in
            component == ".git" || component == ".sage" || component == ".agents"
        }
    }

    public func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
    }

    public func isInsideWorkspace(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        var roots = workspaceRoots.compactMap { try? $0.toAbsPath().asPath }
        if let cwdPath = try? cwd.toAbsPath().asPath {
            roots.append(cwdPath)
        }
        if let temps = temporaryDirectories {
            roots.append(contentsOf: temps.compactMap { try? $0.toAbsPath().asPath })
        }
        return roots.contains { root in
            path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
        }
    }
}

func pathUriFromFileURL(_ url: URL) -> PathUri {
    let path = url.standardizedFileURL.path
    if let abs = try? AbsolutePathBuf.fromAbsolutePath(path) {
        return PathUri.fromAbsPath(abs)
    }
    return PathUri.fromAbsPath(AbsolutePathBuf.resolvePathAgainstBase(path, basePath: "/"))
}
