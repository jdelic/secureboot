#!/bin/bash

set -eu

if [ ! -f ./grub-initial.cfg ]; then
    echo "You must execute this script in the same folder where grub-initial.cfg lives"
    exit 1;
fi

TARGET_GRUB_EFI='/boot/efi/EFI/debian/grubx64.efi.signed'
TARGET_SHIM_EFI='/boot/efi/EFI/debian/shimx64.efi.signed'
SOURCE_SHIM='/usr/lib/shim/shimx64.efi'
SOURCE_GRUB='/boot/efi/EFI/debian/grubx64_signed.efi'
SECUREBOOT_DB_KEY='/home/jonas/jm/rescue/xps13_2/db.key'
SECUREBOOT_DB_CRT='/home/jonas/jm/rescue/xps13_2/db.crt'

# GRUB doesn't allow loading new modules from disk when secure boot is in
# effect, therefore pre-load the required modules.
MODULES=
MODULES="$MODULES part_gpt fat ext2"           # partition and file systems for EFI
MODULES="$MODULES configfile"                  # source command
MODULES="$MODULES verify gcry_sha512 gcry_rsa" # signature verification
MODULES="$MODULES password_pbkdf2"             # hashed password
MODULES="$MODULES echo normal linux linuxefi"  # boot linux
MODULES="$MODULES all_video"                   # video output
MODULES="$MODULES search search_fs_uuid"       # search --fs-uuid
MODULES="$MODULES reboot sleep"                # sleep, reboot
MODULES="$MODULES gzio test font gfxterm"      # others that I found missing
MODULES="$MODULES gfxterm_menu gfxterm_background"
MODULES="$MODULES gfxmenu efifwsetup"

SECTEMP=$(mktemp -d)
TMP_GRUB_EFI="$SECTEMP/grubx64.efi.signed"
TMP_SHIM_EFI="$SECTEMP/shimx64.efi.signed"

# sign the initial standalone grub
sbsign --key "$SECUREBOOT_DB_KEY" --cert "$SECUREBOOT_DB_CRT" \
    --output "$TMP_GRUB_EFI" "$SOURCE_GRUB"

# sign the shim
sbsign --key "$SECUREBOOT_DB_KEY" --cert "$SECUREBOOT_DB_CRT" \
    --output "$TMP_SHIM_EFI" "$SOURCE_SHIM"

echo "writing signed grub.efi to '$TARGET_GRUB_EFI'"
cp "$TMP_GRUB_EFI" "$TARGET_GRUB_EFI"
echo "writing signed shim efi to '$TARGET_SHIM_EFI'"
cp "$TMP_SHIM_EFI" "$TARGET_SHIM_EFI"

# sign the existing kernel
for x in "/boot/vmlinuz"*; do
    if [[ "$x" != *.signed ]]; then 
        name="$(basename "$x")"

        echo "signing '$x' to '$(dirname "$x")'"
	rm -f "$(dirname "$x")/$name.signed"
	sbsign --key "$SECUREBOOT_DB_KEY" --cert "$SECUREBOOT_DB_CRT" \
            --output "$(dirname "$x")/$name.signed" "$(dirname "$x")/$name"
    fi
done

rm -rf "$SECTEMP"

# sanity check to ensure that Debian hasn't (yet again) deleted the "debian signed" entry
if ! efibootmgr --verbose | grep shimx64.efi.signed; then
    echo ""
    echo "***************************************************************"
    echo "ALERT!!! No signed boot entry in EFI boot config"
    echo "***************************************************************"
    echo ""
    echo "You probably want to delete the current entries and create new ones:"
    echo "    efibootmgr -B -b 0000"
    echo "    efibootmgr -c -l '\\EFI\\debian\\shimx64.efi,signed' -L \"debian sbsigned\" -e 3 -w -p 1 -d /dev/nvme0n1"
    echo "    efibootmgr -c -l '\\EFI\\debian\\grubx64.efi' -L \"debian\" -e 3 -w -p 1 -d /dev/nvme0n1"
fi
