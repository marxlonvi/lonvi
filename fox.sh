#!/data/data/com.termux/files/usr/bin/bash

VERSION="1.0.0"
GITHUB="https://raw.githubusercontent.com/marlonvi/lonvi/main"

CONFIG="$HOME/.vidar.conf"

check_update() {
    remote=$(curl -fsSL "$GITHUB/version.txt" 2>/dev/null)

    if [ -n "$remote" ] && [ "$remote" != "$VERSION" ]; then
        echo "Update tersedia ($remote)"
        curl -fsSL "$GITHUB/vidar.sh" -o "$0"
        chmod +x "$0"
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

while true
do
clear
echo "========== VIDAR =========="
echo "1. Masukkan Private Server"
echo "2. Buka Roblox"
echo "0. Keluar"

read -p "Pilih: " menu

case "$menu" in
1)
read -p "Link PS: " PSLINK
save_config
echo "Tersimpan."
sleep 1
;;

2)
termux-open-url "$PSLINK"
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
