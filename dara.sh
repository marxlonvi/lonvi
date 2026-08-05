#!/data/data/com.termux/files/usr/bin/bash

# ═══════════════════════════════════════════════════════════════════════════
# DARA - Roblox Multi-Instance Manager for Termux
# Improved version dengan perbaikan error handling, stability, dan UX
# ═══════════════════════════════════════════════════════════════════════════

export PATH="/data/data/com.termux/files/usr/bin:$PATH"

# ─────────────────────────────────────────────────────────────────────────
# SELF-ELEVATION KE ROOT
# Kalau script belum jalan sebagai root, minta akses root sekali di awal
# lalu re-exec seluruh script lewat `su`. Setelah ini SEMUA command di
# dalam script (am, pm, rm, dll) otomatis jalan sebagai root tanpa perlu
# wrap manual satu-satu. Kalau su tidak tersedia / user tolak akses,
# script tetap lanjut jalan sebagai user biasa (fitur yang butuh root
# akan otomatis nonaktif/terbatas, lihat check_root()).
#
# DARA_ELEVATED dipakai sebagai penanda supaya tidak infinite-loop
# re-exec ke su berkali-kali.
# ─────────────────────────────────────────────────────────────────────────
if [ "$(id -u 2>/dev/null)" != "0" ] && [ -z "$DARA_ELEVATED" ]; then
    if command -v su >/dev/null 2>&1; then
        export DARA_ELEVATED=1
        exec su -c "export PATH='/data/data/com.termux/files/usr/bin:\$PATH'; export DARA_ELEVATED=1; export HOME='$HOME'; export TERM='${TERM:-xterm-256color}'; bash '$0' \"\$@\"" -- "$@" 2>/dev/null \
            || { unset DARA_ELEVATED; echo "Gagal elevate ke root, lanjut sebagai user biasa..."; sleep 1; }
    fi
fi

VERSION="1.1.4"
GITHUB="https://raw.githubusercontent.com/marxlonvi/lonvi/refs/heads/main"

CONFIG="$HOME/.dara"
QUEUEFILE="$HOME/.dara_queue"
PIDFILE="$HOME/.dara.pid"
LOCKFILE="$HOME/.dara.lock"

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
CACHE_PIDFILE="$HOME/.dara_cache.pid"

# Whitelist pattern untuk RAM booster
RAM_BOOST_WHITELIST_PATTERN="^(com\.android\.|com\.google\.android\.(gms|gsf|inputmethod|packageinstaller)|com\.termux|android$|system$)"

# Status cache
ROOT_OK=0
ALREADY_ROOT=0
LAUNCHER_ACTIVE=0
CACHE_ACTIVE=0
RAMBOOST_ACTIVE=0
QUEUE_COUNT=0
declare -a QUEUE_PKGS=()

# ═══════════════════════════════════════════════════════════════════════════
# UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

cleanup() {
    rm -f "$LOCKFILE" 2>/dev/null
}
trap cleanup EXIT

acquire_lock() {
    local timeout=5
    local elapsed=0
    while [ -f "$LOCKFILE" ] && [ $elapsed -lt $timeout ]; do
        sleep 0.2
        elapsed=$((elapsed + 1))
    done
    touch "$LOCKFILE"
}

release_lock() {
    rm -f "$LOCKFILE" 2>/dev/null
}

# Escape special characters untuk awk/sed
escape_string() {
    printf '%s\n' "$1" | sed 's:[&/\]:\\&:g'
}

log_debug() {
    if [ -n "$DEBUG_MODE" ]; then
        echo "[DEBUG] $*" >> "$HOME/.dara_debug.log"
    fi
}

# Check root dengan timeout yang lebih robust
check_root() {
    if [ "$(id -u 2>/dev/null)" = "0" ]; then
        ALREADY_ROOT=1
        ROOT_OK=1
        log_debug "Script running as root (UID 0)"
        return
    fi

    if command -v su >/dev/null 2>&1; then
        if timeout 15 su -c 'echo ok' >/dev/null 2>&1; then
            ROOT_OK=1
            log_debug "Root access available via su"
        else
            ROOT_OK=0
            log_debug "Root access failed or timeout"
        fi
    else
        ROOT_OK=0
        log_debug "su command not found"
    fi
}

# Run privileged command dengan better error handling
run_privileged() {
    local cmd="$1"
    local tmo="${2:-8}"
    
    if [ -z "$cmd" ]; then
        log_debug "run_privileged: empty command"
        return 1
    fi
    
    if [ "$ALREADY_ROOT" -eq 1 ]; then
        eval "$cmd" 2>/dev/null
        return $?
    elif [ "$ROOT_OK" -eq 1 ]; then
        timeout "$tmo" su -c "$cmd" 2>/dev/null
        return $?
    fi
    
    return 1
}

# Check if process exists safely
is_process_running() {
    local pkg="$1"
    [ -z "$pkg" ] && return 1
    pidof "$pkg" >/dev/null 2>&1
}

# Update status cache
update_status_cache() {
    LAUNCHER_ACTIVE=0
    CACHE_ACTIVE=0
    RAMBOOST_ACTIVE=0
    
    if [ -f "$PIDFILE" ] 2>/dev/null; then
        local pid=$(cat "$PIDFILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            LAUNCHER_ACTIVE=1
        fi
    fi
    
    if [ -f "$CACHE_PIDFILE" ] 2>/dev/null; then
        local pid=$(cat "$CACHE_PIDFILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            CACHE_ACTIVE=1
        fi
    fi

    if [ -f "$RAMPIDFILE" ] 2>/dev/null; then
        local pid=$(cat "$RAMPIDFILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            RAMBOOST_ACTIVE=1
        fi
    fi
}

# Auto-update check dengan better error handling
check_for_updates() {
    (
        timeout 5 curl -fsSL "$GITHUB/version.txt" 2>/dev/null | {
            read -r remote
            if [ -z "$remote" ]; then
                log_debug "Update check failed: empty response"
                return
            fi
            
            if [ "$remote" != "$VERSION" ]; then
                tmpfile=$(mktemp 2>/dev/null)
                if [ -z "$tmpfile" ]; then
                    log_debug "Update check failed: cannot create temp file"
                    return
                fi
                
                if timeout 10 curl -fsSL "$GITHUB/dara.sh" -o "$tmpfile" 2>/dev/null && \
                   [ -s "$tmpfile" ] && \
                   chmod +x "$tmpfile" 2>/dev/null; then
                    mv "$tmpfile" "$0" 2>/dev/null && exec "$0"
                fi
                rm -f "$tmpfile" 2>/dev/null
            fi
        }
    ) >/dev/null 2>&1 &
}

# ═══════════════════════════════════════════════════════════════════════════
# CONFIG MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════

save_config() {
    acquire_lock
    cat > "$CONFIG" <<EOF
PSLINK="$(escape_string "$PSLINK")"
AUTO_CLEAR_CACHE="$AUTO_CLEAR_CACHE"
AUTO_RAM_BOOST="$AUTO_RAM_BOOST"
RAM_BOOST_INTERVAL="$RAM_BOOST_INTERVAL"
EOF
    release_lock
}

load_config() {
    if [ -f "$CONFIG" ]; then
        # Source dengan error handling
        if ! source "$CONFIG" 2>/dev/null; then
            log_debug "Config load failed, using defaults"
            PSLINK=""
            AUTO_CLEAR_CACHE="yes"
            AUTO_RAM_BOOST="no"
            RAM_BOOST_INTERVAL="60"
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# QUEUE MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════

load_queue_cache() {
    QUEUE_PKGS=()
    QUEUE_COUNT=0
    
    if [ ! -f "$QUEUEFILE" ]; then
        touch "$QUEUEFILE"
        return
    fi
    
    while IFS='|' read -r pkg delay; do
        [ -z "$pkg" ] && continue
        QUEUE_PKGS+=("$pkg")
        ((QUEUE_COUNT++))
    done < "$QUEUEFILE"
}

view_queue() {
    clear
    echo "===== DAFTAR ANTRIAN ROBLOX ====="
    
    if [ "$QUEUE_COUNT" -eq 0 ]; then
        echo "(antrian kosong)"
    else
        local i=0
        while IFS='|' read -r pkg delay; do
            [ -z "$pkg" ] && continue
            ((i++))
            if is_process_running "$pkg"; then
                echo -e "    $i. ${G}●${W} $pkg (delay: ${delay}s)"
            else
                echo -e "    $i. ${R}●${W} $pkg (delay: ${delay}s)"
            fi
        done < "$QUEUEFILE"
    fi
    echo
}

add_to_queue() {
    clear
    
    # Scan Roblox packages dengan error handling
    local apps_tmp=$(mktemp 2>/dev/null)
    if [ -z "$apps_tmp" ]; then
        echo "Gagal membuat temp file"
        read -p "Enter..."
        return
    fi
    
    if ! pm list packages 2>/dev/null | sed 's/package://' | grep -i roblox > "$apps_tmp"; then
        echo "Gagal scan aplikasi Roblox"
        rm -f "$apps_tmp"
        read -p "Enter..."
        return
    fi
    
    if [ ! -s "$apps_tmp" ]; then
        echo "Roblox tidak ditemukan."
        rm -f "$apps_tmp"
        read -p "Enter..."
        return
    fi
    
    mapfile -t APPS < "$apps_tmp"
    rm -f "$apps_tmp"
    
    clear
    echo "===== TAMBAH ROBLOX KE ANTRIAN ====="
    local i=0
    for app in "${APPS[@]}"; do
        echo "$((++i)). $app"
    done
    echo
    read -p "Pilih nomor (pisahkan spasi, misal: 1 2 3): " pilih_input

    declare -a chosen=()
    for p in $pilih_input; do
        if [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -ge 1 ] && [ "$p" -le "${#APPS[@]}" ]; then
            # Cek duplikat
            local is_dup=0
            for c in "${chosen[@]}"; do
                [ "$c" = "$p" ] && is_dup=1 && break
            done
            [ "$is_dup" -eq 0 ] && chosen+=("$p")
        fi
    done

    if [ ${#chosen[@]} -eq 0 ]; then
        echo "Pilihan tidak valid."
        read -p "Enter..."
        return
    fi

    read -p "Delay antar aplikasi (detik, default 50): " delay
    delay="${delay:-50}"
    
    # Validasi delay
    while [[ ! "$delay" =~ ^[0-9]+$ ]] || [ "$delay" -lt 1 ] || [ "$delay" -gt 3600 ]; do
        read -p "Delay harus angka 1-3600 detik, coba lagi (default 50): " delay
        delay="${delay:-50}"
    done

    echo
    acquire_lock
    for p in "${chosen[@]}"; do
        local pkg="${APPS[$((p-1))]}"
        
        # Cek duplikat di queue
        if grep -q "^$(escape_string "$pkg")|" "$QUEUEFILE"; then
            echo "Sudah ada: $pkg"
        else
            printf "%s|%s\n" "$pkg" "$delay" >> "$QUEUEFILE"
            echo "Ditambahkan: $pkg (delay ${delay}s)"
        fi
    done
    release_lock

    load_queue_cache
    read -p "Enter..."
}

remove_from_queue() {
    view_queue
    
    [ "$QUEUE_COUNT" -eq 0 ] && read -p "Enter..." && return
    
    read -p "Hapus nomor (pisahkan spasi, 'all' hapus semua, 0 batal): " pilih_input

    if [ "$pilih_input" = "0" ]; then
        echo "Dibatalkan."
        read -p "Enter..."
        return
    fi

    if [[ "$pilih_input" =~ ^([Aa][Ll][Ll])$ ]]; then
        acquire_lock
        > "$QUEUEFILE"
        release_lock
        load_queue_cache
        echo "Semua antrian dihapus."
        read -p "Enter..."
        return
    fi

    declare -a nums=()
    for p in $pilih_input; do
        if [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -ge 1 ] && [ "$p" -le "$QUEUE_COUNT" ]; then
            local is_dup=0
            for c in "${nums[@]}"; do
                [ "$c" = "$p" ] && is_dup=1 && break
            done
            [ "$is_dup" -eq 0 ] && nums+=("$p")
        fi
    done

    if [ ${#nums[@]} -eq 0 ]; then
        echo "Nomor tidak valid."
        read -p "Enter..."
        return
    fi

    # Sort descending untuk prevent index shift saat delete
    IFS=$'\n' nums=($(sort -rn <<<"${nums[*]}")); unset IFS

    acquire_lock
    for n in "${nums[@]}"; do
        sed -i "${n}d" "$QUEUEFILE"
    done
    release_lock

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

# ═══════════════════════════════════════════════════════════════════════════
# LAUNCHER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

launch_package() {
    local pkg="$1"
    
    [ -z "$pkg" ] && return 1
    
    log_debug "Launching package: $pkg"
    
    # Coba dengan PSLINK dulu (jika ada)
    if [ -n "$PSLINK" ]; then
        timeout 5 am start -a android.intent.action.VIEW -d "$PSLINK" -n "$(cmd package resolve-activity --brief "$pkg" 2>/dev/null | tail -n 1)" >/dev/null 2>&1 && return 0
    fi
    
    # Fallback: launch biasa dengan resolve-activity
    local activity=$(cmd package resolve-activity --brief "$pkg" 2>/dev/null | tail -n 1)
    if [ -n "$activity" ]; then
        timeout 5 am start -n "$activity" >/dev/null 2>&1 && return 0
    fi
    
    # Last resort: monkey (deprecated tapi still works sometimes)
    timeout 5 monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
    return $?
}

launch_sequence() {
    sleep 3
    
    [ ! -s "$QUEUEFILE" ] && echo "Antrian Roblox masih kosong." && return
    
    while IFS='|' read -r pkg delay; do
        [ -z "$pkg" ] && continue
        log_debug "Sequence: launching $pkg with delay $delay"
        launch_package "$pkg"
        [ -n "$delay" ] && sleep "$delay"
    done < "$QUEUEFILE"
}

# Launcher loop dengan perbaikan
launcher_loop() {
    while true; do
        if [ ! -s "$QUEUEFILE" ]; then
            sleep 30
            continue
        fi

        # Baca semua package dari queue
        local pkgs=($(cut -d'|' -f1 "$QUEUEFILE" 2>/dev/null | grep -v '^$'))
        local total=${#pkgs[@]}
        
        if [ "$total" -gt 0 ]; then
            # Check berapa banyak yang running
            local running=0
            for pkg in "${pkgs[@]}"; do
                is_process_running "$pkg" && ((running++))
            done
            
            log_debug "Launcher check: $running/$total running"
            
            # Jika ada yang tertutup, relaunch
            if [ "$running" -lt "$total" ]; then
                if command -v termux-notification >/dev/null 2>&1; then
                    termux-notification --id dara_launcher --title "DARA Auto-Launcher" \
                        --content "Ada Roblox yang tertutup, menjalankan ulang..." 2>/dev/null
                fi
                launch_sequence
            fi
        fi
        
        sleep 20
    done
}

start_launcher() {
    [ ! -s "$QUEUEFILE" ] && echo "Antrian Roblox masih kosong." && sleep 2 && return
    
    if [ -f "$PIDFILE" ]; then
        local pid=$(cat "$PIDFILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "Auto-Launcher Roblox sudah berjalan."
            sleep 2
            return
        fi
    fi

    nohup bash -c "
        export PATH='/data/data/com.termux/files/usr/bin:\$PATH'
        QUEUEFILE='$(escape_string "$QUEUEFILE")'
        PSLINK='$(escape_string "$PSLINK")'
        $(declare -f launch_package)
        $(declare -f launch_sequence)
        $(declare -f launcher_loop)
        $(declare -f log_debug)
        $(declare -f is_process_running)
        launcher_loop
    " >/dev/null 2>&1 &
    
    local new_pid=$!
    echo "$new_pid" > "$PIDFILE"
    
    echo "Auto-Launcher Roblox dimulai (PID: $new_pid)"
    sleep 2
}

stop_launcher() {
    if [ -f "$PIDFILE" ]; then
        local pid=$(cat "$PIDFILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            sleep 1
            kill -9 "$pid" 2>/dev/null
        fi
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

# ═══════════════════════════════════════════════════════════════════════════
# ROBLOX CONTROL
# ═══════════════════════════════════════════════════════════════════════════

close_all_roblox() {
    clear
    
    local apps_tmp=$(mktemp 2>/dev/null)
    if [ -z "$apps_tmp" ]; then
        echo "Gagal membuat temp file"
        sleep 2
        return
    fi
    
    if ! pm list packages 2>/dev/null | sed 's/package://' | grep -i roblox > "$apps_tmp"; then
        echo "Gagal scan aplikasi Roblox"
        rm -f "$apps_tmp"
        sleep 2
        return
    fi
    
    mapfile -t ALL_ROBLOX < "$apps_tmp"
    rm -f "$apps_tmp"

    if [ ${#ALL_ROBLOX[@]} -eq 0 ]; then
        echo "Tidak ada Roblox terpasang di device."
        sleep 2
        return
    fi

    # Stop launcher dulu supaya tidak auto-relaunch
    if [ -f "$PIDFILE" ]; then
        local pid=$(cat "$PIDFILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            rm -f "$PIDFILE"
        fi
    fi

    echo "Menutup paksa ${#ALL_ROBLOX[@]} Roblox..."
    
    # Non-root attempt
    for pkg in "${ALL_ROBLOX[@]}"; do
        timeout 3 am force-stop "$pkg" >/dev/null 2>&1
    done

    # Root attempt (selalu dicoba, jangan digembok status ROOT_OK
    # karena bisa telat ke-set kalau popup Magisk belum sempat di-approve)
    local su_cmd=""
    for pkg in "${ALL_ROBLOX[@]}"; do
        su_cmd+="am force-stop $pkg; pkill -9 -f $pkg; "
    done
    if [ -n "$su_cmd" ]; then
        if [ "$ALREADY_ROOT" -eq 1 ]; then
            eval "$su_cmd" 2>/dev/null
        else
            timeout 12 su -c "$su_cmd" 2>/dev/null
        fi
    fi

    sleep 2

    # Verifikasi
    local masih_aktif=0
    for pkg in "${ALL_ROBLOX[@]}"; do
        if is_process_running "$pkg"; then
            masih_aktif=$((masih_aktif+1))
            echo -e "   ${R}●${W} $pkg masih aktif"
        fi
    done

    if [ "$masih_aktif" -eq 0 ]; then
        echo "Semua Roblox berhasil ditutup paksa."
    else
        echo "$masih_aktif Roblox masih aktif (butuh root untuk close penuh)."
    fi

    sleep 2
}

open_selected_roblox() {
    local apps_tmp=$(mktemp 2>/dev/null)
    if [ -z "$apps_tmp" ]; then
        echo "Gagal membuat temp file"
        read -p "Enter..."
        return
    fi
    
    if ! pm list packages 2>/dev/null | sed 's/package://' | grep -i roblox > "$apps_tmp"; then
        echo "Gagal scan aplikasi Roblox"
        rm -f "$apps_tmp"
        read -p "Enter..."
        return
    fi
    
    mapfile -t APPS < "$apps_tmp"
    rm -f "$apps_tmp"

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
        if is_process_running "$app"; then
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

    if is_process_running "$pkg"; then
        echo "$pkg sedang aktif, menutup dulu..."
        timeout 3 am force-stop "$pkg" >/dev/null 2>&1
        sleep 1
    else
        echo "$pkg masih tertutup, membuka..."
    fi

    if launch_package "$pkg"; then
        echo "Selesai: $pkg dibuka."
    else
        echo "Gagal membuka $pkg"
    fi
    
    read -p "Enter..."
}

# ═══════════════════════════════════════════════════════════════════════════
# CACHE & RAM MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════

clear_cache_all() {
    [ ! -s "$QUEUEFILE" ] && return

    local cleared=0
    while IFS='|' read -r pkg _; do
        [ -z "$pkg" ] && continue
        if [ "$ALREADY_ROOT" -eq 1 ]; then
            rm -rf "/data/data/$pkg/cache/"* 2>/dev/null && ((cleared++))
        else
            timeout 3 su -c "rm -rf /data/data/$pkg/cache/* 2>/dev/null" 2>/dev/null && ((cleared++))
        fi
    done < "$QUEUEFILE"

    log_debug "Cache cleared for $cleared packages"

    if command -v termux-notification >/dev/null 2>&1; then
        termux-notification --id dara_cache --title "DARA Auto Clear Cache" \
            --content "Cache $cleared Roblox dibersihkan." 2>/dev/null
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
    if [ -f "$CACHE_PIDFILE" ]; then
        local pid=$(cat "$CACHE_PIDFILE" 2>/dev/null)
        [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
        return $?
    fi
    return 1
}

enable_cache_clear() {
    cache_clear_running && return
    
    nohup bash -c "
        export PATH='/data/data/com.termux/files/usr/bin:\$PATH'
        QUEUEFILE='$(escape_string "$QUEUEFILE")'
        ROOT_OK='$ROOT_OK'
        ALREADY_ROOT='$ALREADY_ROOT'
        $(declare -f run_privileged)
        $(declare -f clear_cache_all)
        $(declare -f clear_cache_loop)
        $(declare -f log_debug)
        clear_cache_loop
    " >/dev/null 2>&1 &
    
    echo $! > "$CACHE_PIDFILE"
}

disable_cache_clear() {
    if [ -f "$CACHE_PIDFILE" ]; then
        local pid=$(cat "$CACHE_PIDFILE" 2>/dev/null)
        if [ -n "$pid" ]; then
            kill "$pid" 2>/dev/null
            sleep 1
            kill -9 "$pid" 2>/dev/null
        fi
        rm -f "$CACHE_PIDFILE"
    fi
    
    if command -v termux-notification-remove >/dev/null 2>&1; then
        termux-notification-remove dara_cache 2>/dev/null
    fi
}

ram_boost_once() {
    declare -A PROTECT=()
    
    if [ -s "$QUEUEFILE" ]; then
        while IFS='|' read -r pkg _; do
            [ -z "$pkg" ] && continue
            PROTECT["$pkg"]=1
        done < "$QUEUEFILE"
    fi

    local killed=0
    local su_cmd=""
    
    while read -r pkg; do
        [ -z "$pkg" ] && continue

        # Skip whitelist statis
        [[ "$pkg" =~ $RAM_BOOST_WHITELIST_PATTERN ]] && continue

        # Skip dynamic whitelist (antrian)
        [ -n "${PROTECT[$pkg]}" ] && continue

        # Cek proses running
        if is_process_running "$pkg"; then
            timeout 2 am force-stop "$pkg" >/dev/null 2>&1
            [ "$ROOT_OK" -eq 1 ] && su_cmd+="am force-stop $pkg; "
            ((killed++))
        fi
    done < <(pm list packages -3 2>/dev/null | sed 's/package://')

    if [ "$ROOT_OK" -eq 1 ] && [ -n "$su_cmd" ]; then
        run_privileged "$su_cmd" 8
    fi

    if [ "$killed" -gt 0 ] && command -v termux-notification >/dev/null 2>&1; then
        termux-notification --id dara_ramboost --title "DARA RAM Booster" \
            --content "$killed aplikasi background ditutup, RAM terbebas." 2>/dev/null
    fi
    
    log_debug "RAM boost killed $killed apps"
}

ram_boost_loop() {
    local interval="$1"
    [[ ! "$interval" =~ ^[0-9]+$ ]] && interval=60
    [ "$interval" -lt 5 ] && interval=5

    while true; do
        sleep "$interval"
        ram_boost_once
    done
}

ram_boost_running() {
    if [ -f "$RAMPIDFILE" ]; then
        local pid=$(cat "$RAMPIDFILE" 2>/dev/null)
        [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
        return $?
    fi
    return 1
}

enable_ram_boost() {
    local interval="${1:-$RAM_BOOST_INTERVAL}"
    ram_boost_running && return

    nohup bash -c "
        export PATH='/data/data/com.termux/files/usr/bin:\$PATH'
        QUEUEFILE='$(escape_string "$QUEUEFILE")'
        RAM_BOOST_WHITELIST_PATTERN='$(escape_string "$RAM_BOOST_WHITELIST_PATTERN")'
        ROOT_OK='$ROOT_OK'
        ALREADY_ROOT='$ALREADY_ROOT'
        $(declare -f run_privileged)
        $(declare -f ram_boost_once)
        $(declare -f ram_boost_loop)
        $(declare -f is_process_running)
        $(declare -f log_debug)
        ram_boost_loop '$interval'
    " >/dev/null 2>&1 &
    
    echo $! > "$RAMPIDFILE"
}

disable_ram_boost() {
    if [ -f "$RAMPIDFILE" ]; then
        local pid=$(cat "$RAMPIDFILE" 2>/dev/null)
        if [ -n "$pid" ]; then
            kill "$pid" 2>/dev/null
            sleep 1
            kill -9 "$pid" 2>/dev/null
        fi
        rm -f "$RAMPIDFILE"
    fi
    
    if command -v termux-notification-remove >/dev/null 2>&1; then
        termux-notification-remove dara_ramboost 2>/dev/null
    fi
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
            echo "Auto Clear Cache diaktifkan (pembersihan pertama dalam 20 menit)."
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

toggle_ram_boost() {
    read -p "Aktifkan RAM Booster (kill app background)? (Y/n): " ans
    ans="${ans:-Y}"

    case "$ans" in
        [Yy]*)
            read -p "Interval kill (detik, default 60, min 5): " iv
            iv="${iv:-60}"
            while [[ ! "$iv" =~ ^[0-9]+$ ]] || [ "$iv" -lt 5 ]; do
                read -p "Interval 1-3600 detik, coba lagi (default 60): " iv
                iv="${iv:-60}"
            done
            RAM_BOOST_INTERVAL="$iv"
            AUTO_RAM_BOOST="yes"
            save_config
            disable_ram_boost
            enable_ram_boost "$iv"
            echo "RAM Booster diaktifkan (kill setiap ${iv}s)."
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

# ═══════════════════════════════════════════════════════════════════════════
# INITIALIZATION
# ═══════════════════════════════════════════════════════════════════════════

check_root
load_config
load_queue_cache
update_status_cache
check_for_updates

# Auto-enable features sesuai config
if [ "$AUTO_CLEAR_CACHE" = "yes" ] && [ -s "$QUEUEFILE" ] && ! cache_clear_running; then
    enable_cache_clear &
fi

if [ "$AUTO_RAM_BOOST" = "yes" ] && ! ram_boost_running; then
    enable_ram_boost "$RAM_BOOST_INTERVAL" &
fi

# ═══════════════════════════════════════════════════════════════════════════
# MAIN MENU LOOP
# ═══════════════════════════════════════════════════════════════════════════

while true; do
    clear
    echo -e "${Y}╔══════════════════════════╗${W}"
    echo -e "${Y}║${C}    DARA v$VERSION     ${Y}║${W}"
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

    # Update status display
    update_status_cache
    
    echo -e "${C}Root      :${W} $([ "$ROOT_OK" -eq 1 ] && echo "${G}● TERDETEKSI${W}" || echo "${R}● TIDAK TERDETEKSI${W}")"
    echo -e "${C}Link PS   :${W} ${PSLINK:-Belum diatur}"
    echo -e "${C}Antrian   :${W} $QUEUE_COUNT Roblox"

    if [ "$QUEUE_COUNT" -gt 0 ] && [ -s "$QUEUEFILE" ]; then
        while IFS='|' read -r pkg delay; do
            [ -z "$pkg" ] && continue
            if is_process_running "$pkg"; then
                echo -e "   ${G}●${W} $pkg (delay ${delay}s)"
            else
                echo -e "   ${R}●${W} $pkg (delay ${delay}s)"
            fi
        done < "$QUEUEFILE"
    fi

    echo -e "${C}Launcher   :${W} $([ "$LAUNCHER_ACTIVE" -eq 1 ] && echo "${G}● AKTIF${W}" || echo "${R}● TIDAK AKTIF${W}")"
    echo -e "${C}Clear Cache:${W} $([ "$CACHE_ACTIVE" -eq 1 ] && echo "${G}● AKTIF${W} (root)" || echo "${R}● TIDAK AKTIF${W}")"
    echo -e "${C}RAM Booster:${W} $([ "$RAMBOOST_ACTIVE" -eq 1 ] && echo "${G}● AKTIF${W}" || echo "${R}● TIDAK AKTIF${W}")"
    echo

    read -p "Pilih: " menu

    case "$menu" in
        1)
            read -p "Link PS (PSLINK): " PSLINK
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
            echo "Closing DARA..."
            exit 0
            ;;
    esac
done
