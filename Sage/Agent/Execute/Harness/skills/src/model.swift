//
//  model.swift
//  CodexSkills
//
//  Port of codex-rs/skills/src/model.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol
import CodexUtils
import Foundation

/// Metadata for one skill materialized on the host filesystem.
public struct SkillMetadata: Equatable, Sendable {
    public var name: String
    public var description: String
    public var shortDescription: String?
    public var interface: SkillInterface?
    public var dependencies: SkillDependencies?
    public var policy: SkillPolicy?
    /// Path to the SKILL.md file that declares this skill.
    public var pathToSkillsMd: AbsolutePathBuf
    public var scope: SkillScope
    public var pluginId: String?
    public var remotePluginId: String?

    public init(
        name: String,
        description: String,
        shortDescription: String? = nil,
        interface: SkillInterface? = nil,
        dependencies: SkillDependencies? = nil,
        policy: SkillPolicy? = nil,
        pathToSkillsMd: AbsolutePathBuf,
        scope: SkillScope,
        pluginId: String? = nil,
        remotePluginId: String? = nil
    ) {
        self.name = name
        self.description = description
        self.shortDescription = shortDescription
        self.interface = interface
        self.dependencies = dependencies
        self.policy = policy
        self.pathToSkillsMd = pathToSkillsMd
        self.scope = scope
        self.pluginId = pluginId
        self.remotePluginId = remotePluginId
    }

    public func allowsImplicitInvocation() -> Bool {
        policy?.allowImplicitInvocation ?? true
    }

    public func matchesProductRestrictionForProduct(_ restrictionProduct: Product?) -> Bool {
        skillPolicyMatchesProductRestriction(policy, restrictionProduct)
    }
}

/// URI-native metadata for one skill owned by an execution environment.
public struct EnvironmentSkillMetadata: Equatable, Sendable {
    public var pathToSkillsMd: PathUri
    public var name: String
    public var description: String
    public var shortDescription: String?
    public var dependencies: SkillDependencies?
    public var policy: SkillPolicy?

    public init(
        pathToSkillsMd: PathUri,
        name: String,
        description: String,
        shortDescription: String? = nil,
        dependencies: SkillDependencies? = nil,
        policy: SkillPolicy? = nil
    ) {
        self.pathToSkillsMd = pathToSkillsMd
        self.name = name
        self.description = description
        self.shortDescription = shortDescription
        self.dependencies = dependencies
        self.policy = policy
    }

    public func allowsImplicitInvocation() -> Bool {
        policy?.allowImplicitInvocation ?? true
    }

    public func matchesProductRestriction(_ restrictionProduct: Product?) -> Bool {
        skillPolicyMatchesProductRestriction(policy, restrictionProduct)
    }
}

public struct SkillPolicy: Equatable, Sendable {
    public var allowImplicitInvocation: Bool?
    public var products: [Product]

    public init(allowImplicitInvocation: Bool? = nil, products: [Product] = []) {
        self.allowImplicitInvocation = allowImplicitInvocation
        self.products = products
    }
}

public struct SkillInterface: Equatable, Sendable {
    public var displayName: String?
    public var shortDescription: String?
    public var iconSmall: AbsolutePathBuf?
    public var iconLarge: AbsolutePathBuf?
    public var brandColor: String?
    public var defaultPrompt: String?

    public init(
        displayName: String? = nil,
        shortDescription: String? = nil,
        iconSmall: AbsolutePathBuf? = nil,
        iconLarge: AbsolutePathBuf? = nil,
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

public struct SkillDependencies: Equatable, Sendable {
    public var tools: [SkillToolDependency]

    public init(tools: [SkillToolDependency] = []) {
        self.tools = tools
    }
}

public struct SkillToolDependency: Equatable, Sendable {
    public var type: String
    public var value: String
    public var description: String?
    public var transport: String?
    public var command: String?
    public var url: String?
    public var oauthCallbackPort: UInt16?

    public init(
        type: String,
        value: String,
        description: String? = nil,
        transport: String? = nil,
        command: String? = nil,
        url: String? = nil,
        oauthCallbackPort: UInt16? = nil
    ) {
        self.type = type
        self.value = value
        self.description = description
        self.transport = transport
        self.command = command
        self.url = url
        self.oauthCallbackPort = oauthCallbackPort
    }
}

func skillPolicyMatchesProductRestriction(
    _ policy: SkillPolicy?,
    _ restrictionProduct: Product?
) -> Bool {
    guard let policy else { return true }
    return policy.products.isEmpty
        || restrictionProduct.map { $0.matchesProductRestriction(policy.products) } == true
}
