//
//  SkillTipsBanner.swift
//  Sage
//
//  Unified tip UI for save / choose / consolidate above the composer.
//

import AppKit
import SwiftUI

struct SkillTipsBanner: View {
    @Environment(AppState.self) private var appState
    @Environment(AgentSession.self) private var session
    @Environment(AccessibilitySettings.self) private var accessibility
    @State private var autoDismissTask: Task<Void, Never>?
    @State private var scopeByID: [UUID: SkillScope] = [:]
    @State private var primaryPathByID: [UUID: String] = [:]
    @State private var pointerInsideBanner = false

    private var tips: SkillTipStore { session.skills.tips }

    private var projectDisplayName: String {
        session.agent.state.focusedProject?.name ?? "this project"
    }

    var body: some View {
        if tips.showBanner {
            SkillTipChrome.bannerStack {
                ForEach(tips.items) { item in
                    switch item {
                    case .save(let suggestion):
                        SkillSaveTipRow(
                            suggestion: suggestion,
                            projectDisplayName: projectDisplayName,
                            selectedScope: scopeBinding(for: suggestion),
                            onSave: confirmSuggestion,
                            onDismiss: {
                                withAnimation(SageDesign.Motion.expandAnimation) {
                                    scopeByID[suggestion.id] = nil
                                    tips.dismiss(suggestion.id)
                                }
                            }
                        )
                    case .choose(let choice):
                        SkillChooseTipRow(choice: choice)
                    case .consolidate(let suggestion):
                        SkillConsolidateTipRow(
                            suggestion: suggestion,
                            primaryPath: primaryBinding(for: suggestion),
                            onMerge: confirmConsolidate,
                            onDismiss: {
                                withAnimation(SageDesign.Motion.expandAnimation) {
                                    primaryPathByID[suggestion.id] = nil
                                    tips.dismiss(suggestion.id)
                                }
                            }
                        )
                    case .schedule(let draft):
                        SkillScheduleTipRow(
                            draft: draft,
                            conversationWording: conversationWording,
                            onSave: confirmSchedule,
                            onDismiss: {
                                withAnimation(SageDesign.Motion.expandAnimation) {
                                    tips.dismiss(draft.id)
                                }
                            },
                            onUpdate: { mutate in
                                tips.updateSchedule(draft.id) {
                                    mutate(&$0)
                                    $0.originTaskID = session.agent.state.activeTaskID
                                }
                            }
                        )
                    }
                }
            }
            .onAppear {
                seedPrimaryDefaults()
                scheduleAutoDismiss()
            }
            .onChange(of: tips.revision) { _, _ in
                pruneLocalState()
                seedPrimaryDefaults()
                scheduleAutoDismiss()
            }
            .onHover { pointerInsideBanner = $0 }
            .onDisappear {
                autoDismissTask?.cancel()
                pointerInsideBanner = false
            }
        }
    }

    private func scopeBinding(for suggestion: SkillSuggestion) -> Binding<SkillScope?> {
        Binding(
            get: { scopeByID[suggestion.id] },
            set: { scopeByID[suggestion.id] = $0 }
        )
    }

    private func primaryBinding(for suggestion: SkillConsolidateSuggestion) -> Binding<String> {
        Binding(
            get: { primaryPathByID[suggestion.id] ?? suggestion.primaryPath },
            set: { primaryPathByID[suggestion.id] = $0 }
        )
    }

    private func confirmSuggestion(_ resolved: SkillSuggestion) {
        guard tips.confirmSave(resolved.id) != nil else { return }
        withAnimation(SageDesign.Motion.expandAnimation) {
            scopeByID[resolved.id] = nil
        }
        session.skills.startSuggestionSave(resolved)
    }

    private func confirmConsolidate(_ resolved: SkillConsolidateSuggestion) {
        withAnimation(SageDesign.Motion.expandAnimation) {
            primaryPathByID[resolved.id] = nil
            tips.dismiss(resolved.id)
        }
        session.skills.startConsolidate(resolved)
    }

    private func confirmSchedule(_ draft: ScheduleDraft) {
        let prompt = draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        guard tips.confirmSchedule(draft.id) != nil else { return }
        var saved = draft
        saved.prompt = prompt
        let record = ScheduleRecord.agent(from: saved)
        let trial = saved.runOnceNow
        Task {
            let ok = await appState.schedules.save(record, runOnceNow: trial)
            if !ok, let message = appState.schedules.lastError {
                session.agent.reportFailure(message)
            }
        }
    }

    private var conversationWording: String? {
        ScheduleRecord.latestUserRequest(in: session.agent.state.events)
    }

    private func seedPrimaryDefaults() {
        for item in tips.items {
            guard case .consolidate(let suggestion) = item else { continue }
            if primaryPathByID[suggestion.id] == nil {
                primaryPathByID[suggestion.id] = suggestion.primaryPath
            }
        }
    }

    private func pruneLocalState() {
        let liveIDs = Set(tips.items.map(\.id))
        scopeByID = scopeByID.filter { liveIDs.contains($0.key) }
        primaryPathByID = primaryPathByID.filter { liveIDs.contains($0.key) }
    }

    private func scheduleAutoDismiss() {
        autoDismissTask?.cancel()
        guard tips.choosePrompt == nil else { return }
        autoDismissTask = Task {
            var waited: TimeInterval = 0
            while waited < 20 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                if pointerInsideBanner || accessibility.voiceOverEnabled {
                    continue
                }
                waited += 1
            }
            guard !Task.isCancelled else { return }
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: "Skill suggestion dismissed",
                    .priority: NSAccessibilityPriorityLevel.medium.rawValue,
                ]
            )
            withAnimation(SageDesign.Motion.expandAnimation) {
                scopeByID.removeAll()
                primaryPathByID.removeAll()
                tips.dismissAutoDismissable()
            }
        }
    }
}
