import Foundation

/// One agent workspace: General or a single Project.
/// Owns transcript/runtime/tips/draft for that window; tips live until this session ends.
@Observable
@MainActor
final class AgentSession: Identifiable {
    enum Kind: Hashable, Sendable {
        case general
        case project(UUID)

        var windowAutosaveName: String {
            switch self {
            case .general:
                return "SageAgentWindow.General"

            case .project(let id):
                return "SageAgentWindow.Project.\(id.uuidString)"
            }
        }
    }

    let kind: Kind
    var draft: String = ""
    let agent: AgentRuntime
    /// Skills catalog for this window's focus. MCP tools come from AppState's shared hub.
    let skillCatalog: SkillCatalog
    /// Tip queues + save jobs (observation isolated from streaming runtime).
    let skills: SkillSessionController

    var id: Kind { kind }

    var projectID: UUID? {
        if case .project(let id) = kind { return id }
        return nil
    }

    var isGeneral: Bool {
        if case .general = kind { return true }
        return false
    }

    var windowAutosaveName: String { kind.windowAutosaveName }

    init(
        kind: Kind,
        settings: ModelSettings,
        taskRepository: any TaskRepository,
        mcpHub: CapabilityStore,
        skillStateStore: SkillStateStore
    ) {
        self.kind = kind
        let skillCatalog = SkillCatalog(store: skillStateStore)
        let skills = SkillSessionController()
        self.skillCatalog = skillCatalog
        self.skills = skills
        self.agent = AgentRuntime(
            settings: settings,
            tools: .makeDefault(),
            taskRepository: taskRepository,
            contextResolver: ContinuityTaskResolver(),
            skillCatalog: skillCatalog,
            mcpHub: mcpHub,
            skills: skills
        )
    }
}
