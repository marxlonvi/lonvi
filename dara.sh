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

# Background auto-rejoin loop: does NOT touch the terminal (no clear/echo
# to stdout), so it no longer fights with the interactive menu for screen
# control. It checks every few seconds whether the Roblox package is still
# running; if it has closed/crashed, it relaunches it via the PS link (or,
# if no link is set, via the app's own launcher intent).
rejoin_loop() {
    while true; do
        if [ -n "$PACKAGE" ]; then
            if ! pidof "$PACKAGE" >/dev/null 2>&1; then
                if command -v termux-notification >/dev/null 2>&1; then
                    termux-notification \
                        --id dara_rejoin \
                        --title "DARA Auto-Rejoin" \
                        --content "$PACKAGE tidak berjalan, mencoba rejoin..."
                fi

                if [ -n "$PSLINK" ]; then
                    termux-open-url "$PSLINK"
                else
                    am start -n "$(cmd package resolve-activity --brief "$PACKAGE" 2>/dev/null | tail -n 1)" >/dev/null 2>&1 \
                        || monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
                fi

                # beri waktu app untuk benar-benar terbuka sebelum cek lagi
                sleep 15
            fi
        fi

        sleep 5
    done
}

start_rejoin() {
    if [ -z "$PACKAGE" ]; then
        echo "Pilih Roblox terlebih dahulu (menu 2)."
        sleep 2
        return
    fi

    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "Auto-rejoin sudah berjalan."
        sleep 2
        return
    fi

    nohup bash -c "$(declare -f rejoin_loop); PACKAGE='$PACKAGE'; PSLINK='$PSLINK'; rejoin_loop" >/dev/null 2>&1 &
    echo $! > "$PIDFILE"

    echo "Auto-rejoin dimulai di background."
    sleep 2
}

stop_rejoin() {
    if [ -f "$PIDFILE" ]; then
        kill "$(cat "$PIDFILE")" 2>/dev/null
        rm -f "$PIDFILE"
        if command -v termux-notification-remove >/dev/null 2>&1; then
            termux-notification-remove dara_rejoin
        fi
        echo "Auto-rejoin dihentikan."
    else
        echo "Auto-rejoin tidak berjalan."
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
echo -e "${Y}║${W} 4. Start Rejoin            ${Y}║${W}"
echo -e "${Y}║${W} 5. Stop Rejoin             ${Y}║${W}"
echo -e "${Y}║${W} 0. Keluar                  ${Y}║${W}"
echo -e "${Y}╚════════════════════════════╝${W}"
echo

echo -e "${C}Link PS   :${W} ${PSLINK:-Belum diatur}"
echo -e "${C}Roblox    :${W} ${PACKAGE:-Belum dipilih}"

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo -e "${C}Rejoin    :${W} ${G}● AKTIF${W}"
else
    echo -e "${C}Rejoin    :${W} ${R}● TIDAK AKTIF${W}"
fi

if [ -n "$PACKAGE" ]; then
    if pidof "$PACKAGE" >/dev/null 2>&1; then
        echo -e "${C}Status App:${W} ${G}● RUNNING${W}"
    else
        echo -e "${C}Status App:${W} ${R}● NOT RUNNING${W}"
    fi
fi

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
            start_rejoin
            ;;

        5)
            stop_rejoin
            ;;

        0)
            stop_rejoin
            exit
            ;;

        *)
            echo "Menu tidak tersedia."
            sleep 1
            ;;
    esac
done
