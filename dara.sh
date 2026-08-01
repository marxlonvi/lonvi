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
        curl -fsSL "$GITHUB/dara.sh" -o "$0"
        chmod +x "$0"
        exec "$0"
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

    if [ "$pilih" -ge 1 ] 2>/dev/null && [ "$pilih" -le "${#APPS[@]}" ]; then
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

monitor_loop() {
    while true; do
        clear
echo -e "${Y}╔════════════════════════════╗${W}"
echo -e "${Y}║${C}      DARA MONITOR         ${Y}║${W}"
echo -e "${Y}╚════════════════════════════╝${W}"
echo

echo -e "${C}Package :${W} ${PACKAGE:-Belum dipilih}"

if [ -n "$PACKAGE" ] && pidof "$PACKAGE" >/dev/null 2>&1; then
    echo -e "${G}● RUNNING${W}"
else
    echo -e "${R}● NOT RUNNING${W}"
fi

echo
echo -e "${Y}Tekan Ctrl+C untuk keluar monitor.${W}"
sleep 3
}

start_monitor() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "Monitor sudah berjalan."
        sleep 2
        return
    fi

    monitor_loop &
    echo $! > "$PIDFILE"

    echo "Monitor dimulai."
    sleep 2
}

stop_monitor() {
    if [ -f "$PIDFILE" ]; then
        kill "$(cat "$PIDFILE")" 2>/dev/null
        rm -f "$PIDFILE"
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