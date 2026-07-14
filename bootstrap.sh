#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

log()  { printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"; }
warn() { printf '\n[WARN] %s\n' "$*" >&2; }
die()  { printf '\n[ERROR] %s\n' "$*" >&2; exit 1; }

BOOTSTRAP_USER="${SUDO_USER:-${USER:-root}}"
BOOTSTRAP_HOME="$(getent passwd "$BOOTSTRAP_USER" | cut -d: -f6 2>/dev/null || true)"

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

ensure_dir() {
  local dir="$1"
  mkdir -p "$dir"
}

ensure_file() {
  local file="$1"
  touch "$file"
}

ensure_line() {
  local line="$1"
  local file="$2"
  ensure_file "$file"
  grep -Fqx "$line" "$file" || echo "$line" >> "$file"
}

write_file_if_changed() {
  local target="$1"
  local tmp
  tmp="$(mktemp)"
  cat >"$tmp"

  if [[ ! -f "$target" ]] || ! cmp -s "$tmp" "$target"; then
    install -m 0644 "$tmp" "$target"
    rm -f "$tmp"
    return 0
  fi

  rm -f "$tmp"
  return 1
}

apt_update_once() {
  if [[ -z "${APT_UPDATED:-}" ]]; then
    log "Refreshing apt package index"
    apt-get update
    APT_UPDATED=1
  fi
}

install_packages() {
  local pkgs=()
  for pkg in \
    apt-transport-https \
    bash-completion \
    ca-certificates \
    command-not-found \
    curl \
    git \
    gnupg \
    htop \
    jq \
    less \
    lsb-release \
    nano \
    needrestart \
    rsync \
    software-properties-common \
    tree \
    unzip \
    wget \
    zip; do
    pkg_installed "$pkg" || pkgs+=("$pkg")
  done

  if (( ${#pkgs[@]} > 0 )); then
    apt_update_once
    log "Installing packages: ${pkgs[*]}"
    apt-get install -y "${pkgs[@]}"
  else
    log "Required base packages already installed."
  fi
}

upgrade_system() {
  apt_update_once
  log "Upgrading installed packages"
  apt-get upgrade -y
}

disable_auto_updates() {
  log "Disabling automatic apt update activity"

  systemctl disable --now unattended-upgrades 2>/dev/null || true
  systemctl disable --now apt-daily.service apt-daily.timer 2>/dev/null || true
  systemctl disable --now apt-daily-upgrade.service apt-daily-upgrade.timer 2>/dev/null || true

  write_file_if_changed /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::AutocleanInterval "0";
APT::Periodic::Unattended-Upgrade "0";
EOF

  if pkg_installed unattended-upgrades; then
    apt-get remove -y unattended-upgrades
  fi
}

configure_timezone() {
  local timezone="${1:-Etc/UTC}"

  if [[ -e "/usr/share/zoneinfo/${timezone}" ]]; then
    log "Setting timezone to ${timezone}"
    timedatectl set-timezone "${timezone}"
  else
    warn "Timezone ${timezone} not found. Leaving current timezone unchanged."
  fi
}

configure_time_sync() {
  local timeout="${1:-90}"
  local elapsed=0

  log "Enabling NTP time synchronization"
  timedatectl set-ntp true || die "Failed to enable NTP via timedatectl."

  systemctl enable --now systemd-timesyncd.service >/dev/null 2>&1 || \
    die "Failed to enable systemd-timesyncd.service."

  while (( elapsed < timeout )); do
    if [[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" == "yes" ]]; then
      log "NTP synchronization confirmed"
      return 0
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done

  journalctl -u systemd-timesyncd -n 20 --no-pager >&2 || true
  die "NTP did not synchronize within ${timeout} seconds."
}

configure_ssh() {
  ensure_dir /etc/ssh/sshd_config.d

  cat >/etc/ssh/sshd_config.d/99-bootstrap.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

  if sshd -t; then
    log "Reloading SSH service"
    systemctl reload ssh || systemctl restart ssh
  else
    die "sshd configuration test failed."
  fi
}

configure_user_shell() {
  local home="${BOOTSTRAP_HOME}"
  local profile="${home}/.profile"
  local bashrc="${home}/.bashrc"

  [[ -n "$home" && -d "$home" ]] || return 0

  ensure_file "$profile"
  ensure_file "$bashrc"

  ensure_line 'source ~/.bashrc' "$profile"

  {
    printf "alias dir='ls -aFhl --color'\n"
    printf "alias edit=\"/bin/nano -w\"\n"
    printf "export EDITOR=\"/bin/nano\"\n"
    printf "PS1=\"\\[\\033[1;32m\\][\\$(date '+%Y-%m-%d_%H:%M:%S')]\\[\\033[1;35m\\][\\u@\\h:\\w]\\$\\[\\033[0m\\] \"\n"
  } >> "$bashrc"

  chown "$BOOTSTRAP_USER:$BOOTSTRAP_USER" "$profile" "$bashrc" 2>/dev/null || true
}

configure_ssh_key_scaffold() {
  local ssh_dir="${BOOTSTRAP_HOME}/.ssh"
  local auth_keys="${ssh_dir}/authorized_keys"

  [[ -n "${BOOTSTRAP_HOME}" && -d "${BOOTSTRAP_HOME}" ]] || die "Bootstrap user home not found."

  install -d -m 700 -o "${BOOTSTRAP_USER}" -g "${BOOTSTRAP_USER}" "${ssh_dir}"
  install -m 600 -o "${BOOTSTRAP_USER}" -g "${BOOTSTRAP_USER}" /dev/null "${auth_keys}"

  if [[ ! -f "${ssh_dir}/id_ed25519" ]]; then
    sudo -u "${BOOTSTRAP_USER}" ssh-keygen -t ed25519 -f "${ssh_dir}/id_ed25519" -N ""
  fi

  grep -Fqx "$(cat "${ssh_dir}/id_ed25519.pub")" "${auth_keys}" || \
    cat "${ssh_dir}/id_ed25519.pub" >> "${auth_keys}"

  chown "${BOOTSTRAP_USER}:${BOOTSTRAP_USER}" \
    "${ssh_dir}/id_ed25519" \
    "${ssh_dir}/id_ed25519.pub" \
    "${auth_keys}"

  chmod 700 "${ssh_dir}"
  chmod 600 "${ssh_dir}/id_ed25519" "${auth_keys}"
  chmod 644 "${ssh_dir}/id_ed25519.pub"
}

configure_nanorc() {
  write_file_if_changed /etc/nanorc <<'EOF'
set linenumbers
set mouse
set autoindent
set tabsize 2
set tabstospaces
set softwrap
set historylog
set positionlog
set indicator
set minibar
set scrollercolor brightblue
set titlecolor brightwhite,blue
set selectedcolor black,yellow
set numbercolor cyan
set keycolor cyan
set functioncolor green
EOF
}

configure_bash_environment() {
  write_file_if_changed /etc/profile.d/99-bootstrap-shell.sh <<'EOF'
export EDITOR=nano
export VISUAL=nano
export PAGER=less

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias cls='clear'
EOF

  if [[ -n "${BOOTSTRAP_HOME}" && -d "${BOOTSTRAP_HOME}" ]]; then
    ensure_line '[[ -f /etc/bash_completion ]] && . /etc/bash_completion' "${BOOTSTRAP_HOME}/.bashrc"
    ensure_line 'export EDITOR=nano' "${BOOTSTRAP_HOME}/.bashrc"
    ensure_line 'export VISUAL=nano' "${BOOTSTRAP_HOME}/.bashrc"
    chown "${BOOTSTRAP_USER}:${BOOTSTRAP_USER}" "${BOOTSTRAP_HOME}/.bashrc" 2>/dev/null || true
  fi
}

create_script_dirs() {
  if [[ -n "${BOOTSTRAP_HOME}" && -d "${BOOTSTRAP_HOME}" ]]; then
    ensure_dir "${BOOTSTRAP_HOME}/bin"
    ensure_dir "${BOOTSTRAP_HOME}/scripts"
    chown -R "${BOOTSTRAP_USER}:${BOOTSTRAP_USER}" "${BOOTSTRAP_HOME}/bin" "${BOOTSTRAP_HOME}/scripts" 2>/dev/null || true
  fi

  ensure_dir /usr/local/bin
}

show_summary() {
  log "Bootstrap complete"
  printf '%s\n' \
    "User: ${BOOTSTRAP_USER}" \
    "Home: ${BOOTSTRAP_HOME:-unknown}" \
    "Editor: nano" \
    "Firewall: manage outside the host if desired" \
    "SSH: password auth disabled, root login disabled" \
    "Automatic apt updates: disabled"
}

main() {
  require_root
  require_ubuntu
  install_packages
  upgrade_system
  disable_auto_updates
  configure_timezone "Etc/UTC"
  configure_time_sync 90
  configure_ssh
  configure_nanorc
  configure_bash_environment
  create_script_dirs
  configure_user_shell
  configure_ssh_key_scaffold
  show_summary
}

main "$@"
