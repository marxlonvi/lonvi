#!/system/bin/sh

# Memastikan skrip berjalan dengan akses root secara otomatis
if [ "$(id -u)" -ne 0 ]; then
  SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null)"
  [ -z "$SCRIPT_PATH" ] && SCRIPT_PATH="$0"
  exec su -c "sh '$SCRIPT_PATH'"
fi

TMPLIST="/data/local/tmp/pkglist_$$.txt"
trap 'rm -f "$TMPLIST"' EXIT

clear
echo "========================================="
echo "       PILIH KATEGORI APLIKASI           "
echo "========================================="
echo "1. Aplikasi Sistem (System Apps)"
echo "2. Aplikasi Bawaan / Vendor"
echo "3. Aplikasi Pihak Ketiga (User Apps)"
echo "========================================="
printf "Pilih kategori (1-3): "
read kat

case $kat in
  1)
    echo "Memuat daftar aplikasi sistem..."
    pm list packages -s | sed 's/package://' | sort > "$TMPLIST"
    ;;
  2)
    echo "Memuat daftar aplikasi bawaan..."
    pm list packages -f | grep -E 'system/priv-app|system/app' | sed 's/.*=//' | sort > "$TMPLIST"
    ;;
  3)
    echo "Memuat daftar aplikasi pihak ketiga..."
    pm list packages -3 | sed 's/package://' | sort > "$TMPLIST"
    ;;
  *)
    echo "Pilihan tidak valid!"
    exit 1
    ;;
esac

total=$(wc -l < "$TMPLIST" | tr -d ' ')

if [ "$total" -eq 0 ]; then
  echo "Tidak ada aplikasi ditemukan dalam kategori ini."
  exit 1
fi

clear
echo "========================================="
echo "       DAFTAR APLIKASI TERSEDIA          "
echo "========================================="
i=0
while IFS= read -r line; do
  i=$((i + 1))
  echo "$i. $line"
done < "$TMPLIST"
echo "========================================="
echo "Tips: Masukkan nomor yang ingin dihapus dengan dipisah spasi (contoh: 3 6 8)"
printf "Pilih nomor aplikasi: "
read choices

if [ -z "$choices" ]; then
  echo "Tidak ada nomor yang dipilih."
  exit 1
fi

echo ""
echo "-----------------------------------------"
echo "PROSES PENGHAPUSAN APLIKASI:"
echo "-----------------------------------------"

for choice in $choices; do
  case "$choice" in
    ''|*[!0-9]*)
      echo "Input '$choice' bukan angka yang valid, dilewati."
      continue
      ;;
  esac

  if [ "$choice" -ge 1 ] && [ "$choice" -le "$total" ]; then
    target=$(sed -n "${choice}p" "$TMPLIST")
    echo "Menghapus: $target..."
    pm uninstall --user 0 "$target"
  else
    echo "Nomor $choice di luar jangkauan, dilewati."
  fi
done

echo "-----------------------------------------"
echo "Selesai!"
