#!/data/data/com.termux/files/usr/bin/bash

VERSION="1.0.1"
GITHUB="https://raw.githubusercontent.com/marxlonvi/lonvi/refs/heads/main"

CONFIG="$HOME/.dara7"
QUEUEFILE="$HOME/.dara7_queue"
PIDFILE="$HOME/.dara7.pid"

# Warna
R='\033[0;31m'
G='\033[0;32m'
Y='\033[38;5;208m'
C='\033[0;36m'
W='\033[0m'

PSLINK=""
AUTO_CLEAR_CACHE="yes"

# Status cache (update tiap poll cycle, bukan setiap display)
LAUNCHER_ACTIVE=0
CACHE_ACTIVE=0
QUEUE_COUNT=0
declare -a QUEUE_PKGS=()

# Background update check (non-blocking, silent)
(curl -fsSL "$GITHUB/version.txt" 2>/dev/null | {
    read remote
    if [ -n "$remote" ] && [ "$remote" != "$VERSION" ]; then
        tmpfile=$(mktemp)
        curl -fsSL "$GITHUB/dara7.sh" -o "$tmpfile" 2>/dev/null && \
            chmod +x "$tmpfile" 2>/dev/null && \
            mv "$tmpfile" "$0" 2>/dev/null && \
            exec "$0"
        rm -f "$tmpfile" 2>/dev/null
    fi
}) >/dev/null 2>&1 &

save_config() {
    cat > "$CONFIG" <<EOF
PSLINK="$PSLINK"
AUTO_CLEAR_CACHE="$AUTO_CLEAR_CACHE"
EOF
}

load_queue_cache() {
    QUEUE_PKGS=()
    QUEUE_COUNT=0
    [ -f "$QUEUEFILE" ] || return
    while IFS='|' read -r pkg _ ; do
        [ -z "$pkg" ] && continue
        QUEUE_PKGS+=("$pkg")
        ((QUEUE_COUNT++))
    done < "$QUEUEFILE"
}
