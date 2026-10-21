//
//  user_shell_package_path.swift
//  Sage
//
//  Sage addition (no codex counterpart).
//
//  Finds a packaged `sage-path` directory from an executable path.
//  Directory names follow codex-rs/install-context's package layout.
//  `/shell` prepends that directory and replays it after a snapshot.
//

import Foundation

func sagePackagePathDir(executablePath: String) -> String? {
    guard fileExists(executablePath, directory: false) else { return nil }
    let executable = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath()
    let exeDir = executable.deletingLastPathComponent()
    guard let bin = packageBinDirectory(exeDir) else { return nil }
    return packagePathDirectory(bin)
}

private func packageBinDirectory(_ exeDir: URL) -> URL? {
    switch exeDir.lastPathComponent {
    case "bin":
        return exeDir

    case "sage-resources":
        return exeDir.deletingLastPathComponent().appendingPathComponent("bin")

    case "MacOS":
        return sageCLIPackageBin(exeDir)

    default:
        return nil
    }
}

private func sageCLIPackageBin(_ macosDir: URL) -> URL? {
    let contents = macosDir.deletingLastPathComponent()
    let bundle = contents.deletingLastPathComponent()
    guard contents.lastPathComponent == "Contents", bundle.lastPathComponent == "SageCLI.app" else {
        return nil
    }
    return bundle.deletingLastPathComponent().appendingPathComponent("bin")
}

private func packagePathDirectory(_ bin: URL) -> String? {
    guard isDirectory(bin) else { return nil }
    let package = bin.deletingLastPathComponent()
    let metadata = package.appendingPathComponent("sage-package.json").path
    guard fileExists(metadata, directory: false) else { return nil }
    let pathDir = package.appendingPathComponent("sage-path")
    guard isDirectory(pathDir) else { return nil }
    return pathDir.path
}

private func isDirectory(_ url: URL) -> Bool {
    var isDir = ObjCBool(false)
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
}

private func fileExists(_ path: String, directory: Bool) -> Bool {
    var isDir = ObjCBool(false)
    let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
    return exists && isDir.boolValue == directory
}
