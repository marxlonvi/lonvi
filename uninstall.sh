#!/system/bin/sh

# Memastikan skrip berjalan dengan akses root secara otomatis
if [ "$(id -u)" -ne 0 ]; then
  exec su -c "sh $0"
fi

clear
echo "========================================="
echo "       PILIH KATEGORI APLIKASI           "
echo "========================================="
echo "1. Aplikasi Sistem (System Apps)"
echo "2. Aplikasi Bawaan / Vendor"
echo "3. Aplikasi Pihak Ketiga (User Apps)"
echo "========================================="
read -p "Pilih kategori (1-3): " kat

case $kat in
  1)
    echo "Memuat daftar aplikasi sistem..."
    mapfile -t pkgs < <(pm list packages -s | sed 's/package://' | sort)
    ;;
  2)
    echo "Memuat daftar aplikasi bawaan..."
    mapfile -t pkgs < <(pm list packages -f | grep -E 'system/priv-app|system/app' | sed 's/.*=//' | sort)
    ;;
  3)
    echo "Memuat daftar aplikasi pihak ketiga..."
    mapfile -t pkgs < <(pm list packages -3 | sed 's/package://' | sort)
    ;;
  *)
    echo "Pilihan tidak valid!"
    exit 1
    ;;
esac

if [ ${#pkgs[@]} -eq 0 ]; then
  echo "Tidak ada aplikasi ditemukan dalam kategori ini."
  exit 1
fi

clear
echo "========================================="
echo "       DAFTAR APLIKASI TERSEDIA          "
echo "========================================="
for i in "${!pkgs[@]}"; do
  num=$((i + 1))
  echo "$num. ${pkgs[$i]}"
done
echo "========================================="
echo "Tips: Masukkan nomor yang ingin dihapus dengan dipisah spasi (contoh: 3 6 8)"
read -p "Pilih nomor aplikasi: " -a choices

if [ ${#choices[@]} -eq 0 ]; then
  echo "Tidak ada nomor yang dipilih."
  exit 1
fi

echo ""
echo "-----------------------------------------"
echo "PROSES PENGHAPUSAN APLIKASI:"
echo "-----------------------------------------"

for choice in "${choices[@]}"; do
  if [[ "$choice" =~ ^[0-9]+$ ]]; then
    index=$((choice - 1))
    if [ $index -ge 0 ] && [ $index -lt ${#pkgs[@]} ]; then
      target="${pkgs[$index]}"
      echo "Menghapus: $target..."
      pm uninstall --user 0 "$target"
    else
      echo "Nomor $choice di luar jangkauan, dilewati."
    fi
  else
    echo "Input '$choice' bukan angka yang valid, dilewati."
  fi
done

echo "-----------------------------------------"
echo "Selesai!"
