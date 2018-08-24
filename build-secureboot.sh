#!/bin/bash

set -eu

if [ ! -f ./grub-initial.cfg ]; then
    echo "You must execute this script in the same folder where grub-initial.cfg lives"
    exit 1;
fi

GPG_KEY='7CDC4589'
# Target Grub must be named grubx64.efi, because that's compiled into the shim
TARGET_GRUB_EFI='/boot/efi/EFI/debian/grubx64.efi'
TARGET_SHIM_EFI='/boot/efi/EFI/debian/shimx64.efi.signed'
SOURCE_SHIM='/usr/lib/shim/shimx64.efi'
SOURCE_GRUB='/boot/efi/EFI/debian/grubx64_signed.efi'
SECUREBOOT_DB_KEY='/home/jonas/jm/rescue/xps13_2/db.key'
SECUREBOOT_DB_CRT='/home/jonas/jm/rescue/xps13_2/db.crt'

# FIRST CREATE A STANDALONE GRUB BOOT LOADER THAT WE WILL USE
# ===========================================================
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
TMP_SHIM_EFI="$SECTEMP/shimx64.efi.signed"

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

# sign the initial standalone grub with the Machine Owner Key (MOK)
echo "EFI: Signing the GRUB bootloader"
sbsign --key "$SECUREBOOT_DB_KEY" --cert "$SECUREBOOT_DB_CRT" \
    --output "$SOURCE_GRUB" "$TMP_GRUB_EFI"

# CREATE A SIGNED SHIM THAT LOADS THE MOK FROM UEFI AND VERIFIES FIRST
# GRUB AND THEN THE KERNEL
# ====================================================================
# sign the shim
echo "EFI: Signing the bootloader Shim"
sbsign --key "$SECUREBOOT_DB_KEY" --cert "$SECUREBOOT_DB_CRT" \
    --output "$TMP_SHIM_EFI" "$SOURCE_SHIM"

# INSTALL THE SIGNED STANDALONE GRUB AND SHIM
echo "writing signed grub.efi to '$TARGET_GRUB_EFI'"
cp "$TMP_GRUB_EFI" "$TARGET_GRUB_EFI"
echo "writing signed shim efi to '$TARGET_SHIM_EFI'"
cp "$TMP_SHIM_EFI" "$TARGET_SHIM_EFI"

rm -rf $SECTEMP

# SIGN THE CURRENT KERNEL WITH THE MOK
# ====================================
# EFI sign the existing kernel
rm -f /boot/*.signed.sig
rm -f /boot/*.signed
CURKERNEL="/$(readlink /vmlinuz)"
name="$(basename "$CURKERNEL")"
echo "EFI signing '$CURKERNEL' to '$(dirname "$CURKERNEL")'"
rm -f "$(dirname "$CURKERNEL")/$name.signed"
sbsign --key "$SECUREBOOT_DB_KEY" --cert "$SECUREBOOT_DB_CRT" \
    --output "$(dirname "$CURKERNEL")/$name.efi.signed" "$(dirname "$CURKERNEL")/$name"

# NOW FINALLY SIGN KERNEL AND INITRD WITH THE GPG KEY EMBEDDED IN THE 
# STANDALONE GRUB
# ===================================================================
# sign the existing kernel
for x in "/boot/grub/grub.cfg" "$CURKERNEL.efi.signed" "/$(readlink /initrd.img)"; do
    name="$(basename "$x")"
    echo "GPG signing '$x' to '$(dirname "$x")'"
    rm -f "$(dirname "$x")/$name.sig"
    gpg --default-key "$GPG_KEY" --detach-sign "$(dirname "$x")/$name"
done

# VERIFY THAT THE SIGNED SHIM IS REGISTERED IN THE EFI AND THAT WE HAVE A 
# NON-SECUREBOOT FALLBACK
# 
if ! efibootmgr --verbose | grep shimx64.efi.signed; then
    echo ""
    echo "***************************************************************"
    echo "ALERT!!! No signed boot entry in EFI boot config"
    echo "***************************************************************"
    echo ""
    echo "You probably want to delete the current entries and create new ones:"
    echo "    efibootmgr -B -b 0000"
    echo "    efibootmgr -c -l '\\EFI\\debian\\shimx64.efi.signed' -L \"debian secureboot\" -e 3 -w -p 1 -d /dev/nvme0n1"
    echo "    efibootmgr -c -l '\\EFI\\debian\\grubx64.efi' -L \"debian\" -e 3 -w -p 1 -d /dev/nvme0n1"
fi

