#!/usr/bin/env bash
# Manual fallback for focus detection gaps, including Xwayland web apps.
set -euo pipefail
case "${1:-toggle}" in
  show) visible=true ;;
  hide) visible=false ;;
  toggle)
    # Calling SetVisible false is always safe; for deterministic behavior
    # callers should use 'show' or 'hide'.
    visible=true ;;
  *) echo "Usage: $0 {show|hide|toggle}" >&2; exit 2 ;;
esac
busctl --user call sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 SetVisible b "$visible"
