#!/bin/bash

# ==============================================================================
# ARMBIAN INSTALLER FOR TV BOX AMLogic (UNOFFICIAL)
# @uthor: Pedro Rigolin
# ==============================================================================

# ------------------------------------------------------------------------------
# ROOT PRIVILEGE CHECK
# This script requires root privileges to manipulate disks and partitions.
# ------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root!"
  exit 1
fi

# ------------------------------------------------------------------------------
# DEPENDENCY CHECK
# Required packages:
#   - pv: Progress viewer for disk operations
#   - dialog: TUI dialogs for user interaction
#   - dosfstools: FAT32 filesystem tools (mkfs.vfat)
#   - rsync: Efficient file synchronization
# ------------------------------------------------------------------------------
DEPENDENCIES="pv dialog dosfstools rsync"
MISSING_PKGS=""

echo "Checking dependencies..."

for pkg in $DEPENDENCIES; do

    if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then

        echo "Dependency missing: $pkg"

        MISSING_PKGS="$MISSING_PKGS $pkg"

    fi

done

if [ -n "$MISSING_PKGS" ]; then

    echo "Installing missing dependencies:$MISSING_PKGS"
    
    apt-get update && apt-get install -y $MISSING_PKGS
    
    if [ $? -ne 0 ]; then

        echo "CRITICAL ERROR: Failed to install dependencies ($MISSING_PKGS)."

        echo "Please check your internet connection."

        exit 1

    fi

fi

if ! command -v pv &> /dev/null; then

    echo "CRITICAL ERROR: 'pv' utility is still missing."

    exit 1

fi

# ------------------------------------------------------------------------------
# SINGLE INSTANCE LOCK
# Prevents multiple instances of the installer from running simultaneously.
# Uses file descriptor 200 with flock for atomic locking.
# ------------------------------------------------------------------------------
LOCK_FILE="/tmp/armbian-install-amlogic.lock"

exec 200>"$LOCK_FILE"

flock -n -x 200 || {
    echo ""
    echo "################################################################"
    echo " CRITICAL ERROR: INSTALLER IS ALREADY RUNNING!"
    echo "################################################################"
    echo ""
    echo "Another instance of this script is holding the lock."
    echo "Please finish or kill the previous process before starting a new one."
    echo ""
    exit 1
}

# ------------------------------------------------------------------------------
# SESSION VARIABLES
# Unique session ID based on PID to allow safe concurrent debugging.
# Work directory contains all mount points for this installation session.
# ------------------------------------------------------------------------------
INSTALL_SESSION_ID="armbian-install-amlogic-$$"
WORK_DIR="/mnt/$INSTALL_SESSION_ID"

# Mount points for source (current system) and target (eMMC) partitions
MNT_SRC_BOOT="${WORK_DIR}/src_boot"
MNT_SRC_ROOT="${WORK_DIR}/src_root"
MNT_TGT_BOOT="${WORK_DIR}/tgt_boot"
MNT_TGT_ROOT="${WORK_DIR}/tgt_root"

# ------------------------------------------------------------------------------
# CLEANUP FUNCTION
# Unmounts all partitions and removes temporary directories.
# Called on exit (trap) or when an error occurs.
# Uses lazy unmount (-l) as fallback for stubborn mounts.
# ------------------------------------------------------------------------------
cleanup_mounts() {

    if [ -z "$WORK_DIR" ]; then return; fi

    umount "$MNT_TGT_ROOT" "$MNT_TGT_BOOT" "$MNT_SRC_ROOT" "$MNT_SRC_BOOT" 2>/dev/null
    
    umount -l "$MNT_TGT_ROOT" "$MNT_TGT_BOOT" "$MNT_SRC_ROOT" "$MNT_SRC_BOOT" 2>/dev/null

    if [ -d "$WORK_DIR" ]; then
        rmdir "$WORK_DIR" 2>/dev/null || rm -rf "$WORK_DIR" 2>/dev/null
    fi

}

# ------------------------------------------------------------------------------
# KERNEL LOG LEVEL & TRAP HANDLER
# Saves original kernel log level to restore on exit.
# Suppresses kernel messages (dmesg -n 1) during installation to keep UI clean.
# Trap ensures cleanup runs on INT (Ctrl+C), TERM, or normal EXIT.
# ------------------------------------------------------------------------------
ORIGINAL_LOG_LEVEL=$(awk '{print $1}' /proc/sys/kernel/printk)

if [ -z "$ORIGINAL_LOG_LEVEL" ]; then ORIGINAL_LOG_LEVEL=7; fi

trap 'tput cnorm; cleanup_mounts; dmesg -n "$ORIGINAL_LOG_LEVEL"; clear; echo "Installation finished or interrupted."; exit' INT TERM EXIT

dmesg -n 1

# ------------------------------------------------------------------------------
# LOGGING FUNCTIONS
# All operations are logged to a temporary file for debugging purposes.
# log(): Appends timestamped messages to the log file (default: INFO level).
# log_debug(): Detailed debug information for troubleshooting.
# log_error(): Error messages with ERROR prefix.
# log_warn(): Warning messages with WARN prefix.
# log_var(): Dumps variable name, value, and type for debugging.
# log_state(): Logs current state of important variables.
# log_header(): Creates a visual separator for major phases in the log.
# log_cmd(): Logs a command and its exit code after execution.
# ------------------------------------------------------------------------------
TEMP_LOG="/tmp/armbian-install-amlogic.log"

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" >> "$TEMP_LOG"
}

log_debug() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1" >> "$TEMP_LOG"
}

log_error() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$TEMP_LOG"
}

log_warn() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $1" >> "$TEMP_LOG"
}

# Dump variable with name, value, and whether it's set/empty
log_var() {
    local var_name="$1"
    local var_value="${!var_name}"
    local var_status="SET"
    [ -z "$var_value" ] && var_status="EMPTY"
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] VAR: $var_name = '$var_value' [$var_status]" >> "$TEMP_LOG"
}

# Log multiple variables at once for state inspection
log_state() {
    local label="$1"
    shift
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [STATE] --- $label ---" >> "$TEMP_LOG"
    for var_name in "$@"; do
        local var_value="${!var_name}"
        local var_status="SET"
        [ -z "$var_value" ] && var_status="EMPTY"
        echo -e "    $var_name = '$var_value' [$var_status]" >> "$TEMP_LOG"
    done
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [STATE] --- END $label ---" >> "$TEMP_LOG"
}

# Log exit code from last command
log_exit_code() {
    local code=$?
    local context="$1"
    if [ $code -eq 0 ]; then
        echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] EXIT_CODE: $code (SUCCESS) - $context" >> "$TEMP_LOG"
    else
        echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] EXIT_CODE: $code (FAILED) - $context" >> "$TEMP_LOG"
    fi
    return $code
}

log_header() {
    echo -e "\n================================================================================" >> "$TEMP_LOG"
    echo -e "   $1" >> "$TEMP_LOG"
    echo -e "================================================================================\n" >> "$TEMP_LOG"
}

# Clear previous log
echo "" > "$TEMP_LOG"

DATE_TIME=$(date '+%d/%m/%Y %H:%M:%S')

log_header "New Installation Session: $DATE_TIME"

log "Collecting System Info..."
log "Kernel: $(uname -r)"
log "Uptime: $(uptime -p)"
log_debug "Total Memory: $(free -h | awk '/^Mem:/ {print $2}')"
log_debug "Available Memory: $(free -h | awk '/^Mem:/ {print $7}')"
log_debug "CPU Info: $(grep -m1 'model name' /proc/cpuinfo | cut -d':' -f2 | xargs)"
log_debug "Architecture: $(uname -m)"
log "Mounted Disks (Before):"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT >> "$TEMP_LOG"
log_debug "Block devices with details:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINT >> "$TEMP_LOG" 2>/dev/null

log_state "Session Variables" INSTALL_SESSION_ID WORK_DIR MNT_SRC_BOOT MNT_SRC_ROOT MNT_TGT_BOOT MNT_TGT_ROOT

BACKTITLE="ARMBIAN INSTALLER FOR TV BOX AMLogic - UNOFFICIAL - by Pedro Rigolin"

# ------------------------------------------------------------------------------
# DEFAULT CONFIGURATION
# These values can be overridden by device-specific profiles.
# ------------------------------------------------------------------------------
BASE_CONFIG_DIR="/etc/armbian-install-amlogic"

PROFILES_DIR="${BASE_CONFIG_DIR}/profiles"

# Default partition start offset (sector 262144 = 128MB)
# This preserves the factory bootloader area on AMLogic devices.
OFFSET_START="262144"

# U-Boot environment injection flag (enabled by device profiles)
ENV_INJECTION="false"

SELECTED_PROFILE_NAME="Generic / No Profile"

# ------------------------------------------------------------------------------
# PARTITION SIZE CALCULATIONS
# BOOT partition: 512MB FAT32 for kernel, DTB, and boot scripts.
# ROOT partition: Remaining space as ext4 for the root filesystem.
# Sector size is 512 bytes, so 2048 sectors = 1MB.
# ------------------------------------------------------------------------------
BOOT_SIZE_MB=512

BOOT_WIDTH_SECTORS=$((BOOT_SIZE_MB * 2048))

# ROOT partition starts right after BOOT partition
P2_START=$((OFFSET_START + BOOT_WIDTH_SECTORS))

BOOT_SIZE_STR="+${BOOT_SIZE_MB}M"

dialog --backtitle "$BACKTITLE" \
    --title "Wait" \
    --infobox "\nDetecting available disks..." 5 40

# ------------------------------------------------------------------------------
# DISK DETECTION
# Identifies the current root partition to exclude it from target selection.
# Only eMMC devices (mmcblk*) are considered as installation targets.
# Boot and RPMB partitions are filtered out.
# ------------------------------------------------------------------------------
ROOT_PART=$(findmnt / -o SOURCE -n)
log_debug "findmnt returned: '$ROOT_PART'"

ROOT_DISK=$(lsblk -no pkname $ROOT_PART)
log_debug "lsblk pkname returned: '$ROOT_DISK'"

log "Current System Root: $ROOT_PART (Disk: $ROOT_DISK)"
log_state "Root Detection" ROOT_PART ROOT_DISK

INDEX=1

MENU_OPTIONS=()

AVAILABLE_DISKS=()

# Iterate through all mmcblk devices and filter valid targets
log_debug "Starting disk enumeration..."
log_debug "All block devices: $(lsblk -d -n -o NAME | tr '\n' ' ')"

for disk in $(lsblk -d -n -o NAME | grep "mmcblk"); do

    log_debug "Evaluating disk: $disk"

    # Skip boot partitions and RPMB (Replay Protected Memory Block)
    if [[ "$disk" == *"boot"* ]] || [[ "$disk" == *"rpmb"* ]]; then
        log_debug "  -> SKIPPED (boot/rpmb partition)"
        continue
    fi

    # Skip the disk containing the currently running system
    if [[ "$disk" == "$ROOT_DISK" ]]; then
        log_debug "  -> SKIPPED (contains running system)"
        continue
    fi

    local_disk_size=$(lsblk -b -n -o SIZE "/dev/$disk" 2>/dev/null | head -n1)
    log_debug "  -> ACCEPTED: /dev/$disk (Size: ${local_disk_size:-unknown} bytes)"

    MENU_OPTIONS+=("$INDEX" "/dev/$disk")

    AVAILABLE_DISKS+=("/dev/$disk")

    ((INDEX++))

done

log_debug "Disk enumeration complete. Found ${#AVAILABLE_DISKS[@]} candidate(s)."

if [ ${#AVAILABLE_DISKS[@]} -eq 0 ]; then

    log "ERROR: No available eMMC disks found for installation."

    dialog --backtitle "$BACKTITLE" \
        --title "Error" \
        --ok-label "OK" \
        --msgbox "\nNo available eMMC disks found for installation.\n\nThe installer will now exit." 10 50

    exit 1

fi

log "Available eMMC candidates: ${AVAILABLE_DISKS[*]}"

CHOICE_INDEX=$(dialog --clear \
    --backtitle "$BACKTITLE" \
    --title "Select Target eMMC Disk" \
    --ok-label "Select" \
    --cancel-label "Exit" \
    --menu "\nSelect the target eMMC disk for ARMBIAN installation:\n" \
    15 70 5 \
    "${MENU_OPTIONS[@]}" \
    2>&1 >/dev/tty)

EXIT_CODE=$?
log_debug "Dialog exit code: $EXIT_CODE, CHOICE_INDEX: '$CHOICE_INDEX'"
if [ $EXIT_CODE -ne 0 ]; then
    log "Installation cancelled by user during disk selection."
    exit 0
fi

REAL_INDEX=$((CHOICE_INDEX - 1))
TARGET_DISK="${AVAILABLE_DISKS[$REAL_INDEX]}"

log "User selected target: $TARGET_DISK"
log_var TARGET_DISK
log_var REAL_INDEX
log_debug "Target disk details:"
fdisk -l "$TARGET_DISK" >> "$TEMP_LOG" 2>&1

# ------------------------------------------------------------------------------
# DEVICE PROFILE SELECTION
# Profiles contain device-specific configurations such as:
#   - BOARD_NAME: Human-readable device name
#   - LINUX_START_SECTOR: Custom partition offset for locked bootloaders
#   - ENV_FILE: U-Boot environment binary to inject
#   - ENV_OFFSET: Sector offset for environment injection
# ------------------------------------------------------------------------------
BOARD_OPTIONS=()

PROFILE_FILES=()

# 1. Scan for profiles in the configuration directory
log_debug "Scanning profiles directory: $PROFILES_DIR"
log_var PROFILES_DIR

if [ -d "$PROFILES_DIR" ]; then

    log_debug "Profiles directory exists, listing .conf files..."

    while IFS= read -r file; do

        if [ -f "$file" ]; then

            log_debug "Found profile file: $file"

            # Extract BOARD_NAME from config file
            B_NAME=$(grep -oP 'BOARD_NAME="\K[^"]+' "$file")

            if [ -z "$B_NAME" ]; then 
                B_NAME=$(basename "$file")
                log_debug "  -> No BOARD_NAME found, using filename: $B_NAME"
            else
                log_debug "  -> BOARD_NAME extracted: $B_NAME"
            fi
            
            # Add to arrays
            BOARD_OPTIONS+=("${#PROFILE_FILES[@]}" "$B_NAME")

            PROFILE_FILES+=("$file")

        fi

    done < <(ls "$PROFILES_DIR"/*.conf 2>/dev/null)

    log_debug "Total profiles loaded: ${#PROFILE_FILES[@]}"

else
    log_warn "Profiles directory does not exist: $PROFILES_DIR"
fi

# 2. Add "Generic" Option at the end
GENERIC_INDEX=${#PROFILE_FILES[@]}

BOARD_OPTIONS+=("$GENERIC_INDEX" "Generic / Standard Installation (No U-Boot Mod)")

log "Available installation profiles for selection: ${BOARD_OPTIONS[*]}"

# 3. Show Menu
CHOICE_INDEX=$(dialog --clear \
    --backtitle "$BACKTITLE" \
    --title "Select TV Box Model" \
    --ok-label "Select" \
    --cancel-label "Exit" \
    --menu "\nSelect the target device configuration:\n" \
    15 75 8 \
    "${BOARD_OPTIONS[@]}" \
    2>&1 >/dev/tty)

EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
    log "Installation cancelled by user during box selection."
    exit 0
fi

if [ "$CHOICE_INDEX" -eq "$GENERIC_INDEX" ]; then
    
    dialog --backtitle "$BACKTITLE" \
           --title "\Z1\ZbWARNING: GENERIC INSTALLATION\Zn" \
           --colors \
           --yes-label "Proceed Anyway" \
           --no-label "Exit" \
           --yesno "\nYou selected the \Z1Generic Installation\Zn.\n\nThis mode will \Z1NOT\Zn inject any custom U-Boot environment variables.\n\n\Z1RISK:\Zn On locked devices (like HTV, BTV, ATV), the factory bootloader might fail to load Linux without these modifications, resulting in a black screen or boot loop.\n\nUse this only if:\n1. Your device has an unlocked/standard bootloader.\n2. You are sure you don't need special memory offsets.\n\nDo you want to proceed?" 16 65
    
    if [ $? -ne 0 ]; then
        log "Installation cancelled by user at GENERIC installation warning."
        exit 0
    fi
    
    # Apply Defaults (Generic)
    SELECTED_PROFILE_NAME="Generic / Standard"
    
    ENV_INJECTION="false"
    
else
    
    SELECTED_CONF="${PROFILE_FILES[$CHOICE_INDEX]}"
    log_debug "Loading profile configuration from: $SELECTED_CONF"

    # Log profile content before sourcing
    log_debug "--- Profile content before sourcing ---"
    cat "$SELECTED_CONF" >> "$TEMP_LOG" 2>&1
    log_debug "--- End profile content ---"

    # Load profile configuration into current shell environment
    source "$SELECTED_CONF"
    log_debug "Profile sourced successfully"
    
    # Log all variables that might have been set by the profile
    log_state "Post-Profile Variables" BOARD_NAME LINUX_START_SECTOR ENV_FILE ENV_OFFSET
    
    # Override default partition offset if profile specifies a custom one
    if [ -n "$LINUX_START_SECTOR" ]; then 
        log_debug "Overriding OFFSET_START with profile value: $LINUX_START_SECTOR"
        OFFSET_START="$LINUX_START_SECTOR"; 
    else
        log_debug "Using default OFFSET_START: $OFFSET_START"
    fi
    
    # Enable U-Boot environment injection if profile provides both file and offset
    if [ -n "$ENV_FILE" ] && [ -n "$ENV_OFFSET" ]; then
    
        ENV_INJECTION="true"
        log_debug "Environment injection ENABLED"
    
        SELECTED_PROFILE_NAME="$BOARD_NAME"

        if [ ! -f "$ENV_FILE" ]; then
            log_error "Specified ENV_FILE '$ENV_FILE' does not exist"
            log_debug "Checking path: $(ls -la "$(dirname "$ENV_FILE")" 2>&1)"
            exit 1
        fi
        log_debug "ENV_FILE exists and is accessible"

    else

        ENV_INJECTION="false"
        log_debug "Environment injection DISABLED (missing ENV_FILE or ENV_OFFSET)"
        log_var ENV_FILE
        log_var ENV_OFFSET
    
        SELECTED_PROFILE_NAME="$BOARD_NAME (No Env Injection)"
    
    fi
fi

log "Selected Profile: $SELECTED_PROFILE_NAME"

log "Partition Start Offset: $OFFSET_START"

if [ "$ENV_INJECTION" == "true" ]; then

    log "Env Injection: ENABLED (File: $ENV_FILE @ Offset: $ENV_OFFSET)"
    log_debug "ENV_FILE size: $(stat -c%s "$ENV_FILE" 2>/dev/null || echo 'N/A') bytes"

else

    log "Env Injection: DISABLED"

fi

# Recalculate partition layout after potential profile override
BOOT_WIDTH_SECTORS=$((BOOT_SIZE_MB * 2048))
P2_START=$((OFFSET_START + BOOT_WIDTH_SECTORS))

log_header "FINAL CONFIGURATION STATE"
log_state "Partition Layout" OFFSET_START BOOT_SIZE_MB BOOT_WIDTH_SECTORS P2_START BOOT_SIZE_STR
log_state "Target Configuration" TARGET_DISK ENV_INJECTION SELECTED_PROFILE_NAME
log_state "Source Identification" ROOT_PART ROOT_DISK

dialog --colors \
       --backtitle "$BACKTITLE" \
       --title "\Z1\Zb!!! CRITICAL WARNING !!!\Zn" \
       --yes-label "Continue" \
       --no-label "Exit" \
       --yesno "\nTarget Device: \Z1\Zb$TARGET_DISK\Zn\n\nThis operation will \Z1\ZbERASE ALL DATA\Zn on the selected storage.\nThe partition table will be overwritten.\n\nThis action is \Z1\ZbIRREVERSIBLE\Zn.\n\nAre you absolutely sure you want to proceed?" 15 60

EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
    log "Installation cancelled by user at critical warning."
    exit 0
fi

log_header "PHASE 1: DISK WIPE & PARTITIONING"

DISK_SIZE=$(lsblk -b -n -o SIZE "$TARGET_DISK" | head -n1)
DISK_SIZE_HUMAN=$(numfmt --to=iec-i --suffix=B "$DISK_SIZE" 2>/dev/null || echo "$DISK_SIZE bytes")

log "Target Disk Size: $DISK_SIZE bytes ($DISK_SIZE_HUMAN)"
log_var DISK_SIZE

log_debug "Pre-wipe disk state:"
log_debug "  Partitions: $(lsblk -n -o NAME "$TARGET_DISK" | tr '\n' ' ')"
log_debug "  Partition table type: $(blkid -o value -s PTTYPE "$TARGET_DISK" 2>/dev/null || echo 'none/unknown')"

log "Wiping entire disk $TARGET_DISK with zeros..."
log_debug "Wipe command: dd if=/dev/zero bs=1M | pv | dd of=$TARGET_DISK bs=1M"

# ------------------------------------------------------------------------------
# DISK WIPE
# Writes zeros to the entire disk to ensure clean state.
# Uses dd piped through pv for progress indication.
# oflag=direct bypasses cache for reliable writes to eMMC.
# ------------------------------------------------------------------------------
(
    dd if=/dev/zero bs=1M status=none | \
    pv -n -s "$DISK_SIZE" | \
    dd of="$TARGET_DISK" bs=1M iflag=fullblock oflag=direct 2>/dev/null
) 2>&1 | dialog \
        --backtitle "$BACKTITLE" \
        --title "Wait" \
        --gauge "\nWiping entire eMMC ($TARGET_DISK)...\n\nThis may take a while. Please wait." 10 70 0

log "Disk wipe completed."
log_debug "Post-wipe verification:"
log_debug "  Partition table: $(blkid -o value -s PTTYPE "$TARGET_DISK" 2>/dev/null || echo 'none (expected after wipe)')"

log_debug "Syncing filesystem buffers..."
sync
log_debug "Waiting 5 seconds for device to settle..."
sleep 5

# ------------------------------------------------------------------------------
# U-BOOT ENVIRONMENT INJECTION
# For locked bootloaders (HTV, BTV, ATV, etc.), we need to inject custom
# environment variables that tell U-Boot where to find the Linux kernel.
# This is written to a specific sector offset on the eMMC.
# ------------------------------------------------------------------------------
if [ "$ENV_INJECTION" == "true" ]; then

    log "Injecting Custom U-Boot Environment..."
    log_debug "ENV_FILE: $ENV_FILE"
    log_debug "ENV_OFFSET: $ENV_OFFSET sectors"
    log_debug "ENV_OFFSET in bytes: $((ENV_OFFSET * 512))"
    log_debug "ENV_FILE size: $(stat -c%s "$ENV_FILE") bytes"
    log_debug "DD command: dd if=$ENV_FILE of=$TARGET_DISK bs=512 seek=$ENV_OFFSET conv=notrunc"

    dialog \
        --backtitle "$BACKTITLE" \
        --title "Wait" \
        --infobox "\nInjecting bootloader environment for $BOARD_NAME..." 5 60
    
    # Write environment binary to specific sector offset
    dd if="$ENV_FILE" of="$TARGET_DISK" bs=512 seek="$ENV_OFFSET" conv=notrunc >> "$TEMP_LOG" 2>&1
    DD_EXIT_CODE=$?
    
    log_debug "dd exit code: $DD_EXIT_CODE"
        
    if [ $DD_EXIT_CODE -ne 0 ]; then

        log_error "Environment injection failed! Exit code: $DD_EXIT_CODE"
        log_debug "Checking if target disk is still accessible: $(ls -la $TARGET_DISK 2>&1)"

        dialog --msgbox "Error injecting U-Boot environment.\nCheck log." 8 50

        exit 1

    fi

    log "Environment injection successful."
    log_debug "Verifying injection by reading back first 64 bytes:"
    dd if="$TARGET_DISK" bs=512 skip="$ENV_OFFSET" count=1 2>/dev/null | hexdump -C | head -4 >> "$TEMP_LOG"

    sync
    log_debug "Waiting 5 seconds after env injection..."
    sleep 5

fi

dialog --backtitle "$BACKTITLE" \
    --title "Wait" \
    --infobox "\nCreating partition table on $TARGET_DISK..." 5 55

log "Running fdisk on $TARGET_DISK..."
log_debug "fdisk parameters:"
log_debug "  OFFSET_START (first sector): $OFFSET_START"
log_debug "  BOOT_SIZE_STR: $BOOT_SIZE_STR"
log_debug "  P2_START (root start sector): $P2_START"
log_debug "  P2 will use remaining space"

# ------------------------------------------------------------------------------
# PARTITION TABLE CREATION (fdisk heredoc)
# Creates MBR partition table with:
#   o     - Create new DOS partition table
#   n p 1 - New primary partition 1 (BOOT)
#   t c   - Set type to W95 FAT32 (LBA)
#   a   - Set bootable flag on partition 1
#   n p 2 - New primary partition 2 (ROOT) using remaining space
#   w     - Write changes and exit
# ------------------------------------------------------------------------------
fdisk "$TARGET_DISK" >> "$TEMP_LOG" 2>&1 <<EOF
o
n
p
1
$OFFSET_START
$BOOT_SIZE_STR
t
c
a
n
p
2
$P2_START

w
EOF

partprobe "$TARGET_DISK" >> "$TEMP_LOG" 2>&1
PARTPROBE_EXIT=$?
sleep 5

if [ $PARTPROBE_EXIT -ne 0 ]; then
    
    log_error "fdisk/partprobe failed. Exit code: $PARTPROBE_EXIT"

    dialog --backtitle "$BACKTITLE" \
        --title "Error" \
        --ok-label "OK" \
        --msgbox "\nFailed to create partition table on $TARGET_DISK.\n\nCheck the log at $TEMP_LOG for details." 10 60

    exit 1

fi

log "Partition table created successfully. New layout:"
fdisk -l "$TARGET_DISK" >> "$TEMP_LOG"

log_debug "Verifying partitions were created:"
log_debug "  Partitions found: $(lsblk -n -o NAME "$TARGET_DISK" | tail -n +2 | tr '\n' ' ')"
log_debug "  Partition table type: $(blkid -o value -s PTTYPE "$TARGET_DISK" 2>/dev/null || echo 'unknown')"

# ------------------------------------------------------------------------------
# PARTITION NAMING CONVENTION
# Linux uses different naming schemes for partitions:
#   - mmcblk0 -> mmcblk0p1, mmcblk0p2 (needs 'p' prefix)
#   - sda -> sda1, sda2 (no prefix needed)
# This logic detects which scheme to use based on disk name.
# ------------------------------------------------------------------------------
if [[ "$TARGET_DISK" =~ [0-9]$ ]]; then
    # Disk name ends with number (e.g., mmcblk0) - needs 'p' prefix
    PART_PREFIX="p"
else
    # Disk name ends with letter (e.g., sda) - no prefix
    PART_PREFIX=""
fi

# Build full partition device paths
TARGET_BOOT="${TARGET_DISK}${PART_PREFIX}1"
TARGET_ROOT="${TARGET_DISK}${PART_PREFIX}2"

log_debug "Target disk ends with number: $([[ "$TARGET_DISK" =~ [0-9]$ ]] && echo 'yes' || echo 'no')"
log_debug "Using partition prefix for target: '$PART_PREFIX'"

if [[ "$ROOT_DISK" =~ [0-9]$ ]]; then
    PART_PREFIX_ROOT="p"
else
    PART_PREFIX_ROOT=""
fi

log_debug "Root disk ends with number: $([[ "$ROOT_DISK" =~ [0-9]$ ]] && echo 'yes' || echo 'no')"
log_debug "Using partition prefix for root: '$PART_PREFIX_ROOT'"

ACTUAL_BOOT="/dev/${ROOT_DISK}${PART_PREFIX_ROOT}1"
ACTUAL_ROOT="/dev/${ROOT_DISK}${PART_PREFIX_ROOT}2"

log "Target BOOT: $TARGET_BOOT"
log "Target ROOT: $TARGET_ROOT"
log "Source BOOT: $ACTUAL_BOOT"
log "Source ROOT: $ACTUAL_ROOT"

log_state "Partition Paths" TARGET_BOOT TARGET_ROOT ACTUAL_BOOT ACTUAL_ROOT

# Verify partitions exist
log_debug "Verifying partition devices exist:"
for part in "$TARGET_BOOT" "$TARGET_ROOT" "$ACTUAL_BOOT" "$ACTUAL_ROOT"; do
    if [ -b "$part" ]; then
        log_debug "  $part: EXISTS (block device)"
    else
        log_warn "  $part: NOT FOUND or not a block device"
    fi
done

log_header "PHASE 2: FORMATTING"

dialog --backtitle "$BACKTITLE" \
    --title "Wait" \
    --infobox "\nFormatting partitions on $TARGET_DISK..." 5 55

log "Formatting BOOT (vfat)..."
log_debug "mkfs.vfat command: mkfs.vfat -F 32 -n BOOT $TARGET_BOOT"

mkfs.vfat -F 32 -n BOOT "$TARGET_BOOT" >> "$TEMP_LOG" 2>&1
MKFS_VFAT_EXIT=$?

log_debug "mkfs.vfat exit code: $MKFS_VFAT_EXIT"

if [ $MKFS_VFAT_EXIT -ne 0 ]; then
    
    log_error "Failed to format BOOT partition. Exit code: $MKFS_VFAT_EXIT"
    log_debug "Checking partition state: $(file -s $TARGET_BOOT 2>&1)"
    
    dialog --backtitle "$BACKTITLE" \
        --title "Error" \
        --ok-label "OK" \
        --msgbox "\nFailed to format BOOT partition on $TARGET_DISK.\n\nCheck the log at $TEMP_LOG for details." 10 60
    
    exit 1

fi

log "BOOT partition formatted successfully."
log_debug "BOOT partition details: $(blkid $TARGET_BOOT 2>/dev/null)"

log "Formatting ROOT (ext4)..."
log_debug "mkfs.ext4 command: mkfs.ext4 -F -q -L ROOTFS $TARGET_ROOT"

mkfs.ext4 -F -q -L ROOTFS "$TARGET_ROOT" >> "$TEMP_LOG" 2>&1
MKFS_EXT4_EXIT=$?

log_debug "mkfs.ext4 exit code: $MKFS_EXT4_EXIT"

if [ $MKFS_EXT4_EXIT -ne 0 ]; then
    
    log_error "Failed to format ROOT partition. Exit code: $MKFS_EXT4_EXIT"
    log_debug "Checking partition state: $(file -s $TARGET_ROOT 2>&1)"
    
    dialog --backtitle "$BACKTITLE" \
        --title "Error" \
        --ok-label "OK" \
        --msgbox "\nFailed to format ROOT partition on $TARGET_DISK.\n\nCheck the log at $TEMP_LOG for details." 10 60
    
    exit 1

fi

log "ROOT partition formatted successfully."
log_debug "ROOT partition details: $(blkid $TARGET_ROOT 2>/dev/null)"

log_header "PHASE 3: MOUNTING & COPYING"

log "Creating workspace at $WORK_DIR..."
log_debug "Mount point paths:"
log_debug "  MNT_SRC_BOOT: $MNT_SRC_BOOT"
log_debug "  MNT_SRC_ROOT: $MNT_SRC_ROOT"
log_debug "  MNT_TGT_BOOT: $MNT_TGT_BOOT"
log_debug "  MNT_TGT_ROOT: $MNT_TGT_ROOT"

dialog --backtitle "$BACKTITLE" \
       --title "Wait" \
       --infobox "\nCreating mount points and mounting partitions..." 5 55

# ------------------------------------------------------------------------------
# MOUNT PARTITIONS
# Mounts both source (current system) and target (eMMC) partitions.
# Uses subshell with 'set -e' to fail fast if any mount fails.
# Source partitions: Currently running Armbian system
# Target partitions: Newly formatted eMMC partitions
# ------------------------------------------------------------------------------
log_debug "Creating mount point directories..."
mkdir -p "$MNT_SRC_BOOT" "$MNT_SRC_ROOT" "$MNT_TGT_BOOT" "$MNT_TGT_ROOT" 2>> "$TEMP_LOG"
log_debug "Directories created successfully"

MOUNT_FAILED=0

log_debug "Mounting source BOOT: ${ACTUAL_BOOT} -> $MNT_SRC_BOOT"
mount "${ACTUAL_BOOT}" "$MNT_SRC_BOOT" >> "$TEMP_LOG" 2>&1 || { log_error "Failed to mount ${ACTUAL_BOOT}"; MOUNT_FAILED=1; }

if [ $MOUNT_FAILED -eq 0 ]; then
    log_debug "Mounting source ROOT: ${ACTUAL_ROOT} -> $MNT_SRC_ROOT"
    mount "${ACTUAL_ROOT}" "$MNT_SRC_ROOT" >> "$TEMP_LOG" 2>&1 || { log_error "Failed to mount ${ACTUAL_ROOT}"; MOUNT_FAILED=1; }
fi

if [ $MOUNT_FAILED -eq 0 ]; then
    log_debug "Mounting target BOOT: ${TARGET_BOOT} -> $MNT_TGT_BOOT"
    mount "${TARGET_BOOT}" "$MNT_TGT_BOOT" >> "$TEMP_LOG" 2>&1 || { log_error "Failed to mount ${TARGET_BOOT}"; MOUNT_FAILED=1; }
fi

if [ $MOUNT_FAILED -eq 0 ]; then
    log_debug "Mounting target ROOT: ${TARGET_ROOT} -> $MNT_TGT_ROOT"
    mount "${TARGET_ROOT}" "$MNT_TGT_ROOT" >> "$TEMP_LOG" 2>&1 || { log_error "Failed to mount ${TARGET_ROOT}"; MOUNT_FAILED=1; }
fi

EXIT_CODE=$MOUNT_FAILED

log_debug "Current mounts after mount operations:"
mount | grep "$WORK_DIR" >> "$TEMP_LOG" 2>&1 || log_debug "No mounts found under $WORK_DIR"

if [ $EXIT_CODE -ne 0 ]; then
    
    log_error "Failed to mount one or more partitions. Check individual mount logs above."
    
    dialog --backtitle "$BACKTITLE" \
        --title "Error" \
        --ok-label "OK" \
        --msgbox "\nFailed to mount one or more partitions.\nInstallation cannot continue.\n\nCheck the log at $TEMP_LOG for details." 15 60

    exit 1

fi

log "All partitions mounted successfully."
log_debug "Mount verification:"
log_debug "  Source BOOT files: $(ls -1 $MNT_SRC_BOOT 2>/dev/null | wc -l) items"
log_debug "  Source ROOT files: $(ls -1 $MNT_SRC_ROOT 2>/dev/null | wc -l) items"
log_debug "  Target BOOT files: $(ls -1 $MNT_TGT_BOOT 2>/dev/null | wc -l) items (should be 0)"
log_debug "  Target ROOT files: $(ls -1 $MNT_TGT_ROOT 2>/dev/null | wc -l) items (should be 1 - lost+found)"

log "Starting CP for BOOT partition..."

BOOT_SRC_SIZE=$(du -sh "$MNT_SRC_BOOT" 2>/dev/null | cut -f1)
log_debug "Source BOOT size: $BOOT_SRC_SIZE"
log_debug "Source BOOT contents: $(ls -la $MNT_SRC_BOOT 2>/dev/null | head -20)"
log_debug "cp command: cp -rL $MNT_SRC_BOOT/* $MNT_TGT_BOOT/"

dialog --backtitle "$BACKTITLE" \
       --title "Wait" \
       --infobox "\nCopying BOOT partition data...\n\nThis may take a while. Please wait." 7 60

cp -rL "$MNT_SRC_BOOT"/* "$MNT_TGT_BOOT"/ >> "$TEMP_LOG" 2>&1
CP_BOOT_EXIT=$?

log_debug "cp exit code: $CP_BOOT_EXIT"

if [ $CP_BOOT_EXIT -ne 0 ]; then
    
    log_error "Failed to copy BOOT partition data. Exit code: $CP_BOOT_EXIT"
    log_debug "Target BOOT free space: $(df -h $MNT_TGT_BOOT 2>/dev/null | tail -1)"
    
    dialog --backtitle "$BACKTITLE" \
        --title "Error" \
        --ok-label "OK" \
        --msgbox "\nFailed to copy BOOT partition data.\nInstallation cannot continue.\n\nCheck the log at $TEMP_LOG for details." 15 60

    exit 1

fi

log "BOOT partition copy completed successfully."
log_debug "Target BOOT size after copy: $(du -sh $MNT_TGT_BOOT 2>/dev/null | cut -f1)"
log_debug "Target BOOT files: $(ls -1 $MNT_TGT_BOOT 2>/dev/null | wc -l) items"

log "Starting RSYNC for ROOT partition..."

ROOT_SRC_SIZE=$(du -sh "$MNT_SRC_ROOT" --exclude="$MNT_SRC_ROOT/dev" --exclude="$MNT_SRC_ROOT/proc" --exclude="$MNT_SRC_ROOT/sys" --exclude="$MNT_SRC_ROOT/tmp" --exclude="$MNT_SRC_ROOT/run" --exclude="$MNT_SRC_ROOT/mnt" --exclude="$MNT_SRC_ROOT/media" 2>/dev/null | cut -f1)
log_debug "Source ROOT size (excluding virtual fs): $ROOT_SRC_SIZE"
log_debug "Target ROOT free space: $(df -h $MNT_TGT_ROOT 2>/dev/null | tail -1)"
log_debug "rsync exclude list: /dev, /proc, /sys, /tmp, /run, /mnt, /media, /lost+found"

dialog --backtitle "$BACKTITLE" \
       --title "Wait" \
       --infobox "\nCopying ROOT partition data...\n\nThis may take a while. Please wait." 7 60

# ------------------------------------------------------------------------------
# ROOT PARTITION COPY (rsync)
# Flags: -a (archive), -A (ACLs), -X (xattrs), -v (verbose), --delete (sync)
# Excludes virtual filesystems and temporary directories that should not
# be copied to the target system.
# ------------------------------------------------------------------------------
rsync -aAXv --delete \
      --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} \
      "$MNT_SRC_ROOT"/ \
      "$MNT_TGT_ROOT"/ >> "$TEMP_LOG" 2>&1
RSYNC_EXIT=$?

log_debug "rsync exit code: $RSYNC_EXIT"

if [ $RSYNC_EXIT -ne 0 ]; then
    
    log_error "Failed to copy ROOT partition data. rsync exit code: $RSYNC_EXIT"
    log_debug "rsync exit codes: 0=success, 23=partial transfer (some files could not be transferred)"
    log_debug "rsync exit codes: 24=some source files vanished, 25=max delete limit reached"
    log_debug "Target ROOT free space: $(df -h $MNT_TGT_ROOT 2>/dev/null | tail -1)"
    
    dialog --backtitle "$BACKTITLE" \
        --title "Error" \
        --ok-label "OK" \
        --msgbox "\nFailed to copy ROOT partition data.\nInstallation cannot continue.\n\nCheck the log at $TEMP_LOG for details." 15 60

    exit 1

fi

log "ROOT partition copy completed successfully."
log_debug "Target ROOT size after copy: $(du -sh $MNT_TGT_ROOT 2>/dev/null | cut -f1)"
log_debug "Target ROOT disk usage: $(df -h $MNT_TGT_ROOT 2>/dev/null | tail -1)"

log_header "PHASE 4: CONFIGURATION & UUIDs"

dialog --backtitle "$BACKTITLE" \
       --title "Final Configurations" \
       --infobox "\nUpdating UUIDs and boot configuration...\n\nThis may take a while. Please wait." 7 60

# ------------------------------------------------------------------------------
# UUID DETECTION
# After formatting, each partition gets a new UUID.
# These UUIDs must be updated in fstab and armbianEnv.txt for proper booting.
# partprobe and udevadm ensure the kernel sees the new partitions.
# ------------------------------------------------------------------------------
log "Forcing sync and partprobe to read new UUIDs..."
log_debug "Running partprobe on $TARGET_DISK"

partprobe "$TARGET_DISK"
PARTPROBE_EXIT=$?
log_debug "partprobe exit code: $PARTPROBE_EXIT"

log_debug "Running udevadm settle..."
udevadm settle 2>/dev/null
log_debug "Waiting for device settle (5s)..."
sleep 5
log_debug "Syncing..."
sync
log_debug "Final wait (5s)..."
sleep 5

log_debug "Querying UUIDs with blkid..."
log_debug "Full blkid output for target disk:"
blkid "$TARGET_BOOT" "$TARGET_ROOT" >> "$TEMP_LOG" 2>&1

NEW_UUID_BOOT=$(blkid -s UUID -o value "$TARGET_BOOT")
NEW_UUID_ROOT=$(blkid -s UUID -o value "$TARGET_ROOT")

log "Detected UUID BOOT: $NEW_UUID_BOOT"
log "Detected UUID ROOT: $NEW_UUID_ROOT"
log_state "UUIDs" NEW_UUID_BOOT NEW_UUID_ROOT

if [ -z "$NEW_UUID_ROOT" ] || [ -z "$NEW_UUID_BOOT" ]; then
    
    log_error "CRITICAL: Failed to obtain UUIDs. Aborting config."
    log_debug "UUID_BOOT empty: $([ -z "$NEW_UUID_BOOT" ] && echo 'YES' || echo 'NO')"
    log_debug "UUID_ROOT empty: $([ -z "$NEW_UUID_ROOT" ] && echo 'YES' || echo 'NO')"
    log_debug "Attempting alternate UUID detection methods..."
    log_debug "lsblk UUID for BOOT: $(lsblk -no UUID $TARGET_BOOT 2>/dev/null)"
    log_debug "lsblk UUID for ROOT: $(lsblk -no UUID $TARGET_ROOT 2>/dev/null)"
    
    dialog --msgbox "Critical Error: Could not read new UUIDs." 10 60

    exit 1

fi

# ------------------------------------------------------------------------------
# ARMBIAN BOOT CONFIGURATION (armbianEnv.txt)
# This file contains boot parameters read by U-Boot:
#   - extraargs: Kernel command line arguments
#   - fdtfile: Device Tree Blob file for hardware description
#   - rootdev: UUID of root partition for mounting
# If file exists, we update it. Otherwise, create from template.
# ------------------------------------------------------------------------------
ARMBIANENV_FILE="$MNT_TGT_BOOT/armbianEnv.txt"
log_var ARMBIANENV_FILE
log_debug "Checking if armbianEnv.txt exists at: $ARMBIANENV_FILE"

if [ -f "$ARMBIANENV_FILE" ]; then

    log "armbianEnv.txt found, backing up..."
    log_debug "Original armbianEnv.txt content:"
    cat "$ARMBIANENV_FILE" >> "$TEMP_LOG" 2>&1

    cp "$ARMBIANENV_FILE" "${ARMBIANENV_FILE}.bak"
    log_debug "Backup created at: ${ARMBIANENV_FILE}.bak"

    log "Removing existing rootdev entries from armbianEnv.txt..."
    log_debug "Lines matching rootdev before removal: $(grep -c 'rootdev' "$ARMBIANENV_FILE" 2>/dev/null || echo '0')"

    # Remove existing rootdev entries to avoid duplicates
    sed -i '/^[[:space:]]*#*[[:space:]]*rootdev/d' "$ARMBIANENV_FILE"
    log_debug "Lines matching rootdev after removal: $(grep -c 'rootdev' "$ARMBIANENV_FILE" 2>/dev/null || echo '0')"

else

    log "armbianEnv.txt not found. It will be created from template."
    log_debug "Expected location was: $ARMBIANENV_FILE"
    log_debug "BOOT partition contents: $(ls -la $MNT_TGT_BOOT 2>/dev/null)"

    # ------------------------------------------------------------------
    # DTB (DEVICE TREE BLOB) SELECTION
    # The DTB describes the hardware configuration to the kernel.
    # Selecting the wrong DTB can cause boot failures or missing
    # peripherals (WiFi, Bluetooth, etc.).
    # Common naming: meson-gxl-s905x-*, meson-gxl-s905w-*, etc.
    # ------------------------------------------------------------------
    DTB_BASE_DIR="$MNT_TGT_BOOT/dtb"
    log_var DTB_BASE_DIR

    DTB_SEARCH_DIR="${DTB_BASE_DIR}/amlogic"
    log_debug "Checking for amlogic subdirectory: $DTB_SEARCH_DIR"

    if [ ! -d "$DTB_SEARCH_DIR" ]; then
        log_debug "amlogic subdirectory not found, using base DTB directory"
        DTB_SEARCH_DIR="$DTB_BASE_DIR"
    fi
    log_var DTB_SEARCH_DIR

    log "Scanning for DTBs in $DTB_SEARCH_DIR..."
    log_debug "DTB directory contents: $(ls $DTB_SEARCH_DIR 2>/dev/null | head -20)"

    DTB_OPTIONS=()

    while IFS= read -r filepath; do

        filename=$(basename "$filepath")

        relative_path="${filepath#$DTB_BASE_DIR/}"
        
        DTB_OPTIONS+=("$filename" "$relative_path") 
    
    done < <(find "$DTB_SEARCH_DIR" -maxdepth 1 -name "*.dtb" | sort)    

    if [ ${#DTB_OPTIONS[@]} -eq 0 ]; then

        log "ERROR: No DTB files found."

        dialog --msgbox "No .dtb files found in $DTB_SEARCH_DIR.\nCannot configure bootloader automatically." 10 50

        SELECTED_DTB_PATH=""

    else

        dialog --backtitle "$BACKTITLE" \
            --title "DTB Selection" \
            --msgbox "\nWe need to specify the correct Device Tree Blob (DTB).\n\nSelecting the wrong DTB may cause boot failure or Wi-Fi issues.\n\nExample:\n- S905X usually uses 'meson-gxl-s905x...'\n- S905W usually uses 'meson-gxl-s905w...'" 14 60

        SELECTED_DTB_REL=$(dialog --clear \
            --backtitle "$BACKTITLE" \
            --title "Select Hardware Model (DTB)" \
            --menu "\nChoose the DTB file that matches your TV Box:\n" \
            20 75 10 \
            "${DTB_OPTIONS[@]}" \
            2>&1 >/dev/tty)
        
        EXIT_CODE=$?
        log_debug "DTB dialog exit code: $EXIT_CODE"
        if [ $EXIT_CODE -ne 0 ]; then
            log_warn "User cancelled DTB selection."
            SELECTED_DTB_REL=""
        else
            log "User selected DTB: $SELECTED_DTB_REL"
            log_debug "Full DTB path would be: $DTB_BASE_DIR/$SELECTED_DTB_REL"
        fi

    fi

    if [ -z "$SELECTED_DTB_REL" ]; then
        FDT_LINE="# fdtfile=SELECT_MANUALLY_AFTER_REBOOT"
        log_warn "No DTB selected - user must configure manually after reboot"
    else
        FDT_LINE="fdtfile=$SELECTED_DTB_REL"
    fi
    log_var FDT_LINE

    log "Writing armbianEnv.txt using Amlogic template..."
    log_debug "Template will include: extraargs, bootlogo, verbosity, usbstoragequirks, console, fdtfile"

    # Default kernel parameters for AMLogic devices:
    # - earlycon: Early console for boot debugging
    # - rootflags=data=writeback: Improves eMMC write performance
    # - fsck.fix/repair: Auto-fix filesystem errors on boot
    # - pd_ignore_unused/clk_ignore_unused: Prevents power domain issues
    echo "extraargs=earlycon=meson,0xfe07a000 console=ttyS0,921600n8 rootflags=data=writeback rw no_console_suspend consoleblank=0 fsck.fix=yes fsck.repair=yes net.ifnames=0 watchdog.stop_on_reboot=0 pd_ignore_unused clk_ignore_unused rootdelay=5" > "$ARMBIANENV_FILE"
    echo "bootlogo=false" >> "$ARMBIANENV_FILE"
    echo "verbosity=7" >> "$ARMBIANENV_FILE"
    echo "usbstoragequirks=0x2537:0x1066:u,0x2537:0x1068:u" >> "$ARMBIANENV_FILE"
    echo "console=both" >> "$ARMBIANENV_FILE"
    echo "" >> "$ARMBIANENV_FILE"
    echo "# DTB file selected during installation" >> "$ARMBIANENV_FILE"
    echo "$FDT_LINE" >> "$ARMBIANENV_FILE"
    echo "" >> "$ARMBIANENV_FILE"
    echo "# Enable ONLY for gxbb (S905) / gxl (S905X/L/W) to create fake u-boot header" >> "$ARMBIANENV_FILE"
    echo "#soc_fixup=gxl-" >> "$ARMBIANENV_FILE"

fi

echo -e "\nrootdev=UUID=$NEW_UUID_ROOT" >> "$ARMBIANENV_FILE"

log "--- CONTENT VERIFICATION: armbianEnv.txt ---"
cat "$ARMBIANENV_FILE" >> "$TEMP_LOG"
log "--------------------------------------------"

# ------------------------------------------------------------------------------
# FSTAB CONFIGURATION
# Creates a new /etc/fstab with UUID-based mount points.
# Using UUIDs ensures correct mounting even if device names change.
# Options:
#   - noatime: Don't update access times (reduces eMMC writes)
#   - commit=600: Sync data every 10 minutes (improves performance)
#   - errors=remount-ro: Remount read-only on errors
# ------------------------------------------------------------------------------
log "Updating /etc/fstab with new UUIDs..."

FSTAB_FILE="$MNT_TGT_ROOT/etc/fstab"
log_var FSTAB_FILE

if [ -f "$FSTAB_FILE" ]; then
    log "Backing up existing fstab..."
    log_debug "Original fstab content:"
    cat "$FSTAB_FILE" >> "$TEMP_LOG" 2>&1
    mv "$FSTAB_FILE" "${FSTAB_FILE}.old"
    log_debug "Backup created at: ${FSTAB_FILE}.old"
else
    log_debug "No existing fstab found at $FSTAB_FILE"
fi

log "Creating new fstab..."
log_debug "fstab entries will use:"
log_debug "  ROOT UUID: $NEW_UUID_ROOT"
log_debug "  BOOT UUID: $NEW_UUID_BOOT"

echo "# <file system> <mount point> <type> <options> <dump> <pass>" > "$FSTAB_FILE"
echo "tmpfs /tmp tmpfs defaults,nosuid 0 0" >> "$FSTAB_FILE"
echo "UUID=$NEW_UUID_ROOT / ext4 defaults,noatime,commit=600,errors=remount-ro 0 1" >> "$FSTAB_FILE"
echo "UUID=$NEW_UUID_BOOT /boot vfat defaults,noatime,umask=0077 0 2" >> "$FSTAB_FILE"

log "New fstab created successfully."

log "--- CONTENT VERIFICATION: fstab ---"
cat "$FSTAB_FILE" >> "$TEMP_LOG"
log "-----------------------------------"

log_header "PHASE 5: FINALIZATION"

dialog --backtitle "$BACKTITLE" \
       --title "Finishing" \
       --infobox "\nFinalizing installation and cleaning up...\n\nPlease wait." 7 60

log "Forcing final sync to disk..."
log_debug "Sync started at: $(date '+%H:%M:%S')"

sync

log_debug "Sync completed at: $(date '+%H:%M:%S')"
log_debug "Waiting 5 seconds before unmount..."
sleep 5

log "Unmounting all partitions..."
log_debug "Current mounts before cleanup:"
mount | grep "$WORK_DIR" >> "$TEMP_LOG" 2>&1 || log_debug "No mounts found under $WORK_DIR"

cleanup_mounts

log "All partitions unmounted successfully."
log_debug "Verifying unmount - mounts under $WORK_DIR:"
mount | grep "$WORK_DIR" >> "$TEMP_LOG" 2>&1 || log_debug "Confirmed: No mounts under $WORK_DIR"

log_header "INSTALLATION SUMMARY"
log "Profile Used: $SELECTED_PROFILE_NAME"
log "Target Disk: $TARGET_DISK"
log "Target BOOT: $TARGET_BOOT (UUID: $NEW_UUID_BOOT)"
log "Target ROOT: $TARGET_ROOT (UUID: $NEW_UUID_ROOT)"
log "Partition Offset: $OFFSET_START sectors"
log "Environment Injection: $ENV_INJECTION"
log_debug "Installation end time: $(date '+%Y-%m-%d %H:%M:%S')"
log_debug "Log file location: $TEMP_LOG"

dialog --colors \
       --backtitle "$BACKTITLE" \
       --title "Installation Complete" \
       --yes-label "Power Off" \
       --no-label "Exit to Shell" \
       --yesno "\n\Z2\ZbARMBIAN INSTALLATION COMPLETED SUCCESSFULLY!\Zn\n\nThe system has been installed to the internal eMMC.\nYou can now remove the USB Drive / SD Card.\n\nWould you like to power off the device now?" 15 60

EXIT_CODE=$?
log_debug "Final dialog exit code: $EXIT_CODE"

clear

if [ $EXIT_CODE -eq 0 ]; then

    log "User opted to power off the system."

    log "Installation complete. Powering off."

    echo "System is going down for power off now!"

    echo "Remove the installation media."
    
    sleep 2
    
    poweroff

else

    log "User opted to exit to shell."

    log "Installation complete. Exiting to shell."

    echo "Exiting to shell."

    echo "Remember to reboot or poweroff manually before removing the media."

fi