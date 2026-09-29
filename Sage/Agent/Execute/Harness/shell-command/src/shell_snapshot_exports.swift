//
//  shell_snapshot_exports.swift
//  CodexShellCommand
//
//  Port of codex-rs/shell-command/src/shell_snapshot_exports.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Capture native export declarations and unset POSIX exports.
//  Set POSIX values are captured in bulk for quoting in Swift.
//

func snapshotExportScript(_ shellType: ShellType) -> String {
    let script: String
    switch shellType {
    case .bash:
        script = #"""
        (
          while IFS= read -r __codex_snapshot_export_name; do
            case "$__codex_snapshot_export_name" in
              ""|[0-9]*|*[!A-Za-z0-9_]*|PWD|OLDPWD) continue ;;
            esac
            RECORD_START
            declare -xp "$__codex_snapshot_export_name" 2>/dev/null || true
            RECORD_END
          done < <(compgen -e)
        )

        """#
    case .zsh:
        script = #"""
        (
          unsetopt rcquotes
          # The bundled Zsh does not include the zsh/parameter module.
          for __codex_snapshot_export_name in ${(f)"$(typeset +x)"}; do
            case "$__codex_snapshot_export_name" in
              ""|[0-9]*|*[!A-Za-z0-9_]*|PWD|OLDPWD) continue ;;
            esac
            case "${(tP)__codex_snapshot_export_name}" in
              *readonly*) continue ;;
              *export*) ;;
              *) continue ;;
            esac
            RECORD_START
            typeset -xp "$__codex_snapshot_export_name"
            RECORD_END
          done
        )

        """#
    case .sh:
        script = #"""
        if export -p >/dev/null 2>&1; then
        export -p | __codex_snapshot_command awk '
        /^(export|declare -x|typeset -x) [A-Za-z_][A-Za-z0-9_]*$/ {
          name=$0
          sub(/^(export|declare -x|typeset -x) /, "", name)
          if (name ~ /^(PWD|OLDPWD)$/) {
            next
          }
          if (!seen[name]++) {
            print name
          }
        }' | while IFS= read -r __codex_snapshot_export_name; do
          # Only the validated identifier enters eval. Set values come from the bulk environment.
          if eval '[ "${'"$__codex_snapshot_export_name"'+x}" = x ]'; then
            continue
          fi
          # Only preserve an unset export if the native shell confirms it already exists.
          if (
            set +a
            set -- "$__codex_snapshot_export_name" "$(export -p)"
            export "$1"
            [ "$2" = "$(export -p)" ]
          ); then
            RECORD_START
            printf 'export %s\n' "$__codex_snapshot_export_name"
            RECORD_END
          fi
        done
        fi

        """#
    case .powerShell, .cmd:
        return ""
    }
    return script
        .replacingOccurrences(
            of: "RECORD_START",
            with: #"printf '%s\0' "$__codex_snapshot_export_name""#)
        .replacingOccurrences(of: "RECORD_END", with: #"printf '\0'"#)
}

public func parseExportedAssignments(_ text: String) -> [String: String] {
    var exports: [String: String] = [:]
    for line in text.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("export ") else { continue }
        let body = trimmed.dropFirst("export ".count)
        guard let eq = body.firstIndex(of: "=") else { continue }
        let name = String(body[..<eq])
        var value = String(body[body.index(after: eq)...])
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        exports[name] = value
    }
    return exports
}
