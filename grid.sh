#!/system/bin/sh
# ============================================================
# grid_split.sh (fixed)
# Auto setup grid split-window (freeform) untuk N instance app
# Versi ini VERBOSE (nampilin semua output) + retry logic buat
# nyari TASK_ID, biar ketauan persis gagal di step mana.
# ============================================================

set -e

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
  # Horizontal only: selalu 1 baris, N kolom sejajar ke samping.
  n=$1
  rows=1
  cols=$n
  echo "$rows $cols"
}

# Cari TASK_ID dengan retry, dan cover beberapa format dumpsys
# (lama & baru). Print baris mentah yang match biar bisa diperiksa.
find_task_id() {
  pkg="$1"
  tries=0
  max_tries=6
  while [ "$tries" -lt "$max_tries" ]; do
    RAW=$(dumpsys activity activities 2>/dev/null)

    # Format lama: TaskRecord{... #123 ...visible=true topActivity=ComponentInfo{pkg/...}}
    TID=$(echo "$RAW" | grep "TaskRecord{.*$pkg" | head -1 | sed -E 's/.*#([0-9]+).*/\1/')

    # Format taskId=NUM di baris/blok dekat package
    if [ -z "$TID" ]; then
      TID=$(echo "$RAW" | grep -A2 "$pkg" | grep "taskId=" | head -1 | sed -E 's/.*taskId=([0-9]+).*/\1/')
    fi

    # Format baru (Android 12+): "Task{... #123 ... A=uid:pkg}" atau "* Task{... #123 ...}"
    if [ -z "$TID" ]; then
      TID=$(echo "$RAW" | grep -E "Task\{.*#[0-9]+.*$pkg" | head -1 | sed -E 's/.*#([0-9]+).*/\1/')
    fi

    if [ -n "$TID" ]; then
      echo "$TID"
      return 0
    fi

    tries=$((tries + 1))
    sleep 1
  done
  echo ""
  return 1
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

  set -- $targets

  echo ""
  echo "== Bersihkan instance lama dari package target (biar ga numpuk sisa window) =="
  for pkg in $targets; do
    echo "-> force-stop $pkg"
    am force-stop "$pkg" 2>/dev/null || true
  done
  sleep 1

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
      # Kolom terakhir & baris terakhir dipaksa nyentuh tepi layar,
      # biar sisa pembulatan (SCREEN_W % COLS) gak nyisain strip kosong.
      [ "$c" -eq $((COLS - 1)) ] && RIGHT=$SCREEN_W
      [ "$r" -eq $((ROWS - 1)) ] && BOTTOM=$SCREEN_H

      echo ""
      echo "-> [$idx1/$n_split] Cek resizeability $CUR_PKG"
      RESIZEABLE=$(dumpsys package "$CUR_PKG" 2>/dev/null | grep -i "resizeableActivity" | head -1)
      echo "   $RESIZEABLE"

      echo "-> Launch $CUR_PKG target posisi (${LEFT},${TOP})-(${RIGHT},${BOTTOM})"

      MAIN_ACTIVITY=$(cmd package resolve-activity --brief "$CUR_PKG" 2>/dev/null | tail -1)

      if [ -n "$MAIN_ACTIVITY" ] && [ "$MAIN_ACTIVITY" != "No activity found" ]; then
        echo "   Launching via activity: $MAIN_ACTIVITY"
        am start --windowingMode 5 -n "$MAIN_ACTIVITY"
      else
        echo "   (main activity tidak ketemu, coba start lewat package langsung)"
        am start --windowingMode 5 "$CUR_PKG"
      fi

      echo "   Menunggu task terbentuk..."
      TASK_ID=$(find_task_id "$CUR_PKG")

      if [ -n "$TASK_ID" ]; then
        echo "   TaskId ditemukan: $TASK_ID -> resize"
        am task resize "$TASK_ID" "$LEFT" "$TOP" "$RIGHT" "$BOTTOM"
        sleep 0.5
        BOUNDS_CHECK=$(dumpsys activity activities 2>/dev/null | grep -A1 "#$TASK_ID " | grep -i "bounds=")
        echo "   Bounds sekarang: $BOUNDS_CHECK"
      else
        echo "   !! TaskId TIDAK ketemu untuk $CUR_PKG setelah beberapa percobaan."
        echo "   !! Kemungkinan: app belum kebuka sempurna, atau format dumpsys beda lagi."
        echo "   !! Coba jalankan manual: dumpsys activity activities | grep -B2 -A5 \"$CUR_PKG\""
      fi

      idx=$((idx + 1))
    done
  done

  echo ""
  echo "== Selesai. $idx window sudah diproses dalam grid ${ROWS}x${COLS} =="
}

setup_android_freeform

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
