#!/data/data/com.termux/files/usr/bin/bash

VERSION="1.0.1"
GITHUB="https://raw.githubusercontent.com/marxlonvi/lonvi/refs/heads/main"

CONFIG="$HOME/.dara"
QUEUEFILE="$HOME/.dara_queue"
PIDFILE="$HOME/.dara.pid"
# Warna
R='\033[0;31m'
G='\033[0;32m'
Y='\033[38;5;208m'   # Oranye
C='\033[0;36m'       # Cyan
W='\033[0m'

PSLINK=""
AUTO_CLEAR_CACHE="yes"

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
AUTO_CLEAR_CACHE="$AUTO_CLEAR_CACHE"
EOF
}

[ -f "$CONFIG" ] && source "$CONFIG"
[ -f "$QUEUEFILE" ] || touch "$QUEUEFILE"

# ===== Antrian Roblox (multi-app + delay per app) =====
# Setiap baris di QUEUEFILE formatnya: package|delay_detik

queue_count() {
    wc -l < "$QUEUEFILE" | tr -d ' '
}

view_queue() {
    clear
    echo "===== DAFTAR ROBLOX (ANTRIAN REJOIN) ====="
    if [ ! -s "$QUEUEFILE" ]; then
        echo "(kosong)"
    else
        i=0
        while IFS='|' read -r pkg delay; do
            i=$((i+1))
            echo "$i. $pkg  (delay: ${delay}s)"
        done < "$QUEUEFILE"
    fi
    echo
}

add_to_queue() {
    mapfile -t APPS < <(pm list packages | sed 's/package://' | grep -i roblox)

    if [ ${#APPS[@]} -eq 0 ]; then
        echo "Roblox tidak ditemukan."
        read -p "Enter..."
        return
    fi

    clear
    echo "===== TAMBAH ROBLOX KE ANTRIAN ====="
    for i in "${!APPS[@]}"; do
        echo "$((i+1)). ${APPS[$i]}"
    done
    echo
    read -p "Pilih nomor: " pilih

    if [[ "$pilih" =~ ^[0-9]+$ ]] && [ "$pilih" -ge 1 ] && [ "$pilih" -le "${#APPS[@]}" ]; then
        pkg="${APPS[$((pilih-1))]}"

        delay=""
        while [[ ! "$delay" =~ ^[0-9]+$ ]]; do
            read -p "Delay setelah buka '$pkg' (detik): " delay
        done

        echo "${pkg}|${delay}" >> "$QUEUEFILE"
        echo
        echo "Ditambahkan: $pkg (delay ${delay}s)"
    else
        echo "Pilihan tidak valid."
    fi

    read -p "Enter..."
}

remove_from_queue() {
    view_queue

    if [ ! -s "$QUEUEFILE" ]; then
        read -p "Enter..."
        return
    fi

    read -p "Hapus nomor berapa? (0 batal): " pilih
    total=$(queue_count)

    if [[ "$pilih" =~ ^[0-9]+$ ]] && [ "$pilih" -ge 1 ] && [ "$pilih" -le "$total" ]; then
        sed -i "${pilih}d" "$QUEUEFILE"
        echo "Dihapus."
    else
        echo "Dibatalkan / tidak valid."
    fi

    read -p "Enter..."
}

manage_queue() {
    while true; do
        clear
        echo -e "${Y}╔════════════════════════════╗${W}"
        echo -e "${Y}║${C}   KELOLA ANTRIAN ROBLOX    ${Y}║${W}"
        echo -e "${Y}╠════════════════════════════╣${W}"
        echo -e "${Y}║${W} 1. Lihat Antrian           ${Y}║${W}"
        echo -e "${Y}║${W} 2. Tambah Roblox           ${Y}║${W}"
        echo -e "${Y}║${W} 3. Hapus Roblox            ${Y}║${W}"
        echo -e "${Y}║${W} 0. Kembali                 ${Y}║${W}"
        echo -e "${Y}╚════════════════════════════╝${W}"
        echo
        read -p "Pilih: " sub

        case "$sub" in
            1) view_queue; read -p "Enter..." ;;
            2) add_to_queue ;;
            3) remove_from_queue ;;
            0) return ;;
            *) echo "Menu tidak tersedia."; sleep 1 ;;
        esac
    done
}

launch_package() {
    local pkg="$1"
    am start -n "$(cmd package resolve-activity --brief "$pkg" 2>/dev/null | tail -n 1)" >/dev/null 2>&1 \
        || monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
}

# Jalankan urutan lengkap: buka PS link, delay 3 detik tetap,
# lalu buka tiap Roblox di antrian dengan delay sesuai input masing-masing.
launch_sequence() {
    if [ -n "$PSLINK" ]; then
        termux-open-url "$PSLINK"
    fi
    sleep 3

    if [ ! -s "$QUEUEFILE" ]; then
        echo "Antrian Roblox masih kosong. Tambahkan lewat menu 2."
        return
    fi

    while IFS='|' read -r pkg delay; do
        [ -z "$pkg" ] && continue
        launch_package "$pkg"
        sleep "$delay"
    done < "$QUEUEFILE"
}

# Background auto-rejoin loop: does NOT touch the terminal (no clear/echo
# to stdout), so it no longer fights with the interactive menu for screen
# control. It checks every few seconds whether each Roblox app in the
# antrian is still running; if any has closed/crashed, it replays the
# whole open sequence (PS link -> delay 3s -> roblox1 -> delay input ->
# roblox2 -> delay input -> dst) to bring everything back up.
rejoin_loop() {
    while true; do
        need_relaunch=0

        if [ -s "$QUEUEFILE" ]; then
            while IFS='|' read -r pkg delay; do
                [ -z "$pkg" ] && continue
                if ! pidof "$pkg" >/dev/null 2>&1; then
                    need_relaunch=1
                    break
                fi
            done < "$QUEUEFILE"
        fi

        if [ "$need_relaunch" -eq 1 ]; then
            if command -v termux-notification >/dev/null 2>&1; then
                termux-notification \
                    --id dara_rejoin \
                    --title "DARA Auto-Rejoin" \
                    --content "Ada Roblox yang tertutup, menjalankan ulang antrian..."
            fi

            launch_sequence
        fi

        sleep 5
    done
}

start_rejoin() {
    if [ ! -s "$QUEUEFILE" ]; then
        echo "Antrian Roblox masih kosong. Tambahkan lewat menu 2."
        sleep 2
        return
    fi

    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "Auto-rejoin sudah berjalan."
        sleep 2
        return
    fi

    nohup bash -c "
        QUEUEFILE='$QUEUEFILE'; PSLINK='$PSLINK'
        $(declare -f launch_package)
        $(declare -f launch_sequence)
        $(declare -f rejoin_loop)
        rejoin_loop
    " >/dev/null 2>&1 &
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

# ===== Auto Clear Cache (root) =====
# Loop pertama sengaja cuma delay 5 detik supaya semua Roblox di antrian
# langsung dibersihkan cache-nya begitu fitur ini dinyalakan. Setelah
# putaran pertama itu, jeda berikutnya baru mengikuti interval normal
# (2 jam / 7200 detik) dan seterusnya. Perlu akses root (su) karena Android
# tidak menyediakan cara non-root untuk menghapus cache per-app saja
# (tanpa ikut menghapus data login).
CACHE_PIDFILE="$HOME/.dara_cache.pid"
CACHE_INTERVAL=7200   # 2 jam

clear_cache_all() {
    if [ ! -s "$QUEUEFILE" ]; then
        return
    fi

    while IFS='|' read -r pkg delay; do
        [ -z "$pkg" ] && continue
        su -c "rm -rf /data/data/$pkg/cache/*" >/dev/null 2>&1
    done < "$QUEUEFILE"

    if command -v termux-notification >/dev/null 2>&1; then
        termux-notification \
            --id dara_cache \
            --title "DARA Auto Clear Cache" \
            --content "Cache semua Roblox di antrian sudah dibersihkan."
    fi
}

clear_cache_loop() {
    sleep 5
    clear_cache_all

    while true; do
        sleep "$CACHE_INTERVAL"
        clear_cache_all
    done
}

cache_clear_running() {
    [ -f "$CACHE_PIDFILE" ] && kill -0 "$(cat "$CACHE_PIDFILE")" 2>/dev/null
}

enable_cache_clear() {
    if cache_clear_running; then
        return
    fi

    nohup bash -c "
        QUEUEFILE='$QUEUEFILE'; CACHE_INTERVAL=$CACHE_INTERVAL
        $(declare -f clear_cache_all)
        $(declare -f clear_cache_loop)
        clear_cache_loop
    " >/dev/null 2>&1 &
    echo $! > "$CACHE_PIDFILE"
}

disable_cache_clear() {
    if [ -f "$CACHE_PIDFILE" ]; then
        kill "$(cat "$CACHE_PIDFILE")" 2>/dev/null
        rm -f "$CACHE_PIDFILE"
    fi
    if command -v termux-notification-remove >/dev/null 2>&1; then
        termux-notification-remove dara_cache
    fi
}

# Ditampilkan lewat menu 6: tanya Y/N (default Y), lalu simpan pilihannya
# ke config. Sekali dinyalakan, loop jalan terus di background tanpa perlu
# di-stop manual — kalau mau matikan, tinggal masuk menu 6 lagi dan jawab N.
toggle_cache_clear() {
    if [ ! -s "$QUEUEFILE" ]; then
        echo "Antrian Roblox masih kosong. Tambahkan lewat menu 2 dulu."
        sleep 2
        return
    fi

    read -p "Aktifkan Auto Clear Cache tiap 2 jam? (Y/n): " ans
    ans="${ans:-Y}"

    case "$ans" in
        [Yy]*)
            AUTO_CLEAR_CACHE="yes"
            save_config
            enable_cache_clear
            echo "Auto Clear Cache diaktifkan (pembersihan pertama dalam 5 detik, lalu tiap 2 jam)."
            ;;
        [Nn]*)
            AUTO_CLEAR_CACHE="no"
            save_config
            disable_cache_clear
            echo "Auto Clear Cache dimatikan."
            ;;
        *)
            echo "Input tidak dikenali, tidak ada perubahan."
            ;;
    esac

    sleep 2
}

check_update

# Kalau sebelumnya sudah diaktifkan (tersimpan di config), lanjutkan lagi
# otomatis tanpa perlu masuk menu 6 ulang.
if [ "$AUTO_CLEAR_CACHE" = "yes" ] && [ -s "$QUEUEFILE" ] && ! cache_clear_running; then
    enable_cache_clear
fi

while true; do
    clear
echo -e "${Y}╔════════════════════════════╗${W}"
echo -e "${Y}║${C}         DARA v$VERSION        ${Y}║${W}"
echo -e "${Y}╠════════════════════════════╣${W}"
echo -e "${Y}║${W} 1. Masukkan Link PS        ${Y}║${W}"
echo -e "${Y}║${W} 2. Kelola Antrian Roblox   ${Y}║${W}"
echo -e "${Y}║${W} 3. Buka Semua (Sequence)   ${Y}║${W}"
echo -e "${Y}║${W} 4. Start Rejoin            ${Y}║${W}"
echo -e "${Y}║${W} 5. Stop Rejoin             ${Y}║${W}"
echo -e "${Y}║${W} 6. Auto Clear Cache        ${Y}║${W}"
echo -e "${Y}║${W} 0. Keluar                  ${Y}║${W}"
echo -e "${Y}╚════════════════════════════╝${W}"
echo

echo -e "${C}Link PS   :${W} ${PSLINK:-Belum diatur}"
echo -e "${C}Antrian   :${W} $(queue_count) Roblox terdaftar"

if [ -s "$QUEUEFILE" ]; then
    while IFS='|' read -r pkg delay; do
        [ -z "$pkg" ] && continue
        if pidof "$pkg" >/dev/null 2>&1; then
            echo -e "   ${G}●${W} $pkg (delay ${delay}s)"
        else
            echo -e "   ${R}●${W} $pkg (delay ${delay}s)"
        fi
    done < "$QUEUEFILE"
fi

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo -e "${C}Rejoin    :${W} ${G}● AKTIF${W}"
else
    echo -e "${C}Rejoin    :${W} ${R}● TIDAK AKTIF${W}"
fi

if [ -f "$CACHE_PIDFILE" ] && kill -0 "$(cat "$CACHE_PIDFILE")" 2>/dev/null; then
    echo -e "${C}Clear Cache:${W} ${G}● AKTIF${W} (tiap 2 jam, root)"
else
    echo -e "${C}Clear Cache:${W} ${R}● TIDAK AKTIF${W}"
fi

echo

    read -p "Pilih: " menu

    case "$menu" in
        1)
            read -p "Link PS: " PSLINK
            save_config
            ;;

        2)
            manage_queue
            ;;

        3)
            launch_sequence
            read -p "Enter..."
            ;;

        4)
            start_rejoin
            ;;

        5)
            stop_rejoin
            ;;

        6)
            toggle_cache_clear
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
