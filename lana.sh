#!/data/data/com.termux/files/usr/bin/bash

VERSION="1.2.1"
GITHUB="https://raw.githubusercontent.com/marxlonvi/lonvi/refs/heads/main"

CONFIG="$HOME/.lana"
QUEUEFILE="$HOME/.lana_queue"
PIDFILE="$HOME/.lana.pid"
RAM_PIDFILE="$HOME/.lana_ram.pid"

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
RAM_BOOSTER_ACTIVE=0
QUEUE_COUNT=0
declare -a QUEUE_PKGS=()

# Background update check (non-blocking, silent)
(curl -fsSL "$GITHUB/version.txt" 2>/dev/null | {
    read remote
    if [ -n "$remote" ] && [ "$remote" != "$VERSION" ]; then
        tmpfile=$(mktemp)
        curl -fsSL "$GITHUB/lana.sh" -o "$tmpfile" 2>/dev/null && \
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

update_status_cache() {
    # Cek launcher dan cache dalam satu operasi, bukan multiple test
    LAUNCHER_ACTIVE=0
    CACHE_ACTIVE=0
    
    if [ -f "$PIDFILE" ] 2>/dev/null && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
        LAUNCHER_ACTIVE=1
    fi
    
    if [ -f "$HOME/.lana_cache.pid" ] 2>/dev/null && kill -0 "$(cat "$HOME/.lana_cache.pid" 2>/dev/null)" 2>/dev/null; then
        CACHE_ACTIVE=1
    fi

    RAM_BOOSTER_ACTIVE=0
    if [ -f "$RAM_PIDFILE" ] 2>/dev/null && kill -0 "$(cat "$RAM_PIDFILE" 2>/dev/null)" 2>/dev/null; then
        RAM_BOOSTER_ACTIVE=1
    fi
}

[ -f "$CONFIG" ] && source "$CONFIG"
[ -f "$QUEUEFILE" ] || touch "$QUEUEFILE"

# Load initial cache
load_queue_cache
update_status_cache

# Cache daftar app Roblox terpasang (TTL 15 detik) supaya "pm list packages"
# (yang lumayan berat di Android) tidak dipanggil berulang-ulang tiap menu.
_ROBLOX_APPS_CACHE=()
_ROBLOX_APPS_CACHE_TS=0
get_roblox_apps() {
    local now
    now=$(date +%s 2>/dev/null || echo 0)
    if [ ${#_ROBLOX_APPS_CACHE[@]} -eq 0 ] || [ $((now - _ROBLOX_APPS_CACHE_TS)) -ge 15 ]; then
        mapfile -t _ROBLOX_APPS_CACHE < <(pm list packages 2>/dev/null | sed 's/package://' | grep -i roblox)
        _ROBLOX_APPS_CACHE_TS=$now
    fi
    printf '%s\n' "${_ROBLOX_APPS_CACHE[@]}"
}

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
    mapfile -t APPS < <(get_roblox_apps)
    
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
                    termux-notification --id lana_launcher --title "DARA Auto-Launcher" \
                        --content "Ada Roblox yang tertutup, menjalankan ulang antrian..." 2>/dev/null
                fi
                launch_sequence
            fi
        fi
        
        sleep 20
    done
}

close_all_roblox() {
    mapfile -t ALL_ROBLOX < <(get_roblox_apps)

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

    echo "Menutup paksa ${#ALL_ROBLOX[@]} Roblox..."

    for pkg in "${ALL_ROBLOX[@]}"; do
        # Coba beberapa metode sekaligus supaya benar-benar mati apapun
        # kondisinya (am force-stop bisa gagal kalau ada dialog/izin aneh,
        # jadi di-backup dengan su force-stop dan kill proses langsung).
        am force-stop "$pkg" >/dev/null 2>&1
        am kill "$pkg" >/dev/null 2>&1

        # Cek dulu apakah masih ada proses yang jalan sebelum coba akses root,
        # supaya tidak minta izin su kalau sebenarnya sudah mati (yang bisa
        # bikin script macet nunggu popup izin root muncul/di-tap).
        pid=$(pidof "$pkg" 2>/dev/null)
        if [ -n "$pid" ]; then
            kill -9 $pid >/dev/null 2>&1
            if command -v su >/dev/null 2>&1; then
                timeout 5 su -c "am force-stop $pkg; kill -9 $pid" >/dev/null 2>&1
            fi
        fi
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

    # Bersihkan PID file basi (proses lama sudah mati / PID sudah dipakai
    # ulang oleh proses lain) supaya tidak salah anggap "sudah berjalan".
    if [ -f "$PIDFILE" ]; then
        local old_pid
        old_pid=$(cat "$PIDFILE" 2>/dev/null)
        if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null \
           && ps -p "$old_pid" -o args= 2>/dev/null | grep -q "launcher_loop"; then
            echo "Auto-Launcher Roblox sudah berjalan (PID $old_pid)."
            sleep 2
            return
        fi
        rm -f "$PIDFILE"
    fi

    local runner="nohup"
    command -v setsid >/dev/null 2>&1 && runner="setsid nohup"

    $runner bash -c "
        QUEUEFILE='$QUEUEFILE'; PSLINK='$PSLINK'
        $(declare -f launch_package)
        $(declare -f launch_sequence)
        $(declare -f launcher_loop)
        launcher_loop
    " >/dev/null 2>&1 &
    disown 2>/dev/null
    local new_pid=$!
    echo "$new_pid" > "$PIDFILE"

    sleep 1
    if kill -0 "$new_pid" 2>/dev/null; then
        echo "Auto-Launcher Roblox dimulai di background (PID $new_pid)."
        enable_ram_booster
    else
        rm -f "$PIDFILE"
        echo "Gagal memulai Auto-Launcher. Coba jalankan 'bash lana.sh' ulang, atau cek apakah paket 'util-linux' (untuk setsid) terpasang: pkg install util-linux"
    fi
    sleep 2
}

stop_launcher() {
    if [ -f "$PIDFILE" ]; then
        kill "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
        rm -f "$PIDFILE"
        if command -v termux-notification-remove >/dev/null 2>&1; then
            termux-notification-remove lana_launcher 2>/dev/null
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
    mapfile -t APPS < <(get_roblox_apps)

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

    # Tanpa root, "su" tidak akan ada / tidak akan pernah berhasil. Sebelumnya
    # kegagalan ini didiamkan begitu saja dan tetap muncul notifikasi "sudah
    # dibersihkan" walau sebenarnya tidak terjadi apa-apa. Sekarang dicek dan
    # dilaporkan apa adanya.
    if ! command -v su >/dev/null 2>&1; then
        if command -v termux-notification >/dev/null 2>&1; then
            termux-notification --id lana_cache --title "DARA Auto Clear Cache" \
                --content "Gagal: akses root (su) tidak ditemukan di perangkat ini." 2>/dev/null
        fi
        return
    fi

    # Pakai redirection input (bukan pipe) supaya loop tetap di shell utama,
    # karena kalau lewat pipe ("cut ... | while ..."), while-nya jalan di
    # subshell dan variabel counter di dalamnya tidak akan terlihat lagi
    # setelah loop selesai.
    local cleared=0 failed=0
    while IFS='|' read -r pkg _; do
        [ -z "$pkg" ] && continue
        if timeout 5 su -c "rm -rf /data/data/$pkg/cache/*" >/dev/null 2>&1; then
            ((cleared++))
        else
            ((failed++))
        fi
    done < "$QUEUEFILE"

    if command -v termux-notification >/dev/null 2>&1; then
        if [ "$cleared" -gt 0 ]; then
            termux-notification --id lana_cache --title "DARA Auto Clear Cache" \
                --content "Cache $cleared Roblox di antrian sudah dibersihkan." 2>/dev/null
        else
            termux-notification --id lana_cache --title "DARA Auto Clear Cache" \
                --content "Gagal membersihkan cache, cek izin root (su ditolak/timeout)." 2>/dev/null
        fi
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
    [ -f "$HOME/.lana_cache.pid" ] && kill -0 "$(cat "$HOME/.lana_cache.pid" 2>/dev/null)" 2>/dev/null
}

# Daftar paket yang TIDAK BOLEH ditutup oleh RAM Booster: Termux sendiri,
# semua Roblox yang ada di antrian, home launcher, keyboard aktif, dan
# proses inti Android. Ini yang bikin RAM booster "tidak mengganggu kinerja
# script" -> script & Roblox yang lagi dipakai tidak ikut ke-kill.
get_protected_pkgs() {
    local protected=(com.termux com.termux.api com.termux.boot
                      com.android.systemui com.android.settings
                      android com.android.phone com.android.providers.settings)

    local home_pkg
    home_pkg=$(cmd package resolve-activity --brief -c android.intent.category.HOME 2>/dev/null \
        | tail -n 1 | cut -d'/' -f1)
    [ -n "$home_pkg" ] && [[ "$home_pkg" != *Error* ]] && protected+=("$home_pkg")

    local ime
    ime=$(settings get secure default_input_method 2>/dev/null | cut -d'/' -f1)
    [ -n "$ime" ] && [ "$ime" != "null" ] && protected+=("$ime")

    while IFS='|' read -r pkg _; do
        [ -n "$pkg" ] && protected+=("$pkg")
    done < "$QUEUEFILE"

    printf '%s\n' "${protected[@]}"
}

# Inti logika RAM Booster (tanpa clear/echo interaktif) supaya bisa dipanggil
# baik dari menu (sekali jalan, dengan output) maupun dari background loop
# (setiap 5 menit, silent + notifikasi).
ram_booster_run() {
    local verbose="${1:-1}"

    mapfile -t protected < <(get_protected_pkgs)

    # Ambil daftar proses app pihak ketiga yang sedang berjalan.
    mapfile -t running < <(pm list packages -3 2>/dev/null | sed 's/package://' | while read -r p; do
        pidof "$p" >/dev/null 2>&1 && echo "$p"
    done)

    if [ ${#running[@]} -eq 0 ]; then
        [ "$verbose" -eq 1 ] && echo "Tidak ada aplikasi lain yang perlu ditutup. RAM sudah bersih."
        return
    fi

    local closed=0 skipped=0
    for pkg in "${running[@]}"; do
        [ -z "$pkg" ] && continue
        local skip=0
        for p in "${protected[@]}"; do
            [ "$pkg" = "$p" ] && skip=1 && break
        done
        if [ "$skip" -eq 1 ]; then
            ((skipped++))
            continue
        fi

        am force-stop "$pkg" >/dev/null 2>&1
        am kill "$pkg" >/dev/null 2>&1
        if pidof "$pkg" >/dev/null 2>&1 && command -v su >/dev/null 2>&1; then
            timeout 5 su -c "am force-stop $pkg" >/dev/null 2>&1
        fi

        if pidof "$pkg" >/dev/null 2>&1; then
            [ "$verbose" -eq 1 ] && echo -e "   ${Y}●${W} $pkg gagal ditutup (mungkin butuh root)"
        else
            [ "$verbose" -eq 1 ] && echo -e "   ${G}✕${W} $pkg ditutup"
            ((closed++))
        fi
    done

    if [ "$verbose" -eq 1 ]; then
        echo
        echo "Selesai. $closed aplikasi ditutup, $skipped dilindungi (Termux/antrian/sistem)."
    elif command -v termux-notification >/dev/null 2>&1; then
        termux-notification --id lana_ram --title "DARA RAM Booster" \
            --content "$closed aplikasi ditutup, $skipped dilindungi." 2>/dev/null
    fi
}

# Jalankan sekali secara interaktif dari menu (dengan output ke layar).
ram_booster() {
    clear
    echo "===== RAM BOOSTER (Force Close App Lain) ====="
    echo "Menutup paksa aplikasi latar belakang lain, kecuali Termux,"
    echo "Roblox yang ada di antrian, launcher, dan keyboard aktif."
    echo
    ram_booster_run 1
    read -p "Enter..."
}

# Loop background: jalan sekali saat diaktifkan, lalu berulang tiap 5 menit.
ram_booster_loop() {
    ram_booster_run 0
    while true; do
        sleep 300
        ram_booster_run 0
    done
}

ram_booster_running() {
    [ -f "$RAM_PIDFILE" ] && kill -0 "$(cat "$RAM_PIDFILE" 2>/dev/null)" 2>/dev/null
}

enable_ram_booster() {
    ram_booster_running && return

    nohup bash -c "
        QUEUEFILE='$QUEUEFILE'
        $(declare -f get_protected_pkgs)
        $(declare -f ram_booster_run)
        $(declare -f ram_booster_loop)
        ram_booster_loop
    " >/dev/null 2>&1 &
    disown 2>/dev/null
    echo $! > "$RAM_PIDFILE"
}

disable_ram_booster() {
    if [ -f "$RAM_PIDFILE" ]; then
        kill "$(cat "$RAM_PIDFILE" 2>/dev/null)" 2>/dev/null
        rm -f "$RAM_PIDFILE"
    fi
    if command -v termux-notification-remove >/dev/null 2>&1; then
        termux-notification-remove lana_ram 2>/dev/null
    fi
}

# Menu toggle on/off untuk RAM Booster otomatis (jalan sekali lalu tiap 5 menit).
toggle_ram_booster() {
    clear
    echo "===== RAM BOOSTER OTOMATIS ====="
    if ram_booster_running; then
        echo "Status saat ini: ${G}AKTIF${W} (auto tutup app tiap 5 menit)"
        echo
        read -p "Matikan RAM Booster otomatis? (Y/n): " ans
        ans="${ans:-Y}"
        case "$ans" in
            [Yy]*)
                disable_ram_booster
                echo "RAM Booster otomatis dimatikan."
                ;;
        esac
    else
        echo "Status saat ini: ${R}TIDAK AKTIF${W}"
        echo
        read -p "Aktifkan RAM Booster otomatis? (Y/n): " ans
        ans="${ans:-Y}"
        case "$ans" in
            [Yy]*)
                enable_ram_booster
                echo "RAM Booster otomatis diaktifkan (jalan sekarang, lalu tiap 5 menit)."
                ;;
        esac
    fi
    sleep 2
}

enable_cache_clear() {
    cache_clear_running && return
    
    nohup bash -c "
        QUEUEFILE='$QUEUEFILE'
        $(declare -f clear_cache_all)
        $(declare -f clear_cache_loop)
        clear_cache_loop
    " >/dev/null 2>&1 &
    disown 2>/dev/null
    echo $! > "$HOME/.lana_cache.pid"
}

disable_cache_clear() {
    if [ -f "$HOME/.lana_cache.pid" ]; then
        kill "$(cat "$HOME/.lana_cache.pid" 2>/dev/null)" 2>/dev/null
        rm -f "$HOME/.lana_cache.pid"
    fi
    if command -v termux-notification-remove >/dev/null 2>&1; then
        termux-notification-remove lana_cache 2>/dev/null
    fi
}

toggle_cache_clear() {
    [ ! -s "$QUEUEFILE" ] && echo "Antrian Roblox masih kosong." && sleep 2 && return

    if ! command -v su >/dev/null 2>&1; then
        echo -e "${Y}Peringatan:${W} perangkat ini sepertinya tidak root (perintah 'su' tidak ditemukan)."
        echo "Auto Clear Cache butuh akses root untuk menghapus cache app lain,"
        echo "jadi fitur ini kemungkinan besar tidak akan berefek walau diaktifkan."
        echo
    fi

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

# Main loop dengan optimized status display (cached status, bukan multiple tests)
while true; do
    clear
    echo -e "${Y}╔══════════════════════════╗${W}"
    echo -e "${Y}║${C}       LANA v$VERSION        ${Y}║${W}"
    echo -e "${Y}╠══════════════════════════╣${W}"
    echo -e "${Y}║${W} 1. Masukkan Link PS      ${Y}║${W}"
    echo -e "${Y}║${W} 2. Kelola Antrian Roblox ${Y}║${W}"
    echo -e "${Y}║${W} 3. Buka Semua (Sequence) ${Y}║${W}"
    echo -e "${Y}║${W} 4. Start Launcher Roblox ${Y}║${W}"
    echo -e "${Y}║${W} 5. Stop Launcher Roblox  ${Y}║${W}"
    echo -e "${Y}║${W} 6. Close All Roblox      ${Y}║${W}"
    echo -e "${Y}║${W} 7. Buka Roblox (Pilih)   ${Y}║${W}"
    echo -e "${Y}║${W} 8. Auto Clear Cache      ${Y}║${W}"
    echo -e "${Y}║${W} 9. RAM Booster (On/Off)  ${Y}║${W}"
    echo -e "${Y}║${W} 0. Keluar                ${Y}║${W}"
    echo -e "${Y}╚══════════════════════════╝${W}"
    echo

    # Update status cache sebelum display
    update_status_cache
    
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
    echo -e "${C}RAM Booster:${W} $([ "$RAM_BOOSTER_ACTIVE" -eq 1 ] && echo "${G}● AKTIF${W} (tiap 5 menit)" || echo "${R}● TIDAK AKTIF${W}")"
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
            toggle_ram_booster
            ;;
        0)
            stop_launcher
            disable_cache_clear
            disable_ram_booster
            exit 0
            ;;
    esac
done
