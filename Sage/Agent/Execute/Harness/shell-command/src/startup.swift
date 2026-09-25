//
//  startup.swift
//  CodexShellCommand
//
//  Port of codex-rs/shell-command/src/startup.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Profile seeding shared by shell snapshot capture.
//

public func shellStartupScript(_ shellType: ShellType) -> String {
    switch shellType {
    case .zsh:
        return """
        if [[ -n "${ZDOTDIR-}" ]]; then
          rc="$ZDOTDIR/.zshrc"
        elif [[ -n "${HOME-}" ]]; then
          rc="$HOME/.zshrc"
        else
          rc=
        fi
        [[ -r "$rc" ]] && . "$rc"

        """
    case .bash:
        return """
        if [ -z "${BASH_ENV-}" ] && [ -n "${HOME-}" ] && [ -r "$HOME/.bashrc" ]; then
          . "$HOME/.bashrc"
        fi

        """
    case .sh, .powerShell, .cmd:
        return ""
    }
}
