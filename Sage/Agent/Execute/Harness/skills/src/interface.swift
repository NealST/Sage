//
//  interface.swift
//  CodexSkills
//
//  Port of codex-rs/skills/src/interface.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  `tracing::warn` is omitted; invalid fields still drop to `nil`.
//

import CodexUtils
import Foundation

let INTERFACE_MAX_NAME_LEN = 64
let INTERFACE_MAX_DESCRIPTION_LEN = 1024

/// Interface metadata deserialized from a skill's `agents/openai.yaml` file.
public struct SkillInterfaceFile: Equatable, Sendable {
    public var displayName: String?
    public var shortDescription: String?
    public var iconSmall: String?
    public var iconLarge: String?
    public var brandColor: String?
    public var defaultPrompt: String?

    public init(
        displayName: String? = nil,
        shortDescription: String? = nil,
        iconSmall: String? = nil,
        iconLarge: String? = nil,
        brandColor: String? = nil,
        defaultPrompt: String? = nil
    ) {
        self.displayName = displayName
        self.shortDescription = shortDescription
        self.iconSmall = iconSmall
        self.iconLarge = iconLarge
        self.brandColor = brandColor
        self.defaultPrompt = defaultPrompt
    }
}

/// Controls whether interface icons may resolve through a plugin's shared assets directory.
public enum SkillInterfaceAssetPolicy: Sendable {
    case localOnly
    case pluginShared(pluginRoot: AbsolutePathBuf)
}

/// Validates skill interface metadata and resolves its asset paths.
public func resolveSkillInterface(
    _ interface: SkillInterfaceFile?,
    skillDir: AbsolutePathBuf,
    assetPolicy: SkillInterfaceAssetPolicy
) -> SkillInterface? {
    guard let interface else { return nil }
    let resolved = SkillInterface(
        displayName: resolveStr(interface.displayName, maxLen: INTERFACE_MAX_NAME_LEN),
        shortDescription: resolveStr(
            interface.shortDescription,
            maxLen: INTERFACE_MAX_DESCRIPTION_LEN
        ),
        iconSmall: resolveAssetPath(
            skillDir: skillDir,
            assetPolicy: assetPolicy,
            path: interface.iconSmall
        ),
        iconLarge: resolveAssetPath(
            skillDir: skillDir,
            assetPolicy: assetPolicy,
            path: interface.iconLarge
        ),
        brandColor: resolveColorStr(interface.brandColor),
        defaultPrompt: resolveStr(
            interface.defaultPrompt,
            maxLen: INTERFACE_MAX_DESCRIPTION_LEN
        )
    )
    let hasFields = resolved.displayName != nil
        || resolved.shortDescription != nil
        || resolved.iconSmall != nil
        || resolved.iconLarge != nil
        || resolved.brandColor != nil
        || resolved.defaultPrompt != nil
    return hasFields ? resolved : nil
}

func resolveAssetPath(
    skillDir: AbsolutePathBuf,
    assetPolicy: SkillInterfaceAssetPolicy,
    path: String?
) -> AbsolutePathBuf? {
    guard let path, !path.isEmpty else { return nil }
    if path.hasPrefix("/") {
        return nil
    }

    var normalized: [String] = []
    for component in path.split(separator: "/", omittingEmptySubsequences: false).map(String.init) {
        if component == "." || component.isEmpty { continue }
        if component == ".." {
            return resolvePluginSharedAssetPath(
                skillDir: skillDir,
                assetPolicy: assetPolicy,
                path: path
            )
        }
        normalized.append(component)
    }

    guard normalized.first == "assets" else { return nil }
    var joined = skillDir
    for component in normalized {
        joined = joined.join(component)
    }
    return joined
}

func resolvePluginSharedAssetPath(
    skillDir: AbsolutePathBuf,
    assetPolicy: SkillInterfaceAssetPolicy,
    path: String
) -> AbsolutePathBuf? {
    guard case .pluginShared(let pluginRoot) = assetPolicy else {
        return nil
    }
    let pluginAssetsDir = lexicallyNormalize(pluginRoot.join("assets").path)
    let resolved = lexicallyNormalize(skillDir.join(path).path)
    guard resolved == pluginAssetsDir || resolved.hasPrefix(pluginAssetsDir + "/") else {
        return nil
    }
    return try? AbsolutePathBuf.fromAbsolutePath(resolved)
}

func lexicallyNormalize(_ path: String) -> String {
    var parts: [String] = []
    let isAbsolute = path.hasPrefix("/")
    for component in path.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
        if component == "." { continue }
        if component == ".." {
            if !parts.isEmpty { parts.removeLast() }
            continue
        }
        parts.append(component)
    }
    let joined = parts.joined(separator: "/")
    return isAbsolute ? "/" + joined : joined
}

func resolveStr(_ value: String?, maxLen: Int) -> String? {
    guard let value else { return nil }
    let collapsed = value.split { $0.isWhitespace }.joined(separator: " ")
    if collapsed.isEmpty { return nil }
    if collapsed.count > maxLen { return nil }
    return collapsed
}

func resolveColorStr(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return nil }
    guard trimmed.count == 7, trimmed.first == "#" else { return nil }
    let hex = trimmed.dropFirst()
    guard hex.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { return nil }
    return trimmed
}
