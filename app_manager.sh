#!/bin/sh
# ============================================================
# app_manager.sh
# Script menu looping untuk kelola link, antrian aplikasi,
# jalankan/stop aplikasi, close all, dan auto clear cache.
#
# CATATAN ASUMSI (baca dulu sebelum pakai):
# - Script ini didesain untuk jalan di Termux (Android) karena
#   pakai perintah `pm` (package manager) dan `am`/`monkey`
#   (activity manager) buat scan & kontrol aplikasi terinstall.
# - "jalankan" = membuka aplikasi di antrian satu per satu.
# - "stop" = force-stop 1 aplikasi pilihan (dari antrian).
# - "close all" = force-stop SEMUA aplikasi pihak ketiga yang
#   terinstall (tidak terbatas ke antrian saja).
# - "auto clear cache" = trim cache sistem (aman, tanpa root).
#   Kalau device kamu root, ada opsi hapus folder cache per app.
# - Kalau ada bagian yang beda dari maksud kamu, tinggal bilang
#   nanti aku sesuaikan.
# ============================================================

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
QUEUE_FILE="$BASE_DIR/antrian.txt"
LINK_FILE="$BASE_DIR/link.txt"

touch "$QUEUE_FILE" "$LINK_FILE"

pause() {
    printf "\nTekan ENTER untuk lanjut..."
    read -r _dummy
}

# ------------------------------------------------------------
# 1. INPUT LINK
# ------------------------------------------------------------
input_link() {
    printf "\n=== INPUT LINK ===\n"
    printf "Masukkan link: "
    read -r link
    if [ -z "$link" ]; then
        echo "Link kosong, dibatalkan."
    else
        echo "$link" >> "$LINK_FILE"
        echo "Link disimpan: $link"
    fi
    pause
}

# ------------------------------------------------------------
# 2. KELOLA (submenu)
# ------------------------------------------------------------
lihat_antrian() {
    printf "\n=== ANTRIAN SAAT INI ===\n"
    if [ ! -s "$QUEUE_FILE" ]; then
        echo "(antrian kosong)"
    else
        nl -w2 -s". " "$QUEUE_FILE"
    fi
    pause
}

tambah_antrian() {
    printf "\n=== SCAN APLIKASI ROBLOX TERINSTALL ===\n"
    tmp_list="$BASE_DIR/.pkg_list.tmp"
    pm list packages 2>/dev/null | sed 's/^package://' | grep -i 'roblox' | sort > "$tmp_list"

    if [ ! -s "$tmp_list" ]; then
        echo "Tidak ditemukan aplikasi Roblox yang terinstall (atau perintah 'pm' tidak tersedia)."
        pause
        rm -f "$tmp_list"
        return
    fi

    nl -w2 -s". " "$tmp_list"
    printf "\nMasukkan nomor aplikasi yang mau ditambahkan (pisah spasi, contoh: 1 3 5)\n"
    printf "Kosongkan lalu ENTER untuk batal: "
    read -r pilihan

    if [ -z "$pilihan" ]; then
        echo "Dibatalkan."
        rm -f "$tmp_list"
        pause
        return
    fi

    for no in $pilihan; do
        pkg=$(sed -n "${no}p" "$tmp_list")
        if [ -n "$pkg" ]; then
            if grep -qx "$pkg" "$QUEUE_FILE"; then
                echo "Sudah ada di antrian: $pkg"
            else
                echo "$pkg" >> "$QUEUE_FILE"
                echo "Ditambahkan: $pkg"
            fi
        fi
    done
    rm -f "$tmp_list"
    pause
}

hapus_antrian() {
    printf "\n=== HAPUS DARI ANTRIAN ===\n"
    if [ ! -s "$QUEUE_FILE" ]; then
        echo "(antrian kosong)"
        pause
        return
    fi
    nl -w2 -s". " "$QUEUE_FILE"
    printf "\nMasukkan nomor yang mau dihapus: "
    read -r no
    if [ -z "$no" ]; then
        echo "Dibatalkan."
        pause
        return
    fi
    total=$(wc -l < "$QUEUE_FILE")
    if [ "$no" -ge 1 ] 2>/dev/null && [ "$no" -le "$total" ] 2>/dev/null; then
        pkg=$(sed -n "${no}p" "$QUEUE_FILE")
        sed -i "${no}d" "$QUEUE_FILE"
        echo "Dihapus: $pkg"
    else
        echo "Nomor tidak valid."
    fi
    pause
}

kelola_menu() {
    while true; do
        clear
        printf "=== KELOLA ANTRIAN ===\n"
        printf "1. Lihat antrian\n"
        printf "2. Tambah (scan aplikasi terinstall)\n"
        printf "3. Hapus\n"
        printf "4. Kembali\n"
        printf "Pilih: "
        read -r sub
        case "$sub" in
            1) lihat_antrian ;;
            2) tambah_antrian ;;
            3) hapus_antrian ;;
            4) return ;;
            *) echo "Pilihan tidak dikenal."; pause ;;
        esac
    done
}

# ------------------------------------------------------------
# 3. JALANKAN
# ------------------------------------------------------------
jalankan() {
    printf "\n=== JALANKAN ANTRIAN ===\n"
    if [ ! -s "$QUEUE_FILE" ]; then
        echo "(antrian kosong, tidak ada yang dijalankan)"
        pause
        return
    fi
    while IFS= read -r pkg; do
        [ -z "$pkg" ] && continue
        printf "Menjalankan %s ... " "$pkg"
        out=$(am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p "$pkg" 2>&1)
        if echo "$out" | grep -qi "Error\|Exception\|Denial"; then
            echo "GAGAL"
            echo "  -> $out"
        else
            echo "OK"
        fi
        sleep 1
    done < "$QUEUE_FILE"
    pause
}

# ------------------------------------------------------------
# 4. STOP (stop 1 aplikasi pilihan dari antrian)
# ------------------------------------------------------------
stop_app() {
    printf "\n=== STOP APLIKASI ===\n"
    if [ ! -s "$QUEUE_FILE" ]; then
        echo "(antrian kosong)"
        pause
        return
    fi
    nl -w2 -s". " "$QUEUE_FILE"
    printf "\nPilih nomor aplikasi yang mau di-stop: "
    read -r no
    pkg=$(sed -n "${no}p" "$QUEUE_FILE")
    if [ -z "$pkg" ]; then
        echo "Nomor tidak valid."
    else
        am force-stop "$pkg" 2>/dev/null
        echo "Stopped: $pkg"
    fi
    pause
}

# ------------------------------------------------------------
# 5. CLOSE ALL (semua aplikasi, tidak terbatas di antrian)
# ------------------------------------------------------------
close_all() {
    printf "\n=== CLOSE ALL APLIKASI ===\n"
    printf "Ini akan force-stop SEMUA aplikasi pihak ketiga yang terinstall. Lanjut? (y/n): "
    read -r yakin
    if [ "$yakin" != "y" ] && [ "$yakin" != "Y" ]; then
        echo "Dibatalkan."
        pause
        return
    fi
    pm list packages -3 2>/dev/null | sed 's/^package://' | while IFS= read -r pkg; do
        [ -z "$pkg" ] && continue
        am force-stop "$pkg" 2>/dev/null
        echo "Stopped: $pkg"
    done
    echo "Selesai close all."
    pause
}

# ------------------------------------------------------------
# 6. AUTO CLEAR CACHE
# ------------------------------------------------------------
auto_clear_cache() {
    printf "\n=== AUTO CLEAR CACHE ===\n"
    echo "Trim cache sistem (tanpa root)..."
    pm trim-cache 999G >/dev/null 2>&1 && echo "Cache berhasil di-trim." || echo "Gagal trim-cache (device mungkin tidak mendukung)."

    if [ "$(id -u 2>/dev/null)" = "0" ]; then
        printf "Root terdeteksi. Hapus folder cache per aplikasi di antrian juga? (y/n): "
        read -r r
        if [ "$r" = "y" ] || [ "$r" = "Y" ]; then
            while IFS= read -r pkg; do
                [ -z "$pkg" ] && continue
                rm -rf "/data/data/$pkg/cache/"* 2>/dev/null
                echo "Cache dihapus: $pkg"
            done < "$QUEUE_FILE"
        fi
    fi
    pause
}

# ------------------------------------------------------------
# MENU UTAMA (looping)
# ------------------------------------------------------------
while true; do
    clear
    printf "==============================\n"
    printf "         APP MANAGER\n"
    printf "==============================\n"
    printf "1. Input link\n"
    printf "2. Kelola\n"
    printf "3. Jalankan\n"
    printf "4. Stop\n"
    printf "5. Close all\n"
    printf "6. Auto clear cache\n"
    printf "0. Keluar\n"
    printf "==============================\n"
    printf "Pilih menu: "
    read -r menu

    case "$menu" in
        1) input_link ;;
        2) kelola_menu ;;
        3) jalankan ;;
        4) stop_app ;;
        5) close_all ;;
        6) auto_clear_cache ;;
        0) echo "Keluar."; exit 0 ;;
        *) echo "Pilihan tidak dikenal."; pause ;;
    esac
done
