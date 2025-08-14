#!/bin/bash

####################################
# Copyright (c) [2025] [@ravindu644]
####################################

shopt -s expand_aliases
set -e

export SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export WDIR="${SCRIPT_DIR}"
export RECOVERY_LINK="$1"
export MODEL="$2"
mkdir -p "recovery" "output" "log"
source "${WDIR}/binaries/env.sh"
source "${WDIR}/binaries/gofile.sh"

# Clean-up is required
rm -rf "${WDIR}/recovery/"*
: > "${WDIR}/log/log.txt"

# Define magiskboot's, boot_editor's path and aliases
export BOOT_EDITOR="${WDIR}/boot_editor_v15_r1/gradlew"
export MAGISKBOOT="${WDIR}/binaries/magiskboot"
alias r_unpack="$BOOT_EDITOR unpack"
alias r_repack="$BOOT_EDITOR pack"
alias r_clean="$BOOT_EDITOR clear"

# Define the usage
usage() {
  warn "Usage" "./patch-recovery.sh <URL/Path> <Model Number>"
  exit 1
}

[[ -z "$RECOVERY_LINK" || -z "$MODEL" ]] && usage

# Welcome banner, Install requirements if not installed
init_patch_recovery(){
    info "patch-recovery-revived" "By @ravindu644\n"

    # Install the requirements for building the kernel when running the script for the first time
    if [ ! -f ".requirements" ]; then
        info "\n[INFO]" "Installing requirements...\n"
        {
            sudo apt update -y
            sudo apt install -y lz4 git device-tree-compiler lz4 xz-utils zlib1g-dev openjdk-17-jdk gcc g++ python3 python-is-python3 p7zip-full android-sdk-libsparse-utils erofs-utils
        } >> "${WDIR}/log/log.txt" 2>&1 && touch .requirements
    fi
}

# Source the hex patches database
if [ -f "${WDIR}/hex-patches.sh" ]; then
    source "${WDIR}/hex-patches.sh"
    info "[INFO]" "Loaded $(get_patch_count) hex patches from database.\n"
else
    warn "[ERROR]" "hex-patches.sh not found! Please ensure it exists in the script directory.\n"
    exit 1
fi

# Downloading/copying the recovery
download_recovery(){
    if [[ "${RECOVERY_LINK}" =~ ^https?:// ]]; then
        log "[INFO] Downloading" "${RECOVERY_LINK}\n"
        curl -L "${RECOVERY_LINK}" -o "${WDIR}/recovery/$(basename "${RECOVERY_LINK}")"
    elif [ -f "${RECOVERY_LINK}" ]; then
        cp "${RECOVERY_LINK}" "${WDIR}/recovery/"
    else
        warn "[ERROR] Invalid input" "not a URL or file.\n"
        warn "If you entered a URL, make sure it begins with" "'http://' or 'https://'\n"
        exit 1
    fi
}

# Check if the downloaded/copied file an archive
unarchive_recovery(){

    set -x 
    cd "${WDIR}/recovery/"
    local FILE=$(ls)
    [[ "$FILE" == *.zip ]] && unzip "$FILE" && rm "$FILE"
    [[ "$FILE" == *.lz4 ]] && lz4 -d "$FILE" "${FILE%.lz4}" && rm "$FILE"

    # Check for recovery or vendor boot image
    if [ -f "recovery.img" ]; then
        export RECOVERY_FILE="$(pwd)/recovery.img"
    elif [ -f "vendor_boot.img" ]; then
        export RECOVERY_FILE="$(pwd)/vendor_boot.img"
    else
        warn "[ERROR]" "give a proper recovery.img or vendor_boot.img"
        exit 1
    fi

    export RECOVERY_SIZE=$(stat -c%s "${RECOVERY_FILE}")
    export IMAGE_NAME="$(basename ${RECOVERY_FILE})"

    cd "${WDIR}/"

    set +x
}

# Extract recovery.img
extract_recovery_image(){
    cd "$(dirname $BOOT_EDITOR)"

    log "\n[INFO] Extracting" "${RECOVERY_FILE}"

    # Clean the previous work
    set +e ; r_clean >>"${WDIR}/log/log.txt" 2>&1 ; set -e

    # Copied the file to the boot editor's path
    cp -ar $RECOVERY_FILE "$(dirname $BOOT_EDITOR)" 

    # Unpack
    r_unpack >>"${WDIR}/log/log.txt" 2>&1

    # Some hack to find the exact file to patch
    export PATCHING_TARGET=$(find . -wholename "*/system/bin/recovery" -exec realpath {} \; | head -n 1)
    if [ -n "$PATCHING_TARGET" ]; then
        info "\n[INFO] Found target" "$(basename ${PATCHING_TARGET})"

    else
        fatal "target file not found for patching."
    fi

    cd "${WDIR}/"

    echo ""    
}

# Function to apply hex patches to the recovery binary
apply_hex_patches(){
    local binary_file="$1"
    local patches_applied=0
    local total_patches=${#HEX_PATCHES[@]}
    
    log "[LOG] Applying hex patches to" "${binary_file}"
    log "[LOG] Total patches to try" "${total_patches}\n"
    
    # Temporarily disable exit on error for individual patch attempts
    set +e
    
    for patch in "${HEX_PATCHES[@]}"; do
        # Split the patch string into search and replace patterns
        local search_pattern="${patch%%:*}"
        local replace_pattern="${patch##*:}"
        
        log "[PATCH] Trying" "${search_pattern} -> ${replace_pattern}"
        
        # Apply the patch and capture the exit code
        ${MAGISKBOOT} hexpatch "${binary_file}" "${search_pattern}" "${replace_pattern}"
        local patch_result=$?
        
        if [ $patch_result -eq 0 ]; then
            info "[SUCCESS]" "Patch applied successfully\n"
            ((patches_applied++))
        else
            warn "[SKIP] Pattern not found" "skipping..\n"
        fi
    done
    
    # Re-enable exit on error
    set -e
    
    log "[SUMMARY]" "Applied ${patches_applied}/${total_patches} patches\n"
    
    # Return success if at least one patch was applied
    if [ $patches_applied -gt 0 ]; then
        info "[INFO]" "Hex patching completed successfully\n"
        return 0
    else
        warn "[ERROR]" "No matching hex byte pattern found, aborting..\n"
        return 1
    fi
}

# Hex patch the "recovery" binary to get fastbootd mode back
hexpatch_recovery_image(){

    local recovery_binary="${PATCHING_TARGET}"
    
    # Apply hex patches and check result
    if ! apply_hex_patches "${recovery_binary}"; then
        fatal "Hex patching failed, cannot continue\n"
    fi

}

# Repack the fastbootd patched recovery image
repack_recovery_image(){

    cd "$(dirname $BOOT_EDITOR)"

    log "\n[INFO] Repacking to" "${WDIR}/output/${IMAGE_NAME}\n"

    r_repack >>"${WDIR}/log/log.txt" 2>&1

	mv -f "$(ls *.signed)" "${WDIR}/output/${IMAGE_NAME}"

    cd "${WDIR}/"
}

# Create an ODIN-flashable tar
create_tar(){

    cd "${WDIR}/output/"

    lz4 -B6 --content-size ${IMAGE_NAME} ${IMAGE_NAME}.lz4 && \
        rm ${IMAGE_NAME}

    tar -cvf "${MODEL}-Fastbootd-patched-${IMAGE_NAME%.*}.tar" ${IMAGE_NAME}.lz4 && \
        rm ${IMAGE_NAME}.lz4

    info "\n[INFO] Created ODIN-flashable tar" "${PWD}/${MODEL}-Fastbootd-patched-${IMAGE_NAME%.*}.tar\n"

    # Optional GoFile upload
    if [[ "$GOFILE" == "1" ]]; then
        upload_to_gofile "${MODEL}-Fastbootd-patched-${IMAGE_NAME%.*}.tar"
    fi
    
    cd "${WDIR}/"
}

cleanup_source(){
    rm -rf "${WDIR}/recovery/"*

    cd "$(dirname $BOOT_EDITOR)" ; set +e ; r_clean >>"${WDIR}/log/log.txt" 2>&1 ; set -e ; cd "${WDIR}"
}

init_patch_recovery
download_recovery
unarchive_recovery
extract_recovery_image
hexpatch_recovery_image
repack_recovery_image
create_tar
cleanup_source
