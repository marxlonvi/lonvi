#!/system/bin/sh

# Memastikan skrip berjalan dengan akses root secara otomatis
if [ "$(id -u)" -ne 0 ]; then
  SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null)"
  [ -z "$SCRIPT_PATH" ] && SCRIPT_PATH="$0"
  exec su -c "sh '$SCRIPT_PATH'"
fi

TMPLIST="/data/local/tmp/pkglist_$$.txt"
SAFELIST="/data/local/tmp/safelist_$$.txt"
trap 'rm -f "$TMPLIST" "$SAFELIST" "$TMPLIST.all"' EXIT

# Daftar paket sistem yang UMUMNYA AMAN dihapus (bloat/opsional, bukan komponen inti)
cat > "$SAFELIST" << 'EOF'
com.android.bips
com.android.bookmarkprovider
com.android.calllogbackup
com.android.carrierdefaultapp
com.android.cts.ctsshim
com.android.cts.priv.ctsshim
com.android.dreams.basic
com.android.dynsystem
com.android.egg
com.android.hotspot2
com.android.htmlviewer
com.android.managedprovisioning
com.android.messaging
com.android.musicfx
com.android.nfc
com.android.ons
com.android.pacprocessor
com.android.printservice.recommendation
com.android.protips
com.android.proxyhandler
com.android.se
com.android.sharedstoragebackup
com.android.simappdialog
com.android.soundrecorder
com.android.statementservice
com.android.toolkit
com.android.tools
com.android.traceur
com.android.vpndialogs
com.android.wallpaper.livepicker
com.android.wallpaperbackup
com.baidu.cloud.service
com.google.android.gsf.login
com.wshl.file.observerservice
com.android.backupconfirm
com.android.captiveportallogin
com.android.certinstaller
com.android.companiondevicemanager
com.android.mtp
com.android.printspooler
com.android.providers.downloads.ui
com.android.providers.userdictionary
com.android.soundpicker
com.google.android.play.games
net.sourceforge.opencamera
com.android.deskclock
com.android.dreams.phototable
com.android.gallery3d
com.android.hotspot2.osulogin
com.android.market
com.android.modulemetadata
com.android.monitor
com.android.music
com.android.provider.apt
com.android.provider.patch
com.android.provider.proxy
com.android.provider.root
com.android.provider.xmonitor
com.android.provision
com.android.quicksearchbox
com.android.storagemanager
com.android.wallpapercropper
com.android.wallpaperpicker
com.google.android.apps.nbu.files
com.android.bluetoothmidiservice
com.android.plugin
com.android.theme.color.black
com.android.theme.color.cinnamon
com.android.theme.color.green
com.android.theme.color.ocean
com.android.theme.color.orchid
com.android.theme.color.purple
com.android.theme.color.space
com.android.theme.font.notoserifsource
com.android.theme.icon.roundedrect
com.android.theme.icon.squircle
com.android.theme.icon.teardrop
com.android.theme.icon_pack.circular.android
com.android.theme.icon_pack.circular.launcher
com.android.theme.icon_pack.circular.settings
com.android.theme.icon_pack.circular.systemui
com.android.theme.icon_pack.circular.themepicker
com.android.theme.icon_pack.filled.android
com.android.theme.icon_pack.filled.launcher
com.android.theme.icon_pack.filled.settings
com.android.theme.icon_pack.filled.systemui
com.android.theme.icon_pack.filled.themepicker
com.android.theme.icon_pack.rounded.android
com.android.theme.icon_pack.rounded.launcher
com.android.theme.icon_pack.rounded.settings
com.android.theme.icon_pack.rounded.systemui
com.android.cellbroadcastreceiver
com.android.mms.service
com.android.phone
com.android.providers.blockednumber
com.android.providers.contacts
com.android.providers.telephony
com.android.server.telecom
com.android.smspush
com.android.providers.calendar
com.android.vending
com.android.location.fused
com.android.calendar
com.android.carrierconfig
com.android.contacts
com.android.dialer
com.android.email
com.android.settings.intelligence
com.android.bluetooth
EOF

pause() {
  echo ""
  printf "Tekan Enter untuk kembali ke menu utama..."
  read _dummy
}

# Pilih daftar aplikasi dari kategori 1/2/3, lalu hapus manual (dengan opsi kembali)
manual_uninstall() {
  category_label="$1"

  while true; do
    total=$(wc -l < "$TMPLIST" | tr -d ' ')
    if [ "$total" -eq 0 ]; then
      echo "Tidak ada aplikasi ditemukan dalam kategori ini."
      pause
      return
    fi

    clear
    echo "========================================="
    echo "  DAFTAR APLIKASI: $category_label"
    echo "========================================="
    i=0
    while IFS= read -r line; do
      i=$((i + 1))
      echo "$i. $line"
    done < "$TMPLIST"
    echo "========================================="
    echo "Tips: nomor dipisah spasi (contoh: 3 6 8)"
    echo "Ketik 0 (atau kosongkan) untuk kembali ke menu utama"
    printf "Pilih nomor aplikasi: "
    read choices

    if [ -z "$choices" ] || [ "$choices" = "0" ]; then
      return
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
    pause
    return
  done
}

safe_uninstall() {
  echo "Mencocokkan aplikasi dengan daftar aman..."
  pm list packages -s | sed 's/package://' | sort > "$TMPLIST.all"
  grep -Fxf "$SAFELIST" "$TMPLIST.all" > "$TMPLIST"
  rm -f "$TMPLIST.all"

  total=$(wc -l < "$TMPLIST" | tr -d ' ')
  if [ "$total" -eq 0 ]; then
    echo "Tidak ada aplikasi dari daftar aman yang ditemukan di perangkat ini."
    pause
    return
  fi

  clear
  echo "========================================="
  echo "  DAFTAR APLIKASI AMAN UNTUK DIHAPUS     "
  echo "========================================="
  i=0
  while IFS= read -r line; do
    i=$((i + 1))
    echo "$i. $line"
  done < "$TMPLIST"
  echo "========================================="
  echo "Semua di atas AKAN DIHAPUS, KECUALI yang kamu masukkan nomornya."
  echo "Contoh: simpan nomor 5 dan 12, ketik: 5 12"
  echo "Ketik 'batal' untuk kembali ke menu utama tanpa menghapus apa pun."
  echo "Kosongkan (Enter) jika ingin menghapus SEMUA daftar di atas."
  printf "Nomor yang DIKECUALIKAN (tidak dihapus): "
  read exclude

  if [ "$exclude" = "batal" ]; then
    return
  fi

  echo ""
  echo "-----------------------------------------"
  echo "PROSES PENGHAPUSAN APLIKASI (mode aman):"
  echo "-----------------------------------------"

  i=0
  while IFS= read -r target; do
    i=$((i + 1))
    skip=0
    for ex in $exclude; do
      if [ "$ex" = "$i" ]; then
        skip=1
        break
      fi
    done
    if [ "$skip" -eq 1 ]; then
      echo "Dilewati (dikecualikan): $target"
    else
      echo "Menghapus: $target..."
      pm uninstall --user 0 "$target"
    fi
  done < "$TMPLIST"

  echo "-----------------------------------------"
  echo "Selesai!"
  pause
}

while true; do
  clear
  echo "========================================="
  echo "       PILIH KATEGORI APLIKASI           "
  echo "========================================="
  echo "1. Aplikasi Sistem (System Apps)"
  echo "2. Aplikasi Bawaan / Vendor"
  echo "3. Aplikasi Pihak Ketiga (User Apps)"
  echo "4. Hapus Aman (rekomendasi, bisa kecualikan)"
  echo "0. Keluar"
  echo "========================================="
  printf "Pilih kategori (0-4): "
  read kat

  case $kat in
    1)
      echo "Memuat daftar aplikasi sistem..."
      pm list packages -s | sed 's/package://' | sort > "$TMPLIST"
      manual_uninstall "Aplikasi Sistem"
      ;;
    2)
      echo "Memuat daftar aplikasi bawaan..."
      pm list packages -f | grep -E 'system/priv-app|system/app' | sed 's/.*=//' | sort > "$TMPLIST"
      manual_uninstall "Aplikasi Bawaan / Vendor"
      ;;
    3)
      echo "Memuat daftar aplikasi pihak ketiga..."
      pm list packages -3 | sed 's/package://' | sort > "$TMPLIST"
      manual_uninstall "Aplikasi Pihak Ketiga"
      ;;
    4)
      safe_uninstall
      ;;
    0)
      echo "Keluar. Sampai jumpa!"
      exit 0
      ;;
    *)
      echo "Pilihan tidak valid!"
      pause
      ;;
  esac
done
