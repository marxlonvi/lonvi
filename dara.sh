#!/data/data/com.termux/files/usr/bin/bash

# Pastikan semua binary Termux (bash, timeout, nohup, dll) tetap ketemu
# walaupun script ini dijalankan dari shell root (su), yang PATH-nya
# biasanya di-reset ke /system/bin dkk dan tidak include folder Termux.
export PATH="/data/data/com.termux/files/usr/bin:$PATH"

VERSION="1.0.9"
GITHUB="https://raw.githubusercontent.com/marxlonvi/lonvi/refs/heads/main"

CONFIG="$HOME/.dara"
QUEUEFILE="$HOME/.dara_queue"
PIDFILE="$HOME/.dara.pid"

# Warna
R='\033[0;31m'
G='\033[0;32m'
Y='\033[38;5;208m'
C='\033[0;36m'
W='\033[0m'

PSLINK=""
AUTO_CLEAR_CACHE="yes"
AUTO_RAM_BOOST="no"
RAM_BOOST_INTERVAL="60"

RAMPIDFILE="$HOME/.dara_ramboost.pid"

# Paket yang TIDAK BOLEH di-kill (aman): sistem, launcher, termux, dan
# apapun yang ada di antrian Roblox (biar tidak ikut tertutup oleh RAM booster)
RAM_BOOST_WHITELIST_PATTERN="^(com\.android\.|com\.google\.android\.(gms|gsf|inputmethod|packageinstaller)|com\.termux|android$|system$)"

# ===== ROOT CHECK (cached, satu kali, dengan timeout) =====
# Dulu setiap fitur yang butuh root (close all, cache clear, ram boost)
# manggil `su -c ...` berkali-kali di dalam loop tanpa timeout. Kalau
# popup izin root tidak langsung di-tap, Termux ke-block nunggu su selesai
# -> keliatan "freeze", tidak bisa input, dan output numpuk pas akhirnya
# lepas (menu jadi berantakan). Sekarang root dicek SEKALI di awal,
# hasilnya di-cache, dan tiap su selalu dibungkus timeout.
#
# ALREADY_ROOT=1 kalau script ini SENDIRI sudah dijalankan sebagai root
# (misal lewat `su -c "bash dara.sh"`). Dalam kondisi ini kita TIDAK
# manggil `su` lagi (nested su dari proses yang sudah UID 0 bisa hang di
# sebagian ROM/Magisk karena tidak ada TTY buat prompt ulang) -- command
# privileged langsung dieksekusi saja karena kita memang sudah root.
ROOT_OK=0
ALREADY_ROOT=0
check_root() {
    if [ "$(id -u 2>/dev/null)" = "0" ]; then
        ALREADY_ROOT=1
        ROOT_OK=1
        return
    fi

    if command -v su >/dev/null 2>&1; then
        if timeout 15 su -c 'echo ok' >/dev/null 2>&1; then
            ROOT_OK=1
        else
            ROOT_OK=0
        fi
    else
        ROOT_OK=0
    fi
}
check_root

# Jalankan command privileged: langsung eval kalau proses sudah root,
# atau lewat `su -c` (dengan timeout) kalau perlu elevate dulu.
run_privileged() {
    local cmd="$1"
    local tmo="${2:-8}"
    if [ "$ALREADY_ROOT" -eq 1 ]; then
        eval "$cmd" >/dev/null 2>&1
    elif [ "$ROOT_OK" -eq 1 ]; then
        timeout "$tmo" su -c "$cmd" >/dev/null 2>&1
    fi
}

# Status cache (update tiap poll cycle, bukan setiap display)
LAUNCHER_ACTIVE=0
CACHE_ACTIVE=0
RAMBOOST_ACTIVE=0
QUEUE_COUNT=0
declare -a QUEUE_PKGS=()

# Background update check (non-blocking, silent)
(curl -fsSL "$GITHUB/version.txt" 2>/dev/null | {
    read remote
    if [ -n "$remote" ] && [ "$remote" != "$VERSION" ]; then
        tmpfile=$(mktemp)
        curl -fsSL "$GITHUB/dara.sh" -o "$tmpfile" 2>/dev/null && \
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
AUTO_RAM_BOOST="$AUTO_RAM_BOOST"
RAM_BOOST_INTERVAL="$RAM_BOOST_INTERVAL"
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

update_status_cache() {
    # Cek launcher dan cache dalam satu operasi, bukan multiple test
    LAUNCHER_ACTIVE=0
    CACHE_ACTIVE=0
    
    if [ -f "$PIDFILE" ] 2>/dev/null && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
        LAUNCHER_ACTIVE=1
    fi
    
    if [ -f "$HOME/.dara_cache.pid" ] 2>/dev/null && kill -0 "$(cat "$HOME/.dara_cache.pid" 2>/dev/null)" 2>/dev/null; then
        CACHE_ACTIVE=1
    fi

    RAMBOOST_ACTIVE=0
    if [ -f "$RAMPIDFILE" ] 2>/dev/null && kill -0 "$(cat "$RAMPIDFILE" 2>/dev/null)" 2>/dev/null; then
        RAMBOOST_ACTIVE=1
    fi
}

[ -f "$CONFIG" ] && source "$CONFIG"
[ -f "$QUEUEFILE" ] || touch "$QUEUEFILE"

# Load initial cache
load_queue_cache
update_status_cache

view_queue() {
    clear
    echo "===== DAFTAR ROBLOX (ANTRIAN LAUNCHER ROBLOX) ====="
    if [ "$QUEUE_COUNT" -eq 0 ]; then
        echo "(kosong)"
    else
        local i=0
        while IFS='|' read -r pkg delay; do
            [ -z "$pkg" ] && continue
            ((i++))
            if pidof "$pkg" >/dev/null 2>&1; then
                echo -e "    $i. ${G}●${W} $pkg  (delay: ${delay}s)"
            else
                echo -e "    $i. ${R}●${W} $pkg  (delay: ${delay}s)"
            fi
        done < "$QUEUEFILE"
    fi
    echo
}

add_to_queue() {
    mapfile -t APPS < <(pm list packages 2>/dev/null | sed 's/package://' | grep -i roblox)
    
    if [ ${#APPS[@]} -eq 0 ]; then
        echo "Roblox tidak ditemukan."
        read -p "Enter..."
        return
    fi

    clear
    echo "===== TAMBAH ROBLOX KE ANTRIAN ====="
    local i=0
    for app in "${APPS[@]}"; do
        echo "$((++i)). $app"
    done
    echo
    read -p "Pilih nomor (bisa lebih dari satu, pisahkan spasi, misal: 1 2 3 4): " pilih_input

    declare -a chosen=()
    for p in $pilih_input; do
        if [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -ge 1 ] && [ "$p" -le "${#APPS[@]}" ]; then
            local dup=0
            for c in "${chosen[@]}"; do
                [ "$c" = "$p" ] && dup=1 && break
            done
            [ "$dup" -eq 0 ] && chosen+=("$p")
        fi
    done

    if [ ${#chosen[@]} -eq 0 ]; then
        echo "Pilihan tidak valid."
        read -p "Enter..."
        return
    fi

    read -p "Pilih delay (default 50): " delay
    delay="${delay:-50}"
    while [[ ! "$delay" =~ ^[0-9]+$ ]]; do
        read -p "Delay harus angka, coba lagi (default 50): " delay
        delay="${delay:-50}"
    done

    echo
    for p in "${chosen[@]}"; do
        local pkg="${APPS[$((p-1))]}"
        echo "${pkg}|${delay}" >> "$QUEUEFILE"
        echo "Ditambahkan: $pkg (delay ${delay}s)"
    done

    load_queue_cache
    read -p "Enter..."
}

remove_from_queue() {
    view_queue
    
    [ "$QUEUE_COUNT" -eq 0 ] && read -p "Enter..." && return
    
    read -p "Hapus nomor berapa? (pisahkan spasi utk banyak, 'all' utk semua, 0 batal): " pilih_input

    if [ "$pilih_input" = "0" ]; then
        echo "Dibatalkan."
        read -p "Enter..."
        return
    fi

    if [[ "$pilih_input" =~ ^([Aa][Ll][Ll])$ ]]; then
        > "$QUEUEFILE"
        load_queue_cache
        echo "Semua antrian dihapus."
        read -p "Enter..."
        return
    fi

    declare -a nums=()
    for p in $pilih_input; do
        if [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -ge 1 ] && [ "$p" -le "$QUEUE_COUNT" ]; then
            local dup=0
            for c in "${nums[@]}"; do
                [ "$c" = "$p" ] && dup=1 && break
            done
            [ "$dup" -eq 0 ] && nums+=("$p")
        fi
    done

    if [ ${#nums[@]} -eq 0 ]; then
        echo "Tidak ada nomor valid / dibatalkan."
        read -p "Enter..."
        return
    fi

    # Urutkan descending supaya nomor baris tidak bergeser saat dihapus satu-satu
    IFS=$'\n' nums=($(sort -rn <<<"${nums[*]}")); unset IFS

    for n in "${nums[@]}"; do
        sed -i "${n}d" "$QUEUEFILE"
    done

    load_queue_cache
    echo "Dihapus ${#nums[@]} entri dari antrian."
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
            *) ;;
        esac
    done
}

launch_package() {
    local pkg="$1"
    
    if [ -n "$PSLINK" ]; then
        am start -a android.intent.action.VIEW -d "$PSLINK" -p "$pkg" >/dev/null 2>&1 && return
    fi
    
    am start -n "$(cmd package resolve-activity --brief "$pkg" 2>/dev/null | tail -n 1)" >/dev/null 2>&1 \
        || monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
}

launch_sequence() {
    sleep 3
    
    [ ! -s "$QUEUEFILE" ] && echo "Antrian Roblox masih kosong." && return
    
    while IFS='|' read -r pkg delay; do
        [ -z "$pkg" ] && continue
        launch_package "$pkg"
        sleep "$delay"
    done < "$QUEUEFILE"
}

# Launcher loop yang lebih hemat: single pidof call untuk semua package
launcher_loop() {
    while true; do
        if [ ! -s "$QUEUEFILE" ]; then
            sleep 30
            continue
        fi

        # Single pidof untuk semua package, bandingkan jumlah proses
        local pkgs=($(cut -d'|' -f1 "$QUEUEFILE" 2>/dev/null | grep -v '^$'))
        local total=${#pkgs[@]}
        
        if [ "$total" -gt 0 ]; then
            local running=$(pidof "${pkgs[@]}" 2>/dev/null | wc -w)
            if [ "$running" -lt "$total" ]; then
                if command -v termux-notification >/dev/null 2>&1; then
                    termux-notification --id dara_launcher --title "DARA Auto-Launcher" \
                        --content "Ada Roblox yang tertutup, menjalankan ulang antrian..." 2>/dev/null
                fi
                launch_sequence
            fi
        fi
        
        sleep 20
    done
}

close_all_roblox() {
    clear
    mapfile -t ALL_ROBLOX < <(pm list packages 2>/dev/null | sed 's/package://' | grep -i roblox)

    if [ ${#ALL_ROBLOX[@]} -eq 0 ]; then
        echo "Tidak ada Roblox terpasang di device."
        sleep 2
        return
    fi

    # Matikan launcher dulu supaya tidak auto-relaunch pas kita force-stop
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
        kill "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
        rm -f "$PIDFILE"
    fi

    # Kalau root belum kedeteksi (misal popup izin belum ke-tap saat startup),
    # coba cek ulang sekarang sebelum eksekusi. am force-stop ke package LAIN
    # butuh izin sistem dan akan gagal diam-diam tanpa root.
    if [ "$ROOT_OK" -ne 1 ] && [ "$ALREADY_ROOT" -ne 1 ]; then
        check_root
    fi

    echo "Menutup paksa ${#ALL_ROBLOX[@]} Roblox..."
    [ "$ROOT_OK" -ne 1 ] && [ "$ALREADY_ROOT" -ne 1 ] && \
        echo -e "${R}Peringatan: root tidak terdeteksi, force-stop ke app lain kemungkinan tidak akan berfungsi.${W}"

    # Non-root: force-stop biasa per package (cepat, tidak butuh su, tapi
    # biasanya tidak berefek ke package lain tanpa izin sistem/root)
    for pkg in "${ALL_ROBLOX[@]}"; do
        am force-stop "$pkg" >/dev/null 2>&1
    done

    # Root (kalau ada): SATU panggilan privileged untuk semua package
    # sekaligus (bukan loop per-package), dibungkus timeout. pkill/kill
    # dijalankan DI DALAM sesi su supaya bisa lihat & bunuh proses app lain
    # (pidof dari sisi non-root sering gagal baca proses app lain di
    # Android modern karena dibatasi SELinux/hidepid).
    if [ "$ROOT_OK" -eq 1 ]; then
        local su_cmd=""
        for pkg in "${ALL_ROBLOX[@]}"; do
            su_cmd+="am force-stop $pkg; pkill -9 -f $pkg; "
        done
        run_privileged "$su_cmd" 12
    fi
    # Sisa proses yang masih hidup tanpa root, kill langsung (best effort)
    for pkg in "${ALL_ROBLOX[@]}"; do
        pid=$(pidof "$pkg" 2>/dev/null)
        [ -n "$pid" ] && kill -9 $pid >/dev/null 2>&1
    done

    sleep 1

    # Verifikasi hasil
    local masih_aktif=0
    for pkg in "${ALL_ROBLOX[@]}"; do
        if pidof "$pkg" >/dev/null 2>&1; then
            masih_aktif=$((masih_aktif+1))
            echo -e "   ${R}●${W} $pkg masih aktif"
        fi
    done

    if [ "$masih_aktif" -eq 0 ]; then
        echo "Semua Roblox berhasil ditutup paksa."
    else
        echo "$masih_aktif Roblox masih belum mati (mungkin butuh akses root/su untuk paksa penuh)."
    fi

    sleep 2
}

start_launcher() {
    [ ! -s "$QUEUEFILE" ] && echo "Antrian Roblox masih kosong." && sleep 2 && return
    
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
        echo "Auto-Launcher Roblox sudah berjalan."
        sleep 2
        return
    fi

    nohup bash -c "
        QUEUEFILE='$QUEUEFILE'; PSLINK='$PSLINK'
        $(declare -f launch_package)
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
        kill "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
        rm -f "$PIDFILE"
        if command -v termux-notification-remove >/dev/null 2>&1; then
            termux-notification-remove dara_launcher 2>/dev/null
        fi
        echo "Auto-Launcher Roblox dihentikan."
    else
        echo "Auto-Launcher Roblox tidak berjalan."
    fi
    sleep 2
}

# Buka satu Roblox pilihan (dari SEMUA package Roblox yang terpasang, bukan
# cuma yang ada di antrian). Kalau app-nya masih tertutup -> langsung buka +
# masuk PS link. Kalau app-nya sudah aktif/terbuka -> force-close dulu baru
# buka ulang + masuk PS link (fresh join).
open_selected_roblox() {
    mapfile -t APPS < <(pm list packages 2>/dev/null | sed 's/package://' | grep -i roblox)

    if [ ${#APPS[@]} -eq 0 ]; then
        echo "Roblox tidak ditemukan."
        read -p "Enter..."
        return
    fi

    clear
    echo "===== BUKA ROBLOX ====="
    local i=0
    for app in "${APPS[@]}"; do
        ((i++))
        if pidof "$app" >/dev/null 2>&1; then
            echo -e "$i. ${G}●${W} $app"
        else
            echo -e "$i. ${R}●${W} $app"
        fi
    done
    echo
    read -p "Pilih Roblox: " pilih

    if [[ ! "$pilih" =~ ^[0-9]+$ ]] || [ "$pilih" -lt 1 ] || [ "$pilih" -gt "${#APPS[@]}" ]; then
        echo "Pilihan tidak valid."
        read -p "Enter..."
        return
    fi

    local pkg="${APPS[$((pilih-1))]}"

    if pidof "$pkg" >/dev/null 2>&1; then
        echo "$pkg sedang aktif, menutup dulu lalu membuka ulang..."
        am force-stop "$pkg" >/dev/null 2>&1
        sleep 1
    else
        echo "$pkg masih tertutup, membuka..."
    fi

    launch_package "$pkg"
    echo "Selesai: $pkg dibuka."
    read -p "Enter..."
}

# Cache clear dengan lazy initialization dan exponential backoff
clear_cache_all() {
    [ ! -s "$QUEUEFILE" ] && return
    [ "$ROOT_OK" -ne 1 ] && return

    local su_cmd=""
    while IFS='|' read -r pkg _; do
        [ -z "$pkg" ] && continue
        su_cmd+="rm -rf /data/data/$pkg/cache/* 2>/dev/null; "
    done < "$QUEUEFILE"

    [ -n "$su_cmd" ] && run_privileged "$su_cmd" 15

    if command -v termux-notification >/dev/null 2>&1; then
        termux-notification --id dara_cache --title "DARA Auto Clear Cache" \
            --content "Cache semua Roblox di antrian sudah dibersihkan." 2>/dev/null
    fi
}

clear_cache_loop() {
    sleep 1200  # 20 menit first run
    clear_cache_all
    
    while true; do
        sleep 7200  # 2 jam subsequent runs
        clear_cache_all
    done
}

cache_clear_running() {
    [ -f "$HOME/.dara_cache.pid" ] && kill -0 "$(cat "$HOME/.dara_cache.pid" 2>/dev/null)" 2>/dev/null
}

enable_cache_clear() {
    cache_clear_running && return
    
    nohup bash -c "
        QUEUEFILE='$QUEUEFILE'
        ROOT_OK='$ROOT_OK'
        ALREADY_ROOT='$ALREADY_ROOT'
        $(declare -f run_privileged)
        $(declare -f clear_cache_all)
        $(declare -f clear_cache_loop)
        clear_cache_loop
    " >/dev/null 2>&1 &
    echo $! > "$HOME/.dara_cache.pid"
}

disable_cache_clear() {
    if [ -f "$HOME/.dara_cache.pid" ]; then
        kill "$(cat "$HOME/.dara_cache.pid" 2>/dev/null)" 2>/dev/null
        rm -f "$HOME/.dara_cache.pid"
    fi
    if command -v termux-notification-remove >/dev/null 2>&1; then
        termux-notification-remove dara_cache 2>/dev/null
    fi
}

# ===== RAM BOOSTER =====
# Kill aplikasi pihak ketiga yang berjalan di latar belakang dan aman
# untuk dimatikan (bukan sistem, bukan Termux, bukan Roblox yang lagi
# di-launch/di-antrian). Tujuannya membebaskan RAM tanpa mengganggu
# proses penting.
ram_boost_once() {
    # Kumpulkan package yang harus dilindungi (whitelist dinamis: isi antrian)
    declare -A PROTECT=()
    if [ -s "$QUEUEFILE" ]; then
        while IFS='|' read -r pkg _; do
            [ -z "$pkg" ] && continue
            PROTECT["$pkg"]=1
        done < "$QUEUEFILE"
    fi

    # Ambil semua package pihak ketiga (bukan sistem) yang PROSESNYA aktif
    local killed=0
    local pkg
    local su_cmd=""
    while read -r pkg; do
        [ -z "$pkg" ] && continue

        # Lewati kalau masuk whitelist statis (sistem/termux/dara sendiri)
        [[ "$pkg" =~ $RAM_BOOST_WHITELIST_PATTERN ]] && continue

        # Lewati kalau ada di antrian Roblox (biar tidak mati saat lagi dipakai)
        [ -n "${PROTECT[$pkg]}" ] && continue

        # Cuma proses yang benar-benar jalan di background
        if pidof "$pkg" >/dev/null 2>&1; then
            am force-stop "$pkg" >/dev/null 2>&1
            [ "$ROOT_OK" -eq 1 ] && su_cmd+="am force-stop $pkg; "
            killed=$((killed+1))
        fi
    done < <(pm list packages -3 2>/dev/null | sed 's/package://')

    # Satu panggilan su untuk semua package, dibungkus timeout (bukan
    # loop per-package) supaya tidak pernah menggantung nunggu popup izin.
    if [ "$ROOT_OK" -eq 1 ] && [ -n "$su_cmd" ]; then
        run_privileged "$su_cmd" 8
    fi

    if [ "$killed" -gt 0 ] && command -v termux-notification >/dev/null 2>&1; then
        termux-notification --id dara_ramboost --title "DARA RAM Booster" \
            --content "$killed aplikasi latar belakang ditutup untuk membebaskan RAM." 2>/dev/null
    fi
}

ram_boost_loop() {
    local interval="$1"
    [[ "$interval" =~ ^[0-9]+$ ]] || interval=60
    [ "$interval" -lt 5 ] && interval=5

    while true; do
        sleep "$interval"
        ram_boost_once
    done
}

ram_boost_running() {
    [ -f "$RAMPIDFILE" ] && kill -0 "$(cat "$RAMPIDFILE" 2>/dev/null)" 2>/dev/null
}

enable_ram_boost() {
    local interval="${1:-$RAM_BOOST_INTERVAL}"
    ram_boost_running && return

    nohup bash -c "
        QUEUEFILE='$QUEUEFILE'
        RAM_BOOST_WHITELIST_PATTERN='$RAM_BOOST_WHITELIST_PATTERN'
        ROOT_OK='$ROOT_OK'
        ALREADY_ROOT='$ALREADY_ROOT'
        $(declare -f run_privileged)
        $(declare -f ram_boost_once)
        $(declare -f ram_boost_loop)
        ram_boost_loop '$interval'
    " >/dev/null 2>&1 &
    echo $! > "$RAMPIDFILE"
}

disable_ram_boost() {
    if [ -f "$RAMPIDFILE" ]; then
        kill "$(cat "$RAMPIDFILE" 2>/dev/null)" 2>/dev/null
        rm -f "$RAMPIDFILE"
    fi
    if command -v termux-notification-remove >/dev/null 2>&1; then
        termux-notification-remove dara_ramboost 2>/dev/null
    fi
}

toggle_ram_boost() {
    read -p "Aktifkan RAM Booster (kill app latar belakang otomatis)? (Y/n): " ans
    ans="${ans:-Y}"

    case "$ans" in
        [Yy]*)
            read -p "Interval kill (detik, default 60, min 5): " iv
            iv="${iv:-60}"
            while [[ ! "$iv" =~ ^[0-9]+$ ]] || [ "$iv" -lt 5 ]; do
                read -p "Interval harus angka >= 5, coba lagi (default 60): " iv
                iv="${iv:-60}"
            done
            RAM_BOOST_INTERVAL="$iv"
            AUTO_RAM_BOOST="yes"
            save_config
            disable_ram_boost
            enable_ram_boost "$iv"
            echo "RAM Booster diaktifkan, kill app background tiap ${iv} detik."
            ;;
        [Nn]*)
            AUTO_RAM_BOOST="no"
            save_config
            disable_ram_boost
            echo "RAM Booster dimatikan."
            ;;
    esac

    sleep 2
}

toggle_cache_clear() {
    [ ! -s "$QUEUEFILE" ] && echo "Antrian Roblox masih kosong." && sleep 2 && return
    
    read -p "Aktifkan Auto Clear Cache tiap 2 jam? (Y/n): " ans
    ans="${ans:-Y}"
    
    case "$ans" in
        [Yy]*)
            AUTO_CLEAR_CACHE="yes"
            save_config
            enable_cache_clear
            echo "Auto Clear Cache diaktifkan (pembersihan pertama dalam 20 menit, lalu tiap 2 jam)."
            ;;
        [Nn]*)
            AUTO_CLEAR_CACHE="no"
            save_config
            disable_cache_clear
            echo "Auto Clear Cache dimatikan."
            ;;
    esac
    
    sleep 2
}

# Auto-enable cache clear kalau setting ada
if [ "$AUTO_CLEAR_CACHE" = "yes" ] && [ -s "$QUEUEFILE" ] && ! cache_clear_running; then
    enable_cache_clear &
fi

# Auto-enable ram booster kalau setting ada
if [ "$AUTO_RAM_BOOST" = "yes" ] && ! ram_boost_running; then
    enable_ram_boost "$RAM_BOOST_INTERVAL" &
fi

# Main loop dengan optimized status display (cached status, bukan multiple tests)
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
    echo -e "${Y}║${W} 7. Buka Roblox (Pilih)   ${Y}║${W}"
    echo -e "${Y}║${W} 8. Auto Clear Cache      ${Y}║${W}"
    echo -e "${Y}║${W} 9. RAM Booster (Kill BG) ${Y}║${W}"
    echo -e "${Y}║${W} 0. Keluar                ${Y}║${W}"
    echo -e "${Y}╚══════════════════════════╝${W}"
    echo

    # Update status cache sebelum display
    update_status_cache
    
    echo -e "${C}Root      :${W} $([ "$ROOT_OK" -eq 1 ] && echo "${G}● TERDETEKSI${W}" || echo "${R}● TIDAK TERDETEKSI${W}")"
    echo -e "${C}Link PS   :${W} ${PSLINK:-Belum diatur}"
    echo -e "${C}Antrian   :${W} $QUEUE_COUNT Roblox terdaftar"

    if [ "$QUEUE_COUNT" -gt 0 ] && [ -s "$QUEUEFILE" ]; then
        while IFS='|' read -r pkg delay; do
            [ -z "$pkg" ] && continue
            if pidof "$pkg" >/dev/null 2>&1; then
                echo -e "   ${G}●${W} $pkg (delay ${delay}s)"
            else
                echo -e "   ${R}●${W} $pkg (delay ${delay}s)"
            fi
        done < "$QUEUEFILE"
    fi

    echo -e "${C}Launcher   :${W} $([ "$LAUNCHER_ACTIVE" -eq 1 ] && echo "${G}● AKTIF${W}" || echo "${R}● TIDAK AKTIF${W}")"
    echo -e "${C}Clear Cache:${W} $([ "$CACHE_ACTIVE" -eq 1 ] && echo "${G}● AKTIF${W} (tiap 2 jam, root)" || echo "${R}● TIDAK AKTIF${W}")"
    echo -e "${C}RAM Booster:${W} $([ "$RAMBOOST_ACTIVE" -eq 1 ] && echo "${G}● AKTIF${W} (tiap ${RAM_BOOST_INTERVAL}s)" || echo "${R}● TIDAK AKTIF${W}")"
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
            open_selected_roblox
            ;;
        8)
            toggle_cache_clear
            ;;
        9)
            toggle_ram_boost
            ;;
        0)
            stop_launcher
            disable_cache_clear
            disable_ram_boost
            exit 0
            ;;
    esac
done
