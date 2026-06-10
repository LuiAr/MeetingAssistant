#!/usr/bin/env bash
set -euo pipefail

# Runs the Phase 2 seam regression checks against the frozen sidecar contract
# (rebuild/CONTRACT.md). Builds the sidecar first so the spawn-based tests can find the
# binary in the products directory, then runs the test suite.
#
# Notes:
# - The capture check records about two seconds of real audio. It needs Microphone and
#   Screen Recording granted to the app you run this from (your terminal) in System
#   Settings, Privacy and Security. Without them it skips with a message rather than fail.
# - Everything runs inside rebuild/sidecar; the native app at the repo root is untouched.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIDECAR_DIR="$(cd "$SCRIPT_DIR/../sidecar" && pwd)"

cd "$SIDECAR_DIR"

echo "==> Building the sidecar (debug, for the test harness)"
swift build

echo "==> Running the seam regression checks"
swift test
