//
//  ProjectWorkspaceTab.swift
//  Sage
//
//  Tab identity for the project workspace shell.
//

import Foundation

enum ProjectWorkspaceTab: String, CaseIterable, Identifiable, Sendable {
    case task
    case files
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .task: return "Task"
        case .files: return "Files"
        case .history: return "History"
        }
    }
}
