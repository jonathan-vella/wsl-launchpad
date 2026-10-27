#!/usr/bin/env bash
# Runs in Git Bash or Linux. Only temporary fixtures and mocked commands are used.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../provision.sh"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
check() { "$@" || fail "Test failed: $*"; }

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
