//
//  permissions.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/permissions.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Filesystem and network sandbox policy types, read-deny matching, and
//  workspace-write defaults. globset is replaced by a POSIX glob matcher
//  built on NSRegularExpression (`*`, `?`, `**`, `[abc]`). Windows-only
//  filesystem walks are not ported. `normalize_system_aliases` is not on
//  AbsolutePathBuf yet; the helper below is an identity on POSIX/macOS.
//

import CodexUtils
import Foundation

let protectedMetadataGitPathName = ".git"
let protectedMetadataAgentsPathName = ".agents"
let protectedMetadataCodexPathName = ".codex"

/// Top-level workspace metadata paths that stay protected under writable roots.
public let PROTECTED_METADATA_PATH_NAMES: [String] = [
    protectedMetadataGitPathName,
    protectedMetadataAgentsPathName,
    protectedMetadataCodexPathName,
]

/// Returns true when a path basename is one of the protected workspace metadata names.
public func isProtectedMetadataName(_ name: String) -> Bool {
    PROTECTED_METADATA_PATH_NAMES.contains(name)
}

/// Returns the protected workspace metadata name when an agent write to `path`
/// should be blocked before execution.
public func forbiddenAgentMetadataWrite(
    path: String,
    cwd: String,
    fileSystemSandboxPolicy: FileSystemSandboxPolicy
) -> String? {
    guard fileSystemSandboxPolicy.kind == .restricted else { return nil }
    return withLocalPolicyContext(path: path, cwd: cwd) { path, context in
        fileSystemSandboxPolicy
            .metadataWriteDenial(path, context: context)
            .flatMap { name in
                fileSystemSandboxPolicy.canWritePath(path, context: context) ? nil : name
            }
    } ?? nil
}

public enum NetworkSandboxPolicy: String, Codable, Equatable, Hashable, Sendable {
    case restricted
    case enabled

    public var isEnabled: Bool { self == .enabled }
}

extension NetworkSandboxPolicy: CustomStringConvertible {
    public var description: String { rawValue }
}

/// Access mode for a filesystem entry.
///
/// When two equally specific entries target the same path, we compare these by
/// conflict precedence rather than by capability breadth: `deny` beats
/// `write`, and `write` beats `read`.
public enum FileSystemAccessMode: String, Equatable, Hashable, Sendable {
    case read
    case write
    case deny
}

extension FileSystemAccessMode: Comparable {
    public static func < (lhs: FileSystemAccessMode, rhs: FileSystemAccessMode) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .read: return 0
        case .write: return 1
        case .deny: return 2
        }
    }
}

extension FileSystemAccessMode: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "read": self = .read
        case "write": self = .write
        case "deny", "none": self = .deny
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown FileSystemAccessMode: \(raw)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension FileSystemAccessMode {
    public func canRead() -> Bool { self != .deny }
    public func canWrite() -> Bool { self == .write }
}

extension FileSystemAccessMode: CustomStringConvertible {
    public var description: String { rawValue }
}

public enum FileSystemSpecialPath: Equatable, Hashable, Sendable {
    case root
    case minimal
    case projectRoots(subpath: String?)
    case tmpdir
    case slashTmp
    case unknown(path: String, subpath: String?)

    public static func projectRoots(_ subpath: String?) -> FileSystemSpecialPath {
        .projectRoots(subpath: subpath)
    }

    public static func unknown(_ path: String, subpath: String?) -> FileSystemSpecialPath {
        .unknown(path: path, subpath: subpath)
    }
}

extension FileSystemSpecialPath: Codable {
    private enum KindKey: String, CodingKey { case kind }
    private enum Keys: String, CodingKey { case kind, path, subpath }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: KindKey.self)
        let kind = try container.decode(String.self, forKey: .kind)
        let keys = try decoder.container(keyedBy: Keys.self)
        switch kind {
        case "root":
            self = .root
        case "minimal":
            self = .minimal
        case "project_roots", "current_working_directory":
            self = .projectRoots(subpath: try keys.decodeIfPresent(String.self, forKey: .subpath))
        case "tmpdir":
            self = .tmpdir
        case "slash_tmp":
            self = .slashTmp
        case "unknown":
            self = .unknown(
                path: try keys.decode(String.self, forKey: .path),
                subpath: try keys.decodeIfPresent(String.self, forKey: .subpath))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: container,
                debugDescription: "Unknown FileSystemSpecialPath: \(kind)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        switch self {
        case .root:
            try container.encode("root", forKey: .kind)
        case .minimal:
            try container.encode("minimal", forKey: .kind)
        case .projectRoots(let subpath):
            try container.encode("project_roots", forKey: .kind)
            try container.encodeIfPresent(subpath, forKey: .subpath)
        case .tmpdir:
            try container.encode("tmpdir", forKey: .kind)
        case .slashTmp:
            try container.encode("slash_tmp", forKey: .kind)
        case .unknown(let path, let subpath):
            try container.encode("unknown", forKey: .kind)
            try container.encode(path, forKey: .path)
            try container.encodeIfPresent(subpath, forKey: .subpath)
        }
    }
}

public struct FileSystemSandboxEntry: Equatable, Hashable, Sendable {
    public var path: FileSystemPath
    public var access: FileSystemAccessMode
    public var missingPathBehavior: FileSystemSandboxEntryMissingPathBehavior?

    public init(
        path: FileSystemPath,
        access: FileSystemAccessMode,
        missingPathBehavior: FileSystemSandboxEntryMissingPathBehavior? = nil
    ) {
        self.path = path
        self.access = access
        self.missingPathBehavior = missingPathBehavior
    }

    public static func new(_ path: FileSystemPath, _ access: FileSystemAccessMode) -> FileSystemSandboxEntry {
        FileSystemSandboxEntry(path: path, access: access, missingPathBehavior: nil)
    }

    public static func skipMissingPath(
        _ path: FileSystemPath,
        _ access: FileSystemAccessMode
    ) -> FileSystemSandboxEntry {
        FileSystemSandboxEntry(path: path, access: access, missingPathBehavior: .skip)
    }

    public func skipsMissingPath() -> Bool {
        missingPathBehavior == .skip
    }
}

/// Serialized filesystem entry used at legacy string-based seams.
public struct RawFileSystemSandboxEntry: Codable, Equatable, Hashable, Sendable {
    public var path: RawFileSystemPath
    public var access: FileSystemAccessMode
    public var missingPathBehavior: FileSystemSandboxEntryMissingPathBehavior?

    enum CodingKeys: String, CodingKey {
        case path, access
        case missingPathBehavior = "missing_path_behavior"
    }

    public init(
        path: RawFileSystemPath,
        access: FileSystemAccessMode,
        missingPathBehavior: FileSystemSandboxEntryMissingPathBehavior? = nil
    ) {
        self.path = path
        self.access = access
        self.missingPathBehavior = missingPathBehavior
    }
}

public enum FileSystemSandboxEntryMissingPathBehavior: String, Codable, Equatable, Hashable, Sendable {
    case skip
}

public enum FileSystemSandboxKind: String, Codable, Equatable, Hashable, Sendable {
    case restricted
    case unrestricted
    case externalSandbox = "external-sandbox"
}

extension FileSystemSandboxKind: CustomStringConvertible {
    public var description: String { rawValue }
}

public struct FileSystemSandboxPolicy: Equatable, Sendable {
    public var kind: FileSystemSandboxKind
    public var globScanMaxDepth: Int?
    public var entries: [FileSystemSandboxEntry]

    public init(
        kind: FileSystemSandboxKind,
        globScanMaxDepth: Int? = nil,
        entries: [FileSystemSandboxEntry] = []
    ) {
        self.kind = kind
        self.globScanMaxDepth = globScanMaxDepth
        self.entries = entries
    }
}

enum WritableRootPathResolution {
    case effective
    case preserveMutableComponents

    func resolve(_ path: AbsolutePathBuf) -> AbsolutePathBuf {
        switch self {
        case .effective:
            return normalizeEffectiveAbsolutePath(path)
        case .preserveMutableComponents:
            return (try? path.normalizeSystemAliases()) ?? path
        }
    }
}

/// Serialized filesystem policy used at legacy string-based seams.
public struct RawFileSystemSandboxPolicy: Codable, Equatable, Sendable {
    public var kind: FileSystemSandboxKind
    public var globScanMaxDepth: Int?
    public var entries: [RawFileSystemSandboxEntry]

    enum CodingKeys: String, CodingKey {
        case kind
        case globScanMaxDepth = "glob_scan_max_depth"
        case entries
    }

    public init(
        kind: FileSystemSandboxKind,
        globScanMaxDepth: Int? = nil,
        entries: [RawFileSystemSandboxEntry] = []
    ) {
        self.kind = kind
        self.globScanMaxDepth = globScanMaxDepth
        self.entries = entries
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(FileSystemSandboxKind.self, forKey: .kind)
        globScanMaxDepth = try container.decodeIfPresent(Int.self, forKey: .globScanMaxDepth)
        entries = try container.decodeIfPresent([RawFileSystemSandboxEntry].self, forKey: .entries) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(globScanMaxDepth, forKey: .globScanMaxDepth)
        if !entries.isEmpty {
            try container.encode(entries, forKey: .entries)
        }
    }
}

/// Executor-owned paths needed to interpret filesystem sandbox policy entries.
public struct FileSystemSandboxPolicyContext: Equatable, Sendable {
    public var cwd: PathUri
    public var workspaceRoots: [PathUri]
    public var userHomeDir: PathUri?
    public var temporaryDirectories: [PathUri]?

    public init(
        cwd: PathUri,
        workspaceRoots: [PathUri],
        userHomeDir: PathUri? = nil,
        temporaryDirectories: [PathUri]? = nil
    ) {
        self.cwd = cwd
        self.workspaceRoots = workspaceRoots
        self.userHomeDir = userHomeDir
        self.temporaryDirectories = temporaryDirectories
    }
}

struct ResolvedFileSystemEntry: Equatable {
    var path: AbsolutePathBuf
    var access: FileSystemAccessMode
}

struct PreparedFileSystemEntry {
    var entry: ResolvedFileSystemEntry
    var effectivePath: AbsolutePathBuf
}

struct FileSystemSemanticSignature: Equatable {
    var hasFullDiskReadAccess: Bool
    var hasFullDiskWriteAccess: Bool
    var includePlatformDefaults: Bool
    var readableRoots: [AbsolutePathBuf]
    var writableRoots: [WritableRoot]
    var unreadableRoots: [AbsolutePathBuf]
    var unreadableGlobs: [String]
}

/// Runtime matcher for read-deny entries in a filesystem sandbox policy.
public struct ReadDenyMatcher {
    var nativeCwd: AbsolutePathBuf?
    var userHomeDir: PathUri?
    var temporaryDirectories: [PathUri]
    var prepared: PreparedReadDenyMatcher
}

/// Prepared PathUri deny roots and globs for repeated executor-owned read checks.
struct PreparedReadDenyMatcher {
    var deniedRoots: [PathUri]
    var denyReadMatchers: [GlobMatcher]
    var invalidPattern: Bool
}

extension ReadDenyMatcher {
    /// Builds a matcher for executor-owned URI paths without host projection.
    public static func fromContext(
        _ fileSystemSandboxPolicy: FileSystemSandboxPolicy,
        context: FileSystemSandboxPolicyContext
    ) -> ReadDenyMatcher? {
        guard fileSystemSandboxPolicy.entries.contains(where: { $0.access == .deny }) else {
            return nil
        }
        guard let prepared = try? fileSystemSandboxPolicy.prepareDenyReadMatcher(
            context: context,
            invalidGlobBehavior: .failClosed
        ) else {
            return nil
        }
        return ReadDenyMatcher(
            nativeCwd: nil,
            userHomeDir: nil,
            temporaryDirectories: [],
            prepared: prepared
        )
    }

    /// Builds a local-path matcher for callers that must reject malformed glob patterns.
    public static func tryNewForLocalPaths(
        _ fileSystemSandboxPolicy: FileSystemSandboxPolicy,
        cwd: String
    ) throws -> ReadDenyMatcher? {
        try build(fileSystemSandboxPolicy, cwd: cwd, invalidGlobBehavior: .returnError)
    }

    static func build(
        _ fileSystemSandboxPolicy: FileSystemSandboxPolicy,
        cwd: String,
        invalidGlobBehavior: InvalidDenyReadGlobBehavior
    ) throws -> ReadDenyMatcher? {
        if !fileSystemSandboxPolicy.hasDeniedReadRestrictions() {
            return nil
        }
        let cwdAbs: AbsolutePathBuf
        do {
            cwdAbs = try AbsolutePathBuf.fromAbsolutePath(cwd)
        } catch {
            throw PermissionStringError("invalid read-deny cwd: \(error)")
        }
        let cwdUri = PathUri.fromAbsPath(cwdAbs)
        let userHomeDir = try? PathUri.fromHostNativePath("~")
        let temporaryDirectories = localTemporaryDirectories()
        let context = FileSystemSandboxPolicyContext(
            cwd: cwdUri,
            workspaceRoots: [cwdUri],
            userHomeDir: userHomeDir,
            temporaryDirectories: temporaryDirectories
        )
        let prepared = try fileSystemSandboxPolicy.prepareDenyReadMatcher(
            context: context,
            invalidGlobBehavior: invalidGlobBehavior
        )
        return ReadDenyMatcher(
            nativeCwd: cwdAbs,
            userHomeDir: userHomeDir,
            temporaryDirectories: temporaryDirectories,
            prepared: prepared
        )
    }

    /// Returns whether a local native `path` is denied by this matcher.
    public func isLocalPathReadDenied(_ path: String) -> Bool {
        guard let cwd = nativeCwd else { return true }
        guard let resolved = resolveCandidatePath(path, cwd: cwd.asPath) else { return true }
        let path = PathUri(resolved)
        let cwdUri = PathUri.fromAbsPath(cwd)
        let context = FileSystemSandboxPolicyContext(
            cwd: cwdUri,
            workspaceRoots: [cwdUri],
            userHomeDir: userHomeDir,
            temporaryDirectories: temporaryDirectories
        )
        return isReadDeniedUri(path, context: context)
    }

    /// Returns whether an executor-owned URI is denied under its matching path context.
    public func isReadDeniedUri(_ path: PathUri, context: FileSystemSandboxPolicyContext) -> Bool {
        FileSystemSandboxPolicy.matchesPreparedReadDeny(path, context: context, prepared: prepared)
    }

    public func isLocalPathReadDeniedWithCanonicalPath(_ path: String, canonicalPath: String) -> Bool {
        isLocalPathReadDenied(path) || isLocalPathReadDenied(canonicalPath)
    }
}

enum InvalidDenyReadGlobBehavior {
    case failClosed
    case returnError
}

struct PermissionStringError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

public enum FileSystemPath: Equatable, Hashable, Sendable {
    case path(path: PathUri)
    /// A git-style glob pattern. Pattern entries currently support
    /// FileSystemAccessMode.deny only.
    case globPattern(pattern: String)
    case special(value: FileSystemSpecialPath)
}

/// Serialized filesystem path whose literal path variant preserves the raw
/// legacy string until an explicit seam conversion selects its meaning.
public enum RawFileSystemPath: Equatable, Hashable, Sendable {
    case path(path: LegacyAppPathString)
    case globPattern(pattern: String)
    case special(value: FileSystemSpecialPath)
}

extension RawFileSystemPath: Codable {
    private enum TypeKey: String, CodingKey { case type_ = "type" }
    private enum Keys: String, CodingKey { case type_ = "type", path, pattern, value }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decode(String.self, forKey: .type_)
        let keys = try decoder.container(keyedBy: Keys.self)
        switch type_ {
        case "path":
            self = .path(path: try keys.decode(LegacyAppPathString.self, forKey: .path))
        case "glob_pattern":
            self = .globPattern(pattern: try keys.decode(String.self, forKey: .pattern))
        case "special":
            self = .special(value: try keys.decode(FileSystemSpecialPath.self, forKey: .value))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type_, in: container,
                debugDescription: "Unknown RawFileSystemPath: \(type_)")
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

extension FileSystemPath {
    public init(_ path: AbsolutePathBuf) {
        self = .path(path: PathUri(path))
    }

    public init(_ path: PathUri) {
        self = .path(path: path)
    }
}

func pathUriFromRaw(_ path: LegacyAppPathString) throws -> PathUri {
    if let decoded = try? JSONDecoder().decode(AbsolutePathBuf.self, from: Data("\"\(escapeJsonString(path.asStr()))\"".utf8)) {
        return PathUri(decoded)
    }
    if let abs = try? AbsolutePathBuf.fromAbsolutePath(path.asStr()) {
        return PathUri(abs)
    }
    do {
        return try PathUri(fromLegacy: path)
    } catch {
        throw PermissionStringError(String(describing: error))
    }
}

func rawPathFromUri(_ path: PathUri) throws -> LegacyAppPathString {
    let rawPath = LegacyAppPathString(path)
    let roundTrip = try pathUriFromRaw(rawPath)
    if roundTrip == path {
        return rawPath
    }
    throw PermissionStringError("permission path cannot be represented losslessly")
}

func escapeJsonString(_ string: String) -> String {
    string
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

extension FileSystemPath {
    public init(_ raw: RawFileSystemPath) throws {
        switch raw {
        case .path(let path):
            self = .path(path: try pathUriFromRaw(path))
        case .globPattern(let pattern):
            self = .globPattern(pattern: pattern)
        case .special(let value):
            self = .special(value: value)
        }
    }
}

extension RawFileSystemPath {
    public init(_ path: FileSystemPath) throws {
        switch path {
        case .path(let path):
            self = .path(path: try rawPathFromUri(path))
        case .globPattern(let pattern):
            self = .globPattern(pattern: pattern)
        case .special(let value):
            self = .special(value: value)
        }
    }
}

extension FileSystemSandboxEntry {
    public init(_ entry: RawFileSystemSandboxEntry) throws {
        self.init(
            path: try FileSystemPath(entry.path),
            access: entry.access,
            missingPathBehavior: entry.missingPathBehavior
        )
    }
}

extension RawFileSystemSandboxEntry {
    public init(_ entry: FileSystemSandboxEntry) throws {
        self.init(
            path: try RawFileSystemPath(entry.path),
            access: entry.access,
            missingPathBehavior: entry.missingPathBehavior
        )
    }
}

extension FileSystemSandboxPolicy {
    public init(_ policy: RawFileSystemSandboxPolicy) throws {
        self.init(
            kind: policy.kind,
            globScanMaxDepth: policy.globScanMaxDepth,
            entries: try policy.entries.map { try FileSystemSandboxEntry($0) }
        )
    }
}

extension RawFileSystemSandboxPolicy {
    public init(_ policy: FileSystemSandboxPolicy) throws {
        self.init(
            kind: policy.kind,
            globScanMaxDepth: policy.globScanMaxDepth,
            entries: try policy.entries.map { try RawFileSystemSandboxEntry($0) }
        )
    }
}

let projectRootsGlobPatternPrefix = "codex-project-roots://"

public func projectRootsGlobPattern(_ subpath: String) -> String {
    "\(projectRootsGlobPatternPrefix)\(subpath)"
}

func readOnlyFileSystemEntries() -> [FileSystemSandboxEntry] {
    [FileSystemSandboxEntry.new(.special(value: .root), .read)]
}

extension FileSystemSandboxPolicy {
    public static func readOnly() -> FileSystemSandboxPolicy {
        restricted(readOnlyFileSystemEntries())
    }

    public static func unrestricted() -> FileSystemSandboxPolicy {
        FileSystemSandboxPolicy(kind: .unrestricted, globScanMaxDepth: nil, entries: [])
    }

    public static func externalSandbox() -> FileSystemSandboxPolicy {
        FileSystemSandboxPolicy(kind: .externalSandbox, globScanMaxDepth: nil, entries: [])
    }

    public static func restricted(_ entries: [FileSystemSandboxEntry]) -> FileSystemSandboxPolicy {
        FileSystemSandboxPolicy(kind: .restricted, globScanMaxDepth: nil, entries: entries)
    }

    /// Removes entries that should be skipped when their paths are missing.
    public mutating func removeSkipMissingPathEntries() {
        entries.removeAll { $0.skipsMissingPath() }
    }

    public func hasExplicitNonWriteEntryForLocalPathWithCwd(_ path: String, cwd: String) -> Bool {
        guard let path = resolveCandidatePath(path, cwd: cwd) else { return false }
        let cwdAbs = try? AbsolutePathBuf.fromAbsolutePath(cwd)
        return entries.contains { entry in
            !entry.skipsMissingPath()
                && !entry.access.canWrite()
                && resolveEntryPath(entry.path, cwd: cwdAbs) == path
        }
    }

    func hasRootAccess(_ predicate: (FileSystemAccessMode) -> Bool) -> Bool {
        kind == .restricted
            && entries.contains { entry in
                if case .special(value: .root) = entry.path {
                    return predicate(entry.access)
                }
                return false
            }
    }

    public func hasDeniedReadRestrictions() -> Bool {
        hasDeniedReadRestrictions(for: PathConvention.native())
    }

    func hasDeniedReadRestrictions(for convention: PathConvention?) -> Bool {
        kind == .restricted
            && entries.contains { entry in
                entry.access == .deny
                    && !isSlashTmpIgnoredOnWindows(entry.path, convention: convention)
            }
    }

    public static func fromLegacySandboxPolicyPreservingDenyEntries(
        _ sandboxPolicy: SandboxPolicy,
        cwd: String,
        existing: FileSystemSandboxPolicy
    ) -> FileSystemSandboxPolicy {
        var rebuilt = fromLegacySandboxPolicyForCwd(sandboxPolicy, cwd: cwd)
        guard rebuilt.kind == .restricted else { return rebuilt }
        rebuilt.globScanMaxDepth = existing.globScanMaxDepth
        for denyEntry in existing.entries where denyEntry.access == .deny {
            if !rebuilt.entries.contains(denyEntry) {
                rebuilt.entries.append(denyEntry)
            }
        }
        return rebuilt
    }

    public mutating func preserveDenyReadRestrictionsFrom(_ existing: FileSystemSandboxPolicy) {
        let hasDenyReadEntries = existing.entries.contains { $0.access == .deny }
        if kind == .unrestricted && hasDenyReadEntries {
            self = .restricted([
                FileSystemSandboxEntry.new(.special(value: .root), .write)
            ])
        }
        guard kind == .restricted else { return }
        if globScanMaxDepth == nil {
            globScanMaxDepth = existing.globScanMaxDepth
        }
        for denyEntry in existing.entries where denyEntry.access == .deny {
            if !entries.contains(denyEntry) {
                entries.append(denyEntry)
            }
        }
    }

    func hasWriteNarrowingEntries(_ convention: PathConvention) -> Bool {
        guard kind == .restricted else { return false }
        return entries.contains { entry in
            if entry.access.canWrite() { return false }
            switch entry.path {
            case .path:
                return !hasSameTargetWriteOverride(entry, convention: convention)
            case .globPattern:
                return true
            case .special(let value):
                switch value {
                case .root:
                    return entry.access == .deny
                case .slashTmp where convention == .windows:
                    return false
                case .minimal, .unknown:
                    return false
                default:
                    return !hasSameTargetWriteOverride(entry, convention: convention)
                }
            }
        }
    }

    func hasSameTargetWriteOverride(
        _ entry: FileSystemSandboxEntry,
        convention: PathConvention
    ) -> Bool {
        entries.contains { candidate in
            candidate.access.canWrite()
                && candidate.access > entry.access
                && fileSystemPathsShareTarget(candidate.path, entry.path, convention: convention)
        }
    }

    public static func workspaceWrite(
        _ writableRoots: [AbsolutePathBuf],
        excludeTmpdirEnvVar: Bool,
        excludeSlashTmp: Bool
    ) -> FileSystemSandboxPolicy {
        var entries = [
            FileSystemSandboxEntry.new(.special(value: .root), .read),
            FileSystemSandboxEntry.new(.special(value: .projectRoots(subpath: nil)), .write),
        ]
        if !excludeSlashTmp {
            entries.append(FileSystemSandboxEntry.new(.special(value: .slashTmp), .write))
        }
        if !excludeTmpdirEnvVar {
            entries.append(FileSystemSandboxEntry.new(.special(value: .tmpdir), .write))
        }
        entries.append(contentsOf: writableRoots.map {
            FileSystemSandboxEntry.new(FileSystemPath($0), .write)
        })
        appendDefaultReadOnlyProjectRootSubpathIfNoExplicitRule(&entries, ".git")
        appendDefaultReadOnlyProjectRootSubpathIfNoExplicitRule(&entries, ".agents")
        appendDefaultReadOnlyProjectRootSubpathIfNoExplicitRule(&entries, ".codex")
        for writableRoot in writableRoots {
            for protectedPath in defaultReadOnlySubpathsForWritableRoot(
                writableRoot,
                protectMissingDotCodex: false
            ) {
                appendDefaultReadOnlyPathIfNoExplicitRule(&entries, protectedPath)
            }
        }
        return .restricted(entries)
    }

    public static func fromLegacySandboxPolicyForCwd(
        _ sandboxPolicy: SandboxPolicy,
        cwd: String
    ) -> FileSystemSandboxPolicy {
        var fileSystemPolicy = FileSystemSandboxPolicy(sandboxPolicy)
        if case .workspaceWrite(let writableRoots, _, _, _) = sandboxPolicy {
            if let cwdRoot = try? AbsolutePathBuf.fromAbsolutePath(cwd) {
                for protectedPath in defaultReadOnlySubpathsForWritableRoot(
                    cwdRoot,
                    protectMissingDotCodex: true
                ) {
                    appendDefaultReadOnlyPathIfNoExplicitRule(&fileSystemPolicy.entries, protectedPath)
                }
            }
            for writableRoot in writableRoots {
                for protectedPath in defaultReadOnlySubpathsForWritableRoot(
                    writableRoot,
                    protectMissingDotCodex: false
                ) {
                    appendDefaultReadOnlyPathIfNoExplicitRule(&fileSystemPolicy.entries, protectedPath)
                }
            }
        }
        return fileSystemPolicy
    }

    public func hasFullDiskReadAccess() -> Bool {
        hasFullDiskReadAccess(for: PathConvention.native())
    }

    public func hasFullDiskReadAccess(for convention: PathConvention?) -> Bool {
        switch kind {
        case .unrestricted, .externalSandbox:
            return true
        case .restricted:
            return hasRootAccess { $0.canRead() }
                && !hasDeniedReadRestrictions(for: convention)
        }
    }

    public func hasFullDiskWriteAccess() -> Bool {
        hasFullDiskWriteAccess(for: PathConvention.native())
    }

    public func hasFullDiskWriteAccess(context: FileSystemSandboxPolicyContext) -> Bool {
        hasFullDiskWriteAccess(for: context.cwd.inferPathConvention())
    }

    public func hasFullDiskWriteAccess(for convention: PathConvention?) -> Bool {
        switch kind {
        case .unrestricted, .externalSandbox:
            return true
        case .restricted:
            guard let convention else { return false }
            return hasRootAccess({ $0.canWrite() }) && !hasWriteNarrowingEntries(convention)
        }
    }

    public func includePlatformDefaults() -> Bool {
        !hasFullDiskReadAccess()
            && kind == .restricted
            && entries.contains { entry in
                if case .special(value: .minimal) = entry.path {
                    return entry.access.canRead()
                }
                return false
            }
    }

    public func resolveAccessForLocalPathWithCwd(_ path: String, cwd: String) -> FileSystemAccessMode {
        withLocalPolicyContext(path: path, cwd: cwd) { path, context in
            (try? prepareLocalMatching(context: context))?.resolveAccess(path) ?? .deny
        } ?? .deny
    }

    public func canReadLocalPathWithCwd(_ path: String, cwd: String) -> Bool {
        resolveAccessForLocalPathWithCwd(path, cwd: cwd).canRead()
    }

    public func canWriteLocalPathWithCwd(_ path: String, cwd: String) -> Bool {
        withLocalPolicyContext(path: path, cwd: cwd) { path, context in
            guard let matching = try? prepareLocalMatching(context: context) else { return false }
            return (try? matching.canWritePath(path)) ?? false
        } ?? false
    }

    public func resolveAccess(_ path: PathUri, context: FileSystemSandboxPolicyContext) -> FileSystemAccessMode {
        switch kind {
        case .unrestricted, .externalSandbox:
            return .write
        case .restricted:
            break
        }
        guard let convention = context.cwd.inferPathConvention() else { return .deny }
        if path.inferPathConvention() != convention
            || path.lexicalDepth() == nil
            || context.cwd.lexicalDepth() == nil
        {
            return .deny
        }

        var scored: [(PathUri, FileSystemAccessMode, Int)] = []
        for (root, access) in resolvedEntries(context) {
            if let depth = root.lexicalDepth() {
                scored.append((root, access, depth))
            } else if root.isOpaque() {
                continue
            } else {
                return .deny
            }
        }
        return scored
            .filter { path.startsWith($0.0) }
            .max { lhs, rhs in
                if lhs.2 != rhs.2 { return lhs.2 < rhs.2 }
                return lhs.1 < rhs.1
            }
            .map(\.1) ?? .deny
    }

    public func canWritePath(_ path: PathUri, context: FileSystemSandboxPolicyContext) -> Bool {
        guard resolveAccess(path, context: context).canWrite() else { return false }
        return hasFullDiskWriteAccess(context: context)
            || metadataWriteDenial(path, context: context) == nil
    }

    func metadataWriteDenial(_ path: PathUri, context: FileSystemSandboxPolicyContext) -> String? {
        guard kind == .restricted else { return nil }
        let entries = resolvedEntries(context)
        var protected: PathUri?
        var metadataName: String?
        for (root, access) in entries where access.canWrite() {
            for name in PROTECTED_METADATA_PATH_NAMES {
                guard let candidate = try? root.joinDescendant(name), path.startsWith(candidate) else {
                    continue
                }
                protected = candidate
                metadataName = name
                break
            }
            if protected != nil { break }
        }
        guard let protected, let metadataName else { return nil }
        let overridden = entries.contains { root, access in
            access.canWrite() && path.startsWith(root) && root.startsWith(protected)
        }
        return overridden ? nil : metadataName
    }

    func prepareDenyReadMatcher(
        context: FileSystemSandboxPolicyContext,
        invalidGlobBehavior: InvalidDenyReadGlobBehavior
    ) throws -> PreparedReadDenyMatcher {
        let filesystemRoot = fileSystemRoot(context)
        let deniedRoots = resolvedEntries(context)
            .filter { $0.1 == .deny }
            .filter { root, _ in
                guard let filesystemRoot else { return true }
                return !(root.startsWith(filesystemRoot) && filesystemRoot.startsWith(root))
            }
            .map(\.0)
        guard let convention = context.cwd.inferPathConvention() else {
            return PreparedReadDenyMatcher(
                deniedRoots: deniedRoots,
                denyReadMatchers: [],
                invalidPattern: true
            )
        }
        let patterns: [String]
        do {
            patterns = try denyReadGlobs(context)
        } catch {
            switch invalidGlobBehavior {
            case .failClosed:
                return PreparedReadDenyMatcher(
                    deniedRoots: deniedRoots,
                    denyReadMatchers: [],
                    invalidPattern: true
                )
            case .returnError:
                throw error
            }
        }
        var denyReadMatchers: [GlobMatcher] = []
        var invalidPattern = false
        for pattern in patterns {
            do {
                denyReadMatchers.append(try buildGlobMatcher(pattern, convention: convention))
            } catch {
                switch invalidGlobBehavior {
                case .failClosed:
                    invalidPattern = true
                case .returnError:
                    throw PermissionStringError(
                        "invalid deny-read glob pattern `\(pattern)`: \(error)")
                }
            }
        }
        return PreparedReadDenyMatcher(
            deniedRoots: deniedRoots,
            denyReadMatchers: denyReadMatchers,
            invalidPattern: invalidPattern
        )
    }

    static func matchesPreparedReadDeny(
        _ path: PathUri,
        context: FileSystemSandboxPolicyContext,
        prepared: PreparedReadDenyMatcher
    ) -> Bool {
        guard let convention = context.cwd.inferPathConvention() else { return true }
        if path.inferPathConvention() != convention
            || path.lexicalDepth() == nil
            || context.cwd.lexicalDepth() == nil
        {
            return true
        }
        if prepared.invalidPattern { return true }
        if prepared.deniedRoots.contains(where: { path.startsWith($0) }) {
            return true
        }
        let bytes: [UInt8]
        switch convention {
        case .posix:
            bytes = path.decodedPathBytes()
        case .windows:
            bytes = Array(
                path.inferredNativePathString()
                    .replacingOccurrences(of: "\\", with: "/")
                    .utf8
            )
        }
        return prepared.denyReadMatchers.contains { $0.isMatch(bytes) }
    }

    func denyReadGlobs(_ context: FileSystemSandboxPolicyContext) throws -> [String] {
        var results: [String] = []
        for entry in entries where entry.access == .deny {
            guard case .globPattern(let pattern) = entry.path else { continue }
            let isWindows = context.cwd.inferPathConvention() == .windows
            let homeRelative: String?
            if let suffix = pattern.stripPrefix("~/") {
                homeRelative = suffix
            } else if isWindows, let suffix = pattern.stripPrefix("~\\") {
                homeRelative = suffix
            } else {
                homeRelative = nil
            }
            let root: PathUri
            let resolvedPattern: String
            if let suffix = homeRelative {
                guard let home = context.userHomeDir else {
                    throw PermissionStringError(
                        "unable to resolve deny-read glob pattern `\(pattern)` without executor home")
                }
                root = home
                resolvedPattern = String(suffix.drop(while: { $0 == "/" || (isWindows && $0 == "\\") }))
            } else {
                root = context.cwd
                resolvedPattern = pattern
            }
            let convention: PathConvention = isWindows ? .windows : .posix
            if (try? LegacyAppPathString.fromString(resolvedPattern).toPathUri(convention)) == nil {
                do {
                    try root.validateGlobDirectory(convention: convention)
                } catch {
                    throw PermissionStringError(String(describing: error))
                }
            }
            do {
                results.append(try root.join(resolvedPattern).inferredNativePathString())
            } catch {
                throw PermissionStringError(
                    "unable to resolve deny-read glob pattern `\(pattern)`")
            }
        }
        return results
    }

    public func materializeProjectRootsWithWorkspaceRoots(
        _ workspaceRoots: [AbsolutePathBuf]
    ) -> FileSystemSandboxPolicy {
        materializeProjectRootsWithPathUris(workspaceRoots.map(PathUri.fromAbsPath))
    }

    public func materializeProjectRootsWithPathUris(_ workspaceRoots: [PathUri]) -> FileSystemSandboxPolicy {
        tryMaterializeProjectRootsWithPathUris(workspaceRoots) ?? .restricted([])
    }

    func tryMaterializeProjectRootsWithPathUris(_ workspaceRoots: [PathUri]) -> FileSystemSandboxPolicy? {
        var materialized = self
        var entries: [FileSystemSandboxEntry] = []
        entries.reserveCapacity(self.entries.count)
        for entry in self.entries {
            let subpath: String?
            let isGlob: Bool
            switch entry.path {
            case .special(value: .projectRoots(let value)):
                subpath = value
                isGlob = false
            case .globPattern(let pattern) where pattern.hasPrefix(projectRootsGlobPatternPrefix):
                subpath = String(pattern.dropFirst(projectRootsGlobPatternPrefix.count))
                isGlob = true
            default:
                entries.append(entry)
                continue
            }
            if entry.access == .deny,
               let subpath,
               workspaceRoots.contains(where: { root in
                   root.inferPathConvention()?.homeRelativeSuffix(subpath) != nil
               })
            {
                return nil
            }
            for root in workspaceRoots {
                let path: PathUri?
                if isGlob,
                   root.inferPathConvention().map({ (try? root.validateGlobDirectory(convention: $0)) == nil }) ?? true
                {
                    path = nil
                } else if let subpath {
                    path = resolveScopedWorkspacePath(root, subpath: subpath)
                } else {
                    path = root
                }
                let (resolvedPath, access): (FileSystemPath, FileSystemAccessMode)
                if let path, isGlob {
                    resolvedPath = .globPattern(pattern: path.inferredNativePathString())
                    access = entry.access
                } else if let path {
                    resolvedPath = .path(path: path)
                    access = entry.access
                } else if !entry.access.canWrite() {
                    resolvedPath = .path(path: root)
                    access = .deny
                } else {
                    continue
                }
                entries.append(FileSystemSandboxEntry(
                    path: resolvedPath,
                    access: access,
                    missingPathBehavior: entry.missingPathBehavior
                ))
            }
        }
        materialized.entries = entries
        return materialized
    }

    public func withMaterializedProjectRootsForWorkspaceRoots(
        _ workspaceRoots: [AbsolutePathBuf]
    ) -> FileSystemSandboxPolicy {
        withMaterializedProjectRootsForPathUris(workspaceRoots.map(PathUri.fromAbsPath))
    }

    public func withAdditionalReadableRoots(
        cwd: String,
        additionalReadableRoots: [AbsolutePathBuf]
    ) -> FileSystemSandboxPolicy {
        if hasFullDiskReadAccess() { return self }
        var copy = self
        for path in additionalReadableRoots {
            if canReadLocalPathWithCwd(path.asPath, cwd: cwd) { continue }
            copy.entries.append(FileSystemSandboxEntry.new(FileSystemPath(path), .read))
        }
        return copy
    }

    public func withAdditionalWritableRoots(
        cwd: String,
        additionalWritableRoots: [AbsolutePathBuf]
    ) -> FileSystemSandboxPolicy {
        var copy = self
        for path in additionalWritableRoots {
            if canWriteLocalPathWithCwd(path.asPath, cwd: cwd) { continue }
            copy.entries.append(FileSystemSandboxEntry.new(FileSystemPath(path), .write))
        }
        return copy
    }

    public func withAdditionalLegacyWorkspaceWritableRoots(
        _ additionalWritableRoots: [AbsolutePathBuf]
    ) -> FileSystemSandboxPolicy {
        guard kind == .restricted else { return self }
        var copy = self
        for path in additionalWritableRoots {
            let uri = PathUri.fromAbsPath(path)
            if !copy.entries.contains(where: { entry in
                entry.access.canWrite()
                    && {
                        if case .path(let existing) = entry.path { return existing == uri }
                        return false
                    }()
            }) {
                copy.entries.append(FileSystemSandboxEntry.new(FileSystemPath(path), .write))
            }
            for protectedPath in defaultReadOnlySubpathsForWritableRoot(
                path,
                protectMissingDotCodex: false
            ) {
                appendDefaultReadOnlyPathIfNoExplicitRule(&copy.entries, protectedPath)
            }
        }
        return copy
    }

    public func needsDirectRuntimeEnforcement(
        networkPolicy: NetworkSandboxPolicy,
        cwd: String
    ) -> Bool {
        guard kind == .restricted else { return false }
        guard let legacyPolicy = try? toLegacySandboxPolicy(networkPolicy, cwd: cwd) else {
            return true
        }
        if protectedMetadataNamesNeedDirectRuntimeEnforcement(self, legacyPolicy, cwd: cwd) {
            return true
        }
        return semanticSignature(cwd) != legacyRuntimeFileSystemPolicyForCwd(legacyPolicy, cwd: cwd)
            .semanticSignature(cwd)
    }

    public func isSemanticallyEquivalentTo(_ other: FileSystemSandboxPolicy, cwd: String) -> Bool {
        semanticSignature(cwd) == other.semanticSignature(cwd)
    }

    public func getReadableRootsWithCwd(_ cwd: String) -> [AbsolutePathBuf] {
        if hasFullDiskReadAccess() { return [] }
        guard let localContext = LocalPolicyContext(cwd: cwd),
              let matching = try? prepareLocalMatching(context: localContext.asContext())
        else {
            return []
        }
        return dedupAbsolutePaths(
            resolvedEntriesWithCwd(cwd)
                .filter { $0.access.canRead() }
                .filter { matching.resolveAccess(PathUri.fromAbsPath($0.path)).canRead() }
                .map(\.path),
            normalizeEffectivePaths: true
        )
    }

    public func getWritableRootsWithCwd(_ cwd: String) -> [WritableRoot] {
        getWritableRootsWithCwd(cwd, pathResolution: .effective)
    }

    public func hasConfiguredWritableRootsWithCwd(_ cwd: String) -> Bool {
        withLocalPolicyContext(path: cwd, cwd: cwd) { _, context in
            hasConfiguredWritableRoots(context)
        } ?? false
    }

    public func hasConfiguredWritableRoots(_ context: FileSystemSandboxPolicyContext) -> Bool {
        !hasFullDiskWriteAccess(context: context)
            && resolvedEntries(context).contains { path, access in
                access.canWrite() && canWritePath(path, context: context)
            }
    }

    public func getWritableRootsWithCwdPreservingMutablePaths(_ cwd: String) -> [WritableRoot] {
        getWritableRootsWithCwd(cwd, pathResolution: .preserveMutableComponents)
    }

    func getWritableRootsWithCwd(
        _ cwd: String,
        pathResolution: WritableRootPathResolution
    ) -> [WritableRoot] {
        if hasFullDiskWriteAccess() { return [] }
        let resolvedEntries = resolvedEntriesWithCwd(cwd)
        guard resolvedEntries.contains(where: { $0.access.canWrite() }) else { return [] }
        guard let localContext = LocalPolicyContext(cwd: cwd),
              let matching = try? prepareLocalMatching(context: localContext.asContext())
        else {
            return []
        }
        let effectiveEntries = resolvedEntries.filter { entry in
            entry.access.canWrite()
                == ((try? matching.canWritePath(PathUri.fromAbsPath(entry.path))) ?? false)
        }
        guard effectiveEntries.contains(where: { $0.access.canWrite() }) else { return [] }

        let includeResolvedGitdirs: Bool
        switch pathResolution {
        case .effective:
            includeResolvedGitdirs = false
        case .preserveMutableComponents:
            includeResolvedGitdirs = true
        }

        var resolvedGitdirEntries: [ResolvedFileSystemEntry] = []
        if includeResolvedGitdirs {
            for entry in effectiveEntries where entry.access.canWrite() {
                let dotGit = pathResolution.resolve(entry.path).join(protectedMetadataGitPathName)
                if isGitPointerFile(dotGit), let gitdir = resolveGitdirFromFile(dotGit),
                   !hasExplicitResolvedPathEntry(resolvedEntries, gitdir)
                {
                    resolvedGitdirEntries.append(
                        ResolvedFileSystemEntry(path: gitdir, access: .read))
                }
            }
        }

        var preparedEntries: [PreparedFileSystemEntry] = effectiveEntries.map {
            PreparedFileSystemEntry(entry: $0, effectivePath: pathResolution.resolve($0.path))
        }
        preparedEntries.append(contentsOf: resolvedGitdirEntries.map { entry in
            PreparedFileSystemEntry(
                entry: entry,
                effectivePath: (try? entry.path.canonicalize())
                    ?? WritableRootPathResolution.effective.resolve(entry.path)
            )
        })

        let writableEntries = preparedEntries.filter { $0.entry.access.canWrite() }
        let effectiveCwd = (try? AbsolutePathBuf.fromAbsolutePath(cwd)).map { pathResolution.resolve($0) }

        return dedupAbsolutePaths(writableEntries.map(\.effectivePath), normalizeEffectivePaths: false)
            .map { root in
                let preserveRawCarveoutPaths = root.parent != nil
                let rawWritableRoots = writableEntries
                    .filter { $0.effectivePath == root }
                    .map(\.entry.path)
                let protectedMetadataNames = protectedMetadataNamesForWritableRoot(
                    matching, root: root, rawWritableRoots: rawWritableRoots)
                let protectMissingDotCodex = effectiveCwd == root
                var readOnlySubpaths = defaultReadOnlySubpathsForWritableRoot(
                    root, protectMissingDotCodex: protectMissingDotCodex
                ).filter { !hasExplicitResolvedPathEntry(resolvedEntries, $0) }
                for prepared in preparedEntries where !prepared.entry.access.canWrite() {
                    let entry = prepared.entry
                    let effectivePath = prepared.effectivePath
                    let rawCarveoutPath: AbsolutePathBuf?
                    if preserveRawCarveoutPaths {
                        if entry.path == root {
                            rawCarveoutPath = nil
                        } else if pathHasPrefix(entry.path.asPath, prefix: root.asPath) {
                            rawCarveoutPath = entry.path
                        } else {
                            rawCarveoutPath = rawWritableRoots.compactMap { rawRoot -> AbsolutePathBuf? in
                                guard let suffix = pathStripPrefix(entry.path.asPath, prefix: rawRoot.asPath),
                                      !suffix.isEmpty
                                else { return nil }
                                return root.join(suffix)
                            }.first
                        }
                    } else {
                        rawCarveoutPath = nil
                    }
                    if let rawCarveoutPath {
                        readOnlySubpaths.append(rawCarveoutPath)
                        continue
                    }
                    if effectivePath == root || !pathHasPrefix(effectivePath.asPath, prefix: root.asPath) {
                        continue
                    }
                    readOnlySubpaths.append(effectivePath)
                }
                return WritableRoot(
                    root: root,
                    readOnlySubpaths: dedupAbsolutePaths(readOnlySubpaths, normalizeEffectivePaths: false),
                    protectedMetadataNames: protectedMetadataNames
                )
            }
    }

    public func getUnreadableRootsWithCwd(_ cwd: String) -> [AbsolutePathBuf] {
        guard kind == .restricted else { return [] }
        let root = (try? AbsolutePathBuf.fromAbsolutePath(cwd)).map(absoluteRootPathForCwd)
        let localContext = LocalPolicyContext(cwd: cwd)
        let matching = localContext.flatMap { try? prepareLocalMatching(context: $0.asContext()) }
        return dedupAbsolutePaths(
            resolvedEntriesWithCwd(cwd)
                .filter { $0.access == .deny }
                .filter { entry in
                    !(matching?.resolveAccess(PathUri.fromAbsPath(entry.path)).canRead() ?? false)
                }
                .filter { entry in root != entry.path }
                .map(\.path),
            normalizeEffectivePaths: true
        )
    }

    public func getUnreadableGlobsWithCwd(_ cwd: String) -> [String] {
        guard kind == .restricted else { return [] }
        var patterns = entries.compactMap { entry -> String? in
            guard entry.access == .deny, case .globPattern(let pattern) = entry.path else {
                return nil
            }
            return AbsolutePathBuf.resolvePathAgainstBase(pattern, basePath: cwd).toStringLossy
        }
        patterns.sort()
        var unique: [String] = []
        for pattern in patterns where unique.last != pattern {
            unique.append(pattern)
        }
        return unique
    }

    public func toLegacySandboxPolicy(
        _ networkPolicy: NetworkSandboxPolicy,
        cwd: String
    ) throws -> SandboxPolicy {
        switch kind {
        case .externalSandbox:
            return .externalSandbox(networkAccess: networkPolicy.isEnabled ? .enabled : .restricted)
        case .unrestricted:
            if networkPolicy.isEnabled {
                return .dangerFullAccess
            }
            return .externalSandbox(networkAccess: .restricted)
        case .restricted:
            let cwdAbsolute = try? AbsolutePathBuf.fromAbsolutePath(cwd)
            let hasFullDiskWriteAccess = hasFullDiskWriteAccess()
            var workspaceRootWritable = false
            var writableRoots: [AbsolutePathBuf] = []
            var tmpdirWritable = false
            var slashTmpWritable = false
            var unbridgeableRootWrite = false

            for entry in entries {
                switch entry.path {
                case .globPattern:
                    break
                case .path(let path):
                    if entry.access.canWrite() {
                        let path = try path.toAbsPath()
                        if cwdAbsolute == path {
                            workspaceRootWritable = true
                        } else {
                            writableRoots.append(path)
                        }
                    }
                case .special(let value):
                    switch value {
                    case .root:
                        if entry.access == .write { unbridgeableRootWrite = true }
                    case .minimal, .unknown:
                        break
                    case .projectRoots(let subpath):
                        if subpath == nil && entry.access.canWrite() {
                            workspaceRootWritable = true
                        } else if let path = resolveFileSystemSpecialPath(value, cwd: cwdAbsolute),
                                  entry.access.canWrite()
                        {
                            writableRoots.append(path)
                        }
                    case .tmpdir:
                        if entry.access.canWrite() { tmpdirWritable = true }
                    case .slashTmp:
                        if entry.access.canWrite() { slashTmpWritable = true }
                    }
                }
            }

            if hasFullDiskWriteAccess {
                return networkPolicy.isEnabled
                    ? .dangerFullAccess
                    : .externalSandbox(networkAccess: .restricted)
            }
            if workspaceRootWritable {
                return .workspaceWrite(
                    writableRoots: dedupAbsolutePaths(writableRoots, normalizeEffectivePaths: false),
                    networkAccess: networkPolicy.isEnabled,
                    excludeTmpdirEnvVar: !tmpdirWritable,
                    excludeSlashTmp: !slashTmpWritable
                )
            }
            if unbridgeableRootWrite || !writableRoots.isEmpty || tmpdirWritable || slashTmpWritable {
                throw IOError.invalidInput(
                    "permissions profile requests filesystem writes outside the workspace root, which is not supported until the runtime enforces FileSystemSandboxPolicy directly"
                )
            }
            return .readOnly(networkAccess: networkPolicy.isEnabled)
        }
    }

    func resolvedEntriesWithCwd(_ cwd: String) -> [ResolvedFileSystemEntry] {
        let cwdAbsolute = try? AbsolutePathBuf.fromAbsolutePath(cwd)
        return entries.compactMap { entry in
            resolveEntryPath(entry.path, cwd: cwdAbsolute).map {
                ResolvedFileSystemEntry(path: $0, access: entry.access)
            }
        }
    }

    /// Resolves configured roots using executor paths without inspecting the filesystem.
    public func resolvedEntries(
        _ context: FileSystemSandboxPolicyContext
    ) -> [(PathUri, FileSystemAccessMode)] {
        let convention = context.cwd.inferPathConvention()
        var results: [(PathUri, FileSystemAccessMode)] = []
        for entry in entries {
            let paths: [PathUri]
            switch entry.path {
            case .path(let path):
                paths = [path]
            case .globPattern:
                paths = []
            case .special(let value):
                switch value {
                case .root:
                    paths = fileSystemRoot(context).map { [$0] } ?? []
                case .projectRoots(let subpath):
                    paths = context.workspaceRoots.compactMap { root in
                        if let subpath {
                            return try? root.join(subpath)
                        }
                        return root
                    }
                case .tmpdir:
                    paths = context.temporaryDirectories ?? []
                case .slashTmp where convention == .posix:
                    paths = (try? context.cwd.join("/tmp")).map { [$0] } ?? []
                case .slashTmp, .minimal, .unknown:
                    paths = []
                }
            }
            for path in paths where path.inferPathConvention() == convention {
                results.append((path, entry.access))
            }
        }
        return results
    }

    func semanticSignature(_ cwd: String) -> FileSystemSemanticSignature {
        FileSystemSemanticSignature(
            hasFullDiskReadAccess: hasFullDiskReadAccess(),
            hasFullDiskWriteAccess: hasFullDiskWriteAccess(),
            includePlatformDefaults: includePlatformDefaults(),
            readableRoots: sortedAbsolutePaths(getReadableRootsWithCwd(cwd)),
            writableRoots: sortedWritableRoots(getWritableRootsWithCwd(cwd)),
            unreadableRoots: sortedAbsolutePaths(getUnreadableRootsWithCwd(cwd)),
            unreadableGlobs: getUnreadableGlobsWithCwd(cwd)
        )
    }
}

extension FileSystemSandboxPolicy {
    /// `From<&SandboxPolicy>`.
    public init(_ value: SandboxPolicy) {
        switch value {
        case .dangerFullAccess:
            self = .unrestricted()
        case .externalSandbox:
            self = .externalSandbox()
        case .readOnly:
            self = .restricted([
                FileSystemSandboxEntry.new(.special(value: .root), .read)
            ])
        case .workspaceWrite(let writableRoots, _, let excludeTmpdir, let excludeSlashTmp):
            self = .workspaceWrite(
                writableRoots,
                excludeTmpdirEnvVar: excludeTmpdir,
                excludeSlashTmp: excludeSlashTmp
            )
        }
    }
}

extension NetworkSandboxPolicy {
    /// `From<&SandboxPolicy>`.
    public init(_ value: SandboxPolicy) {
        self = value.hasFullNetworkAccess ? .enabled : .restricted
    }
}

func resolveFileSystemPath(
    _ path: FileSystemPath,
    cwd: AbsolutePathBuf?
) -> AbsolutePathBuf? {
    switch path {
    case .path(let path):
        return try? path.toAbsPath()
    case .globPattern:
        return nil
    case .special(let value):
        return resolveFileSystemSpecialPath(value, cwd: cwd)
    }
}

func resolveEntryPath(_ path: FileSystemPath, cwd: AbsolutePathBuf?) -> AbsolutePathBuf? {
    if case .special(value: .root) = path {
        return cwd.map(absoluteRootPathForCwd)
    }
    return resolveFileSystemPath(path, cwd: cwd)
}

func resolveCandidatePath(_ path: String, cwd: String) -> AbsolutePathBuf? {
    if path.hasPrefix("/") {
        return try? AbsolutePathBuf.fromAbsolutePath(path)
    }
    return (try? AbsolutePathBuf.fromAbsolutePath(cwd))?.join(path)
}

func resolveScopedWorkspacePath(_ root: PathUri, subpath: String) -> PathUri? {
    guard let convention = root.inferPathConvention() else { return nil }
    if subpath.hasPrefix("/")
        || (convention == .windows && subpath.hasPrefix("\\"))
        || convention.pathSegments(subpath).contains(where: { $0 == "." || $0 == ".." })
        || (convention == .windows && convention.pathSegments(subpath).contains(where: { $0.contains(":") }))
    {
        return nil
    }
    guard let path = try? root.join(subpath), path.startsWith(root) else { return nil }
    return path
}

func withLocalPolicyContext<T>(
    path: String,
    cwd: String,
    evaluate: (PathUri, FileSystemSandboxPolicyContext) -> T
) -> T? {
    guard let cwdAbs = try? AbsolutePathBuf.fromAbsolutePath(cwd),
          let resolved = resolveCandidatePath(path, cwd: cwdAbs.asPath),
          let context = LocalPolicyContext(cwd: cwdAbs.asPath)
    else {
        return nil
    }
    return evaluate(PathUri(resolved), context.asContext())
}

public func fileSystemRoot(_ context: FileSystemSandboxPolicyContext) -> PathUri? {
    guard context.cwd.lexicalDepth() != nil else { return nil }
    return context.cwd.ancestors().last
}

func localTemporaryDirectories() -> [PathUri] {
    guard let tmpdir = ProcessInfo.processInfo.environment["TMPDIR"], !tmpdir.isEmpty,
          let abs = try? AbsolutePathBuf.fromAbsolutePath(tmpdir)
    else {
        return []
    }
    return [PathUri(abs)]
}

func fileSystemPathsShareTarget(
    _ left: FileSystemPath,
    _ right: FileSystemPath,
    convention: PathConvention
) -> Bool {
    switch (left, right) {
    case (.path(let left), .path(let right)):
        return left == right
    case (.special(let left), .special(let right)):
        return specialPathsShareTarget(left, right)
    case (.path(let path), .special(let value)), (.special(let value), .path(let path)):
        return path.inferPathConvention() == convention && specialPathMatchesPathUri(value, path)
    case (.globPattern(let left), .globPattern(let right)):
        return left == right
    default:
        return false
    }
}

func specialPathsShareTarget(_ left: FileSystemSpecialPath, _ right: FileSystemSpecialPath) -> Bool {
    switch (left, right) {
    case (.root, .root), (.minimal, .minimal), (.tmpdir, .tmpdir), (.slashTmp, .slashTmp):
        return true
    case (.projectRoots(let left), .projectRoots(let right)):
        return left == right
    case (.unknown(let left, let leftSub), .unknown(let right, let rightSub)):
        return left == right && leftSub == rightSub
    default:
        return false
    }
}

func specialPathMatchesPathUri(_ value: FileSystemSpecialPath, _ path: PathUri) -> Bool {
    switch value {
    case .root:
        return path.lexicalDepth() != nil && path.parent() == nil
    case .slashTmp:
        return path.inferPathConvention() == .posix
            && path.lexicalDepth() == 1
            && path.basename() == "tmp"
    default:
        return false
    }
}

func absoluteRootPathForCwd(_ cwd: AbsolutePathBuf) -> AbsolutePathBuf {
    let root = cwd.ancestors().last ?? cwd
    return (try? AbsolutePathBuf.fromAbsolutePath(root.asPath)) ?? cwd
}

func resolveFileSystemSpecialPath(
    _ value: FileSystemSpecialPath,
    cwd: AbsolutePathBuf?
) -> AbsolutePathBuf? {
    switch value {
    case .root, .minimal, .unknown:
        return nil
    case .projectRoots(let subpath):
        guard let cwd else { return nil }
        if let subpath {
            return AbsolutePathBuf.resolvePathAgainstBase(subpath, basePath: cwd.asPath)
        }
        return cwd
    case .tmpdir:
        guard let tmpdir = ProcessInfo.processInfo.environment["TMPDIR"], !tmpdir.isEmpty else {
            return nil
        }
        return try? AbsolutePathBuf.fromAbsolutePath(tmpdir)
    case .slashTmp:
        guard let slashTmp = try? AbsolutePathBuf.fromAbsolutePath("/tmp") else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: slashTmp.asPath, isDirectory: &isDir),
              isDir.boolValue
        else {
            return nil
        }
        return slashTmp
    }
}

func dedupAbsolutePaths(_ paths: [AbsolutePathBuf], normalizeEffectivePaths: Bool) -> [AbsolutePathBuf] {
    var deduped: [AbsolutePathBuf] = []
    var seen = Set<String>()
    for path in paths {
        let dedupPath = normalizeEffectivePaths ? normalizeEffectiveAbsolutePath(path) : path
        if seen.insert(dedupPath.asPath).inserted {
            deduped.append(dedupPath)
        }
    }
    return deduped
}

func sortedAbsolutePaths(_ paths: [AbsolutePathBuf]) -> [AbsolutePathBuf] {
    paths.sorted { $0.asPath < $1.asPath }
}

func sortedWritableRoots(_ roots: [WritableRoot]) -> [WritableRoot] {
    roots.map { root in
        var copy = root
        copy.readOnlySubpaths = sortedAbsolutePaths(copy.readOnlySubpaths)
        copy.protectedMetadataNames.sort()
        var unique: [String] = []
        for name in copy.protectedMetadataNames where unique.last != name {
            unique.append(name)
        }
        copy.protectedMetadataNames = unique
        return copy
    }
    .sorted { $0.root.asPath < $1.root.asPath }
}

func normalizeEffectiveAbsolutePath(_ path: AbsolutePathBuf) -> AbsolutePathBuf {
    let rawPath = path.asPath
    for ancestor in path.ancestors() {
        var st = stat()
        guard lstat(ancestor.asPath, &st) == 0 else { continue }
        guard let normalizedAncestor = try? canonicalizePreservingSymlinks(ancestor.asPath),
              let suffix = pathStripPrefix(rawPath, prefix: ancestor.asPath),
              let normalizedPath = try? AbsolutePathBuf.fromAbsolutePath(
                suffix.isEmpty ? normalizedAncestor : (normalizedAncestor as NSString).appendingPathComponent(suffix)
              )
        else {
            continue
        }
        return normalizedPath
    }
    return path
}

func defaultReadOnlySubpathsForWritableRoot(
    _ writableRoot: AbsolutePathBuf,
    protectMissingDotCodex: Bool
) -> [AbsolutePathBuf] {
    var subpaths: [AbsolutePathBuf] = []
    let topLevelGit = writableRoot.join(protectedMetadataGitPathName)
    let topLevelGitIsFile = isRegularFile(topLevelGit.asPath)
    let topLevelGitIsDir = isDirectory(topLevelGit.asPath)
    if topLevelGitIsDir || topLevelGitIsFile {
        if topLevelGitIsFile, isGitPointerFile(topLevelGit), let gitdir = resolveGitdirFromFile(topLevelGit) {
            subpaths.append(gitdir)
        }
        subpaths.append(topLevelGit)
    }
    let topLevelAgents = writableRoot.join(protectedMetadataAgentsPathName)
    if isDirectory(topLevelAgents.asPath) {
        subpaths.append(topLevelAgents)
    }
    let topLevelCodex = writableRoot.join(protectedMetadataCodexPathName)
    if protectMissingDotCodex || isDirectory(topLevelCodex.asPath) {
        subpaths.append(topLevelCodex)
    }
    return dedupAbsolutePaths(subpaths, normalizeEffectivePaths: false)
}

func legacyRuntimeFileSystemPolicyForCwd(
    _ sandboxPolicy: SandboxPolicy,
    cwd: String
) -> FileSystemSandboxPolicy {
    guard case .workspaceWrite(let writableRoots, _, let excludeTmpdir, let excludeSlashTmp) = sandboxPolicy else {
        return FileSystemSandboxPolicy(sandboxPolicy)
    }
    var entries = [
        FileSystemSandboxEntry.new(.special(value: .root), .read),
        FileSystemSandboxEntry.new(.special(value: .projectRoots(subpath: nil)), .write),
    ]
    if !excludeSlashTmp {
        entries.append(FileSystemSandboxEntry.new(.special(value: .slashTmp), .write))
    }
    if !excludeTmpdir {
        entries.append(FileSystemSandboxEntry.new(.special(value: .tmpdir), .write))
    }
    entries.append(contentsOf: writableRoots.map {
        FileSystemSandboxEntry.new(FileSystemPath($0), .write)
    })
    if let cwdRoot = try? AbsolutePathBuf.fromAbsolutePath(cwd) {
        for protectedPath in defaultReadOnlySubpathsForWritableRoot(cwdRoot, protectMissingDotCodex: true) {
            appendDefaultReadOnlyPathIfNoExplicitRule(&entries, protectedPath)
        }
    }
    for writableRoot in writableRoots {
        for protectedPath in defaultReadOnlySubpathsForWritableRoot(
            writableRoot,
            protectMissingDotCodex: false
        ) {
            appendDefaultReadOnlyPathIfNoExplicitRule(&entries, protectedPath)
        }
    }
    return .restricted(entries)
}

func appendDefaultReadOnlyProjectRootSubpathIfNoExplicitRule(
    _ entries: inout [FileSystemSandboxEntry],
    _ subpath: String
) {
    appendDefaultReadOnlyEntryIfNoExplicitRule(
        &entries,
        .special(value: .projectRoots(subpath: subpath))
    )
}

func appendDefaultReadOnlyPathIfNoExplicitRule(
    _ entries: inout [FileSystemSandboxEntry],
    _ path: AbsolutePathBuf
) {
    appendDefaultReadOnlyEntryIfNoExplicitRule(&entries, FileSystemPath(path))
}

func appendDefaultReadOnlyEntryIfNoExplicitRule(
    _ entries: inout [FileSystemSandboxEntry],
    _ path: FileSystemPath
) {
    if entries.contains(where: {
        fileSystemPathsShareTarget($0.path, path, convention: PathConvention.native())
    }) {
        return
    }
    entries.append(FileSystemSandboxEntry.skipMissingPath(path, .read))
}

func hasExplicitResolvedPathEntry(
    _ entries: [ResolvedFileSystemEntry],
    _ path: AbsolutePathBuf
) -> Bool {
    entries.contains { $0.path == path }
}

func protectedMetadataNamesForWritableRoot(
    _ matching: LocalFileSystemPolicyMatcher,
    root: AbsolutePathBuf,
    rawWritableRoots: [AbsolutePathBuf]
) -> [String] {
    var protectedNames: [String] = []
    for metadataName in PROTECTED_METADATA_PATH_NAMES {
        var metadataPaths = [root.join(metadataName)]
        metadataPaths.append(contentsOf: rawWritableRoots.map { $0.join(metadataName) })
        if metadataPaths.allSatisfy({ path in
            (try? matching.canWritePath(PathUri.fromAbsPath(path))) != true
        }) {
            protectedNames.append(metadataName)
        }
    }
    return protectedNames
}

func protectedMetadataNamesNeedDirectRuntimeEnforcement(
    _ policy: FileSystemSandboxPolicy,
    _ legacyPolicy: SandboxPolicy,
    cwd: String
) -> Bool {
    let legacyRoots = sandboxPolicyWritableRootsWithCwd(legacyPolicy, cwd: cwd)
    return policy.getWritableRootsWithCwd(cwd).contains { writableRoot in
        guard let legacyRoot = legacyRoots.first(where: { $0.root == writableRoot.root }) else {
            return !writableRoot.protectedMetadataNames.isEmpty
        }
        return writableRoot.protectedMetadataNames.contains { metadataName in
            let metadataPath = writableRoot.root.join(metadataName)
            return !legacyRoot.readOnlySubpaths.contains(metadataPath)
        }
    }
}

/// Local copy of `SandboxPolicy::get_writable_roots_with_cwd` so this file
/// does not need to edit `protocol.swift`.
func sandboxPolicyWritableRootsWithCwd(_ policy: SandboxPolicy, cwd: String) -> [WritableRoot] {
    switch policy {
    case .dangerFullAccess, .externalSandbox, .readOnly:
        return []
    case .workspaceWrite(let writableRoots, _, let excludeTmpdir, let excludeSlashTmp):
        var roots = writableRoots
        if let cwdAbs = try? AbsolutePathBuf.fromAbsolutePath(cwd) {
            roots.append(cwdAbs)
        }
        if !excludeSlashTmp, let slashTmp = try? AbsolutePathBuf.fromAbsolutePath("/tmp"),
           isDirectory(slashTmp.asPath)
        {
            roots.append(slashTmp)
        }
        if !excludeTmpdir,
           let tmpdir = ProcessInfo.processInfo.environment["TMPDIR"], !tmpdir.isEmpty,
           let tmpdirPath = try? AbsolutePathBuf.fromAbsolutePath(tmpdir)
        {
            roots.append(tmpdirPath)
        }
        let cwdRoot = try? AbsolutePathBuf.fromAbsolutePath(cwd)
        return roots.map { writableRoot in
            WritableRoot(
                root: writableRoot,
                readOnlySubpaths: defaultReadOnlySubpathsForWritableRoot(
                    writableRoot,
                    protectMissingDotCodex: cwdRoot == writableRoot
                ),
                protectedMetadataNames: []
            )
        }
    }
}

func isGitPointerFile(_ path: AbsolutePathBuf) -> Bool {
    isRegularFile(path.asPath) && (path.asPath as NSString).lastPathComponent == protectedMetadataGitPathName
}

func resolveGitdirFromFile(_ dotGit: AbsolutePathBuf) -> AbsolutePathBuf? {
    guard let contents = try? String(contentsOfFile: dotGit.asPath, encoding: .utf8) else {
        return nil
    }
    let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let colon = trimmed.firstIndex(of: ":") else { return nil }
    let prefix = trimmed[..<colon].trimmingCharacters(in: .whitespaces)
    guard prefix == "gitdir" else { return nil }
    let gitdirRaw = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    guard !gitdirRaw.isEmpty, let base = dotGit.parent else { return nil }
    let gitdirPath = AbsolutePathBuf.resolvePathAgainstBase(gitdirRaw, basePath: base.asPath)
    guard FileManager.default.fileExists(atPath: gitdirPath.asPath) else { return nil }
    return gitdirPath
}

func isSlashTmpIgnoredOnWindows(_ path: FileSystemPath, convention: PathConvention?) -> Bool {
    if case .special(value: .slashTmp) = path, convention == .windows {
        return true
    }
    return false
}

func isDirectory(_ path: String) -> Bool {
    var isDir: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
}

func isRegularFile(_ path: String) -> Bool {
    var isDir: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && !isDir.boolValue
}

func pathHasPrefix(_ path: String, prefix: String) -> Bool {
    path == prefix || path.hasPrefix(prefix.hasSuffix("/") ? prefix : prefix + "/")
}

func pathStripPrefix(_ path: String, prefix: String) -> String? {
    if path == prefix { return "" }
    let boundary = prefix.hasSuffix("/") ? prefix : prefix + "/"
    guard path.hasPrefix(boundary) else { return nil }
    return String(path.dropFirst(boundary.count))
}

extension String {
    fileprivate func stripPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}

extension AbsolutePathBuf {
    /// Stand-in for `normalize_system_aliases`. Not yet ported on AbsolutePathBuf;
    /// POSIX/macOS returns `self`.
    func normalizeSystemAliases() throws -> AbsolutePathBuf { self }
}

// MARK: - POSIX glob matcher (globset stand-in)

struct GlobMatcher {
    let regex: NSRegularExpression

    func isMatch(_ bytes: [UInt8]) -> Bool {
        let path = String(decoding: bytes, as: UTF8.self)
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        return regex.firstMatch(in: path, options: [], range: range) != nil
    }
}

func buildGlobMatcher(_ pattern: String, convention: PathConvention) throws -> GlobMatcher {
    let normalized = convention == .windows
        ? pattern.replacingOccurrences(of: "\\", with: "/")
        : pattern
    let regexPattern = try globToRegex(
        normalized,
        backslashEscape: convention == .posix,
        caseInsensitive: convention == .windows
    )
    let options: NSRegularExpression.Options = convention == .windows ? [.caseInsensitive] : []
    do {
        let regex = try NSRegularExpression(pattern: regexPattern, options: options)
        return GlobMatcher(regex: regex)
    } catch {
        throw PermissionStringError(String(describing: error))
    }
}

/// Convert a globset-style pattern into an anchored regular expression.
/// `*` and `?` stay inside one path component; `**` crosses `/`; unclosed
/// `[` is treated as a literal (globset `allow_unclosed_class`).
func globToRegex(
    _ pattern: String,
    backslashEscape: Bool,
    caseInsensitive: Bool
) throws -> String {
    var regex = "^"
    let chars = Array(pattern)
    var i = 0
    while i < chars.count {
        let ch = chars[i]
        if backslashEscape && ch == "\\" {
            i += 1
            if i < chars.count {
                regex += NSRegularExpression.escapedPattern(for: String(chars[i]))
                i += 1
            } else {
                regex += "\\\\"
            }
            continue
        }
        if ch == "*" {
            if i + 1 < chars.count && chars[i + 1] == "*" {
                regex += ".*"
                i += 2
                if i < chars.count && chars[i] == "/" {
                    i += 1
                }
            } else {
                regex += "[^/]*"
                i += 1
            }
            continue
        }
        if ch == "?" {
            regex += "[^/]"
            i += 1
            continue
        }
        if ch == "[" {
            var j = i + 1
            var closed = false
            if j < chars.count && (chars[j] == "!" || chars[j] == "^") {
                j += 1
            }
            if j < chars.count && chars[j] == "]" {
                j += 1
            }
            while j < chars.count {
                if chars[j] == "]" {
                    closed = true
                    break
                }
                j += 1
            }
            if !closed {
                regex += "\\["
                i += 1
                continue
            }
            let classBody = String(chars[(i + 1)..<j])
            try validateGlobCharacterClass(classBody)
            let negated = classBody.hasPrefix("!") || classBody.hasPrefix("^")
            let body = negated ? String(classBody.dropFirst()) : classBody
            regex += "["
            if negated { regex += "^" }
            regex += escapeGlobClassBody(body)
            regex += "]"
            i = j + 1
            continue
        }
        regex += NSRegularExpression.escapedPattern(for: String(ch))
        i += 1
    }
    regex += "$"
    _ = caseInsensitive
    return regex
}

func validateGlobCharacterClass(_ body: String) throws {
    let chars = Array(body.hasPrefix("!") || body.hasPrefix("^") ? body.dropFirst() : body[...])
    var i = 0
    while i < chars.count {
        if i + 2 < chars.count && chars[i + 1] == "-" {
            let start = chars[i]
            let end = chars[i + 2]
            if start > end {
                throw PermissionStringError("invalid character class range")
            }
            i += 3
        } else {
            i += 1
        }
    }
}

func escapeGlobClassBody(_ body: String) -> String {
    body.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "]", with: "\\]")
}