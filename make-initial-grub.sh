#!/bin/bash

set -eu

if [ ! -f ./grub-initial.cfg ]; then
    echo "You must execute this script in the same folder where grub-initial.cfg lives"
    exit 1;
fi

GPG_KEY='7CDC4589'
TARGET_EFI='/boot/efi/EFI/debian/grubx64_signed.efi'
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
TMP_GPG_KEY="$SECTEMP/gpg.key"
TMP_GRUB_CFG="$SECTEMP/grub-initial.cfg"
TMP_GRUB_SIG="$TMP_GRUB_CFG.sig"
TMP_GRUB_EFI="$SECTEMP/grubx64_signed.efi"

gpg --export "$GPG_KEY" >"$TMP_GPG_KEY"

cp grub-initial.cfg "$TMP_GRUB_CFG"
rm -f "$TMP_GRUB_SIG"
gpg --default-key "$GPG_KEY" --detach-sign "$TMP_GRUB_CFG"

grub-mkstandalone \
    --directory /usr/lib/grub/x86_64-efi \
    --format x86_64-efi \
    --modules "$MODULES" \
    --pubkey "$TMP_GPG_KEY" \
    --output "$TMP_GRUB_EFI" \
    "boot/grub/grub.cfg=$TMP_GRUB_CFG" \
    "boot/grub/grub.cfg.sig=$TMP_GRUB_SIG"

# sign the initial grub
sbsign --key "$SECUREBOOT_DB_KEY" --cert "$SECUREBOOT_DB_CRT" \
    --output "$TMP_GRUB_EFI" "$TMP_GRUB_EFI"

echo "writing signed grub.efi to '$TARGET_EFI'"
cp "$TMP_GRUB_EFI" "$TARGET_EFI"

# sign the existing kernel
for x in "/boot/grub/grub.cfg" "/boot/vmlinuz"* "/boot/initrd"*; do
    if [[ "$x" != *.sig ]]; then 
        name="$(basename "$x")"

        echo "signing '$x' to '$(dirname "$x")'"
        rm -f "$(dirname "$x")/$name.sig"
        gpg --default-key "$GPG_KEY" --detach-sign "$(dirname "$x")/$name"
    fi
done

rm -rf "$SECTEMP"
