#!/bin/sh
# Update/Upgrade System

# script must be run as root...
if [ $(id -u) -eq 0 ]; then
  echo "\nPre-cleaning old files...\n"
  apt-get autoremove -y

  echo "\nUpdating Software Repositories...\n"
  apt-get update -y

  echo "\nApplying available upgrades...\n"
  apt-get upgrade -y

  echo "\nUprading Distro if available...\n"
  apt-get dist-upgrade -y

  echo "\nPost-cleaning old files...\n"
  apt-get autoremove -y

  echo "\n"
else
  echo "\nThis script must be run as root."
  echo "\nUse: 'sudo ./update.ubuntu.sh'\n"
  exit 1
fi
