#!/data/data/com.termux/files/usr/bin/bash

VERSION="1.0.1"
GITHUB="https://raw.githubusercontent.com/marxlonvi/lonvi/main"

CONFIG="$HOME/.dara"
PACKAGE="com.roblox.client"

check_update() {
    remote=$(curl -fsSL "$GITHUB/version.txt" 2>/dev/null)

    if [ -n "$remote" ] && [ "$remote" != "$VERSION" ]; then
        echo "[INFO] Update tersedia ($remote)"
        curl -fsSL "$GITHUB/dara.sh" -o "$0"
        chmod +x "$0"
        echo "[INFO] Restart..."
        exec "$0"
    fi
}

check_update

[ -f "$CONFIG" ] && source "$CONFIG"

save_config() {
cat > "$CONFIG" <<EOF
PSLINK="$PSLINK"
EOF
}

monitor() {
    while true; do
        clear
        echo "========== DARA =========="
        echo

        if pidof "$PACKAGE" >/dev/null; then
            echo "Status : RUNNING"
        else
            echo "Status : CRASH/DC"
            echo "Rejoin dalam 5 detik..."

            sleep 5

            if [ -n "$PSLINK" ]; then
                termux-open-url "$PSLINK"
            fi
        fi

        sleep 3
    done
}

while true; do
    clear
    echo "========== DARA =========="
    echo "1. Masukkan Private Server"
    echo "2. Buka Roblox"
    echo "3. Start Monitor"
    echo "0. Keluar"
    echo

    read -p "Pilih: " menu

    case "$menu" in
        1)
            read -p "Link PS: " PSLINK
            save_config
            echo "Private Server berhasil disimpan."
            sleep 1
            ;;

        2)
            if [ -n "$PSLINK" ]; then
                termux-open-url "$PSLINK"
            else
                echo "Masukkan Link Private Server terlebih dahulu."
                sleep 2
            fi
            ;;

        3)
            monitor
            ;;

        0)
            exit
            ;;

        *)
            echo "Menu tidak tersedia."
            sleep 1
            ;;
    esac
done
