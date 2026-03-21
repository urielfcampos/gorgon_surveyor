#!/usr/bin/env bash
set -euo pipefail

# Build the Phoenix desktop release and place it as a Tauri sidecar.
#
# Usage: ./scripts/build-desktop.sh
#
# This script:
# 1. Builds assets (tailwind + esbuild, minified)
# 2. Creates a Mix release named "desktop"
# 3. Copies the release start script to src-tauri/binaries/ with the
#    correct target-triple naming convention for Tauri sidecars

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

# Detect target triple
TARGET_TRIPLE=$(rustc --print host-tuple 2>/dev/null || echo "unknown")
if [ "$TARGET_TRIPLE" = "unknown" ]; then
  echo "Error: rustc not found. Install Rust to determine target triple."
  exit 1
fi

echo "==> Building for target: $TARGET_TRIPLE"

# Build assets
echo "==> Building assets..."
mise exec -- mix assets.deploy

# Build the release
echo "==> Building Mix release (desktop)..."
MIX_ENV=prod mise exec -- mix release desktop --overwrite

RELEASE_DIR="$PROJECT_ROOT/_build/prod/rel/desktop"

if [ ! -d "$RELEASE_DIR" ]; then
  echo "Error: Release not found at $RELEASE_DIR"
  exit 1
fi

# Create a wrapper script that sets env vars and starts the release
BINARIES_DIR="$PROJECT_ROOT/src-tauri/binaries"
mkdir -p "$BINARIES_DIR"

SIDECAR_PATH="$BINARIES_DIR/phoenix-server-$TARGET_TRIPLE"

cat > "$SIDECAR_PATH" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="\$(cd "\$(dirname "\$0")" && pwd)"

# Check for bundled release (production) first, then dev build location
if [ -d "\$SCRIPT_DIR/desktop" ]; then
  RELEASE_ROOT="\$SCRIPT_DIR/desktop"
else
  RELEASE_ROOT="$RELEASE_DIR"
fi

export PHX_SERVER=true
export PORT=4840
export GORGON_DESKTOP=true
export RELEASE_DISTRIBUTION=none

exec "\$RELEASE_ROOT/bin/desktop" start
WRAPPER

chmod +x "$SIDECAR_PATH"

echo "==> Sidecar built: $SIDECAR_PATH"
echo ""
echo "Next steps:"
echo "  npm install              # install Tauri CLI (first time)"
echo "  npm run tauri build      # build the desktop app"
