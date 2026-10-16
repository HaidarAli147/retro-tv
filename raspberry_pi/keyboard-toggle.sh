#!/usr/bin/env bash
# Manually show/hide the native Wayland keyboard when auto-focus is unavailable.
set -euo pipefail
case "${1:-show}" in
  show) visible=true ;;
  hide) visible=false ;;
  *) echo "Usage: $0 {show|hide}" >&2; exit 2 ;;
esac
busctl --user call sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 SetVisible b "$visible"
