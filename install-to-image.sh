#!/bin/bash

# ==============================================================================
# ARMBIAN-INSTALL-AMLOGIC — IMAGE INSTALLER
# Injects armbian-install-amlogic into an Armbian .img file via losetup,
# without requiring the system to be running on the target hardware.
# Usage: sudo ./install-to-image.sh <path-to-armbian.img>
# @uthor: Pedro Rigolin
# ==============================================================================

# ------------------------------------------------------------------------------
# ROOT PRIVILEGE CHECK
# ------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root!"
    exit 1
fi

# ------------------------------------------------------------------------------
# ARGUMENT VALIDATION
# ------------------------------------------------------------------------------
if [ -z "$1" ]; then
    echo "Usage: $0 <path-to-armbian.img>"
    echo ""
    echo "Example: sudo $0 /home/user/Armbian_24.11_amlogic.img"
    exit 1
fi

IMAGE_FILE="$1"

if [ ! -f "$IMAGE_FILE" ]; then
    echo "ERROR: Image file not found: $IMAGE_FILE"
    exit 1
fi

# ------------------------------------------------------------------------------
# SOURCE DIRECTORY
# ------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_SCRIPT="${SCRIPT_DIR}/armbian-install-amlogic.sh"
SRC_PROFILES_DIR="${SCRIPT_DIR}/armbian-install-amlogic/profiles"
SRC_ASSETS_DIR="${SCRIPT_DIR}/armbian-install-amlogic/assets"

# ------------------------------------------------------------------------------
# DESTINATION PATHS (inside the image)
# ------------------------------------------------------------------------------
DEST_BIN="/usr/bin/armbian-install-amlogic"
DEST_BASE="/etc/armbian-install-amlogic"
DEST_PROFILES_DIR="${DEST_BASE}/profiles"
DEST_ASSETS_DIR="${DEST_BASE}/assets"

# ------------------------------------------------------------------------------
# LOGGING
# ------------------------------------------------------------------------------
TEMP_LOG="/tmp/armbian-install-amlogic-image-installer.log"
BACKTITLE="ARMBIAN-INSTALL-AMLOGIC — Image Installer — by Pedro Rigolin"

echo "" > "$TEMP_LOG"

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" >> "$TEMP_LOG"
}

log_debug() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1" >> "$TEMP_LOG"
}

log_error() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$TEMP_LOG"
}

log_header() {
    echo -e "\n================================================================================" >> "$TEMP_LOG"
    echo -e "   $1" >> "$TEMP_LOG"
    echo -e "================================================================================\n" >> "$TEMP_LOG"
}

log_header "New Image Installer Session: $(date '+%d/%m/%Y %H:%M:%S')"
log "Script directory: $SCRIPT_DIR"
log "Target image: $IMAGE_FILE"

# ------------------------------------------------------------------------------
# WORK DIRECTORY
# ------------------------------------------------------------------------------
WORK_DIR="/mnt/armbian-image-installer-$$"
MNT_ROOTFS="${WORK_DIR}/rootfs"
LOOP_DEV=""

# ------------------------------------------------------------------------------
# CLEANUP FUNCTION
# ------------------------------------------------------------------------------
cleanup() {
    # Only attempt unmount if the directory is actually mounted
    if mountpoint -q "$MNT_ROOTFS" 2>/dev/null; then
        umount "$MNT_ROOTFS" 2>/dev/null
        umount -l "$MNT_ROOTFS" 2>/dev/null
    fi
    if [ -n "$LOOP_DEV" ]; then
        losetup -d "$LOOP_DEV" 2>/dev/null
        log_debug "Loop device detached: $LOOP_DEV"
    fi
    [ -d "$WORK_DIR" ] && rm -rf "$WORK_DIR" 2>/dev/null
}

trap 'tput cnorm; cleanup; clear; echo "Installer finished or interrupted."; exit' INT TERM EXIT

# ------------------------------------------------------------------------------
# DEPENDENCY CHECK
# This script runs on the host system, which may not be Debian/Ubuntu based.
# Dependencies are checked by binary availability only — no auto-install.
# ------------------------------------------------------------------------------
MISSING_BINS=()

command -v dialog  &>/dev/null || MISSING_BINS+=(dialog)
command -v pigz    &>/dev/null || MISSING_BINS+=(pigz)
command -v losetup &>/dev/null || MISSING_BINS+=(losetup)
command -v blkid   &>/dev/null || MISSING_BINS+=(blkid)
command -v fdisk   &>/dev/null || MISSING_BINS+=(fdisk)

if [ ${#MISSING_BINS[@]} -ne 0 ]; then
    echo "ERROR: The following required tools are missing on this system:"
    for bin in "${MISSING_BINS[@]}"; do
        echo "  - $bin"
    done
    echo ""
    echo "Please install them using your distribution's package manager and try again."
    exit 1
fi

# ------------------------------------------------------------------------------
# PRE-FLIGHT VALIDATION
# ------------------------------------------------------------------------------
log "Running pre-flight validation..."

if [ ! -f "$SRC_SCRIPT" ]; then
    dialog --backtitle "$BACKTITLE" \
        --title "Error" \
        --ok-label "OK" \
        --msgbox "\nInstaller script not found:\n  $SRC_SCRIPT\n\nEnsure you are running this from the repository root." 10 60
    log_error "Main script not found: $SRC_SCRIPT"
    exit 1
fi

if [ ! -d "$SRC_PROFILES_DIR" ]; then
    dialog --backtitle "$BACKTITLE" \
        --title "Error" \
        --ok-label "OK" \
        --msgbox "\nProfiles directory not found:\n  $SRC_PROFILES_DIR" 10 60
    log_error "Profiles directory not found: $SRC_PROFILES_DIR"
    exit 1
fi

if [ ! -d "$SRC_ASSETS_DIR" ]; then
    dialog --backtitle "$BACKTITLE" \
        --title "Error" \
        --ok-label "OK" \
        --msgbox "\nAssets directory not found:\n  $SRC_ASSETS_DIR" 10 60
    log_error "Assets directory not found: $SRC_ASSETS_DIR"
    exit 1
fi

# ------------------------------------------------------------------------------
# IMAGE VALIDATION & ROOTFS DETECTION
# Attaches the image as a loop device and identifies the rootfs partition.
# Expects a standard two-partition Armbian layout: BOOT (FAT32) + ROOT (ext4).
#
# Detection strategy:
#   1. losetup -fP attaches the image and creates one partition device per entry
#      in the partition table (e.g. /dev/loop0p1, /dev/loop0p2).
#   2. blkid probes each partition device for its filesystem type.
#   3. The first partition reporting TYPE="ext4" is selected as rootfs.
#
# blkid is used instead of lsblk because it reads the superblock directly from
# the device, making it reliable regardless of kernel udev settling delays that
# can cause lsblk to miss newly attached loop partitions.
# ------------------------------------------------------------------------------
dialog --backtitle "$BACKTITLE" \
    --title "Validating Image" \
    --infobox "\nAttaching image as loop device...\n\n  $(basename "$IMAGE_FILE")" 7 65

log "Attaching image: $IMAGE_FILE"

LOOP_DEV=$(losetup -fP --show "$IMAGE_FILE" 2>>"$TEMP_LOG")

if [ $? -ne 0 ] || [ -z "$LOOP_DEV" ]; then
    dialog --backtitle "$BACKTITLE" \
        --title "Error" \
        --ok-label "OK" \
        --msgbox "\nFailed to attach image as loop device.\n\nCheck the log for details:\n  $TEMP_LOG" 10 60
    log_error "losetup failed for: $IMAGE_FILE"
    exit 1
fi

log "Loop device attached: $LOOP_DEV"
log_debug "Partition table:"
fdisk -l "$LOOP_DEV" >> "$TEMP_LOG" 2>&1

# Probe each partition with blkid and select the first ext4
ROOTFS_PART=""
for part in "${LOOP_DEV}"p*; do
    [ -b "$part" ] || continue
    fs_type=$(blkid -o value -s TYPE "$part" 2>/dev/null)
    log_debug "Partition $part: TYPE=$fs_type"
    if [ "$fs_type" = "ext4" ]; then
        ROOTFS_PART="$part"
        break
    fi
done

if [ -z "$ROOTFS_PART" ]; then
    dialog --backtitle "$BACKTITLE" \
        --title "Error" \
        --ok-label "OK" \
        --msgbox "\nCould not identify a rootfs (ext4) partition in the image.\n\nThis installer expects a standard two-partition Armbian image.\nThe image may be unsupported or corrupt.\n\nCheck the log for details:\n  $TEMP_LOG" 12 65
    log_error "No ext4 partition found in $LOOP_DEV"
    exit 1
fi

log "Rootfs partition identified: $ROOTFS_PART"

# ------------------------------------------------------------------------------
# PROFILE DISCOVERY
# ------------------------------------------------------------------------------
log "Scanning profiles directory: $SRC_PROFILES_DIR"

PROFILE_FILES=()
PROFILE_NAMES=()
PROFILE_ASSETS=()

while IFS= read -r conf_file; do

    [ -f "$conf_file" ] || continue

    board_name=$(grep 'BOARD_NAME=' "$conf_file" | cut -d'"' -f2)
    env_file=$(grep 'ENV_FILE=' "$conf_file" | cut -d'"' -f2)

    if [ -z "$board_name" ]; then
        board_name=$(basename "$conf_file" .conf)
        log_debug "No BOARD_NAME in $conf_file, using filename: $board_name"
    fi

    asset_basename=""
    if [ -n "$env_file" ]; then
        asset_basename=$(basename "$env_file")
    fi

    log_debug "Profile: $conf_file | BOARD_NAME=$board_name | asset=$asset_basename"

    PROFILE_FILES+=("$conf_file")
    PROFILE_NAMES+=("$board_name")
    PROFILE_ASSETS+=("$asset_basename")

done < <(ls "$SRC_PROFILES_DIR"/*.conf 2>/dev/null | sort)

log "Total profiles found: ${#PROFILE_FILES[@]}"

if [ ${#PROFILE_FILES[@]} -eq 0 ]; then
    log_debug "No profiles found, proceeding with generic installation only."
fi

# ------------------------------------------------------------------------------
# PROFILE SELECTION — CHECKLIST
# Generic Installation is always listed first regardless of available profiles.
# ------------------------------------------------------------------------------
CHECKLIST_ITEMS=()

# Generic entry uses reserved tag "Generic"
CHECKLIST_ITEMS+=("Generic" "Generic Installation (no device-specific profiles)" "off")

for i in "${!PROFILE_FILES[@]}"; do
    CHECKLIST_ITEMS+=("$i" "${PROFILE_NAMES[$i]}" "off")
done

SELECTED_INDEXES=$(dialog --clear \
    --backtitle "$BACKTITLE" \
    --title "Select Device Profiles" \
    --ok-label "Next" \
    --cancel-label "Cancel" \
    --checklist "\nSelect the device profiles to inject into the image.\nUse SPACE to select, ENTER to confirm.\n" \
    20 70 10 \
    "${CHECKLIST_ITEMS[@]}" \
    2>&1 >/dev/tty)

EXIT_CODE=$?
log_debug "Checklist exit code: $EXIT_CODE | Selected: '$SELECTED_INDEXES'"

if [ $EXIT_CODE -ne 0 ]; then
    log "Installation cancelled by user."
    exit 0
fi

if [ -z "$SELECTED_INDEXES" ]; then
    dialog --backtitle "$BACKTITLE" \
        --title "No Selection" \
        --ok-label "OK" \
        --msgbox "\nNo profiles selected. Installation aborted." 7 45
    log "No profiles selected. Exiting."
    exit 0
fi

read -ra SELECTED_IDX_ARRAY <<< "$SELECTED_INDEXES"
log "Selected profile indexes: ${SELECTED_IDX_ARRAY[*]}"

# Detect if generic installation was selected
INSTALL_GENERIC=false
BOARD_IDX_ARRAY=()
for idx in "${SELECTED_IDX_ARRAY[@]}"; do
    if [ "$idx" = "Generic" ]; then
        INSTALL_GENERIC=true
        log_debug "Generic installation selected."
    else
        BOARD_IDX_ARRAY+=("$idx")
    fi
done

# ------------------------------------------------------------------------------
# FORMAT SELECTION — RADIOLIST PER PROFILE
# Generic installation skips this step entirely.
# For each selected board profile with an asset, ask: compressed or decompressed.
# ------------------------------------------------------------------------------
declare -A BOARD_FORMAT

for idx in "${BOARD_IDX_ARRAY[@]}"; do

    asset="${PROFILE_ASSETS[$idx]}"

    if [ -z "$asset" ]; then
        BOARD_FORMAT[$idx]="none"
        log_debug "Profile $idx has no asset, skipping format selection."
        continue
    fi

    board_name="${PROFILE_NAMES[$idx]}"

    FORMAT_CHOICE=$(dialog --clear \
        --backtitle "$BACKTITLE" \
        --title "Asset Format — ${board_name}" \
        --ok-label "OK" \
        --cancel-label "Cancel" \
        --radiolist "\nSelect the installation format for the U-Boot asset:\n\n  ${asset}\n" \
        14 65 2 \
        "gz"  "Compressed   (.img.gz) — recommended, saves disk space" "on" \
        "img" "Decompressed (.img)    — larger, no decompression overhead" "off" \
        2>&1 >/dev/tty)

    EXIT_CODE=$?
    log_debug "Radiolist exit code: $EXIT_CODE | Profile $idx format: '$FORMAT_CHOICE'"

    if [ $EXIT_CODE -ne 0 ]; then
        log "Injection cancelled by user during format selection."
        exit 0
    fi

    BOARD_FORMAT[$idx]="$FORMAT_CHOICE"

done

# ------------------------------------------------------------------------------
# CONFIRMATION SUMMARY
# ------------------------------------------------------------------------------
SUMMARY=""
if [ "$INSTALL_GENERIC" = true ]; then
    SUMMARY+="\n  • Generic Installation (no device-specific profiles)"
fi
for idx in "${BOARD_IDX_ARRAY[@]}"; do
    fmt="${BOARD_FORMAT[$idx]}"
    name="${PROFILE_NAMES[$idx]}"
    case "$fmt" in
        gz)   fmt_label="compressed (.img.gz)" ;;
        img)  fmt_label="decompressed (.img)"  ;;
        none) fmt_label="no asset"             ;;
    esac
    SUMMARY+="\n  • ${name} — ${fmt_label}"
done

dialog --backtitle "$BACKTITLE" \
    --title "Confirm Injection" \
    --yes-label "Inject" \
    --no-label "Cancel" \
    --yesno "\nThe following profiles will be injected into:\n  $(basename "$IMAGE_FILE")\n\nRootfs partition: ${ROOTFS_PART}\n\nProfiles:${SUMMARY}\n" \
    20 70

if [ $? -ne 0 ]; then
    log "Installation cancelled by user at confirmation."
    exit 0
fi

# ------------------------------------------------------------------------------
# MOUNT ROOTFS
# ------------------------------------------------------------------------------
log_header "Injection"

dialog --backtitle "$BACKTITLE" \
    --title "Injecting" \
    --infobox "\nMounting rootfs partition...\n  $ROOTFS_PART" 6 55

mkdir -p "$MNT_ROOTFS"

mount "$ROOTFS_PART" "$MNT_ROOTFS" 2>>"$TEMP_LOG"

if [ $? -ne 0 ]; then
    dialog --backtitle "$BACKTITLE" \
        --title "Error" \
        --ok-label "OK" \
        --msgbox "\nFailed to mount rootfs partition:\n  $ROOTFS_PART\n\nCheck the log:\n  $TEMP_LOG" 10 60
    log_error "Failed to mount $ROOTFS_PART at $MNT_ROOTFS"
    exit 1
fi

log "Rootfs mounted at: $MNT_ROOTFS"

MNT_DEST_BIN="${MNT_ROOTFS}${DEST_BIN}"
MNT_DEST_PROFILES="${MNT_ROOTFS}${DEST_PROFILES_DIR}"
MNT_DEST_ASSETS="${MNT_ROOTFS}${DEST_ASSETS_DIR}"

log "Creating destination directories inside image..."
mkdir -p "$MNT_DEST_PROFILES" "$MNT_DEST_ASSETS"
mkdir -p "$(dirname "$MNT_DEST_BIN")"

log "Injecting main script: $SRC_SCRIPT -> $MNT_DEST_BIN"
cp "$SRC_SCRIPT" "$MNT_DEST_BIN" && chmod +x "$MNT_DEST_BIN"
if [ $? -ne 0 ]; then
    dialog --backtitle "$BACKTITLE" \
        --title "Error" \
        --ok-label "OK" \
        --msgbox "\nFailed to inject main script into image." 8 55
    log_error "Failed to copy main script to $MNT_DEST_BIN"
    exit 1
fi

INSTALL_ERRORS=0

# Generic installation: directories already created above, nothing else to do.
if [ "$INSTALL_GENERIC" = true ] && [ ${#BOARD_IDX_ARRAY[@]} -eq 0 ]; then
    log "Generic installation selected with no board profiles — skipping asset loop."
fi

for idx in "${BOARD_IDX_ARRAY[@]}"; do

    conf_file="${PROFILE_FILES[$idx]}"
    conf_basename=$(basename "$conf_file")
    asset_basename="${PROFILE_ASSETS[$idx]}"
    fmt="${BOARD_FORMAT[$idx]}"
    board_name="${PROFILE_NAMES[$idx]}"

    dialog --backtitle "$BACKTITLE" \
        --title "Injecting" \
        --infobox "\nInjecting profile: ${board_name}..." 5 55

    log "Copying profile: $conf_file -> $MNT_DEST_PROFILES/$conf_basename"
    cp "$conf_file" "$MNT_DEST_PROFILES/$conf_basename"

    if [ $? -ne 0 ]; then
        log_error "Failed to copy profile: $conf_file"
        ((INSTALL_ERRORS++))
        continue
    fi

    [ "$fmt" = "none" ] && continue

    src_img="${SRC_ASSETS_DIR}/${asset_basename}"
    src_gz="${SRC_ASSETS_DIR}/${asset_basename}.gz"

    if [ "$fmt" = "gz" ]; then

        if [ -f "$src_gz" ]; then
            log "Copying asset (gz): $src_gz -> $MNT_DEST_ASSETS/"
            cp "$src_gz" "$MNT_DEST_ASSETS/"
            if [ $? -ne 0 ]; then
                log_error "Failed to copy asset: $src_gz"
                ((INSTALL_ERRORS++))
                continue
            fi
        elif [ -f "$src_img" ]; then
            log "Asset .gz not found, compressing from .img: $src_img"
            dialog --backtitle "$BACKTITLE" \
                --title "Injecting" \
                --infobox "\nCompressing asset for ${board_name}...\nThis may take a moment." 6 55
            pigz -9 -c "$src_img" > "$MNT_DEST_ASSETS/${asset_basename}.gz"
            if [ $? -ne 0 ]; then
                log_error "Failed to compress asset: $src_img"
                ((INSTALL_ERRORS++))
                continue
            fi
        else
            log_error "Asset not found (tried .gz and .img): $asset_basename"
            ((INSTALL_ERRORS++))
            continue
        fi

    elif [ "$fmt" = "img" ]; then

        if [ -f "$src_img" ]; then
            log "Copying asset (img): $src_img -> $MNT_DEST_ASSETS/"
            cp "$src_img" "$MNT_DEST_ASSETS/"
            if [ $? -ne 0 ]; then
                log_error "Failed to copy asset: $src_img"
                ((INSTALL_ERRORS++))
                continue
            fi
        elif [ -f "$src_gz" ]; then
            log "Asset .img not found, decompressing from .gz: $src_gz"
            dialog --backtitle "$BACKTITLE" \
                --title "Injecting" \
                --infobox "\nDecompressing asset for ${board_name}...\nThis may take a moment." 6 55
            pigz -dc "$src_gz" > "$MNT_DEST_ASSETS/${asset_basename}"
            if [ $? -ne 0 ]; then
                log_error "Failed to decompress asset: $src_gz"
                ((INSTALL_ERRORS++))
                continue
            fi
        else
            log_error "Asset not found (tried .img and .gz): $asset_basename"
            ((INSTALL_ERRORS++))
            continue
        fi

    fi

    log "Profile '${board_name}' injected successfully."

done

# Sync before unmount
dialog --backtitle "$BACKTITLE" \
    --title "Injecting" \
    --infobox "\nFlushing writes to image..." 5 40

log "Syncing filesystem..."
sync

log "Unmounting rootfs..."
umount "$MNT_ROOTFS" 2>>"$TEMP_LOG"
losetup -d "$LOOP_DEV" 2>>"$TEMP_LOG"
LOOP_DEV=""

# ------------------------------------------------------------------------------
# RESULT
# ------------------------------------------------------------------------------
if [ $INSTALL_ERRORS -gt 0 ]; then
    dialog --backtitle "$BACKTITLE" \
        --title "Injection Completed with Errors" \
        --ok-label "OK" \
        --msgbox "\nInjection completed with ${INSTALL_ERRORS} error(s).\n\nCheck the log for details:\n  $TEMP_LOG" 10 60
    log_error "Injection completed with $INSTALL_ERRORS error(s)."
    exit 1
else
    dialog --backtitle "$BACKTITLE" \
        --title "Injection Complete" \
        --ok-label "OK" \
        --msgbox "\nInjection completed successfully.\n\nImage is ready to flash:\n  $(basename "$IMAGE_FILE")" 10 60
    log "Injection completed successfully."
fi

exit 0
