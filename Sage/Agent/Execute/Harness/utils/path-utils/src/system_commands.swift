//
//  system_commands.swift
//  CodexUtils
//
//  Port of codex-rs/utils/path-utils/src/system_commands.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  macOS-only port: the `cfg(windows)` `installation_roots` (SHGetKnownFolderPath)
//  and the Windows branch of `system_directories` are excluded per plan §2.3;
//  the Linux WSL extension of `system_directories` is kept under
//  `#if os(Linux)`.
//
//  `dunce::canonicalize` is plain `fs::canonicalize` off Windows, so
//  `realpathString` stands in for both. `std::env::consts::EXE_SUFFIX` is ""
//  on Unix. `std::env::join_paths` maps to `joined(separator: ":")`.
//

import Foundation

/// Finds an installed helper without consulting PATH, PATHEXT, or the working
/// directory.
public func systemExecutable(_ name: String) -> String? {
    executableInDirectories(name, systemDirectories())
}

/// Child-process PATH for automatic helpers, not for user-requested tools.
public func systemPath() throws -> String {
    let directories = systemDirectories()
    if directories.isEmpty {
        throw IOError(kind: .other, "no trusted executable directories")
    }
    return directories.joined(separator: ":")
}

func executableInDirectories(_ name: String, _ directories: [String]) -> String? {
    // Do not allow callers to accidentally escape the installation
    // directories (`Path::new(name).file_name() != Some(name)`).
    guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else {
        return nil
    }
    for directory in directories {
        guard let executable = try? realpathString(directory + "/" + name) else {
            continue
        }
        // A symlink into a workspace is not an installed executable. Package
        // manager links may target sibling libexec/Cellar directories.
        let installed = directories.contains { executable.hasPrefix($0 + "/") || executable == $0 }
            || installationRoots().contains { executable.hasPrefix($0 + "/") || executable == $0 }
        guard installed else {
            continue
        }
        #if os(macOS) || os(Linux)
            // `is_file()` + unix mode check; `stat` follows symlinks like
            // `fs::metadata`.
            var statBuffer = stat()
            guard stat(executable, &statBuffer) == 0,
                  statBuffer.st_mode & S_IFMT == S_IFREG,
                  statBuffer.st_mode & 0o111 != 0 else {
                continue
            }
        #else
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: executable, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                continue
            }
        #endif
        return executable
    }
    return nil
}

#if os(macOS) || os(Linux)
    func installationRoots() -> [String] {
        [
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "/usr/local",
            "/opt/homebrew",
            "/opt/local",
            "/Library/Developer/CommandLineTools",
            "/Applications/Xcode.app/Contents/Developer",
            "/nix/store",
            "/mnt/c/Windows/System32",
        ]
    }
#endif

func systemDirectories() -> [String] {
    #if os(macOS) || os(Linux)
        var directories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/opt/local/bin",
            "/run/current-system/sw/bin",
            "/nix/var/nix/profiles/default/bin",
            "/Library/Developer/CommandLineTools/usr/bin",
            "/Applications/Xcode.app/Contents/Developer/usr/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        #if os(Linux)
            if isWsl() {
                directories.append("/mnt/c/Windows/System32")
                directories.append("/mnt/c/Windows/System32/WindowsPowerShell/v1.0")
            }
        #endif
    #else
        var directories: [String] = []
    #endif
    let roots = installationRoots()
    return directories
        .compactMap { try? realpathString($0) }
        .filter { directory in
            roots.contains { directory.hasPrefix($0 + "/") || directory == $0 }
        }
}
