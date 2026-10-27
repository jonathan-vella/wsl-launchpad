#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-test.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT
cd "$ROOT"

if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* ]]; then
    probe="$ROOT/symlink-probe"
    if ! ln -s target "$probe" 2>/dev/null || [[ ! -L "$probe" ]]; then
        printf 'SKIP: this Git Bash environment cannot create symbolic links.\n'
        exit 0
    fi
    rm -f "$probe"
fi

export HOME="$ROOT/home with spaces"
export XDG_CONFIG_HOME="$ROOT/config #semi; with spaces"
mkdir -p "$HOME" "$XDG_CONFIG_HOME/dotfiles"

failures=0

assert() {
    local description="$1"
    shift
    if "$@"; then
        printf 'PASS: %s\n' "$description"
    else
        printf 'FAIL: %s\n' "$description" >&2
        failures=$((failures + 1))
    fi
}

assert_link() {
    local path="$1" target="$2"
    assert "$path is linked" test -L "$path"
    assert "$path has the expected target" test "$(readlink "$path")" = "$target"
}

printf '[user]\n\tname = Existing User\n\temail = existing@example.com\n[core]\n\teditor = code\n' > "$HOME/.gitconfig"
printf 'old backup\n' > "$XDG_CONFIG_HOME/dotfiles/gitconfig.bak"
printf 'original tracked config\n' > "$XDG_CONFIG_HOME/dotfiles/gitconfig"

if git config --file "$REPO/git/.gitconfig" --get user.name >/dev/null; then
    printf 'FAIL: tracked Git configuration must not set user.name\n' >&2
    failures=$((failures + 1))
else
    printf 'PASS: tracked Git configuration does not set user.name\n'
fi
if grep -Eqi 'vscode|settings\.json' "$REPO/install.sh"; then
    printf 'FAIL: Bash installer must not configure VS Code settings\n' >&2
    failures=$((failures + 1))
else
    printf 'PASS: Bash installer does not configure VS Code settings\n'
fi

bash "$REPO/install.sh" >/dev/null

assert_link "$XDG_CONFIG_HOME/dotfiles/gitconfig" "$REPO/git/.gitconfig"
assert_link "$HOME/.profile" "$REPO/shell/.profile"
assert_link "$HOME/.bashrc" "$REPO/shell/.bashrc"
assert_link "$HOME/.zshrc" "$REPO/shell/.zshrc"
assert_link "$HOME/.zprofile" "$REPO/shell/.zprofile"
assert "existing backup is preserved" grep -qx 'old backup' "$XDG_CONFIG_HOME/dotfiles/gitconfig.bak"
assert "new backup uses a unique name" grep -qx 'original tracked config' "$XDG_CONFIG_HOME/dotfiles/gitconfig.bak.1"
assert "user .gitconfig content is preserved" \
    test "$(git config --file "$HOME/.gitconfig" core.editor)" = code
assert "existing Git identity is preserved" \
    test "$(git config --file "$HOME/.gitconfig" user.email)" = existing@example.com
assert "dotfiles config is included before user settings" \
    test "$(git config --file "$HOME/.gitconfig" --get include.path)" = "$XDG_CONFIG_HOME/dotfiles/gitconfig"
assert "original user .gitconfig is backed up" \
    test "$(git config --file "$HOME/.gitconfig.bak" core.editor)" = code

bash "$REPO/install.sh" >/dev/null
assert "repeat install creates no extra backup" test ! -e "$XDG_CONFIG_HOME/dotfiles/gitconfig.bak.2"
assert "repeat install creates no extra user config backup" test ! -e "$HOME/.gitconfig.bak.1"
if [[ "$(uname -s)" != MINGW* && "$(uname -s)" != MSYS* ]]; then
    assert "generated user config is owner-only" \
        test "$(stat -c '%a' "$HOME/.gitconfig" 2>/dev/null || stat -f '%Lp' "$HOME/.gitconfig")" = 600
fi

: > "$HOME/.gitconfig"
git config --file "$HOME/.gitconfig" core.editor code
git config --file "$HOME/.gitconfig" --add include.path "$XDG_CONFIG_HOME/dotfiles/gitconfig"
bash "$REPO/install.sh" >/dev/null
assert "existing include is moved before user settings" \
    test "$(git config --file "$HOME/.gitconfig" --name-only --get-regexp '.*' | sed -n '1p')" = include.path
assert "repositioned include remains unique" \
    test "$(git config --file "$HOME/.gitconfig" --get-all include.path | grep -Fxc "$XDG_CONFIG_HOME/dotfiles/gitconfig")" = 1

rm "$HOME/.bashrc"
ln -s "$ROOT/missing" "$HOME/.bashrc"
"$REPO/install.sh" >/dev/null
assert_link "$HOME/.bashrc" "$REPO/shell/.bashrc"

printf 'export LAUNCHPAD_DOTFILES_TEST=loaded\n' > "$HOME/.profile.local"
profile_result="$(
    HOME="$HOME" bash --noprofile --norc -c \
        'source "$1"; printf "%s" "$LAUNCHPAD_DOTFILES_TEST"' \
        _ "$REPO/shell/.profile"
)"
assert "profile loads an optional local override" \
    test "$profile_result" = loaded

printf 'Architecture: %s\n' "$(uname -m)"
printf 'Failures: %d\n' "$failures"
exit "$failures"
