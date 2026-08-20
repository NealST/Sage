//
//  TaskWorkingMemory.swift
//  Sage
//
//  Model-facing fold of older turns. Never shown in the transcript UI.
//

import Foundation

/// A high-density working-memory snapshot for one task.
///
/// Replaces a contiguous prefix of `TaskRecord.events` when assembling a
/// model request. The original events stay in SQLite; the user-visible
/// transcript is unchanged.
///
/// Distinct from `WorkPlan` (a user-confirmed strategy, frozen onto
/// schedules) and from `TaskRecord.summary` / `topic` (chrome titles).
nonisolated struct TaskWorkingMemory: Identifiable, Codable, Sendable, Equatable {
    /// How the compressor filled this snapshot.
    enum Mode: String, Codable, Sendable, Equatable {
        /// Eight working-memory sections, for restoring agent state after a fold.
        case structured
        /// Unstructured prose when the compressor could not fill the sections.
        case simple
    }

    /// JSON blob version stored on `tasks.working_memory_json`.
    static let currentSchemaVersion = 1

    /// Identifies this fold so a later compact can replace it in place.
    let id: UUID
    /// Decoder compatibility for the JSON blob on `tasks.working_memory_json`.
    var schemaVersion: Int
    /// First event included in this fold (inclusive).
    var foldedFromEventID: UUID
    /// Last event included in this fold (inclusive). Turns after this stay verbatim.
    var foldedThroughEventID: UUID
    /// Structured eight-section snapshot, or simple prose fallback.
    var mode: Mode
    /// Model identifier that produced this snapshot, when known.
    var sourceModel: String?
    /// Current goal, background, and how the user's intent has evolved.
    var overview: String?
    /// Frameworks, architecture, and design patterns in play.
    var architecture: String?
    /// Files touched, why they changed, and their current state.
    var touchedFiles: String?
    /// Errors encountered, fixes tried, and remaining debug clues.
    var troubleshooting: String?
    /// Done, remaining, and verified work.
    var progress: String?
    /// Where the agent left off immediately before the fold.
    var focus: String?
    /// Recent commands and tool outcomes.
    var recentActions: String?
    /// Open todos and the first action after restoring this snapshot.
    var nextSteps: String?
    /// Simple-mode body, or extra prose when structured sections are incomplete.
    var narrative: String?
    /// When this fold was written. Incremental compact replaces the row in place.
    var createdAt: Date

    /// Creates a model-only snapshot covering `foldedFromEventID`...`foldedThroughEventID`.
    init(
        id: UUID = UUID(),
        schemaVersion: Int = Self.currentSchemaVersion,
        foldedFromEventID: UUID,
        foldedThroughEventID: UUID,
        mode: Mode,
        sourceModel: String? = nil,
        overview: String? = nil,
        architecture: String? = nil,
        touchedFiles: String? = nil,
        troubleshooting: String? = nil,
        progress: String? = nil,
        focus: String? = nil,
        recentActions: String? = nil,
        nextSteps: String? = nil,
        narrative: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.foldedFromEventID = foldedFromEventID
        self.foldedThroughEventID = foldedThroughEventID
        self.mode = mode
        self.sourceModel = sourceModel?.nilIfEmpty
        self.overview = overview?.nilIfEmpty
        self.architecture = architecture?.nilIfEmpty
        self.touchedFiles = touchedFiles?.nilIfEmpty
        self.troubleshooting = troubleshooting?.nilIfEmpty
        self.progress = progress?.nilIfEmpty
        self.focus = focus?.nilIfEmpty
        self.recentActions = recentActions?.nilIfEmpty
        self.nextSteps = nextSteps?.nilIfEmpty
        self.narrative = narrative?.nilIfEmpty
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? Self.currentSchemaVersion
        foldedFromEventID = try container.decode(UUID.self, forKey: .foldedFromEventID)
        foldedThroughEventID = try container.decode(UUID.self, forKey: .foldedThroughEventID)
        mode = try container.decode(Mode.self, forKey: .mode)
        sourceModel = try container.decodeIfPresent(String.self, forKey: .sourceModel)?.nilIfEmpty
        overview = try container.decodeIfPresent(String.self, forKey: .overview)?.nilIfEmpty
        architecture = try container.decodeIfPresent(String.self, forKey: .architecture)?.nilIfEmpty
        touchedFiles = try container.decodeIfPresent(String.self, forKey: .touchedFiles)?.nilIfEmpty
        troubleshooting = try container.decodeIfPresent(String.self, forKey: .troubleshooting)?.nilIfEmpty
        progress = try container.decodeIfPresent(String.self, forKey: .progress)?.nilIfEmpty
        focus = try container.decodeIfPresent(String.self, forKey: .focus)?.nilIfEmpty
        recentActions = try container.decodeIfPresent(String.self, forKey: .recentActions)?.nilIfEmpty
        nextSteps = try container.decodeIfPresent(String.self, forKey: .nextSteps)?.nilIfEmpty
        narrative = try container.decodeIfPresent(String.self, forKey: .narrative)?.nilIfEmpty
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    /// Creates a structured eight-section snapshot.
    static func makeStructured(
        foldedFromEventID: UUID,
        foldedThroughEventID: UUID,
        sourceModel: String? = nil,
        overview: String? = nil,
        architecture: String? = nil,
        touchedFiles: String? = nil,
        troubleshooting: String? = nil,
        progress: String? = nil,
        focus: String? = nil,
        recentActions: String? = nil,
        nextSteps: String? = nil,
        narrative: String? = nil
    ) -> Self {
        Self(
            foldedFromEventID: foldedFromEventID,
            foldedThroughEventID: foldedThroughEventID,
            mode: .structured,
            sourceModel: sourceModel,
            overview: overview,
            architecture: architecture,
            touchedFiles: touchedFiles,
            troubleshooting: troubleshooting,
            progress: progress,
            focus: focus,
            recentActions: recentActions,
            nextSteps: nextSteps,
            narrative: narrative
        )
    }

    /// Creates a prose-only fallback snapshot.
    static func makeSimple(
        foldedFromEventID: UUID,
        foldedThroughEventID: UUID,
        narrative: String,
        sourceModel: String? = nil
    ) -> Self {
        Self(
            foldedFromEventID: foldedFromEventID,
            foldedThroughEventID: foldedThroughEventID,
            mode: .simple,
            sourceModel: sourceModel,
            narrative: narrative
        )
    }

    /// Whether this snapshot has any model-usable body text.
    var hasContent: Bool {
        if narrative != nil { return true }
        return overview != nil
            || architecture != nil
            || touchedFiles != nil
            || troubleshooting != nil
            || progress != nil
            || focus != nil
            || recentActions != nil
            || nextSteps != nil
    }

    /// System-prompt appendix for the execution model. Stable for a given snapshot.
    ///
    /// Does not mention the UI. Recall names event IDs only — the recall tool
    /// is registered separately.
    var promptAppendix: String {
        guard hasContent else { return "" }

        var lines = [
            "",
            "## Working memory",
            "Earlier turns in this task are folded into the snapshot below. "
                + "Original events from \(foldedFromEventID.uuidString) through "
                + "\(foldedThroughEventID.uuidString) remain stored on the task. "
                + "If you need exact prior text, tool output, or code, call `recall_task_transcript` "
                + "with those from_event_id and through_event_id values.",
        ]

        switch mode {
        case .simple:
            if let narrative {
                lines.append(narrative)
            }

        case .structured:
            appendSection(heading: "Overview", body: overview, to: &lines)
            appendSection(heading: "Architecture", body: architecture, to: &lines)
            appendSection(heading: "Files", body: touchedFiles, to: &lines)
            appendSection(heading: "Troubleshooting", body: troubleshooting, to: &lines)
            appendSection(heading: "Progress", body: progress, to: &lines)
            appendSection(heading: "Focus", body: focus, to: &lines)
            appendSection(heading: "Recent actions", body: recentActions, to: &lines)
            appendSection(heading: "Next steps", body: nextSteps, to: &lines)
            if let narrative {
                appendSection(heading: "Notes", body: narrative, to: &lines)
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Returns this snapshot when both fold endpoints still exist in `events`, in order.
    ///
    /// An empty `events` array is treated as unknown history and returns `self`
    /// unchanged — metadata-only loads must not wipe the fold.
    func validated(against events: [AgentEvent]) -> Self? {
        guard !events.isEmpty else { return self }
        guard let fromIndex = events.firstIndex(where: { $0.id == foldedFromEventID }),
              let throughIndex = events.firstIndex(where: { $0.id == foldedThroughEventID }),
              fromIndex <= throughIndex
        else {
            return nil
        }
        return self
    }

    /// Event IDs in `events` that this snapshot covers, in transcript order.
    func foldedEventIDs(in events: [AgentEvent]) -> [UUID] {
        guard let fromIndex = events.firstIndex(where: { $0.id == foldedFromEventID }),
              let throughIndex = events.firstIndex(where: { $0.id == foldedThroughEventID }),
              fromIndex <= throughIndex
        else {
            return []
        }
        return events[fromIndex...throughIndex].map(\.id)
    }

    private func appendSection(heading: String, body: String?, to lines: inout [String]) {
        guard let body else { return }
        lines.append("\(heading): \(body)")
    }

    private enum CodingKeys: String, CodingKey {
        case id, schemaVersion, foldedFromEventID, foldedThroughEventID
        case mode, sourceModel
        case overview, architecture, touchedFiles, troubleshooting
        case progress, focus, recentActions, nextSteps, narrative
        case createdAt
    }
}
