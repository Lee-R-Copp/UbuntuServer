#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

log()  { printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"; }
warn() { printf '\n[WARN] %s\n' "$*" >&2; }
die()  { printf '\n[ERROR] %s\n' "$*" >&2; exit 1; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Run as root or with sudo."
  fi
}

require_ubuntu() {
  [[ -r /etc/os-release ]] || die "/etc/os-release not found."
  . /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || die "This script supports Ubuntu only."
}

pkg_installed() {
  dpkg -s "$1" >/dev/null 2>&1
}

install_packages() {
  local pkgs=()
  for pkg in curl ca-certificates git nano; do
    pkg_installed "$pkg" || pkgs+=("$pkg")
  done

  if (( ${#pkgs[@]} > 0 )); then
    log "Installing packages: ${pkgs[*]}"
    apt-get update
    apt-get install -y "${pkgs[@]}"
  else
    log "Required packages already installed."
  fi
}

ensure_dir() {
  local dir="$1"
  mkdir -p "$dir"
}

configure_ssh() {
  ensure_dir /etc/ssh/sshd_config.d
  cat >/etc/ssh/sshd_config.d/99-custom.conf <<'EOF'
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
EOF
  systemctl reload ssh || systemctl restart ssh
}

main() {
  require_root
  require_ubuntu
  install_packages
  configure_ssh
  log "Bootstrap complete."
}

main "$@"
