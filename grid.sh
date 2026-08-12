#!/system/bin/sh
# ============================================================
# grid_split.sh
# Auto setup grid split-window (freeform) untuk N instance app
# Support Android 10 (freeform experimental) & Android 12+
# Sistem INTERAKTIF: minta input jumlah split, bisa diulang.
#
# CATATAN PENTING:
# 1. Butuh akses ADB shell (dijalankan via `adb shell` dari PC,
#    atau Termux dengan adb over wifi ke device sendiri).
# 2. Freeform window cuma mengatur POSISI/UKURAN window, bukan
#    membuat banyak instance dari 1 APK yang sama. Karena kamu
#    sudah punya clone package (com.roblox.clienu s/d clienz),
#    script ini akan pakai clone-clone itu, satu package per grid.
# 3. Jalankan: sh grid_split.sh
#    Lalu ikuti prompt untuk memasukkan jumlah split.
# ============================================================

set -e

# ------------------------------------------------------------
# Daftar package clone yang sudah kamu siapkan.
# Kalau clone kamu beda jumlah/pola, edit BASE_PKG & SUFFIXES.
# ------------------------------------------------------------
BASE_PKG="com.roblox.clien"
SUFFIXES="u v w x y z"
MAX_AVAILABLE=$(echo $SUFFIXES | wc -w)

setup_android_freeform() {
  echo "== Deteksi versi Android =="
  SDK=$(getprop ro.build.version.sdk)
  REL=$(getprop ro.build.version.release)
  echo "Android release: $REL (SDK $SDK)"

  echo "== Mengaktifkan freeform & resizable activities =="
  settings put global development_settings_enabled 1
  settings put global force_resizable_activities 1
  settings put global enable_freeform_support 1

  if [ "$SDK" -le 29 ]; then
    echo "-> Android 10 terdeteksi, set window manager flag tambahan"
    wm set-fixed-to-user-rotation enabled 2>/dev/null || true
    settings put global sys_can_enter_freeform 1 2>/dev/null || true
  fi
}

calc_grid() {
  n=$1
  cols=1
  while [ $((cols * cols)) -lt "$n" ]; do
    cols=$((cols + 1))
  done
  rows=$(( (n + cols - 1) / cols ))
  echo "$rows $cols"
}

run_grid_split() {
  n_split="$1"
  targets="$2"

  SIZE_LINE=$(wm size | tail -1)
  SCREEN_W=$(echo "$SIZE_LINE" | sed -E 's/.*: ([0-9]+)x([0-9]+)/\1/')
  SCREEN_H=$(echo "$SIZE_LINE" | sed -E 's/.*: ([0-9]+)x([0-9]+)/\2/')
  echo "Ukuran layar terdeteksi: ${SCREEN_W}x${SCREEN_H}"

  GRID=$(calc_grid "$n_split")
  ROWS=$(echo "$GRID" | awk '{print $1}')
  COLS=$(echo "$GRID" | awk '{print $2}')
  echo "Grid layout: ${ROWS} baris x ${COLS} kolom (untuk $n_split window)"

  CELL_W=$((SCREEN_W / COLS))
  CELL_H=$((SCREEN_H / ROWS))

  set -- $targets  # positional params $1..$n_split sekarang isi package list

  idx=0
  for r in $(seq 0 $((ROWS - 1))); do
    for c in $(seq 0 $((COLS - 1))); do
      [ "$idx" -ge "$n_split" ] && break

      idx1=$((idx + 1))
      CUR_PKG=$(eval echo \$$idx1)

      LEFT=$((c * CELL_W))
      TOP=$((r * CELL_H))
      RIGHT=$((LEFT + CELL_W))
      BOTTOM=$((TOP + CELL_H))

      echo "-> Launch $CUR_PKG (instance $idx1/$n_split) di posisi (${LEFT},${TOP})-(${RIGHT},${BOTTOM})"

      MAIN_ACTIVITY=$(cmd package resolve-activity --brief "$CUR_PKG" 2>/dev/null | tail -1)

      if [ -n "$MAIN_ACTIVITY" ] && [ "$MAIN_ACTIVITY" != "No activity found" ]; then
        am start --windowingMode 5 -n "$MAIN_ACTIVITY" >/dev/null 2>&1
      else
        echo "   (main activity tidak ketemu, coba start lewat package langsung)"
        am start --windowingMode 5 "$CUR_PKG" >/dev/null 2>&1
      fi

      sleep 1.5

      # Format dumpsys berbeda-beda per device/versi Android:
      # ada yang pakai "taskId=NUM", ada yang pakai "TaskRecord{... #NUM ...}"
      TASK_ID=$(dumpsys activity activities | grep "TaskRecord{.*$CUR_PKG" | head -1 | sed -E 's/.*#([0-9]+).*/\1/')
      if [ -z "$TASK_ID" ]; then
        TASK_ID=$(dumpsys activity activities | grep -A2 "$CUR_PKG" | grep "taskId=" | head -1 | sed -E 's/.*taskId=([0-9]+).*/\1/')
      fi

      if [ -n "$TASK_ID" ]; then
        am task resize "$TASK_ID" "$LEFT" "$TOP" "$RIGHT" "$BOTTOM" 2>/dev/null || \
          echo "   (gagal resize taskId $TASK_ID, mungkin app tidak resizable)"
      else
        echo "   (taskId tidak ketemu untuk $CUR_PKG, lewati resize)"
      fi

      idx=$((idx + 1))
    done
  done

  echo "== Selesai. $idx window sudah di-setup dalam grid ${ROWS}x${COLS} =="
}

# ------------------------------------------------------------
# Setup freeform sekali di awal (cukup 1x per sesi ADB)
# ------------------------------------------------------------
setup_android_freeform

# ------------------------------------------------------------
# Loop input interaktif: minta jumlah split berulang kali
# ------------------------------------------------------------
while true; do
  echo ""
  echo "=== Grid Split Setup ==="
  echo "Package tersedia: $MAX_AVAILABLE (huruf: $SUFFIXES)"
  printf "Masukkan jumlah split (1-%s), atau 'q' untuk keluar: " "$MAX_AVAILABLE"
  read N

  case "$N" in
    q|Q|quit|exit) echo "Keluar dari script."; exit 0 ;;
  esac

  case "$N" in
    ''|*[!0-9]*)
      echo "!! Input tidak valid, masukkan angka."
      continue
      ;;
  esac

  if [ "$N" -lt 1 ] || [ "$N" -gt "$MAX_AVAILABLE" ]; then
    echo "!! Jumlah split harus antara 1 sampai $MAX_AVAILABLE."
    continue
  fi

  TARGETS=""
  i=0
  for s in $SUFFIXES; do
    [ "$i" -ge "$N" ] && break
    TARGETS="$TARGETS ${BASE_PKG}${s}"
    i=$((i + 1))
  done

  echo "Package yang akan dipakai:$TARGETS"
  run_grid_split "$N" "$TARGETS"

  echo ""
  printf "Mau setup grid lagi dengan jumlah lain? (y/n): "
  read AGAIN
  case "$AGAIN" in
    y|Y|yes) continue ;;
    *) echo "Selesai. Keluar dari script."; exit 0 ;;
  esac
done
