#!/bin/bash

# ==============================================================================
# ARMBIAN-INSTALL-AMLOGIC — SYSTEM INSTALLER
# Installs armbian-install-amlogic into the running system.
# Allows selective installation of device profiles and their assets.
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
# SOURCE DIRECTORY
# All paths are resolved relative to the script's own location,
# so the installer works regardless of where it is called from.
# ------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_SCRIPT="${SCRIPT_DIR}/armbian-install-amlogic.sh"
SRC_PROFILES_DIR="${SCRIPT_DIR}/armbian-install-amlogic/profiles"
SRC_ASSETS_DIR="${SCRIPT_DIR}/armbian-install-amlogic/assets"

# ------------------------------------------------------------------------------
# DESTINATION PATHS
# ------------------------------------------------------------------------------
DEST_BIN="/usr/bin/armbian-install-amlogic"
DEST_BASE="/etc/armbian-install-amlogic"
DEST_PROFILES_DIR="${DEST_BASE}/profiles"
DEST_ASSETS_DIR="${DEST_BASE}/assets"

# ------------------------------------------------------------------------------
# LOGGING
# ------------------------------------------------------------------------------
TEMP_LOG="/tmp/armbian-install-amlogic-installer.log"
BACKTITLE="ARMBIAN-INSTALL-AMLOGIC — System Installer — by Pedro Rigolin"

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

log_header "New Installer Session: $(date '+%d/%m/%Y %H:%M:%S')"
log "Script directory: $SCRIPT_DIR"

# ------------------------------------------------------------------------------
# TRAP HANDLER
# ------------------------------------------------------------------------------
trap 'tput cnorm; clear; echo "Installer finished or interrupted."; exit' INT TERM EXIT

# ------------------------------------------------------------------------------
# DEPENDENCY CHECK
# ------------------------------------------------------------------------------
DEPENDENCIES=(dialog pigz)
MISSING_PKGS=()

echo "Checking dependencies..."

for pkg in "${DEPENDENCIES[@]}"; do
    if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
        echo "Dependency missing: $pkg"
        MISSING_PKGS+=("$pkg")
    fi
done

if [ ${#MISSING_PKGS[@]} -ne 0 ]; then
    echo "Installing missing dependencies: ${MISSING_PKGS[*]}"
    apt-get update
    apt-get install -y "${MISSING_PKGS[@]}"
    if [ $? -ne 0 ]; then
        echo "CRITICAL ERROR: Failed to install dependencies (${MISSING_PKGS[*]})."
        exit 1
    fi
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
        --msgbox "\nProfiles directory not found:\n  $SRC_PROFILES_DIR\n\nEnsure the repository structure is intact." 10 60
    log_error "Profiles directory not found: $SRC_PROFILES_DIR"
    exit 1
fi

if [ ! -d "$SRC_ASSETS_DIR" ]; then
    dialog --backtitle "$BACKTITLE" \
        --title "Error" \
        --ok-label "OK" \
        --msgbox "\nAssets directory not found:\n  $SRC_ASSETS_DIR\n\nEnsure the repository structure is intact." 10 60
    log_error "Assets directory not found: $SRC_ASSETS_DIR"
    exit 1
fi

# ------------------------------------------------------------------------------
# PROFILE DISCOVERY
# Iterates over all .conf files in the profiles directory.
# Extracts BOARD_NAME for display and ENV_FILE for asset resolution.
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
    log_debug "No profiles found, checklist will show Generic Installation only."
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
    --checklist "\nSelect the device profiles to install.\nUse SPACE to select, ENTER to confirm.\n" \
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
        log "Installation cancelled by user during format selection."
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
    --title "Confirm Installation" \
    --yes-label "Install" \
    --no-label "Cancel" \
    --yesno "\nThe following profiles will be installed into the running system:\n${SUMMARY}\n\nDestination:\n  ${DEST_BIN}\n  ${DEST_BASE}/\n" \
    20 70

if [ $? -ne 0 ]; then
    log "Installation cancelled by user at confirmation."
    exit 0
fi

# ------------------------------------------------------------------------------
# INSTALLATION
# ------------------------------------------------------------------------------
log_header "Installation"

dialog --backtitle "$BACKTITLE" \
    --title "Installing" \
    --infobox "\nCreating destination directories..." 5 45

log "Creating destination directories..."
mkdir -p "$DEST_PROFILES_DIR" "$DEST_ASSETS_DIR"

log "Installing main script: $SRC_SCRIPT -> $DEST_BIN"
cp "$SRC_SCRIPT" "$DEST_BIN" && chmod +x "$DEST_BIN"
if [ $? -ne 0 ]; then
    dialog --backtitle "$BACKTITLE" \
        --title "Error" \
        --ok-label "OK" \
        --msgbox "\nFailed to install main script to:\n  $DEST_BIN" 8 55
    log_error "Failed to copy main script to $DEST_BIN"
    exit 1
fi

log "Main script installed successfully."

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
        --title "Installing" \
        --infobox "\nInstalling profile: ${board_name}..." 5 55

    log "Copying profile: $conf_file -> $DEST_PROFILES_DIR/$conf_basename"
    cp "$conf_file" "$DEST_PROFILES_DIR/$conf_basename"

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
            log "Copying asset (gz): $src_gz -> $DEST_ASSETS_DIR/"
            cp "$src_gz" "$DEST_ASSETS_DIR/"
            if [ $? -ne 0 ]; then
                log_error "Failed to copy asset: $src_gz"
                ((INSTALL_ERRORS++))
                continue
            fi
        elif [ -f "$src_img" ]; then
            log "Asset .gz not found, compressing from .img: $src_img"
            dialog --backtitle "$BACKTITLE" \
                --title "Installing" \
                --infobox "\nCompressing asset for ${board_name}...\nThis may take a moment." 6 55
            pigz -9 -c "$src_img" > "$DEST_ASSETS_DIR/${asset_basename}.gz"
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
            log "Copying asset (img): $src_img -> $DEST_ASSETS_DIR/"
            cp "$src_img" "$DEST_ASSETS_DIR/"
            if [ $? -ne 0 ]; then
                log_error "Failed to copy asset: $src_img"
                ((INSTALL_ERRORS++))
                continue
            fi
        elif [ -f "$src_gz" ]; then
            log "Asset .img not found, decompressing from .gz: $src_gz"
            dialog --backtitle "$BACKTITLE" \
                --title "Installing" \
                --infobox "\nDecompressing asset for ${board_name}...\nThis may take a moment." 6 55
            pigz -dc "$src_gz" > "$DEST_ASSETS_DIR/${asset_basename}"
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

    log "Profile '${board_name}' installed successfully."

done

# ------------------------------------------------------------------------------
# RESULT
# ------------------------------------------------------------------------------
if [ $INSTALL_ERRORS -gt 0 ]; then
    dialog --backtitle "$BACKTITLE" \
        --title "Installation Completed with Errors" \
        --ok-label "OK" \
        --msgbox "\nInstallation completed with ${INSTALL_ERRORS} error(s).\n\nCheck the log for details:\n  $TEMP_LOG" 10 60
    log_error "Installation completed with $INSTALL_ERRORS error(s)."
    exit 1
else
    dialog --backtitle "$BACKTITLE" \
        --title "Installation Complete" \
        --ok-label "OK" \
        --msgbox "\nInstallation completed successfully.\n\nThe installer is now available at:\n  $DEST_BIN\n\nRun it as root to install Armbian to eMMC." 12 60
    log "Installation completed successfully."
fi

exit 0
