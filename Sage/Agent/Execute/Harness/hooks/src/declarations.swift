//
//  declarations.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/declarations.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `PluginHookSource` is a local stand-in until `codex_plugin` is ported.
//  Declaration keys still use `hook_key`.
//

import CodexProtocol
import Foundation

/// Minimal declaration metadata for one bundled plugin hook handler.
public struct PluginHookDeclaration: Equatable, Sendable {
    public var key: String
    public var eventName: HookEventName

    public init(key: String, eventName: HookEventName) {
        self.key = key
        self.eventName = eventName
    }
}

public struct PluginHookMatcherGroup: Equatable, Sendable {
    public var handlerCount: Int

    public init(handlerCount: Int) {
        self.handlerCount = handlerCount
    }
}

public struct PluginHookSource: Equatable, Sendable {
    public var pluginId: String
    public var sourceRelativePath: String
    public var groupsByEvent: [(HookEventName, [PluginHookMatcherGroup])]

    public init(
        pluginId: String,
        sourceRelativePath: String,
        groupsByEvent: [(HookEventName, [PluginHookMatcherGroup])] = []
    ) {
        self.pluginId = pluginId
        self.sourceRelativePath = sourceRelativePath
        self.groupsByEvent = groupsByEvent
    }

    public static func == (lhs: PluginHookSource, rhs: PluginHookSource) -> Bool {
        lhs.pluginId == rhs.pluginId
            && lhs.sourceRelativePath == rhs.sourceRelativePath
            && lhs.groupsByEvent.count == rhs.groupsByEvent.count
            && zip(lhs.groupsByEvent, rhs.groupsByEvent).allSatisfy {
                $0.0 == $1.0 && $0.1 == $1.1
            }
    }
}

/// Return the hook handlers declared by plugin bundles without projecting live runtime state.
public func pluginHookDeclarations(_ hookSources: [PluginHookSource]) -> [PluginHookDeclaration] {
    var declarations: [PluginHookDeclaration] = []
    for source in hookSources {
        let keySource = pluginHookKeySource(
            pluginId: source.pluginId,
            sourceRelativePath: source.sourceRelativePath
        )
        for (eventName, groups) in source.groupsByEvent {
            for (groupIndex, group) in groups.enumerated() {
                for handlerIndex in 0..<group.handlerCount {
                    declarations.append(
                        PluginHookDeclaration(
                            key: hookKey(
                                keySource: keySource,
                                eventName: eventName,
                                groupIndex: groupIndex,
                                handlerIndex: handlerIndex
                            ),
                            eventName: eventName
                        )
                    )
                }
            }
        }
    }
    return declarations
}

func pluginHookKeySource(pluginId: String, sourceRelativePath: String) -> String {
    "\(pluginId):\(sourceRelativePath)"
}
