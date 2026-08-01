#!/data/data/com.termux/files/usr/bin/bash

VERSION="1.0.1"
GITHUB="https://raw.githubusercontent.com/marxlonvi/lonvi/refs/heads/main"

CONFIG="$HOME/.dara"
PIDFILE="$HOME/.dara.pid"
# Warna
R='\033[0;31m'
G='\033[0;32m'
Y='\033[38;5;208m'   # Oranye
C='\033[0;36m'       # Cyan
W='\033[0m'

PSLINK=""
PACKAGE=""

check_update() {
    remote=$(curl -fsSL "$GITHUB/version.txt" 2>/dev/null)

    if [ -n "$remote" ] && [ "$remote" != "$VERSION" ]; then
        echo "Update tersedia: $remote"
        tmpfile=$(mktemp)
        if curl -fsSL "$GITHUB/dara.sh" -o "$tmpfile"; then
            chmod +x "$tmpfile"
            mv "$tmpfile" "$0"
            exec "$0"
        else
            echo "Gagal mengunduh update, melanjutkan dengan versi saat ini."
            rm -f "$tmpfile"
            sleep 2
        fi
    fi
}

save_config() {
cat > "$CONFIG" <<EOF
PSLINK="$PSLINK"
PACKAGE="$PACKAGE"
EOF
}

[ -f "$CONFIG" ] && source "$CONFIG"

choose_roblox() {
    mapfile -t APPS < <(pm list packages | sed 's/package://' | grep -i roblox)

    if [ ${#APPS[@]} -eq 0 ]; then
        echo "Roblox tidak ditemukan."
        read -p "Enter..."
        return
    fi

    clear
    echo "===== PILIH ROBLOX ====="

    for i in "${!APPS[@]}"; do
        echo "$((i+1)). ${APPS[$i]}"
    done

    echo
    read -p "Pilih nomor: " pilih

    if [[ "$pilih" =~ ^[0-9]+$ ]] && [ "$pilih" -ge 1 ] && [ "$pilih" -le "${#APPS[@]}" ]; then
        PACKAGE="${APPS[$((pilih-1))]}"
        save_config
        echo
        echo "Dipilih:"
        echo "$PACKAGE"
    else
        echo "Pilihan tidak valid."
    fi

    read -p "Enter..."
}

# Background monitor: does NOT touch the terminal (no clear/echo to stdout),
# so it no longer fights with the interactive menu for screen control.
# Status is pushed via a Termux notification instead (requires termux-api).
monitor_loop() {
    while true; do
        if [ -n "$PACKAGE" ] && pidof "$PACKAGE" >/dev/null 2>&1; then
            STATUS="RUNNING"
        else
            STATUS="NOT RUNNING"
        fi

        if command -v termux-notification >/dev/null 2>&1; then
            termux-notification \
                --id dara_monitor \
                --title "DARA Monitor" \
                --content "Package: ${PACKAGE:-Belum dipilih} | Status: $STATUS" \
                --ongoing
        fi

        sleep 3
    done
}

start_monitor() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "Monitor sudah berjalan."
        sleep 2
        return
    fi

    nohup bash -c "$(declare -f monitor_loop); PACKAGE='$PACKAGE'; monitor_loop" >/dev/null 2>&1 &
    echo $! > "$PIDFILE"

    echo "Monitor dimulai (berjalan di background, cek notifikasi)."
    sleep 2
}

stop_monitor() {
    if [ -f "$PIDFILE" ]; then
        kill "$(cat "$PIDFILE")" 2>/dev/null
        rm -f "$PIDFILE"
        if command -v termux-notification-remove >/dev/null 2>&1; then
            termux-notification-remove dara_monitor
        fi
        echo "Monitor dihentikan."
    else
        echo "Monitor tidak berjalan."
    fi

    sleep 2
}

check_update

while true; do
    clear
echo -e "${Y}╔════════════════════════════╗${W}"
echo -e "${Y}║${C}         DARA v$VERSION        ${Y}║${W}"
echo -e "${Y}╠════════════════════════════╣${W}"
echo -e "${Y}║${W} 1. Masukkan Link PS        ${Y}║${W}"
echo -e "${Y}║${W} 2. Pilih Roblox            ${Y}║${W}"
echo -e "${Y}║${W} 3. Buka Roblox             ${Y}║${W}"
echo -e "${Y}║${W} 4. Start Monitor           ${Y}║${W}"
echo -e "${Y}║${W} 5. Stop Monitor            ${Y}║${W}"
echo -e "${Y}║${W} 0. Keluar                  ${Y}║${W}"
echo -e "${Y}╚════════════════════════════╝${W}"
echo

    read -p "Pilih: " menu

    case "$menu" in
        1)
            read -p "Link PS: " PSLINK
            save_config
            ;;

        2)
            choose_roblox
            ;;

        3)
            if [ -n "$PSLINK" ]; then
                termux-open-url "$PSLINK"
            else
                echo "Masukkan Link PS terlebih dahulu."
                sleep 2
            fi
            ;;

        4)
            start_monitor
            ;;

        5)
            stop_monitor
            ;;

        0)
            stop_monitor
            exit
            ;;

        *)
            echo "Menu tidak tersedia."
            sleep 1
            ;;
    esac
done
