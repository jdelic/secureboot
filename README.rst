# commands

.. code-block::

    openssl genrsa -aes256 -out db.key 2048
    openssl genrsa -aes256 -out KEK.key 2048
    openssl genrsa -aes256 -out PK.key 2048

    openssl req -new -x509 -key db.key -subj '/O=maurus.networks GmbH/CN=XPS13_2 db/' -out db.cr
    openssl req -new -x509 -key KEK.key -subj '/O=maurus.networks GmbH/CN=XPS13_2 KEK/' -out KEK.crt
    openssl req -new -x509 -key PK.key -subj '/O=maurus.networks GmbH/CN=XPS13_2 PK/' -out PK.crt

    cert-to-efi-sig-list PK.crt PK.esl
    cert-to-efi-sig-list db.crt db.esl
    cert-to-efi-sig-list KEK.crt KEK.esl

    sign-efi-sig-list -k PK.key -c PK.crt PK PK.esl PK.auth
    sign-efi-sig-list -k PK.key -c PK.crt KEK KEK.esl KEK.auth
    sign-efi-sig-list -k KEK.key -c KEK.crt db db.esl db.auth

The ``.auth`` files can be easily imported in the Dell BIOS by copying them to
the EFI vfat partitions and clicking "import" in the BIOS.

Use 1000000 PBKDF2 iterations for the grub2 user password.

After running `make-initial-grub.sh` add the signed GRUB UEFI loader like this:

.. code-block::

    efibootmgr -c -l '\EFI\debian\grubx64_signed.efi' -L "debian signed" -w -p 1 -d /dev/nvme0n1

Once Secure Boot is enabled, only this UEFI entry will work. I would leave the
"Debian package managed" UEFI entry alone. It can be useful to boot the system
after turning Secure Boot off in the BIOS for a rescue attempt.

