#!/data/data/com.termux/files/usr/bin/bash

VERSION="1.0.0"
GITHUB="https://raw.githubusercontent.com/marxlonvi/lonvi/main"

# ===== Auto Update =====
check_update() {
    if ! command -v curl >/dev/null 2>&1; then
        pkg install -y curl >/dev/null 2>&1
    fi

    REMOTE=$(curl -fsSL "$GITHUB/version.txt" 2>/dev/null)

    if [ -n "$REMOTE" ] && [ "$REMOTE" != "$VERSION" ]; then
        clear
        echo "=================================="
        echo "        VIDAR UPDATER"
        echo "=================================="
        echo "Versi Baru : $REMOTE"
        echo "Mengupdate..."

        curl -fsSL "$GITHUB/vidar.sh" -o "$0"
        chmod +x "$0"

        echo "Update berhasil!"
        sleep 2
        exec "$0"
    fi
}

check_update

# ===== Root =====
su -c "true" >/dev/null 2>&1 || {
    echo "Root tidak tersedia!"
    exit 1
}

ROOT() {
    su -c "$*"
}

CONFIG="$HOME/.vidar.conf"
PKG="com.roblox.client"

[ -f "$CONFIG" ] && source "$CONFIG"

save_config() {
cat > "$CONFIG" <<EOF
PSLINK="$PSLINK"
EOF
}

while true
do
clear
echo "=================================="
echo "            V I D A R"
echo "=================================="
echo "1. Masukkan Private Server"
echo "2. Buka Roblox"
echo "3. Force Close Roblox"
echo "4. Clear Cache"
echo "5. Rejoin"
echo "0. Exit"
echo "=================================="

read -p "Pilih : " menu

case "$menu" in

1)
read -p "Link Private Server : " PSLINK
save_config
echo "Berhasil disimpan."
sleep 1
;;

2)
ROOT "am start -a android.intent.action.VIEW -d '$PSLINK'"
;;

3)
ROOT "am force-stop $PKG"
echo "Selesai."
sleep 1
;;

4)
ROOT "pm clear $PKG"
echo "Cache dibersihkan."
sleep 2
;;

5)
ROOT "
am force-stop $PKG
sleep 2
pm clear $PKG
sleep 2
am start -a android.intent.action.VIEW -d '$PSLINK'
"
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
