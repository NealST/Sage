//
//  shell_snapshot.swift
//  SageShellCommand
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
    __sage_snapshot_expand_env() (
      set +u
      __sage_snapshot_getenv() {
        # Preserve the value separately from lookup status and its formatting newline.
        __sage_env_expanded=$(
          if command -v printenv >/dev/null 2>&1; then
            printenv "$1"
          elif [ "$1" = PATH ]; then
            [ "${PATH+x}" = x ] && printf '%s\n' "$PATH"
          else
            command -p printenv "$1"
          fi && printf '.'
        ) || return 1
        __sage_env_expanded=${__sage_env_expanded%?}
        __sage_env_expanded=${__sage_env_expanded%?}
      }
      __sage_env_file=$1
      case "$__sage_env_file" in
        '~/'*) __sage_env_file="${HOME-}/${__sage_env_file#*/}" ;;
        '${PATH%%:*}') __sage_env_file="${PATH%%:*}" ;;
        '${PATH%%:*}/'*) __sage_env_file="${PATH%%:*}/${__sage_env_file#*/}" ;;
        '${'*)
          __sage_env_body=${__sage_env_file#\$\{}
          case "$__sage_env_body" in
            *\}*)
              __sage_env_name=${__sage_env_body%%\}*}
              __sage_env_suffix=${__sage_env_body#*\}}
              case "$__sage_env_name" in
                *:-*)
                  __sage_env_default=${__sage_env_name#*:-}
                  __sage_env_name=${__sage_env_name%%:-*}
                  __sage_env_has_default=1
                  ;;
                *) __sage_env_has_default= ;;
              esac
              case "$__sage_env_name" in
                ''|[0-9]*|*[!A-Za-z0-9_]*) ;;
                *)
                  case "$__sage_env_suffix" in
                    ''|/*)
                      if __sage_snapshot_getenv "$__sage_env_name" 2>/dev/null &&
                        { [ -n "$__sage_env_expanded" ] || [ -z "$__sage_env_has_default" ]; }; then
                        __sage_env_file="$__sage_env_expanded$__sage_env_suffix"
                      elif [ -n "$__sage_env_has_default" ]; then
                        __sage_env_default=$(__sage_snapshot_expand_env "$__sage_env_default")
                        __sage_env_file="$__sage_env_default$__sage_env_suffix"
                      fi
                      ;;
                  esac
                  ;;
              esac
              ;;
          esac
          ;;
        '$'*)
          __sage_env_name=${__sage_env_file%%/*}
          __sage_env_name=${__sage_env_name#\$}
          case "$__sage_env_name" in
            ''|[0-9]*|*[!A-Za-z0-9_]*) ;;
            *)
              if __sage_snapshot_getenv "$__sage_env_name" 2>/dev/null; then
                if [ "$__sage_env_file" = "\$$__sage_env_name" ]; then
                  __sage_env_file=$__sage_env_expanded
                else
                  __sage_env_file="$__sage_env_expanded/${__sage_env_file#*/}"
                fi
              fi
              ;;
          esac
          ;;
      esac
      printf '%s' "$__sage_env_file"
    )
    """#
}
