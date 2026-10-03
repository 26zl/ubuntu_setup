#!/usr/bin/env bash
# Windows 11 guest on libvirt/KVM: UEFI + Secure Boot, emulated TPM 2.0 (swtpm),
# virtio disk and network, q35, SPICE. The `default` storage pool is created when
# missing, and both ISOs are uploaded into it because the pool is root-owned and
# home directories are not readable by libvirt-qemu.
#
#   bash scripts/new-windows-vm.sh --prepare                    # pool + virtio driver ISO only
#   bash scripts/new-windows-vm.sh ~/Downloads/Win11.iso        # create and start "win11"
#   bash scripts/new-windows-vm.sh ~/Downloads/Win11.iso lab    # another name
#   bash scripts/new-windows-vm.sh ~/Downloads/Win11.iso --dry-run
#
# Windows 11 ISO: https://www.microsoft.com/software-download/windows11 (browser only).
# During setup pick "Load driver" and choose the virtio-win CD, viostor\w11\amd64;
# after the first boot run virtio-win-guest-tools.exe from the same CD.
# Needs the libvirt group (log out and in after apply-system.sh).
set -euo pipefail

TEAL='\033[38;2;136;192;208m'
RED='\033[38;2;191;97;106m'
RESET='\033[0m'
ok()   { echo -e "  ${TEAL}✓${RESET} $1"; }
info() { echo -e "  ${TEAL}→${RESET} $1"; }
die()  { echo -e "  ${RED}!${RESET} $1" >&2; exit 1; }

URI=qemu:///system
# virtio-win pinned to a release directory and its SHA-256: the stable-virtio/
# alias redirects to plain http and moves between versions. The project publishes
# MD5 sums for its RPMs only, so the ISO hash is trust-on-first-download; a new
# upstream release means updating all four VIRTIO_* values.
VIRTIO_DIR=https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.302-1
VIRTIO_ISO=virtio-win-0.1.302.iso
VIRTIO_SHA256=303f7ae40dad495d6ae474fdc571df58958a4dbc5c37a522d80f9a203867949d
VIRTIO_SIZE=877373440
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/virtio-win.iso"
RAM_MIB=8192
VCPUS=4
DISK_GIB=80

iso=""; name=win11; DRY=0; PREPARE=0
for arg in "$@"; do
    case "$arg" in
        --prepare) PREPARE=1 ;;
        --dry-run) DRY=1 ;;
        -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) if [ -z "$iso" ] && [ "$PREPARE" -eq 0 ]; then iso=$arg; else name=$arg; fi ;;
    esac
done
[ "$EUID" -ne 0 ] || die "run as your user, not root (the libvirt group is enough)"
command -v virt-install >/dev/null || die "virt-install missing: run apply-system.sh (virt group)"
id -nG | grep -qw libvirt || die "not in the libvirt group yet; log out and in"
if [ "$PREPARE" -eq 0 ]; then
    [ -n "$iso" ] || { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
    [ -r "$iso" ] || die "cannot read $iso"
fi
v() { virsh -c "$URI" "$@"; }

# upload FILE VOLNAME — copy an ISO into the pool through the daemon (raw volume)
upload() {
    local file=$1 vol=$2 size
    if v vol-info --pool default "$vol" >/dev/null 2>&1; then ok "$vol already in the pool"; return 0; fi
    size=$(stat -c %s "$file")
    v vol-create-as default "$vol" "$size" --format raw >/dev/null
    v vol-upload --pool default "$vol" "$file" >/dev/null ||
        { v vol-delete --pool default "$vol" >/dev/null 2>&1; die "upload of $vol failed; volume removed"; }
    ok "$vol uploaded ($((size / 1024 / 1024)) MB)"
}
virtio_ok() { echo "$VIRTIO_SHA256  $CACHE" | sha256sum -c --quiet - 2>/dev/null; }

if [ "$DRY" -eq 1 ]; then
    info "dry run: storage pool, virtio ISO download and ISO uploads skipped"
# storage pool: virt-manager normally creates it on first launch; the daemon
# does the directory work as root, no sudo needed
elif ! v pool-info default >/dev/null 2>&1; then
    v pool-define-as default dir --target /var/lib/libvirt/images >/dev/null
    v pool-build default >/dev/null
    v pool-start default >/dev/null
    v pool-autostart default >/dev/null
    ok "storage pool 'default' created at /var/lib/libvirt/images"
else
    v pool-start default >/dev/null 2>&1 || true
    ok "storage pool 'default' present"
fi

# virtio drivers (storage, network, balloon, guest tools) from the Fedora project
if [ "$DRY" -eq 1 ]; then
    :
elif ! v vol-info --pool default virtio-win.iso >/dev/null 2>&1; then
    # a partial download is resumed; a complete file that is not this release is replaced
    if [ -s "$CACHE" ] && ! virtio_ok && [ "$(stat -c %s "$CACHE")" -ge "$VIRTIO_SIZE" ]; then
        info "cached ISO is not $VIRTIO_ISO; downloading again"; rm -f "$CACHE"
    fi
    if ! virtio_ok; then
        info "downloading $VIRTIO_ISO ($((VIRTIO_SIZE / 1024 / 1024)) MB)"
        curl --fail --location --progress-bar --proto '=https' --tlsv1.2 --continue-at - "$VIRTIO_DIR/$VIRTIO_ISO" -o "$CACHE"
        virtio_ok || { rm -f "$CACHE"; die "checksum mismatch: $VIRTIO_ISO (removed; run again, or update VIRTIO_* for a new release)"; }
    fi
    ok "$VIRTIO_ISO verified (SHA-256)"
    upload "$CACHE" virtio-win.iso
else
    ok "virtio-win.iso already in the pool"
fi
if [ "$PREPARE" -eq 1 ]; then
    [ "$DRY" -eq 1 ] || ok "prepared; run again with the Windows ISO"
    exit 0
fi

winvol=$(basename "$iso")
[ "$DRY" -eq 1 ] || upload "$iso" "$winvol"
win_path=$(v vol-path --pool default "$winvol" 2>/dev/null || echo "/var/lib/libvirt/images/$winvol")
virtio_path=$(v vol-path --pool default virtio-win.iso 2>/dev/null || echo /var/lib/libvirt/images/virtio-win.iso)

args=(
    --connect "$URI" --name "$name" --osinfo win11
    --memory "$RAM_MIB" --vcpus "$VCPUS" --cpu host-passthrough
    --machine q35
    --boot "firmware=efi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=yes"
    --tpm "model=tpm-crb,backend.type=emulator,backend.version=2.0"
    --disk "pool=default,size=$DISK_GIB,format=qcow2,bus=virtio,discard=unmap"
    --cdrom "$win_path"
    --disk "path=$virtio_path,device=cdrom,bus=sata"
    --network "network=default,model=virtio"
    --graphics spice --video virtio
)
if [ "$DRY" -eq 1 ]; then
    info "would run: virt-install ${args[*]}"
    exit 0
fi
info "creating $name ($VCPUS vCPU, $((RAM_MIB / 1024)) GiB RAM, $DISK_GIB GiB disk); virt-viewer opens the console"
virt-install "${args[@]}"
ok "$name created; manage it in virt-manager"
