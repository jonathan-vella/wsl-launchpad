#!/usr/bin/env bash
# Runs in Git Bash or Linux. Only temporary fixtures and mocked commands are used.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../provision.sh"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
check() { "$@" || fail "Test failed: $*"; }

# GA checks run without package installs, account changes, or host configuration.
mkdir -p "$work/repositories"
cat > "$work/os-release" <<'EOF'
ID=azurelinux
VERSION_ID=4.0
PRETTY_NAME="Azure Linux 4.0"
EOF
for channel in base microsoft; do
    file=azurelinux
    [[ "$channel" != microsoft ]] || file=microsoft
    cat > "$work/repositories/$file.repo" <<EOF
[azurelinux-$channel]
baseurl=https://packages.microsoft.com/azurelinux/4/prod/$channel/\$basearch
enabled=1
EOF
done
check assert_ga_release "$work/os-release" "$work/repositories"
cp "$work/os-release" "$work/ga-release"
printf 'PRETTY_NAME="Azure Linux 4.0 (WSL Beta)"\n' >> "$work/os-release"
if (assert_ga_release "$work/os-release" "$work/repositories") > "$work/beta.log" 2>&1; then
    fail 'Accepted beta branding with production repositories'
fi
check grep -q 'beta/preview' "$work/beta.log"
cp "$work/ga-release" "$work/os-release"
cp "$work/repositories/azurelinux.repo" "$work/ga-repository"
sed 's@/4/prod/@/4.0/beta/@' "$work/ga-repository" > "$work/repositories/azurelinux.repo"
if (assert_ga_release "$work/os-release" "$work/repositories") > "$work/feed.log" 2>&1; then
    fail 'Accepted beta feeds with GA branding'
fi
check grep -q 'production feed' "$work/feed.log"
cp "$work/ga-repository" "$work/repositories/azurelinux.repo"
printf '\n[azurelinux-base]\nbaseurl=https://packages.microsoft.com/azurelinux/4/prod/base/$basearch\nenabled=1\n' >> "$work/repositories/azurelinux.repo"
if (assert_ga_release "$work/os-release" "$work/repositories") > "$work/duplicate.log" 2>&1; then
    fail 'Accepted duplicate base repository declarations'
fi
cp "$work/ga-repository" "$work/repositories/azurelinux.repo"
sed 's/enabled=1/enabled=0/' "$work/repositories/microsoft.repo" > "$work/disabled.repo"
if (assert_ga_repository "$work/disabled.repo" azurelinux-microsoft microsoft) > "$work/disabled.log" 2>&1; then
    fail 'Accepted a disabled production repository'
fi
if (assert_ga_release "$work/os-release" "$work/missing") > "$work/missing.log" 2>&1; then
    fail 'Accepted missing production repositories'
fi

mkdir -p "$work/etc"
cat > "$work/etc/automatic.conf" <<'EOF'
# Existing administrator settings
[commands]
apply_updates=no
reboot=when-needed
network_online_timeout=90
[emitters]
emit_via=stdio
EOF
cp "$work/etc/automatic.conf" "$work/original"
configure_updates "$work/etc/automatic.conf" "$work/timer.d"
cp "$work/etc/automatic.conf" "$work/first"
configure_updates "$work/etc/automatic.conf" "$work/timer.d"
check cmp -s "$work/first" "$work/etc/automatic.conf"
check cmp -s "$work/original" "$work/etc/automatic.conf.wsl-launchpad-before-bootstrap"
for setting in apply_updates=yes upgrade_type=default reboot=never network_online_timeout=90 emit_via=stdio; do
    check grep -qx "$setting" "$work/etc/automatic.conf"
done
check grep -qx 'OnCalendar=' "$work/timer.d/weekly.conf"
check grep -qx 'OnCalendar=Sun \*-\*-\* 06:00:00' "$work/timer.d/weekly.conf"
check grep -qx 'Persistent=true' "$work/timer.d/weekly.conf"
configure_updates "$work/new/automatic.conf" "$work/new/timer.d"
check grep -qx 'apply_updates=yes' "$work/new/automatic.conf"
mkdir -p "$work/legacy"
printf 'before migration\n' > "$work/legacy/automatic.conf"
printf 'original backup\n' > "$work/legacy/automatic.conf.csa-before-bootstrap"
configure_updates "$work/legacy/automatic.conf" "$work/legacy/timer.d"
check grep -qx 'original backup' "$work/legacy/automatic.conf.csa-before-bootstrap"
check test ! -e "$work/legacy/automatic.conf.wsl-launchpad-before-bootstrap"

# Invalid user selection is rejected before account/home mutation.
if (select_user root) > "$work/root.log" 2>&1; then fail 'Accepted root user'; fi
if (select_user 'bad;name') > "$work/user.log" 2>&1; then fail 'Accepted shell metacharacters'; fi
check grep -q 'non-root' "$work/root.log"

# The real checksum function must reject bytes from a mocked downloader.
curl() {
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == -o ]]; then printf 'fake binary' > "$2"; return; fi
        shift
    done
    fail 'Mock curl did not get an output path.'
}
if (download https://example.invalid/binary "$work/binary" "$(printf '%064d' 0)") > "$work/hash.log" 2>&1; then
    fail 'Accepted a mismatched binary checksum'
fi
check grep -q 'FAILED' "$work/hash.log"

status=0
bash -s -- invalid < "$(dirname "${BASH_SOURCE[0]}")/../provision.sh" > "$work/stdin.log" 2>&1 || status=$?
check test "$status" -eq 1
check grep -q 'Expected system phase' "$work/stdin.log"
printf 'PASS: isolated INI/timer idempotence, preservation, invalid users and binary hash checks.\n'
