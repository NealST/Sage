//
//  shell_snapshot.swift
//  CodexShellCommand
//
//  Port of codex-rs/shell-command/src/shell_snapshot.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Facade types plus the POSIX ENV-path helper. Capture / credential /
//  literal / render live in the sibling snapshot files.
//

public struct ShellSnapshot: Equatable, Sendable {
    public var shellType: ShellType
    public var exports: [String: String]
    public var aliases: [String: String]
    public var functions: [String: String]

    public init(
        shellType: ShellType,
        exports: [String: String] = [:],
        aliases: [String: String] = [:],
        functions: [String: String] = [:]
    ) {
        self.shellType = shellType
        self.exports = exports
        self.aliases = aliases
        self.functions = functions
    }
}

public enum SnapshotStartup: Equatable, Sendable {
    case interactive
    case nonInteractive
}

/// Returns the POSIX shell helper used to resolve supported `ENV` startup paths.
///
/// The helper deliberately supports only non-evaluating path forms. Unsupported
/// shell expressions are returned unchanged rather than executed.
public func posixEnvPathExpansionFunction() -> String {
    #"""
    __codex_snapshot_expand_env() (
      set +u
      __codex_snapshot_getenv() {
        # Preserve the value separately from lookup status and its formatting newline.
        __codex_env_expanded=$(
          if command -v printenv >/dev/null 2>&1; then
            printenv "$1"
          elif [ "$1" = PATH ]; then
            [ "${PATH+x}" = x ] && printf '%s\n' "$PATH"
          else
            command -p printenv "$1"
          fi && printf '.'
        ) || return 1
        __codex_env_expanded=${__codex_env_expanded%?}
        __codex_env_expanded=${__codex_env_expanded%?}
      }
      __codex_env_file=$1
      case "$__codex_env_file" in
        '~/'*) __codex_env_file="${HOME-}/${__codex_env_file#*/}" ;;
        '${PATH%%:*}') __codex_env_file="${PATH%%:*}" ;;
        '${PATH%%:*}/'*) __codex_env_file="${PATH%%:*}/${__codex_env_file#*/}" ;;
        '${'*)
          __codex_env_body=${__codex_env_file#\$\{}
          case "$__codex_env_body" in
            *\}*)
              __codex_env_name=${__codex_env_body%%\}*}
              __codex_env_suffix=${__codex_env_body#*\}}
              case "$__codex_env_name" in
                *:-*)
                  __codex_env_default=${__codex_env_name#*:-}
                  __codex_env_name=${__codex_env_name%%:-*}
                  __codex_env_has_default=1
                  ;;
                *) __codex_env_has_default= ;;
              esac
              case "$__codex_env_name" in
                ''|[0-9]*|*[!A-Za-z0-9_]*) ;;
                *)
                  case "$__codex_env_suffix" in
                    ''|/*)
                      if __codex_snapshot_getenv "$__codex_env_name" 2>/dev/null &&
                        { [ -n "$__codex_env_expanded" ] || [ -z "$__codex_env_has_default" ]; }; then
                        __codex_env_file="$__codex_env_expanded$__codex_env_suffix"
                      elif [ -n "$__codex_env_has_default" ]; then
                        __codex_env_default=$(__codex_snapshot_expand_env "$__codex_env_default")
                        __codex_env_file="$__codex_env_default$__codex_env_suffix"
                      fi
                      ;;
                  esac
                  ;;
              esac
              ;;
          esac
          ;;
        '$'*)
          __codex_env_name=${__codex_env_file%%/*}
          __codex_env_name=${__codex_env_name#\$}
          case "$__codex_env_name" in
            ''|[0-9]*|*[!A-Za-z0-9_]*) ;;
            *)
              if __codex_snapshot_getenv "$__codex_env_name" 2>/dev/null; then
                if [ "$__codex_env_file" = "\$$__codex_env_name" ]; then
                  __codex_env_file=$__codex_env_expanded
                else
                  __codex_env_file="$__codex_env_expanded/${__codex_env_file#*/}"
                fi
              fi
              ;;
          esac
          ;;
      esac
      printf '%s' "$__codex_env_file"
    )
    """#
}
