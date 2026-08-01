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
GRID_MODE="off"   # off | 2x3 | 3x3 | 4x4

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
GRID_MODE="$GRID_MODE"
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
    echo "===== DAFTAR ROBLOX (ANTRIAN LAUNCHER ROBLOX) ====="
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

    if [ -n "$PSLINK" ]; then
        # Arahkan link PS langsung ke package clone ini (-p), supaya Android
        # tidak menampilkan dialog "buka dengan aplikasi apa" dan langsung
        # masuk ke clone Roblox yang bersangkutan.
        am start -a android.intent.action.VIEW -d "$PSLINK" -p "$pkg" >/dev/null 2>&1 \
            && return
    fi

    # Fallback: kalau tidak ada PS link atau intent di atas gagal,
    # buka app-nya biasa lewat launcher.
    am start -n "$(cmd package resolve-activity --brief "$pkg" 2>/dev/null | tail -n 1)" >/dev/null 2>&1 \
        || monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
}

close_all_roblox() {
    if [ ! -s "$QUEUEFILE" ]; then
        echo "Antrian Roblox masih kosong."
        sleep 2
        return
    fi

    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "Auto-Launcher Roblox sedang aktif, dimatikan dulu supaya tidak langsung buka ulang..."
        stop_launcher
    fi

    while IFS='|' read -r pkg delay; do
        [ -z "$pkg" ] && continue
        am force-stop "$pkg" >/dev/null 2>&1
    done < "$QUEUEFILE"

    echo "Semua Roblox di antrian sudah ditutup."
    sleep 2
}

# ===== Grid Layout (freeform window, root) =====
# Menyusun tiap window Roblox clone otomatis ke grid rapi (2x3 / 3x3 / 4x4)
# di posisi landscape, pakai freeform window resize (am task resize).
# CATATAN: butuh root, dan di banyak device Android 10 juga butuh Developer
# Options > "Force activities to be resizable" / freeform windows aktif.
# Beberapa vendor (Samsung/Xiaomi/dll) membatasi ini walau sudah root.

grid_dimensions() {
    case "$1" in
        off) echo "" ;;
        *[0-9]x[0-9]*)
            echo "${1%x*} ${1#*x}"
            ;;
        *) echo "" ;;
    esac
}

apply_grid_layout() {
    [ "$GRID_MODE" = "off" ] && return
    [ ! -s "$QUEUEFILE" ] && return

    read -r rows cols < <(grid_dimensions "$GRID_MODE")
    [ -z "$rows" ] && return

    # aktifkan dukungan freeform window
    su -c "settings put global enable_freeform_support 1" >/dev/null 2>&1

    # ambil resolusi layar, paksa hitung dalam orientasi landscape (lebar > tinggi)
    res=$(wm size 2>/dev/null | grep -oE '[0-9]+x[0-9]+' | tail -1)
    w="${res%x*}"
    h="${res#*x}"
    if [ -z "$w" ] || [ -z "$h" ]; then
        return
    fi
    if [ "$h" -gt "$w" ]; then
        tmp="$w"; w="$h"; h="$tmp"
    fi

    cell_w=$(( w / cols ))
    cell_h=$(( h / rows ))

    i=0
    while IFS='|' read -r pkg delay; do
        [ -z "$pkg" ] && continue

        row=$(( i / cols ))
        col=$(( i % cols ))

        # kalau jumlah Roblox melebihi kapasitas grid, sisanya ditumpuk
        # di slot paling akhir supaya tidak error
        if [ "$row" -ge "$rows" ]; then
            row=$(( rows - 1 ))
            col=$(( cols - 1 ))
        fi

        left=$(( col * cell_w ))
        top=$(( row * cell_h ))
        right=$(( left + cell_w ))
        bottom=$(( top + cell_h ))

        taskid=$(dumpsys activity activities 2>/dev/null | grep -m1 "$pkg" | grep -oE '#[0-9]+' | head -1 | tr -d '#')
        if [ -n "$taskid" ]; then
            su -c "am task resize $taskid $left $top $right $bottom" >/dev/null 2>&1
        fi

        i=$((i+1))
    done < "$QUEUEFILE"
}

choose_grid_layout() {
    clear
    echo "===== ATUR GRID LAYOUT ====="
    echo "Format: <baris>x<kolom>, contoh:"
    echo "  2x3  -> 2 baris, 3 kolom"
    echo "  2x5  -> 2 baris, 5 kolom"
    echo "  4x4  -> 4 baris, 4 kolom"
    echo "Ketik 'off' untuk mematikan."
    echo
    echo "Grid saat ini: $GRID_MODE"
    echo
    read -p "Grid baru: " g
    g="$(echo "$g" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"

    if [ "$g" = "off" ]; then
        GRID_MODE="off"
    elif [[ "$g" =~ ^[0-9]+x[0-9]+$ ]]; then
        GRID_MODE="$g"
    else
        echo "Format tidak valid. Contoh yang benar: 2x3, 2x5, 4x4, atau 'off'."
        sleep 2
        return
    fi

    save_config
    echo "Grid layout disetel ke: $GRID_MODE"

    if [ "$GRID_MODE" != "off" ]; then
        echo "Menerapkan ke window yang sedang terbuka..."
        apply_grid_layout
    fi

    sleep 2
}

# Jalankan urutan lengkap: delay 3 detik tetap, lalu buka PS link di
# tiap Roblox clone secara langsung (targeted intent per package) dengan
# delay sesuai input masing-masing.
launch_sequence() {
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

    # setelah semua clone kebuka, rapikan ke grid kalau fiturnya aktif
    apply_grid_layout
}

# Background auto-launcher roblox loop: does NOT touch the terminal (no clear/echo
# to stdout), so it no longer fights with the interactive menu for screen
# control. It checks every few seconds whether each Roblox app in the
# antrian is still running; if any has closed/crashed, it replays the
# whole open sequence (PS link -> delay 3s -> roblox1 -> delay input ->
# roblox2 -> delay input -> dst) to bring everything back up.
launcher_loop() {
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
                    --id dara_launcher \
                    --title "DARA Auto-Launcher" \
                    --content "Ada Roblox yang tertutup, menjalankan ulang antrian..."
            fi

            launch_sequence
        fi

        sleep 5
    done
}

start_launcher() {
    if [ ! -s "$QUEUEFILE" ]; then
        echo "Antrian Roblox masih kosong. Tambahkan lewat menu 2."
        sleep 2
        return
    fi

    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "Auto-Launcher Roblox sudah berjalan."
        sleep 2
        return
    fi

    nohup bash -c "
        QUEUEFILE='$QUEUEFILE'; PSLINK='$PSLINK'; GRID_MODE='$GRID_MODE'
        $(declare -f launch_package)
        $(declare -f grid_dimensions)
        $(declare -f apply_grid_layout)
        $(declare -f launch_sequence)
        $(declare -f launcher_loop)
        launcher_loop
    " >/dev/null 2>&1 &
    echo $! > "$PIDFILE"

    echo "Auto-Launcher Roblox dimulai di background."
    sleep 2
}

stop_launcher() {
    if [ -f "$PIDFILE" ]; then
        kill "$(cat "$PIDFILE")" 2>/dev/null
        rm -f "$PIDFILE"
        if command -v termux-notification-remove >/dev/null 2>&1; then
            termux-notification-remove dara_launcher
        fi
        echo "Auto-Launcher Roblox dihentikan."
    else
        echo "Auto-Launcher Roblox tidak berjalan."
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
echo -e "${Y}╔══════════════════════════╗${W}"
echo -e "${Y}║${C}       DARA v$VERSION        ${Y}║${W}"
echo -e "${Y}╠══════════════════════════╣${W}"
echo -e "${Y}║${W} 1. Masukkan Link PS      ${Y}║${W}"
echo -e "${Y}║${W} 2. Kelola Antrian Roblox ${Y}║${W}"
echo -e "${Y}║${W} 3. Buka Semua (Sequence) ${Y}║${W}"
echo -e "${Y}║${W} 4. Start Launcher Roblox ${Y}║${W}"
echo -e "${Y}║${W} 5. Stop Launcher Roblox  ${Y}║${W}"
echo -e "${Y}║${W} 6. Close All Roblox      ${Y}║${W}"
echo -e "${Y}║${W} 7. Auto Clear Cache      ${Y}║${W}"
echo -e "${Y}║${W} 8. Atur Grid Layout      ${Y}║${W}"
echo -e "${Y}║${W} 0. Keluar                ${Y}║${W}"
echo -e "${Y}╚══════════════════════════╝${W}"
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
    echo -e "${C}Launcher   :${W} ${G}● AKTIF${W}"
else
    echo -e "${C}Launcher   :${W} ${R}● TIDAK AKTIF${W}"
fi

if [ -f "$CACHE_PIDFILE" ] && kill -0 "$(cat "$CACHE_PIDFILE")" 2>/dev/null; then
    echo -e "${C}Clear Cache:${W} ${G}● AKTIF${W} (tiap 2 jam, root)"
else
    echo -e "${C}Clear Cache:${W} ${R}● TIDAK AKTIF${W}"
fi

echo -e "${C}Grid       :${W} $GRID_MODE"

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
            start_launcher
            ;;

        5)
            stop_launcher
            ;;

        6)
            close_all_roblox
            ;;

        7)
            toggle_cache_clear
            ;;

        8)
            choose_grid_layout
            ;;

        0)
            stop_launcher
            exit
            ;;

        *)
            echo "Menu tidak tersedia."
            sleep 1
            ;;
    esac
done
