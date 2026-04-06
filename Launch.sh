#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# Marinara Engine + JanitorAI Launcher v1.0 (Linux/macOS)
# by iaminvisibru
#
# A standalone launcher that adds JanitorAI back to the Bot
# Browser. Works alongside the official start.sh — just use
# this launcher instead.
# ═══════════════════════════════════════════════════════════════

set -e

LAUNCHER_DIR="$(cd "$(dirname "$0")" && pwd)"
HASH_FILE="$LAUNCHER_DIR/known-hashes.txt"
PATCHED_ROUTES="$LAUNCHER_DIR/bot-browser.routes.patched.ts"
PATCHED_VIEW="$LAUNCHER_DIR/BotBrowserView.patched.tsx"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
GRAY='\033[0;37m'
NC='\033[0m'

status() { echo -e "  ${CYAN}[..]${NC} $1"; }
ok()     { echo -e "  ${GREEN}[OK]${NC} $1"; }
warn()   { echo -e "  ${YELLOW}[!!]${NC} $1"; }
err()    { echo -e "  ${RED}[XX]${NC} $1"; }

file_hash() {
    if [ ! -f "$1" ]; then
        echo "MISSING"
    else
        sha256sum "$1" 2>/dev/null | awk '{print $1}' || shasum -a 256 "$1" 2>/dev/null | awk '{print $1}' || echo "UNKNOWN"
    fi
}

clear
echo ""
echo -e "  ${MAGENTA}+=============================================+${NC}"
echo -e "  ${MAGENTA}|   Marinara Engine + JanitorAI Launcher      |${NC}"
echo -e "  ${MAGENTA}|   v1.0 by iaminvisibru                      |${NC}"
echo -e "  ${MAGENTA}+=============================================+${NC}"
echo ""

# ══════════════════════════════════════════════
# FIND MARINARA ENGINE
# ══════════════════════════════════════════════
MARINARA_DIR=""
POSSIBLE_PATHS=(
    "$HOME/.local/share/MarinaraEngine"
    "$HOME/MarinaraEngine"
    "$HOME/marinara-engine"
    "$HOME/Marinara-Engine"
    "$HOME/Desktop/MarinaraEngine"
    "/opt/MarinaraEngine"
    "$HOME/.marinara-engine"
)

for p in "${POSSIBLE_PATHS[@]}"; do
    if [ -f "$p/package.json" ]; then
        MARINARA_DIR="$p"
        break
    fi
done

if [ -z "$MARINARA_DIR" ]; then
    warn "Could not auto-detect Marinara Engine location."
    echo ""
    echo -e "  ${GRAY}Common locations:${NC}"
    echo -e "  ${GRAY}  ~/.local/share/MarinaraEngine${NC}"
    echo -e "  ${GRAY}  ~/MarinaraEngine${NC}"
    echo ""
    read -rp "  Enter your Marinara Engine folder path: " custom
    custom="${custom%/}"
    custom="${custom/#\~/$HOME}"
    if [ -f "$custom/package.json" ]; then
        MARINARA_DIR="$custom"
    else
        err "No package.json found at: $custom"
        read -rp "Press Enter to exit"
        exit 1
    fi
fi

ok "Found Marinara Engine at: $MARINARA_DIR"

# File paths
TARGET_ROUTES="$MARINARA_DIR/packages/server/src/routes/bot-browser.routes.ts"
TARGET_VIEW="$MARINARA_DIR/packages/client/src/components/bot-browser/BotBrowserView.tsx"

# Verify patch files
if [ ! -f "$PATCHED_ROUTES" ]; then
    err "Missing file: bot-browser.routes.patched.ts"
    err "It should be in the same folder as this launcher."
    read -rp "Press Enter to exit"
    exit 1
fi
if [ ! -f "$PATCHED_VIEW" ]; then
    err "Missing file: BotBrowserView.patched.tsx"
    err "It should be in the same folder as this launcher."
    read -rp "Press Enter to exit"
    exit 1
fi

# Verify targets exist
if [ ! -f "$TARGET_ROUTES" ]; then
    err "Cannot find: $TARGET_ROUTES"
    err "Your Marinara install may be corrupted or a different version."
    read -rp "Press Enter to exit"
    exit 1
fi
if [ ! -f "$TARGET_VIEW" ]; then
    err "Cannot find: $TARGET_VIEW"
    err "Your Marinara install may be corrupted or a different version."
    read -rp "Press Enter to exit"
    exit 1
fi

# ══════════════════════════════════════════════
# CHECK NODE.JS & PNPM
# ══════════════════════════════════════════════
if ! command -v node &>/dev/null; then
    err "Node.js not found. Install Node.js 20+ from https://nodejs.org"
    read -rp "Press Enter to exit"
    exit 1
fi
ok "Node.js: $(node -v)"

cd "$MARINARA_DIR"

PNPM_VERSION="10.30.3"
if [ -f "package.json" ]; then
    PKG_MGR=$(node -p "JSON.parse(require('fs').readFileSync('package.json','utf8')).packageManager || ''" 2>/dev/null)
    if [[ "$PKG_MGR" == pnpm@* ]]; then
        PNPM_VERSION="${PKG_MGR#pnpm@}"
    fi
fi

if ! command -v pnpm &>/dev/null; then
    status "Installing pnpm $PNPM_VERSION..."
    if command -v corepack &>/dev/null; then
        corepack enable 2>/dev/null
        corepack prepare "pnpm@$PNPM_VERSION" --activate 2>/dev/null
    else
        npm install -g "pnpm@$PNPM_VERSION" 2>/dev/null
    fi
else
    CURRENT_PNPM=$(pnpm -v 2>/dev/null)
    if [ "$CURRENT_PNPM" != "$PNPM_VERSION" ]; then
        status "Aligning pnpm to $PNPM_VERSION..."
        if command -v corepack &>/dev/null; then
            corepack enable 2>/dev/null
            corepack prepare "pnpm@$PNPM_VERSION" --activate 2>/dev/null
        else
            npm install -g "pnpm@$PNPM_VERSION" 2>/dev/null
        fi
    fi
fi
ok "pnpm $PNPM_VERSION ready"

# ══════════════════════════════════════════════
# GIT UPDATE
# ══════════════════════════════════════════════
NEEDS_REBUILD=false
SKIP_PATCH=false

if [ -d "$MARINARA_DIR/.git" ]; then
    status "Checking for updates..."

    OLD_HEAD=$(git rev-parse HEAD 2>/dev/null)

    STASHED=false
    if ! git diff --quiet 2>/dev/null; then
        git stash push -q -m "janitor-launcher-auto-stash" 2>/dev/null && STASHED=true
    fi

    if git pull 2>&1 | while read -r line; do echo -e "    ${GRAY}$line${NC}"; done; then
        NEW_HEAD=$(git rev-parse HEAD 2>/dev/null)

        if [ "$OLD_HEAD" != "$NEW_HEAD" ]; then
            ok "Updated to latest version!"
            NEEDS_REBUILD=true

            if [ "$STASHED" = true ]; then
                git stash drop -q 2>/dev/null
                STASHED=false
            fi

            status "Reinstalling dependencies..."
            pnpm install 2>&1 | while read -r line; do echo -e "    ${GRAY}$line${NC}"; done

            status "Cleaning old builds..."
            rm -rf packages/shared/dist packages/server/dist packages/client/dist
            rm -f packages/shared/tsconfig.tsbuildinfo packages/server/tsconfig.tsbuildinfo packages/client/tsconfig.tsbuildinfo
        else
            ok "Already up to date."
            if [ "$STASHED" = true ]; then
                git stash pop -q 2>/dev/null
            fi
        fi
    else
        warn "Git pull failed. Continuing with current version."
        if [ "$STASHED" = true ]; then
            git stash pop -q 2>/dev/null
        fi
    fi
else
    warn "Not a git repo - skipping update."
fi

if [ ! -d "$MARINARA_DIR/node_modules" ]; then
    status "Installing dependencies (first run)..."
    pnpm install 2>&1 | while read -r line; do echo -e "    ${GRAY}$line${NC}"; done
    NEEDS_REBUILD=true
fi

# ══════════════════════════════════════════════
# CHECK FILE COMPATIBILITY
# ══════════════════════════════════════════════
status "Checking file compatibility..."

CURRENT_ROUTES_HASH=$(file_hash "$TARGET_ROUTES")
CURRENT_VIEW_HASH=$(file_hash "$TARGET_VIEW")

if [ -f "$HASH_FILE" ]; then
    KNOWN_ROUTES_HASH=$(sed -n '1p' "$HASH_FILE")
    KNOWN_VIEW_HASH=$(sed -n '2p' "$HASH_FILE")

    ROUTES_CHANGED=false
    VIEW_CHANGED=false
    [ "$CURRENT_ROUTES_HASH" != "$KNOWN_ROUTES_HASH" ] && ROUTES_CHANGED=true
    [ "$CURRENT_VIEW_HASH" != "$KNOWN_VIEW_HASH" ] && VIEW_CHANGED=true

    if [ "$ROUTES_CHANGED" = true ] || [ "$VIEW_CHANGED" = true ]; then
        echo ""
        err "============================================"
        err "  UPSTREAM FILES HAVE CHANGED!"
        err "============================================"
        echo ""
        [ "$ROUTES_CHANGED" = true ] && err "  Changed: bot-browser.routes.ts"
        [ "$VIEW_CHANGED" = true ] && err "  Changed: BotBrowserView.tsx"
        echo ""
        warn "The JanitorAI patch may not work with the updated files."
        echo ""
        echo -e "  ${NC}[1] Launch WITHOUT JanitorAI (safe)${NC}"
        echo -e "  ${YELLOW}[2] Force patch anyway (may break!)${NC}"
        echo -e "  ${CYAN}[3] I updated the patch files - reset hashes${NC}"
        echo -e "  ${GRAY}[4] Exit${NC}"
        echo ""
        read -rp "  Enter choice (1/2/3/4): " choice

        case "$choice" in
            1)
                status "Launching without JanitorAI patch..."
                SKIP_PATCH=true
                ;;
            2)
                warn "Force-patching. If it breaks, run the official start.sh to fix."
                ;;
            3)
                status "Resetting hashes..."
                echo "$CURRENT_ROUTES_HASH" > "$HASH_FILE"
                echo "$CURRENT_VIEW_HASH" >> "$HASH_FILE"
                ok "Done. Re-run this launcher."
                read -rp "Press Enter to exit"
                exit 0
                ;;
            *)
                exit 0
                ;;
        esac
    else
        ok "Files compatible - safe to patch!"
    fi
else
    status "First run - saving file signatures..."
    echo "$CURRENT_ROUTES_HASH" > "$HASH_FILE"
    echo "$CURRENT_VIEW_HASH" >> "$HASH_FILE"
    ok "Baseline saved."
fi

# ══════════════════════════════════════════════
# PATCH FILES
# ══════════════════════════════════════════════
if [ "$SKIP_PATCH" = false ]; then
    echo ""
    status "Patching bot-browser.routes.ts (adding JanitorAI routes)..."
    cp "$PATCHED_ROUTES" "$TARGET_ROUTES"
    ok "Server routes patched!"

    status "Patching BotBrowserView.tsx (adding JanitorAI provider)..."
    cp "$PATCHED_VIEW" "$TARGET_VIEW"
    ok "Client view patched!"
    echo ""

    rm -rf packages/server/dist packages/client/dist
    rm -f packages/server/tsconfig.tsbuildinfo packages/client/tsconfig.tsbuildinfo
    NEEDS_REBUILD=true
fi

# ══════════════════════════════════════════════
# VERSION MISMATCH CHECK
# ══════════════════════════════════════════════
SHARED_DIST="$MARINARA_DIR/packages/shared/dist"
SERVER_DIST="$MARINARA_DIR/packages/server/dist"
CLIENT_DIST="$MARINARA_DIR/packages/client/dist"
DEFAULTS_JS="$SHARED_DIST/constants/defaults.js"

if [ -f "$DEFAULTS_JS" ]; then
    SOURCE_VER=$(node -p "require('./package.json').version" 2>/dev/null || echo "")
    DIST_VER=$(node -e "try{const m=require('$DEFAULTS_JS');console.log(m.APP_VERSION)}catch{}" 2>/dev/null || echo "")

    if [ -n "$SOURCE_VER" ] && [ -n "$DIST_VER" ] && [ "$SOURCE_VER" != "$DIST_VER" ]; then
        warn "Version mismatch: source v$SOURCE_VER vs dist v$DIST_VER"
        status "Forcing full rebuild..."
        rm -rf "$SHARED_DIST" "$SERVER_DIST" "$CLIENT_DIST"
        NEEDS_REBUILD=true
    fi
fi

# ══════════════════════════════════════════════
# BUILD
# ══════════════════════════════════════════════
if [ ! -d "$SHARED_DIST" ] || [ "$NEEDS_REBUILD" = true ]; then
    status "Building shared types..."
    pnpm build:shared 2>&1 | while read -r line; do echo -e "    ${GRAY}$line${NC}"; done
fi

if [ ! -d "$SERVER_DIST" ]; then
    status "Building server..."
    pnpm build:server 2>&1 | while read -r line; do echo -e "    ${GRAY}$line${NC}"; done
fi

if [ ! -d "$CLIENT_DIST" ]; then
    status "Building client..."
    pnpm build:client 2>&1 | while read -r line; do echo -e "    ${GRAY}$line${NC}"; done
fi

ok "Build complete!"

# ══════════════════════════════════════════════
# LAUNCH
# ══════════════════════════════════════════════
if [ -f "$MARINARA_DIR/.env" ]; then
    set -a
    source "$MARINARA_DIR/.env"
    set +a
fi

export NODE_ENV=production
export PORT="${PORT:-7860}"
export HOST="${HOST:-0.0.0.0}"

PROTOCOL="http"
if [ -n "$SSL_CERT" ] && [ -n "$SSL_KEY" ]; then
    PROTOCOL="https"
fi

LISTEN_URL="${PROTOCOL}://localhost:${PORT}"

echo ""
echo -e "  ${GREEN}============================================${NC}"
echo -e "  ${GREEN}  Starting Marinara Engine${NC}"
echo -e "  ${GREEN}  $LISTEN_URL${NC}"
if [ "$SKIP_PATCH" = false ]; then
    echo -e "  ${MAGENTA}  JanitorAI: ENABLED${NC}"
else
    echo -e "  ${YELLOW}  JanitorAI: DISABLED (needs update)${NC}"
fi
echo -e "  ${GREEN}  Press Ctrl+C to stop${NC}"
echo -e "  ${GREEN}============================================${NC}"
echo ""

# Auto-open browser
AUTO_OPEN="${AUTO_OPEN_BROWSER:-1}"
if [[ ! "$AUTO_OPEN" =~ ^(0|false|no|off)$ ]]; then
    (sleep 4 && xdg-open "$LISTEN_URL" 2>/dev/null || open "$LISTEN_URL" 2>/dev/null) &
fi

# Start server
cd "$MARINARA_DIR/packages/server"
node dist/index.js

echo ""
err "Server exited unexpectedly. Check the error above."
read -rp "Press Enter to exit"
