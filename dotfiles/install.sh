#!/usr/bin/env bash
# Create symlinks for dotfiles on Linux and macOS.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XDG_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"

path_exists() {
    [[ -e "$1" || -L "$1" ]]
}

next_backup_path() {
    local dst="$1"
    local candidate="$dst.bak"
    local index=1

    while path_exists "$candidate"; do
        candidate="$dst.bak.$index"
        index=$((index + 1))
    done
    printf '%s\n' "$candidate"
}

preflight_link() {
    local src="$1" dst="$2"
    local dir temp
    if ! path_exists "$src"; then
        echo "error: source file does not exist: $src" >&2
        return 1
    fi
    dir="$(dirname "$dst")"
    mkdir -p "$dir"
    temp="$dir/.dotfiles-link-test.$$.$RANDOM"

    if ! ln -s "$src" "$temp" 2>/dev/null; then
        echo "error: cannot create symbolic links in $dir" >&2
        return 1
    fi
    rm -f "$temp"
}

preflight_file() {
    local dst="$1"
    local dir temp
    dir="$(dirname "$dst")"
    mkdir -p "$dir"
    temp="$dir/.dotfiles-file-test.$$.$RANDOM"

    if ! (umask 077 && : > "$temp") 2>/dev/null; then
        echo "error: cannot create files in $dir" >&2
        return 1
    fi
    rm -f "$temp"
}

link_file() {
    local src="$1" dst="$2"
    local dir temp backup=''
    dir="$(dirname "$dst")"
    temp="$dir/.dotfiles-link.$$.$RANDOM"

    if path_exists "$dst" && [[ -L "$dst" ]] && [[ "$(readlink "$dst")" == "$src" ]]; then
        echo "  unchanged: $dst"
        return
    fi

    ln -s "$src" "$temp"

    if path_exists "$dst"; then
        backup="$(next_backup_path "$dst")"
        echo "  backup: $dst -> $backup"
        mv "$dst" "$backup"
    fi

    if ! mv "$temp" "$dst"; then
        rm -f "$temp"
        if [[ -n "$backup" ]] && ! path_exists "$dst"; then
            mv "$backup" "$dst"
        fi
        echo "error: failed to link $dst" >&2
        return 1
    fi

    echo "  linked: $dst"
}

ensure_git_include() {
    local dotfiles_config="$1" user_config="$2"
    local temp include_fragment sanitized backup='' existing=''
    local first_key first_include includes exact_count
    temp="$(dirname "$user_config")/.dotfiles-gitconfig.$$.$RANDOM"
    include_fragment="$(dirname "$user_config")/.dotfiles-gitinclude.$$.$RANDOM"
    sanitized="$(dirname "$user_config")/.dotfiles-gitbody.$$.$RANDOM"

    if path_exists "$user_config"; then
        if ! first_key="$(
            cd "$HOME" &&
                git config --file "$user_config" --name-only --get-regexp '.*' 2>/dev/null |
                sed -n '1p'
        )"; then
            first_key=''
        fi
        if ! first_include="$(
            cd "$HOME" &&
                git config --file "$user_config" --get include.path 2>/dev/null
        )"; then
            first_include=''
        fi
        if ! includes="$(
            cd "$HOME" &&
                git config --file "$user_config" --get-all include.path 2>/dev/null
        )"; then
            includes=''
        fi
        exact_count="$(printf '%s\n' "$includes" | grep -Fxc "$dotfiles_config" || true)"
        if [[ "$first_key" == 'include.path' &&
            "$first_include" == "$dotfiles_config" &&
            "$exact_count" == 1 ]]; then
            echo "  unchanged: $user_config"
            return
        fi

        cp -p "$user_config" "$sanitized"
        (
            cd "$HOME"
            git config --file "$sanitized" --fixed-value \
                --unset-all include.path "$dotfiles_config" 2>/dev/null || true
        )
        existing="$(cat "$sanitized")"
        rm -f "$sanitized"
    fi

    umask 077
    (cd "$HOME" && git config --file "$include_fragment" include.path "$dotfiles_config")
    {
        cat "$include_fragment"
        printf '\n'
        if [[ -n "$existing" ]]; then
            printf '%s\n' "$existing"
        fi
    } > "$temp"
    rm -f "$include_fragment"

    if ! (cd "$HOME" && git config --file "$temp" --list >/dev/null); then
        rm -f "$temp" "$include_fragment" "$sanitized"
        echo "error: generated Git configuration is invalid" >&2
        return 1
    fi

    if path_exists "$user_config"; then
        backup="$(next_backup_path "$user_config")"
        echo "  backup: $user_config -> $backup"
        mv "$user_config" "$backup"
    fi

    if ! mv "$temp" "$user_config"; then
        rm -f "$temp"
        if [[ -n "$backup" ]] && ! path_exists "$user_config"; then
            mv "$backup" "$user_config"
        fi
        echo "error: failed to update $user_config" >&2
        return 1
    fi

    echo "  included: $dotfiles_config"
}

GIT_CONFIG="$XDG_CONFIG_DIR/dotfiles/gitconfig"
USER_GIT_CONFIG="$HOME/.gitconfig"
PROFILE="$HOME/.profile"
BASHRC="$HOME/.bashrc"
ZSHRC="$HOME/.zshrc"
ZPROFILE="$HOME/.zprofile"

# Verify every destination filesystem before changing existing configuration.
if ! command -v git >/dev/null 2>&1; then
    echo 'error: git is required to install the Git configuration' >&2
    exit 1
fi
preflight_link "$DOTFILES_DIR/git/.gitconfig" "$GIT_CONFIG"
preflight_link "$DOTFILES_DIR/shell/.profile" "$PROFILE"
preflight_link "$DOTFILES_DIR/shell/.bashrc" "$BASHRC"
preflight_link "$DOTFILES_DIR/shell/.zshrc" "$ZSHRC"
preflight_link "$DOTFILES_DIR/shell/.zprofile" "$ZPROFILE"
preflight_file "$USER_GIT_CONFIG"

echo "==> Linking git"
link_file "$DOTFILES_DIR/git/.gitconfig" "$GIT_CONFIG"
ensure_git_include "$GIT_CONFIG" "$USER_GIT_CONFIG"

echo "==> Linking shell"
link_file "$DOTFILES_DIR/shell/.profile" "$PROFILE"
link_file "$DOTFILES_DIR/shell/.bashrc" "$BASHRC"
link_file "$DOTFILES_DIR/shell/.zshrc" "$ZSHRC"
link_file "$DOTFILES_DIR/shell/.zprofile" "$ZPROFILE"

echo
echo "Done. Restart your shell or source its configuration file."
