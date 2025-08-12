#!/bin/bash

#==============================================================================
# System Initialization and Configuration Script
#==============================================================================

# --- Script Configuration and Preamble ---

# Exit immediately if a command exits with a non-zero status.
set -e

# Set DEBIAN_FRONTEND to noninteractive to prevent prompts.
export DEBIAN_FRONTEND=noninteractive

# --- Function Definitions ---

#
# Clears on-disk history for all users and the root account.
#
clean_history() {
    echo "▶ Clearing on-disk command history files..."

    # Unset HISTFILE for the script's session to prevent its own commands from being logged.
    unset HISTFILE

    # Define the common history filenames to clear.
    local history_files=(".bash_history" ".zsh_history" ".fish_history")

    # Clear history for the root user.
    echo "  - Clearing history for user: root"
    for hist_file in "${history_files[@]}"; do
        # Check if the history file exists for root before trying to clear it.
        if [ -f "/root/${hist_file}" ]; then
            cat /dev/null > "/root/${hist_file}"
        fi
    done

    # Iterate over user directories in /home.
    for user_dir in /home/*; do
        # Ensure it is a directory.
        if [ -d "$user_dir" ]; then
            local user
            user=$(basename "$user_dir")
            echo "  - Clearing history for user: $user"
            for hist_file in "${history_files[@]}"; do
                local full_path="${user_dir}/${hist_file}"
                # Check if the history file exists before trying to clear it.
                if [ -f "$full_path" ]; then
                    cat /dev/null > "$full_path"
                fi
            done
        fi
    done

    echo "✔ On-disk history files cleared."
    echo "ℹ NOTE: To clear the history of your CURRENT terminal session, please run 'history -c' after this script completes."
}

#
# Configure Firewall
#
configure_firewall() {
  echo "▶ Configuring Firewall...\e[0m"

  ufw default deny incoming
  ufw default allow outgoing
  ufw allow ssh
  ufw enable
  ufw status
  ufw status numbered  # Backup the original configuration file
  echo "✔ Firewall configured."
}

#
# Hardens OpenSSL configuration to modern standards.
#
configure_openssl() {
  echo "▶ Configuring OpenSSL security settings..."
  local openssl_config="/etc/ssl/openssl.cnf"

  # Backup the original configuration file
  cp "$openssl_config" "$openssl_config.bak"

  # Add MinProtocol and CipherString if they don't already exist
  if ! grep -q "^MinProtocol" "$openssl_config"; then
    sed -i '/^\[system_default_sect\]$/a MinProtocol = TLSv1.2' "$openssl_config"
  fi
  if ! grep -q "^CipherString" "$openssl_config"; then
    sed -i '/^\[system_default_sect\]$/a CipherString = DEFAULT@SECLEVEL=2' "$openssl_config"
  fi
  echo "✔ OpenSSL security settings applied."
}

#
# Configure the system timezone.
#
configure_timezone() {
    echo "▶ Configuring system timezone to UTC..."
    # Set the timezone
    sudo timedatectl set-timezone Etc/UTC
    echo "✔ Timezone configured to UTC."
}

#
# Performs initial checks to ensure script can run successfully.
#
initial_checks() {
  echo "▶ Performing initial checks..."
  # Check for root privileges
  if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run this script as root or using sudo." >&2
    exit 1
  fi
}

#
# Updates package lists and installs all required packages in one go.
#
install_packages() {
  echo "▶ Updating package repositories..."

  echo "▶ Updating package lists..."
  apt-get update -y 2>&1 | grep -v "WARNING: apt does not have a stable CLI interface"

  echo "▶ Installing all required packages..."
  apt-get install -y \
    apt-file \
    haveged \
    nano \
    net-tools \
    wget \
    unzip \
    2>&1 | grep -v "WARNING: apt does not have a stable CLI interface"
  echo "✔ Package installation complete."
}

#
# Enables and restarts all necessary services.
#
restart_services() {
  echo "▶ Enabling and restarting services..."

  # Restart services that use SSH or OpenSSL
  local services_to_restart=("ssh")
  for service in "${services_to_restart[@]}"; do
    if systemctl list-units --full --all | grep -q "${service}.service"; then
      echo "  - Restarting ${service}..."
      systemctl restart "${service}"
    else
      echo "  - Service ${service} not found, skipping restart."
    fi
  done
  echo "✔ Services have been restarted."
}

# --- Main Execution ---

main() {
  initial_checks
  install_packages
  configure_openssl
  configure_timezone
  configure_firewall()
  restart_services
  clean_history
  
  echo -e "\n\e[1;32m✅ System setup and configuration are complete.\e[0m"
}

main "$@"
# --- End of Script ---
