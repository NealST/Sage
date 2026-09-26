//
//  local_projects.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/projects.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Filename is `local_projects.swift` so SPM object-file basenames do not
//  collide with `thread-store/src/projects.swift`. Project CRUD is a
//  state-db path. Without GRDB every operation throws
//  `unsupported("projects")`. `InMemoryThreadStore` already implements the
//  catalog. `LocalThreadStore.supportsProjects()` stays false.
//

import Foundation

func listProjects(
    store: LocalThreadStore,
    params: ListProjectsParams
) throws -> StoredProjectsPage {
    _ = params
    throw unsupportedProjects(store)
}

func readProject(
    store: LocalThreadStore,
    projectId: String
) throws -> StoredProject? {
    _ = projectId
    throw unsupportedProjects(store)
}

func createProject(
    store: LocalThreadStore,
    params: CreateProjectParams
) throws -> CreatedProject {
    _ = params
    throw unsupportedProjects(store)
}

func updateProject(
    store: LocalThreadStore,
    params: UpdateProjectParams
) throws -> UpdatedProject? {
    _ = params
    throw unsupportedProjects(store)
}

func moveProject(
    store: LocalThreadStore,
    params: MoveProjectParams
) throws -> ProjectMoveOutcome? {
    _ = params
    throw unsupportedProjects(store)
}

func deleteProject(
    store: LocalThreadStore,
    projectId: String
) throws -> DeletedProject? {
    _ = projectId
    throw unsupportedProjects(store)
}

private func unsupportedProjects(_ store: LocalThreadStore) -> ThreadStoreError {
    _ = store
    return .unsupported(operation: "projects")
}
