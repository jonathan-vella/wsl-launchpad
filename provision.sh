#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
unset BASH_ENV ENV GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN
trap 'printf "Bootstrap failed at line %s; resolve the error and rerun.\n" "$LINENO" >&2' ERR

fail() { printf '%s\n' "$*" >&2; exit 1; }

backup_before_bootstrap() {
    local file=$1
    [[ -f "$file.wsl-launchpad-before-bootstrap" || -f "$file.csa-before-bootstrap" ]] ||
        cp -p "$file" "$file.wsl-launchpad-before-bootstrap"
}

# Keep unrelated INI settings; retain the first pre-bootstrap copy.
set_ini() {
    local file=$1 section=$2 key=$3 value=$4 temporary
    [[ ! -L "$file" ]] || fail "Refusing symlink configuration: $file"
    temporary=$(mktemp)
    if [[ -f "$file" ]]; then
        backup_before_bootstrap "$file"
    fi
    awk -v section="$section" -v key="$key" -v value="$value" '
        function emit() { if (inside && !written) print key "=" value }
        BEGIN { inside=0; seen=0; written=0 }
        /^[[:space:]]*\[/ {
            emit()
            name=$0
            sub(/^[[:space:]]*\[/, "", name)
            sub(/\].*$/, "", name)
            inside=(name == section)
            if (inside) { seen=1; written=0 }
        }
        inside && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            if (!written) print key "=" value
            written=1
            next
        }
        { print }
        END {
            emit()
            if (!seen) print "\n[" section "]\n" key "=" value
        }
    ' "${file:-/dev/null}" > "$temporary"
    cat "$temporary" > "$file"
    rm -f "$temporary"
}

download() {
    local url=$1 target=$2 hash=$3
    [[ "$hash" =~ ^[a-f0-9]{64}$ ]] || fail 'Missing official binary checksum.'
    curl --disable --proto '=https' --proto-redir '=https' --fail --show-error --location \
        --retry 3 --connect-timeout 30 --max-time 600 "$url" -o "$target"
    printf '%s  %s\n' "$hash" "$target" | sha256sum --check --strict -
}

select_user() {
    local user=$1 entry uid
    [[ "$user" =~ ^[a-z_][a-z0-9_-]{0,31}$ && "$user" != root ]] || fail 'Choose a valid non-root Linux user.'
    entry=$(getent passwd "$user") || fail "Linux user not found: $user"
    IFS=: read -r _ _ uid _ _ user_home _ <<< "$entry"
    [[ "$uid" -ge 1000 && "$user_home" == /* && -d "$user_home" ]] || fail 'User needs UID >=1000 and an existing absolute home directory.'
}

as_user() {
    runuser -u "$user" -- env -i HOME="$user_home" USER="$user" LOGNAME="$user" \
        PATH="$PATH" "$@"
}

configure_updates() {
    local config=$1 dropin=$2
    mkdir -p "$(dirname "$config")" "$dropin"
    [[ -e "$config" ]] || touch "$config"
    set_ini "$config" commands apply_updates yes
    set_ini "$config" commands upgrade_type default
    set_ini "$config" commands reboot never
    local timer="$dropin/weekly.conf"
    [[ ! -L "$timer" ]] || fail "Refusing symlink configuration: $timer"
    [[ ! -f "$timer" ]] || backup_before_bootstrap "$timer"
    cat > "$timer" <<'EOF'
[Timer]
OnCalendar=
OnCalendar=Sun *-*-* 06:00:00
Persistent=true
EOF
}

provision_system() {
    local user=$1 expected_arch=$2 bicep_version=$3 bicep_hash=$4 copilot_version=$5 copilot_hash=$6 arch work
    [[ "$EUID" -eq 0 ]] || fail 'System phase requires WSL root.'
    source /etc/os-release
    [[ "$ID" == azurelinux && "$VERSION_ID" == 4.0 ]] || fail 'Expected native Azure Linux 4.0; no changes made.'
    case "$(uname -m)" in
        x86_64) arch=x64 ;;
        aarch64) arch=arm64 ;;
        *) fail 'Only native x86_64 and aarch64 Linux are supported.' ;;
    esac
    [[ "$arch" == "$expected_arch" ]] || fail 'Existing distro architecture differs from the native Windows host; no changes made.'
    [[ "$(cat /proc/1/comm)" == systemd ]] ||
        fail 'systemd must be PID 1. Review /etc/wsl.conf [boot] systemd=true; restart only this distro yourself, then rerun.'
    [[ "$user" =~ ^[a-z_][a-z0-9_-]{0,31}$ && "$user" != root ]] || fail 'Invalid Linux user.'
    [[ "$bicep_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ &&
       "$copilot_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'Invalid stable binary version.'
    command -v dnf5 >/dev/null || fail 'DNF5 is required; this is not an Azure Linux 4 WSL image.'
    local -a packages=(azure-cli git jq curl unzip libicu tar gzip shadow-utils util-linux dnf5-plugin-automatic)
    dnf5 --refresh --setopt=gpgcheck=1 install -y "${packages[@]}"
    dnf5 --setopt=gpgcheck=1 upgrade -y "${packages[@]}"
    if ! getent passwd "$user" >/dev/null; then
        useradd --create-home --shell /bin/bash "$user"
        printf 'Created %s with a locked password; set one yourself with passwd if needed.\n' "$user"
    fi
    select_user "$user"
    work=$(mktemp -d)
    trap "rm -rf -- '$work'" EXIT
    # Use the official RPM repository with mandatory package signature checking.
    curl --disable --proto '=https' --proto-redir '=https' --fail --show-error --location \
        --retry 3 https://cli.github.com/packages/rpm/gh-cli.repo -o "$work/gh-cli.repo"
    [[ ! -L /etc/yum.repos.d/gh-cli.repo ]] || fail 'Refusing symlink repository configuration.'
    [[ ! -e /etc/yum.repos.d/gh-cli.repo ]] ||
        cmp -s "$work/gh-cli.repo" /etc/yum.repos.d/gh-cli.repo ||
        fail 'Existing gh-cli.repo differs from the official file; review it manually.'
    install -m 0644 "$work/gh-cli.repo" /etc/yum.repos.d/gh-cli.repo
    dnf5 --setopt=gpgcheck=1 --setopt=gh-cli.gpgcheck=1 install -y gh
    dnf5 --refresh --setopt=gpgcheck=1 --setopt=gh-cli.gpgcheck=1 upgrade -y gh
    download "https://github.com/Azure/bicep/releases/download/v${bicep_version}/bicep-linux-${arch}" \
        "$work/bicep" "$bicep_hash"
    download "https://github.com/github/copilot-cli/releases/download/v${copilot_version}/copilot-linux-${arch}.tar.gz" \
        "$work/copilot.tar.gz" "$copilot_hash"
    tar -xzf "$work/copilot.tar.gz" -C "$work" copilot
    install -m 0755 "$work/bicep" /usr/local/bin/bicep
    install -m 0755 "$work/copilot" /usr/local/bin/copilot
    as_user /usr/bin/az config set bicep.use_binary_from_path=true bicep.check_version=false auto-upgrade.enable=false
    configure_updates /etc/dnf/automatic.conf /etc/systemd/system/dnf5-automatic.timer.d
    systemctl daemon-reload
    systemctl enable --now dnf5-automatic.timer
    systemctl is-enabled --quiet dnf5-automatic.timer
    systemctl is-active --quiet dnf5-automatic.timer
    as_user /usr/bin/az --version
    as_user /usr/bin/gh --version
    as_user /usr/local/bin/bicep --version
    as_user /usr/bin/az bicep version
    as_user env COPILOT_AUTO_UPDATE=false /usr/local/bin/copilot --version
    printf 'Native tools and weekly DNF timer verified. No authentication performed.\n'
}

main() {
    case "${1:-}" in
        system) [[ $# -eq 7 ]] || fail 'Invalid system arguments.'; shift; provision_system "$@" ;;
        *) fail 'Expected system phase.' ;;
    esac
}

if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then main "$@"; fi
