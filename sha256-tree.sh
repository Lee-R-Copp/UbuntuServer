#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <directory>" >&2
  exit 1
fi

root=$1

if [ ! -d "$root" ]; then
  echo "Error: '$root' is not a directory" >&2
  exit 1
fi

# Recursively compute sha256 for each file
find "$root" -type f -exec sha256sum '{}' \;
