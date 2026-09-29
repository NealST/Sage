//
//  core_agents_md.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agents_md.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  R4a: basename collides with context/world_state/agents_md.swift.
//  LoadedAgentsMd text assembly and filename/path discovery are faithful.
//  `load_project_instructions` still waits on Config / TurnEnvironmentSnapshot
//  / ConfigLayerStack. Project-root markers default to `.git` until the
//  config crate is ported. Concurrent ancestor probes walk sequentially,
//  matching FileSystem.find_up.
//

import CodexProtocol
import CodexUtils
import FileSystem
import Foundation

/// Default filename scanned for AGENTS.md instructions.
public let DEFAULT_AGENTS_MD_FILENAME = "AGENTS.md"
/// Preferred local override for AGENTS.md instructions.
public let LOCAL_AGENTS_MD_FILENAME = "AGENTS.override.md"

/// When both user and project AGENTS.md docs are present, they will be
/// concatenated with the following separator.
let AGENTS_MD_SEPARATOR = "\n\n--- project-doc ---\n\n"

let MAX_CONCURRENT_ANCESTOR_PROBES: Int = 256

/// Host-supplied instruction text, optionally backed by a source file.
public struct Instructions: Equatable, Sendable {
    public var text: String
    public var source: AbsolutePathBuf?

    public init(text: String, source: AbsolutePathBuf? = nil) {
        self.text = text
        self.source = source
    }
}

/// Model-visible instructions loaded from AGENTS.md files and internal guidance.
public struct LoadedAgentsMd: Equatable, Sendable {
    public var userInstructions: Instructions?
    public var threadInstructions: Instructions?
    public var entries: [InstructionEntry]

    public init(
        userInstructions: Instructions? = nil,
        threadInstructions: Instructions? = nil,
        entries: [InstructionEntry] = []
    ) {
        self.userInstructions = userInstructions
        self.threadInstructions = threadInstructions
        self.entries = entries
    }

    /// Creates loaded instructions containing one user-level AGENTS.md entry.
    public static func newUser(contents: String, path: AbsolutePathBuf) -> LoadedAgentsMd {
        if contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return LoadedAgentsMd()
        }
        return LoadedAgentsMd(
            userInstructions: Instructions(text: contents, source: path)
        )
    }

    public static func fromUserInstructions(_ userInstructions: Instructions?) -> LoadedAgentsMd {
        LoadedAgentsMd(
            userInstructions: userInstructions.flatMap { instructions in
                instructions.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : instructions
            }
        )
    }

    public func withInstructions(
        userInstructions: Instructions?,
        threadInstructions: Instructions?
    ) -> LoadedAgentsMd? {
        var copy = self
        copy.userInstructions = userInstructions.flatMap { instructions in
            instructions.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : instructions
        }
        copy.threadInstructions = threadInstructions.flatMap { instructions in
            instructions.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : instructions
        }
        return copy.isEmpty() ? nil : copy
    }

    /// Creates source-less user instructions for tests.
    public static func fromTextForTesting(_ contents: String) -> LoadedAgentsMd {
        if contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return LoadedAgentsMd()
        }
        return LoadedAgentsMd(
            entries: [InstructionEntry(contents: contents, provenance: .internal)]
        )
    }

    public func isEmpty() -> Bool {
        userInstructions == nil
            && threadInstructions == nil
            && entries.allSatisfy { $0.contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Returns the concatenated model-visible instruction text.
    public func text() -> String {
        hasMultipleProjectEnvironments() ? environmentLabeledText() : legacyText()
    }

    func legacyText() -> String {
        var output = ""
        var hasPrevious = false
        var previousWasProject = false
        for instructions in [userInstructions, threadInstructions].compactMap({ $0 }) {
            if hasPrevious {
                output += "\n\n"
            }
            output += instructions.text
            hasPrevious = true
        }
        for entry in entries {
            let isProject: Bool
            if case .project = entry.provenance {
                isProject = true
            } else {
                isProject = false
            }
            if hasPrevious {
                output += isProject && !previousWasProject ? AGENTS_MD_SEPARATOR : "\n\n"
            }
            output += entry.contents
            hasPrevious = true
            previousWasProject = isProject
        }
        return output
    }

    func environmentLabeledText() -> String {
        var output = ""
        var hasPrevious = false
        var previousEnvironment: (String, PathUri)?
        for instructions in [userInstructions, threadInstructions].compactMap({ $0 }) {
            if hasPrevious {
                output += "\n\n"
            }
            output += instructions.text
            hasPrevious = true
        }
        for entry in entries {
            switch entry.provenance {
            case .project(_, let environmentId, let cwd):
                if hasPrevious {
                    output += "\n\n"
                }
                let environment = (environmentId, cwd)
                if previousEnvironment.map({ $0.0 != environment.0 || $0.1 != environment.1 }) ?? true {
                    output += "for `\(environmentId)` with root \(cwd.inferredNativePathString())\n\n"
                }
                output += entry.contents
                previousEnvironment = environment
            case .internal:
                if hasPrevious {
                    output += "\n\n"
                }
                output += entry.contents
                previousEnvironment = nil
            }
            hasPrevious = true
        }
        return output
    }

    public func contextualUserFragment() -> UserInstructions {
        let directory = hasMultipleProjectEnvironments()
            ? nil
            : singleProjectCwd()?.inferredNativePathString()
        return UserInstructions(directory: directory, text: text())
    }

    /// Returns the AGENTS.md files that supplied instruction entries.
    public func sources() -> [PathUri] {
        var paths: [PathUri] = []
        for instructions in [userInstructions, threadInstructions].compactMap({ $0 }) {
            if let source = instructions.source {
                paths.append(PathUri.fromAbsPath(source))
            }
        }
        for entry in entries {
            if let path = entry.provenance.path() {
                paths.append(path)
            }
        }
        return paths
    }

    func hasMultipleProjectEnvironments() -> Bool {
        var firstEnvironmentId: String?
        for entry in entries {
            guard case .project(_, let environmentId, _) = entry.provenance else {
                continue
            }
            if let first = firstEnvironmentId {
                if first != environmentId { return true }
            } else {
                firstEnvironmentId = environmentId
            }
        }
        return false
    }

    func singleProjectCwd() -> PathUri? {
        for entry in entries {
            if case .project(_, _, let cwd) = entry.provenance {
                return cwd
            }
        }
        return nil
    }
}

/// One model-visible instruction and its provenance.
public struct InstructionEntry: Equatable, Sendable {
    public var contents: String
    public var provenance: InstructionProvenance

    public init(contents: String, provenance: InstructionProvenance) {
        self.contents = contents
        self.provenance = provenance
    }
}

public enum InstructionProvenance: Equatable, Sendable {
    case project(sourcePath: PathUri, environmentId: String, cwd: PathUri)
    case `internal`

    public func path() -> PathUri? {
        switch self {
        case .project(let sourcePath, _, _):
            return sourcePath
        case .internal:
            return nil
        }
    }
}

public func defaultProjectRootMarkers() -> [String] {
    [".git"]
}

/// Loads project AGENTS.md content and combines it with host-provided user instructions.
public func loadProjectInstructions() async throws -> LoadedAgentsMd? {
    throw CodexErr.unsupportedOperation(
        "load_project_instructions waits on Config / TurnEnvironmentSnapshot / ConfigLayerStack"
    )
}

/// Discovers AGENTS.md files from the project root to the current working directory.
public func agentsMdPaths(
    cwd: PathUri,
    filesystem: any ExecutorFileSystem,
    projectRootMarkers: [String] = defaultProjectRootMarkers(),
    fallbackFilenames: [String] = [],
    sandbox: FileSystemSandboxContext? = nil
) async throws -> [PathUri] {
    _ = MAX_CONCURRENT_ANCESTOR_PROBES
    let projectRoot = try await findNearestAncestorWithMarkers(
        fileSystem: filesystem,
        start: cwd,
        markers: projectRootMarkers,
        errorPolicy: .ignore,
        sandbox: sandbox
    )
    let searchDirs: [PathUri]
    if let root = projectRoot {
        var dirs: [PathUri] = []
        var cursor = cwd
        while true {
            dirs.append(cursor)
            if cursor == root { break }
            guard let parent = cursor.parent() else { break }
            cursor = parent
        }
        dirs.reverse()
        searchDirs = dirs
    } else {
        searchDirs = [cwd]
    }

    let names = candidateFilenames(cwd: cwd, fallbackFilenames: fallbackFilenames)
    var found: [PathUri] = []
    for directory in searchDirs {
        for name in names {
            let candidate: PathUri
            do {
                candidate = try directory.join(name)
            } catch {
                throw IOError.invalidInput(String(describing: error))
            }
            do {
                let metadata = try await filesystem.getMetadata(
                    candidate,
                    options: .default,
                    sandbox: sandbox
                )
                if metadata.isFile {
                    found.append(candidate)
                    break
                }
            } catch let error as IOError where error.kind == .notFound {
                continue
            }
        }
    }
    return found
}

/// Attempt to locate and load AGENTS.md documentation.
public func readAgentsMd(
    cwd: PathUri,
    filesystem: any ExecutorFileSystem,
    environmentId: String,
    maxTotal: Int,
    projectRootMarkers: [String] = defaultProjectRootMarkers(),
    fallbackFilenames: [String] = [],
    sandbox: FileSystemSandboxContext? = nil
) async throws -> LoadedAgentsMd? {
    if maxTotal == 0 { return nil }
    let paths = try await agentsMdPaths(
        cwd: cwd,
        filesystem: filesystem,
        projectRootMarkers: projectRootMarkers,
        fallbackFilenames: fallbackFilenames,
        sandbox: sandbox
    )
    if paths.isEmpty { return nil }

    var remaining = UInt64(maxTotal)
    var loaded = LoadedAgentsMd()
    for path in paths {
        if remaining == 0 { break }
        let data: [UInt8]
        do {
            data = try await filesystem.readFile(path, options: .default, sandbox: sandbox)
        } catch let error as IOError where error.kind == .notFound {
            continue
        }
        var bytes = data
        let size = UInt64(bytes.count)
        if size > remaining {
            bytes = Array(bytes.prefix(Int(remaining)))
        }
        let text = String(decoding: bytes, as: UTF8.self)
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            loaded.entries.append(
                InstructionEntry(
                    contents: text,
                    provenance: .project(sourcePath: path, environmentId: environmentId, cwd: cwd)
                )
            )
            remaining = remaining &- UInt64(bytes.count)
        }
    }
    return loaded.isEmpty() ? nil : loaded
}

public func candidateFilenames(cwd: PathUri, fallbackFilenames: [String]) -> [String] {
    var names: [String] = [LOCAL_AGENTS_MD_FILENAME, DEFAULT_AGENTS_MD_FILENAME]
    for candidate in fallbackFilenames {
        if candidate.isEmpty { continue }
        if candidate == "." || candidate == ".."
            || candidate.contains("/") || candidate.contains("\0")
            || (cwd.inferPathConvention() == .windows
                && (candidate.contains("\\") || candidate.contains(":"))) {
            continue
        }
        if !names.contains(candidate) {
            names.append(candidate)
        }
    }
    return names
}
