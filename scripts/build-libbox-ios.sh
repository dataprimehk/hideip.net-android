#!/bin/sh
# Compatibility entry point. The unified recipe keeps Android and iOS inputs
# in lockstep and performs the security checks before installing the framework.
set -eu

REPO_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
exec "$REPO_DIR/scripts/build-libbox.sh" --ios
