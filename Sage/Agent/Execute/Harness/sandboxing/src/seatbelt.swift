//
//  seatbelt.swift
//  CodexSandboxing
//
//  Port of codex-rs/sandboxing/src/seatbelt.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: partial
//
//  Seatbelt profile assembly, glob→regex translation, and
//  `createSeatbeltCommandArgs` match upstream. `.sbpl` fragments are
//  bundled (`include_str!` → `Bundle.module`). Network-proxy inputs use
//  the inlined type layer. `regex_lite::escape` is
//  `NSRegularExpression.escapedPattern`.
//

import CodexProtocol
import CodexUtils
import Foundation

public let MACOS_PATH_TO_SEATBELT_EXECUTABLE = "/usr/bin/sandbox-exec"

enum MacosSeatbeltProfile: Equatable, Sendable {
    case process
    case fileSystemHelper
}

enum SeatbeltPreparationError: Error, CustomStringConvertible {
    case fileSystem(String)
    case environmentNetworkProxy(String)

    var description: String {
        switch self {
        case .fileSystem(let message), .environmentNetworkProxy(let message):
            return message
        }
    }
}

struct SeatbeltAccessRoot: Equatable, Sendable {
    var root: AbsolutePathBuf
    var excludedSubpaths: [AbsolutePathBuf]
    var protectedMetadataNames: [String]
}

public struct CreateSeatbeltCommandArgsParams: Sendable {
    public var command: [String]
    public var fileSystemSandboxPolicy: FileSystemSandboxPolicy
    public var networkSandboxPolicy: NetworkSandboxPolicy
    public var sandboxPolicyCwd: String
    public var enforceManagedNetwork: Bool
    public var managedNetwork: ManagedNetworkSandboxContext?
    public var environmentId: String?
    public var network: NetworkProxy?
    public var extraAllowUnixSockets: [AbsolutePathBuf]

    public init(
        command: [String],
        fileSystemSandboxPolicy: FileSystemSandboxPolicy,
        networkSandboxPolicy: NetworkSandboxPolicy,
        sandboxPolicyCwd: String,
        enforceManagedNetwork: Bool,
        managedNetwork: ManagedNetworkSandboxContext? = nil,
        environmentId: String? = nil,
        network: NetworkProxy? = nil,
        extraAllowUnixSockets: [AbsolutePathBuf] = []
    ) {
        self.command = command
        self.fileSystemSandboxPolicy = fileSystemSandboxPolicy
        self.networkSandboxPolicy = networkSandboxPolicy
        self.sandboxPolicyCwd = sandboxPolicyCwd
        self.enforceManagedNetwork = enforceManagedNetwork
        self.managedNetwork = managedNetwork
        self.environmentId = environmentId
        self.network = network
        self.extraAllowUnixSockets = extraAllowUnixSockets
    }
}

public func createSeatbeltCommandArgs(
    _ args: CreateSeatbeltCommandArgsParams
) throws -> [String] {
    try createSeatbeltCommandArgsWithProfile(
        args,
        profile: .process,
        allowedSymlinkedCodexHome: nil
    )
}

func createSeatbeltCommandArgsWithProfile(
    _ args: CreateSeatbeltCommandArgsParams,
    profile: MacosSeatbeltProfile,
    allowedSymlinkedCodexHome: AbsolutePathBuf?
) throws -> [String] {
    let policy = args.fileSystemSandboxPolicy
    let cwd = args.sandboxPolicyCwd
    let unreadableRoots = policy.getUnreadableRootsWithCwd(cwd)
    var writableRoots = policy.getWritableRootsWithCwdPreservingMutablePaths(cwd)
    let includePlatformDefaults = policy.includePlatformDefaults()
    let scratchReads: [SeatbeltAccessRoot]
    if includePlatformDefaults && profile == .process {
        let scratch = try scratchAccessRoots(policy: policy, cwd: cwd, writableRoots: writableRoots)
        writableRoots.append(contentsOf: scratch.writes)
        scratchReads = scratch.reads
    } else {
        scratchReads = []
    }

    var protectedAncestors = Set<String>()
    for writableRoot in writableRoots {
        let root = normalizePathForSandbox(writableRoot.root.asPath) ?? writableRoot.root
        for path in writableRoot.readOnlySubpaths {
            let logical = try normalizeTopLevelAliasForSandbox(path)
            let resolved = normalizePathForSandbox(logical.asPath).flatMap { $0 != logical ? $0 : nil }
            for protectedPath in [logical] + (resolved.map { [$0] } ?? []) {
                for ancestor in protectedPath.ancestors().dropFirst() {
                    if !ancestor.asPath.hasPrefix(root.asPath == "/" ? "/" : root.asPath + "/")
                        && ancestor.asPath != root.asPath {
                        break
                    }
                    protectedAncestors.insert(ancestor.asPath)
                }
            }
        }
    }
    let protectedAncestorParams = protectedAncestors.sorted().enumerated().map { index, path in
        ("PROTECTED_ANCESTOR_\(index)", path)
    }

    let (fileWritePolicy, fileWriteDirParams): (String, [(String, String)])
    if policy.hasFullDiskWriteAccess() {
        if unreadableRoots.isEmpty {
            fileWritePolicy = #"(allow file-write* (regex #"^/"))"#
            fileWriteDirParams = []
        } else {
            (fileWritePolicy, fileWriteDirParams) = try buildSeatbeltAccessPolicy(
                accessKind: .write,
                roots: [
                    SeatbeltAccessRoot(
                        root: rootAbsolutePath(),
                        excludedSubpaths: unreadableRoots,
                        protectedMetadataNames: []
                    )
                ],
                allowedSymlinkedCodexHome: nil
            )
        }
    } else {
        (fileWritePolicy, fileWriteDirParams) = try buildSeatbeltAccessPolicy(
            accessKind: .write,
            roots: writableRoots.map { root in
                SeatbeltAccessRoot(
                    root: root.root,
                    excludedSubpaths: root.readOnlySubpaths,
                    protectedMetadataNames: protectedMetadataNamesForWritableRoot(
                        policy: policy,
                        writableRoot: root,
                        cwd: cwd
                    )
                )
            },
            allowedSymlinkedCodexHome: allowedSymlinkedCodexHome
        )
    }

    let (fileReadPolicy, fileReadDirParams): (String, [(String, String)])
    if policy.hasFullDiskReadAccess() {
        if unreadableRoots.isEmpty {
            fileReadPolicy = "; allow read-only file operations\n(allow file-read*)"
            fileReadDirParams = []
        } else {
            let built = try buildSeatbeltAccessPolicy(
                accessKind: .read,
                roots: [
                    SeatbeltAccessRoot(
                        root: rootAbsolutePath(),
                        excludedSubpaths: unreadableRoots,
                        protectedMetadataNames: []
                    )
                ],
                allowedSymlinkedCodexHome: nil
            )
            fileReadPolicy = "; allow read-only file operations\n\(built.0)"
            fileReadDirParams = built.1
        }
    } else {
        let built = try buildSeatbeltAccessPolicy(
            accessKind: .read,
            roots: policy.getReadableRootsWithCwd(cwd).map { root in
                SeatbeltAccessRoot(
                    root: root,
                    excludedSubpaths: unreadableRoots.filter {
                        $0.asPath.hasPrefix(root.asPath == "/" ? "/" : root.asPath + "/")
                            || $0.asPath == root.asPath
                    },
                    protectedMetadataNames: []
                )
            } + scratchReads,
            allowedSymlinkedCodexHome: nil
        )
        fileReadPolicy = built.0.isEmpty ? "" : "; allow read-only file operations\n\(built.0)"
        fileReadDirParams = built.1
    }

    let proxy = try proxyPolicyInputs(
        managedNetwork: args.managedNetwork,
        network: args.network,
        environmentId: args.environmentId,
        extraAllowUnixSockets: args.extraAllowUnixSockets
    )
    let networkPolicy = dynamicNetworkPolicyForNetwork(
        args.networkSandboxPolicy,
        enforceManagedNetwork: args.enforceManagedNetwork,
        proxy: proxy
    )
    let denyReadPolicy = buildSeatbeltUnreadableGlobPolicy(policy, cwd: cwd)

    var policySections = [
        seatbeltResource("seatbelt_base_policy.sbpl"),
        fileReadPolicy,
        fileWritePolicy,
        networkPolicy,
    ]
    if policy.hasFullDiskReadAccess() {
        policySections.append(seatbeltResource("seatbelt_preferences_policy.sbpl"))
    }
    if includePlatformDefaults {
        policySections.append(seatbeltResource("seatbelt_read_only_platform_defaults.sbpl"))
        if profile == .process {
            policySections.append(#"(allow file-read* (subpath "/Applications"))"#)
        }
    }
    if !policy.hasFullDiskWriteAccess() {
        let directory = try sharedDaemonSocketDirectory()
        policySections.append(try seatbeltDaemonProtectionPolicy(directory: directory))
    }
    policySections.append(#"(deny mach-lookup (xpc-service-name-prefix ""))"#)
    policySections.append(denyReadPolicy)
    policySections.append(contentsOf: protectedAncestorParams.map { key, _ in
        "(deny file-write-unlink (require-all (vnode-type DIRECTORY) (literal (param \"\(key)\"))))"
    })
    if !policy.hasFullDiskWriteAccess() {
        policySections.append("(deny system-fcntl (fcntl-command 80 110))")
    }

    let fullPolicy = policySections.joined(separator: "\n")
    let dirParams = fileReadDirParams + fileWriteDirParams + protectedAncestorParams + unixSocketDirParams(proxy)
    var seatbeltArgs = ["-p", fullPolicy]
    seatbeltArgs.append(contentsOf: dirParams.map { key, value in "-D\(key)=\(value)" })
    seatbeltArgs.append("--")
    seatbeltArgs.append(contentsOf: args.command)
    return seatbeltArgs
}

private enum SeatbeltAccessKind { case read, write }
private enum SeatbeltPathMatch { case literal, subpath }
private enum NormalizedWritableRoot {
    case subpath(AbsolutePathBuf)
    case literal(AbsolutePathBuf)
}

private struct ProxyPolicyInputs {
    var ports: [UInt16] = []
    var hasProxyConfig = false
    var allowLocalBinding = false
    var unixDomainSocketPolicy: UnixDomainSocketPolicy = .restricted(allowed: [])
}

private enum UnixDomainSocketPolicy {
    case allowAll
    case restricted(allowed: [AbsolutePathBuf])
}

private func isLoopbackHost(_ host: String) -> Bool {
    host.caseInsensitiveCompare("localhost") == .orderedSame
        || host == "127.0.0.1"
        || host == "::1"
}

private func proxySchemeDefaultPort(_ scheme: String) -> UInt16 {
    switch scheme {
    case "https": return 443
    case "socks5", "socks5h", "socks4", "socks4a": return 1080
    default: return 80
    }
}

private func proxyLoopbackPortsFromEnv(_ env: [String: String]) -> [UInt16] {
    var ports = Set<UInt16>()
    for key in PROXY_URL_ENV_KEYS {
        guard let proxyURL = proxyURLEnvValue(env, key: key) else { continue }
        let trimmed = proxyURL.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { continue }
        let candidate = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let parsed = URL(string: candidate), let host = parsed.host, isLoopbackHost(host) else {
            continue
        }
        let scheme = parsed.scheme?.lowercased() ?? "http"
        ports.insert(UInt16(parsed.port ?? Int(proxySchemeDefaultPort(scheme))))
    }
    return ports.sorted()
}

private func proxyPolicyInputs(
    managedNetwork: ManagedNetworkSandboxContext?,
    network: NetworkProxy?,
    environmentId: String?,
    extraAllowUnixSockets: [AbsolutePathBuf]
) throws -> ProxyPolicyInputs {
    let extraAllowed = extraAllowUnixSockets.compactMap { normalizePathForSandbox($0.asPath) }
    let unixPolicy: UnixDomainSocketPolicy
    if let context = managedNetwork {
        unixPolicy = context.dangerouslyAllowAllUnixSockets
            ? .allowAll
            : .restricted(allowed: context.allowUnixSockets.compactMap {
                normalizePathForSandbox($0)
            } + extraAllowed)
        return ProxyPolicyInputs(
            ports: context.loopbackPorts,
            hasProxyConfig: true,
            allowLocalBinding: context.allowLocalBinding,
            unixDomainSocketPolicy: unixPolicy
        )
    }
    if let network {
        unixPolicy = network.dangerouslyAllowAllUnixSocketsValue()
            ? .allowAll
            : .restricted(allowed: network.allowUnixSocketsValue().compactMap {
                normalizePathForSandbox($0)
            } + extraAllowed)
        var env: [String: String] = [:]
        try network.applyToEnvForOptionalEnvironment(&env, environmentId: environmentId)
        return ProxyPolicyInputs(
            ports: proxyLoopbackPortsFromEnv(env),
            hasProxyConfig: hasProxyURLEnvVars(env),
            allowLocalBinding: network.allowLocalBindingValue(),
            unixDomainSocketPolicy: unixPolicy
        )
    }
    return ProxyPolicyInputs(unixDomainSocketPolicy: .restricted(allowed: extraAllowed))
}

private func unixSocketDirParams(_ proxy: ProxyPolicyInputs) -> [(String, String)] {
    guard case .restricted(let allowed) = proxy.unixDomainSocketPolicy else { return [] }
    var seen: [String: AbsolutePathBuf] = [:]
    for path in allowed { seen[path.toStringLossy] = path }
    return seen.values.sorted().enumerated().map { index, path in
        ("UNIX_SOCKET_PATH_\(index)", path.asPath)
    }
}

private func unixSocketPolicy(_ proxy: ProxyPolicyInputs) -> String {
    let params = unixSocketDirParams(proxy)
    let hasAccess: Bool = {
        if case .allowAll = proxy.unixDomainSocketPolicy { return true }
        return !params.isEmpty
    }()
    if !hasAccess { return "" }
    var policy = "(allow system-socket (socket-domain AF_UNIX))\n"
    if case .allowAll = proxy.unixDomainSocketPolicy {
        policy += "(allow network-bind (local unix-socket))\n"
        policy += "(allow network-outbound (remote unix-socket))\n"
        return policy
    }
    for (key, _) in params {
        policy += "(allow network-bind (local unix-socket (subpath (param \"\(key)\"))))\n"
        policy += "(allow network-outbound (remote unix-socket (subpath (param \"\(key)\"))))\n"
    }
    return policy
}

private func dynamicNetworkPolicyForNetwork(
    _ networkPolicy: NetworkSandboxPolicy,
    enforceManagedNetwork: Bool,
    proxy: ProxyPolicyInputs
) -> String {
    let hasUnix: Bool = {
        switch proxy.unixDomainSocketPolicy {
        case .allowAll: return true
        case .restricted(let allowed): return !allowed.isEmpty
        }
    }()
    let restricted = !proxy.ports.isEmpty
        || proxy.hasProxyConfig
        || enforceManagedNetwork
        || (!networkPolicy.isEnabled && hasUnix)
    if restricted {
        var policy = ""
        if proxy.allowLocalBinding {
            policy += "; allow local binding and loopback traffic\n"
            policy += "(allow network-bind (local ip \"*:*\"))\n"
            policy += "(allow network-inbound (local ip \"localhost:*\"))\n"
            policy += "(allow network-outbound (remote ip \"localhost:*\"))\n"
        }
        if proxy.allowLocalBinding && !proxy.ports.isEmpty {
            policy += "; allow DNS lookups while application traffic remains proxy-routed\n"
            policy += "(allow network-outbound (remote ip \"*:53\"))\n"
        }
        for port in proxy.ports {
            policy += "(allow network-outbound (remote ip \"localhost:\(port)\"))\n"
        }
        let unix = unixSocketPolicy(proxy)
        if !unix.isEmpty {
            policy += "; allow unix domain sockets for local IPC\n"
            policy += unix
        }
        return policy + seatbeltResource("seatbelt_network_policy.sbpl")
    }
    if proxy.hasProxyConfig || enforceManagedNetwork {
        return ""
    }
    if networkPolicy.isEnabled {
        var policy = "(allow network-outbound)\n(allow network-inbound)\n"
        let unix = unixSocketPolicy(proxy)
        if !unix.isEmpty {
            policy += "; allow unix domain sockets for local IPC\n"
            policy += unix
        }
        return policy + seatbeltResource("seatbelt_network_policy.sbpl")
    }
    return ""
}

private func rootAbsolutePath() -> AbsolutePathBuf {
    (try? AbsolutePathBuf.fromAbsolutePath("/")) ?? AbsolutePathBuf.resolvePathAgainstBase("/", basePath: "/")
}

func normalizePathForSandbox(_ path: String) -> AbsolutePathBuf? {
    guard path.hasPrefix("/") else { return nil }
    guard let absolute = try? AbsolutePathBuf.fromAbsolutePath(path) else { return nil }
    if let canonical = try? absolute.canonicalize() {
        return canonical
    }
    return absolute
}

func normalizeTopLevelAliasForSandbox(_ path: AbsolutePathBuf) throws -> AbsolutePathBuf {
    if path.asPath == "/tmp" || path.asPath.hasPrefix("/tmp/") {
        let mapped = "/private" + path.asPath
        return (try? AbsolutePathBuf.fromAbsolutePath(mapped)) ?? path
    }
    if path.asPath == "/var" || path.asPath.hasPrefix("/var/") {
        let mapped = "/private" + path.asPath
        return (try? AbsolutePathBuf.fromAbsolutePath(mapped)) ?? path
    }
    return path
}

func protectedMetadataNamesForWritableRoot(
    policy: FileSystemSandboxPolicy,
    writableRoot: WritableRoot,
    cwd: String
) -> [String] {
    var names = writableRoot.protectedMetadataNames
    for name in PROTECTED_METADATA_PATH_NAMES {
        if names.contains(name) { continue }
        let path = writableRoot.root.join(name)
        if !policy.canWriteLocalPathWithCwd(path.asPath, cwd: cwd) {
            names.append(name)
        }
    }
    return names
}

private func nestedSymlinkComponent(_ path: String) -> String? {
    var current = path
    while current != "/" {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: current),
           attrs[.type] as? FileAttributeType == .typeSymbolicLink {
            let parent = (current as NSString).deletingLastPathComponent
            let grand = (parent as NSString).deletingLastPathComponent
            if !grand.isEmpty { return current }
        }
        let parent = (current as NSString).deletingLastPathComponent
        if parent == current { break }
        current = parent
    }
    return nil
}

private func normalizeWritableRootForSandbox(
    _ root: AbsolutePathBuf,
    allowedSymlinkedCodexHome: AbsolutePathBuf?
) throws -> NormalizedWritableRoot {
    let allowSymlinks = allowedSymlinkedCodexHome.map { home in
        root.asPath.hasPrefix(home.asPath)
            || (normalizePathForSandbox(home.asPath).map { root.asPath.hasPrefix($0.asPath) } ?? false)
    } ?? false
    if !allowSymlinks, let symlink = nestedSymlinkComponent(root.asPath) {
        throw SeatbeltPreparationError.fileSystem(
            "writable root \(root.display) contains symlink component \(symlink); symlinked writable roots are not supported."
        )
    }
    let normalized = allowSymlinks
        ? (normalizePathForSandbox(root.asPath) ?? root)
        : (try normalizeTopLevelAliasForSandbox(root))
    do {
        let attrs = try FileManager.default.attributesOfItem(atPath: normalized.asPath)
        if attrs[.type] as? FileAttributeType == .typeDirectory {
            return .subpath(normalized)
        }
        return .literal(normalized)
    } catch {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain
            && (ns.code == NSFileReadNoSuchFileError || ns.code == NSFileNoSuchFileError) {
            return .subpath(normalized)
        }
        throw SeatbeltPreparationError.fileSystem(
            "failed to inspect Seatbelt writable root \(normalized.display): \(error)"
        )
    }
}

private func buildSeatbeltAccessPolicy(
    accessKind: SeatbeltAccessKind,
    roots: [SeatbeltAccessRoot],
    allowedSymlinkedCodexHome: AbsolutePathBuf?
) throws -> (String, [(String, String)]) {
    var policyComponents: [String] = []
    var rootAnchorDenies: [String] = []
    var params: [(String, String)] = []
    let (action, paramPrefix): (String, String) = {
        switch accessKind {
        case .read: return ("file-read*", "READABLE_ROOT")
        case .write: return ("file-write*", "WRITABLE_ROOT")
        }
    }()

    for (index, accessRoot) in roots.enumerated() {
        let root: AbsolutePathBuf
        let pathMatch: SeatbeltPathMatch
        switch accessKind {
        case .read:
            root = normalizePathForSandbox(accessRoot.root.asPath) ?? accessRoot.root
            pathMatch = .subpath
        case .write:
            switch try normalizeWritableRootForSandbox(
                accessRoot.root,
                allowedSymlinkedCodexHome: allowedSymlinkedCodexHome
            ) {
            case .subpath(let value):
                root = value
                pathMatch = .subpath
            case .literal(let value):
                root = value
                pathMatch = .literal
            }
        }
        let rootParam = "\(paramPrefix)_\(index)"
        params.append((rootParam, root.asPath))
        if accessKind == .write {
            rootAnchorDenies.append(
                "(deny file-write-unlink (require-all (literal (param \"\(rootParam)\")) (vnode-type DIRECTORY)))"
            )
        }
        let rootFilter = pathMatch == .literal
            ? "(literal (param \"\(rootParam)\"))"
            : "(subpath (param \"\(rootParam)\"))"
        if accessRoot.excludedSubpaths.isEmpty && accessRoot.protectedMetadataNames.isEmpty {
            policyComponents.append(rootFilter)
            continue
        }
        var requireParts = [rootFilter]
        for (excludedIndex, excludedSubpath) in accessRoot.excludedSubpaths.enumerated() {
            let excludedParam = "\(paramPrefix)_\(index)_EXCLUDED_\(excludedIndex)"
            let excludedPairs: [(String, AbsolutePathBuf)]
            switch accessKind {
            case .read:
                excludedPairs = [
                    (excludedParam, normalizePathForSandbox(excludedSubpath.asPath) ?? excludedSubpath)
                ]
            case .write:
                let logical = try normalizeTopLevelAliasForSandbox(excludedSubpath)
                var pairs = [(excludedParam, logical)]
                if let resolved = normalizePathForSandbox(logical.asPath), resolved != logical {
                    pairs.append(("\(excludedParam)_RESOLVED", resolved))
                }
                excludedPairs = pairs
            }
            for (param, path) in excludedPairs {
                params.append((param, path.asPath))
                requireParts.append("(require-not (literal (param \"\(param)\")))")
                requireParts.append("(require-not (subpath (param \"\(param)\")))")
            }
        }
        for metadataName in accessRoot.protectedMetadataNames {
            let regex = seatbeltProtectedMetadataNameRegex(root, name: metadataName)
                .replacingOccurrences(of: "\"", with: "\\\"")
            requireParts.append("(require-not (regex #\"\(regex)\"))")
        }
        policyComponents.append("(require-all \(requireParts.joined(separator: " ")) )")
    }

    if policyComponents.isEmpty {
        return ("", [])
    }
    var policies = ["(allow \(action)\n\(policyComponents.joined(separator: " "))\n)"]
    policies.append(contentsOf: rootAnchorDenies)
    return (policies.joined(separator: "\n"), params)
}

private func seatbeltProtectedMetadataNameRegex(_ root: AbsolutePathBuf, name: String) -> String {
    var rootPath = root.toStringLossy
    while rootPath.count > 1 && rootPath.hasSuffix("/") { rootPath.removeLast() }
    let rootEsc = NSRegularExpression.escapedPattern(for: rootPath)
    let nameEsc = NSRegularExpression.escapedPattern(for: name)
    if rootPath == "/" {
        return "^/\(nameEsc)(/.*)?$"
    }
    return "^\(rootEsc)/\(nameEsc)(/.*)?$"
}

private func buildSeatbeltUnreadableGlobPolicy(
    _ policy: FileSystemSandboxPolicy,
    cwd: String
) -> String {
    let globs = policy.getUnreadableGlobsWithCwd(cwd)
    if globs.isEmpty { return "" }
    var components: [String] = []
    for pattern in globs {
        var patterns = Set([pattern])
        if let canonical = canonicalizeGlobStaticPrefixForSandbox(pattern) {
            patterns.insert(canonical)
        }
        for pattern in patterns {
            let globalLiteralBasename = pattern.hasPrefix("/**/") && {
                let name = String(pattern.dropFirst(4))
                return !name.isEmpty && name != "." && name != ".."
                    && !name.contains(where: { "/ * ? [ ] { } \\".contains($0) })
            }()
            guard var regex = seatbeltRegexForGlob(pattern, globMatch: .subtree) else { continue }
            if globalLiteralBasename {
                regex.removeLast()
                regex += "(/.*)?$"
            }
            let escaped = regex.replacingOccurrences(of: "\"", with: "\\\"")
            components.append("(deny file-read* (regex #\"\(escaped)\"))")
            components.append("(deny file-write* (regex #\"\(escaped)\"))")
            if globalLiteralBasename { continue }
            var ancestor = (pattern as NSString).deletingLastPathComponent
            while !ancestor.isEmpty && ancestor != "." {
                if let regex = seatbeltRegexForGlob(ancestor, globMatch: .exact) {
                    let escaped = regex.replacingOccurrences(of: "\"", with: "\\\"")
                    components.append(
                        "(deny file-write-unlink (require-all (vnode-type DIRECTORY) (regex #\"\(escaped)\")))"
                    )
                }
                let parent = (ancestor as NSString).deletingLastPathComponent
                if parent == ancestor { break }
                ancestor = parent
            }
        }
    }
    return components.joined(separator: "\n")
}

private func canonicalizeGlobStaticPrefixForSandbox(_ pattern: String) -> String? {
    guard let firstGlob = pattern.firstIndex(where: { "*?[]{\\".contains($0) }) else {
        return normalizePathForSandbox(pattern)?.toStringLossy
    }
    let staticPrefix = String(pattern[..<firstGlob])
    let prefixEnd = staticPrefix.hasSuffix("/")
        ? staticPrefix.count - 1
        : (staticPrefix.lastIndex(of: "/")?.utf16Offset(in: staticPrefix) ?? 0)
    if prefixEnd == 0 { return nil }
    let endIndex = pattern.index(pattern.startIndex, offsetBy: prefixEnd)
    guard let root = normalizePathForSandbox(String(pattern[..<endIndex])) else { return nil }
    let suffix = String(pattern[endIndex...])
    let normalized = root.toStringLossy + suffix
    return normalized != pattern ? normalized : nil
}

enum GlobMatch { case exact, subtree }

func seatbeltRegexForGlob(_ pattern: String, globMatch: GlobMatch) -> String? {
    if pattern.isEmpty { return nil }
    var regex = "^"
    var chars = Array(pattern)
    var i = 0
    var sawGlob = false
    var alternateDepth = 0
    while i < chars.count {
        let ch = chars[i]
        i += 1
        switch ch {
        case "*":
            sawGlob = true
            if i < chars.count && chars[i] == "*" {
                i += 1
                if i < chars.count && chars[i] == "/" {
                    i += 1
                    regex += "(.*/)?"
                } else {
                    regex += ".*"
                }
            } else {
                regex += "[^/]*"
            }
        case "?":
            sawGlob = true
            regex += "[^/]"
        case "\\":
            if i < chars.count {
                regex += NSRegularExpression.escapedPattern(for: String(chars[i]))
                i += 1
            } else {
                regex += "\\\\"
            }
        case "{":
            sawGlob = true
            alternateDepth += 1
            regex += "("
        case "}" where alternateDepth > 0:
            alternateDepth -= 1
            regex += ")"
        case "," where alternateDepth > 0:
            regex += "|"
        case "[":
            sawGlob = true
            var classChars: [Character] = []
            var closed = false
            while i < chars.count {
                let classCh = chars[i]
                i += 1
                if classCh == "]" {
                    closed = true
                    break
                }
                classChars.append(classCh)
            }
            if !closed {
                regex += "\\["
                chars.insert(contentsOf: classChars.reversed(), at: i)
                continue
            }
            regex += "["
            if let first = classChars.first {
                switch first {
                case "!": regex += "^"
                case "^": regex += "\\^"
                default: regex.append(first)
                }
                for classCh in classChars.dropFirst() {
                    if classCh == "\\" { regex += "\\\\" }
                    else { regex.append(classCh) }
                }
            }
            regex += "]"
        case "]":
            sawGlob = true
            regex += "\\]"
        default:
            regex += NSRegularExpression.escapedPattern(for: String(ch))
        }
    }
    for _ in 0..<alternateDepth { regex += ")" }
    if !sawGlob && globMatch == .subtree {
        regex += "(/.*)?"
    }
    regex += "$"
    return regex
}

private func seatbeltResource(_ name: String) -> String {
    if let url = Bundle.module.url(forResource: name, withExtension: nil),
       let contents = try? String(contentsOf: url, encoding: .utf8) {
        return contents
    }
    // SPM resource copy may drop the extension into the resource name.
    let stem = (name as NSString).deletingPathExtension
    if let url = Bundle.module.url(forResource: stem, withExtension: "sbpl"),
       let contents = try? String(contentsOf: url, encoding: .utf8) {
        return contents
    }
    return ""
}
