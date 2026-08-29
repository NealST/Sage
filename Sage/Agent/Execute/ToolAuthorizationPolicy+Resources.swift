//
//  ToolAuthorizationPolicy+Resources.swift
//  Sage
//

import CryptoKit
import Foundation

extension ToolAuthorizationPolicy {
    static func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    static func isHomePolicy(_ policy: PathGuard.Policy) -> Bool {
        if case .home = policy { return true }
        return false
    }

    static func skillContentFingerprint(_ skill: SkillRecord) -> String {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: skill.path)) else {
            return "unreadable"
        }
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func skillExecutionFingerprint(_ skill: SkillRecord, scriptPath: String) -> String {
        let skillURL = URL(fileURLWithPath: skill.path)
        let skillDirectory = skillURL.deletingLastPathComponent()
        let scriptURL = skillDirectory
            .appendingPathComponent(scriptPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let directoryPath = skillDirectory.resolvingSymlinksInPath().path
        guard scriptURL.path.hasPrefix(directoryPath + "/"),
              let skillData = try? Data(contentsOf: skillURL),
              let scriptData = try? Data(contentsOf: scriptURL) else {
            return "unreadable:\(skillContentFingerprint(skill))"
        }
        var payload = skillData
        payload.append(0)
        payload.append(Data(scriptURL.path.utf8))
        payload.append(0)
        payload.append(scriptData)
        return SHA256.hash(data: payload)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func fileWriteResources(
        name: String,
        arguments: [String: Any],
        policy: PathGuard.Policy
    ) -> [ToolAuthorizationResource] {
        if relocatesProtectedRoot(name: name, arguments: arguments, policy: policy) {
            return [
                ToolAuthorizationResource(capability: .localWrite, roots: []),
            ]
        }
        var resources: [ToolAuthorizationResource] = []
        let sensitiveRoots = sensitiveReadRoots(
            name: name,
            arguments: arguments,
            policy: policy
        )
        if !sensitiveRoots.isEmpty {
            resources.append(
                ToolAuthorizationResource(
                    capability: .sensitiveRead,
                    roots: sensitiveRoots
                )
            )
        }
        let writeRoots = resolvedWriteRoots(name: name, arguments: arguments, policy: policy)
        resources.append(
            ToolAuthorizationResource(
                capability: .localWrite,
                roots: Array(Set(writeRoots)).sorted()
            )
        )
        return resources
    }

    private static func sensitiveReadRoots(
        name: String,
        arguments: [String: Any],
        policy: PathGuard.Policy
    ) -> [String] {
        guard name == "copy_file"
                || name == "move_file"
                || name == "rename_file"
                || name == "delete_file",
              let sourcePath = arguments[
                  name == "rename_file" || name == "delete_file" ? "path" : "source"
              ] as? String,
              let source = try? PathGuard.resolveAllowed(
                  sourcePath,
                  policy: policy,
                  access: .read
              ) else {
            return []
        }
        let roots: [URL]
        if directoryExists(at: source) {
            roots = SensitiveResourcePolicy.intersectingRoots(for: source)
        } else {
            roots = SensitiveResourcePolicy.containingRoot(for: source).map { [$0] } ?? []
        }
        return Array(Set(roots.map(normalized))).sorted()
    }

    private static func resolvedWriteRoots(
        name: String,
        arguments: [String: Any],
        policy: PathGuard.Policy
    ) -> [String] {
        switch name {
        case "move_file", "copy_file":
            return transferWriteRoots(arguments: arguments, policy: policy, includeSourceParent: name == "move_file")

        case "rename_file":
            guard let rawPath = arguments["path"] as? String,
                  let newName = arguments["new_name"] as? String,
                  isValidFileName(newName),
                  let source = try? PathGuard.resolveAllowed(
                      rawPath,
                      policy: policy,
                      access: .read
                  ) else {
                return []
            }
            return [normalized(source.deletingLastPathComponent())]

        default:
            guard let rawPath = arguments["path"] as? String,
                  let url = try? PathGuard.resolveAllowed(
                      rawPath,
                      policy: policy,
                      access: .read
                  ) else {
                return []
            }
            return [normalized(writeRoot(name: name, url: url))]
        }
    }

    private static func transferWriteRoots(
        arguments: [String: Any],
        policy: PathGuard.Policy,
        includeSourceParent: Bool
    ) -> [String] {
        guard let sourcePath = arguments["source"] as? String,
              let destinationPath = arguments["destination"] as? String,
              let source = try? PathGuard.resolveAllowed(
                  sourcePath,
                  policy: policy,
                  access: .read
              ),
              let destination = try? PathGuard.resolveAllowed(
                  destinationPath,
                  policy: policy,
                  access: .read
              ) else {
            return []
        }
        let finalDestination = directoryExists(at: destination)
            ? destination.appendingPathComponent(source.lastPathComponent)
            : destination
        var urls = [finalDestination.deletingLastPathComponent()]
        if includeSourceParent {
            urls.append(source.deletingLastPathComponent())
        }
        return Array(Set(urls.map(normalized))).sorted()
    }

    private static func relocatesProtectedRoot(
        name: String,
        arguments: [String: Any],
        policy: PathGuard.Policy
    ) -> Bool {
        guard name == "copy_file" || name == "move_file" || name == "rename_file" else {
            return false
        }
        let sourceKey = name == "rename_file" ? "path" : "source"
        guard let sourcePath = arguments[sourceKey] as? String,
              let source = try? PathGuard.resolveAllowed(
                  sourcePath,
                  policy: policy,
                  access: .read
              ) else {
            return false
        }
        return SensitiveResourcePolicy.wouldRelocateProtectedRoot(source: source)
    }

    private static func isValidFileName(_ name: String) -> Bool {
        !name.isEmpty
            && name != "."
            && name != ".."
            && !name.contains("/")
            && !name.contains("\0")
    }

    static func writeRoot(name: String, url: URL) -> URL {
        name == "create_directory" ? url : url.deletingLastPathComponent()
    }

    static func normalized(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
