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
    cd "${WDIR}/recovery/"
    local FILE=$(ls)
    [[ "$FILE" == *.zip ]] && unzip "$FILE" && rm "$FILE"
    [[ "$FILE" == *.lz4 ]] && lz4 -d "$FILE" "${FILE%.lz4}" > /dev/null 2>&1 && rm "$FILE"
    [[ "$FILE" == *.tar ]] && tar -xf "$FILE" && rm "$FILE"

    # Decompress any lz4 files that were extracted from zip/tar archives
    for lz4_file in *.lz4; do
        if [ -f "$lz4_file" ]; then
            log "[INFO]" "Decompressing ${lz4_file}"
            lz4 -d "$lz4_file" "${lz4_file%.lz4}" >>"${WDIR}/log/log.txt" 2>&1 && rm "$lz4_file"
        fi
    done

    # Check for recovery or vendor boot image
    if [ -f "recovery.img" ]; then
        export RECOVERY_FILE="$(pwd)/recovery.img"
    elif [ -f "vendor_boot.img" ]; then
        export RECOVERY_FILE="$(pwd)/vendor_boot.img"
    else
        warn "[ERROR]" "give a proper recovery.img or vendor_boot.img"
        exit 1
    fi

    if [ -f "boot.img" ]; then
        export BOOT_FILE="$(pwd)/boot.img"
    fi

    export RECOVERY_SIZE=$(stat -c%s "${RECOVERY_FILE}")
    export IMAGE_NAME="$(basename ${RECOVERY_FILE})"

    cd "${WDIR}/"
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
    r_unpack >>"${WDIR}/log/log.txt" 2>&1 || fatal "Unpacking failed\n"

    # check if the binary exists
    FASTBOOTD=$(find . -type f -path "*/system/bin/fastbootd" -exec realpath {} \; 2>/dev/null | head -n 1)
    [ -n "$FASTBOOTD" ] || fatal "Your recovery does not have a fastbootd binary. Patching would be useless. Aborting..\n"

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

    log "[INFO] Repacking to" "${WDIR}/output/${IMAGE_NAME}\n"

    r_repack >>"${WDIR}/log/log.txt" 2>&1 || fatal "Repacking failed\n"

	mv -f "$(ls *.signed)" "${WDIR}/output/${IMAGE_NAME}"

    cd "${WDIR}/"
}

break_boot_image(){
    # Break the SHA1 hash of the boot image by unpacking and repacking it
    if [ -n "$BOOT_FILE" ] && [ -f "$BOOT_FILE" ]; then
        log "\n[INFO] Breaking boot image signature" "${BOOT_FILE}"
        
        # Create a temporary directory for boot image processing
        local TEMP_DIR=$(mktemp -d -t boot_break.XXXXXX)
        trap "rm -rf '${TEMP_DIR}'" EXIT
        
        # Copy boot.img to temp directory
        cp "${BOOT_FILE}" "${TEMP_DIR}/boot.img"
        cd "${TEMP_DIR}"
        
        # Unpack the boot image
        log "[INFO] Unpacking" "boot.img"
        ${MAGISKBOOT} unpack boot.img >>"${WDIR}/log/log.txt" 2>&1 || fatal "Failed to unpack boot.img\n"
        
        # Repack the boot image (this breaks the signature)
        log "[INFO] Repacking" "boot.img (signature will be broken)"
        ${MAGISKBOOT} repack boot.img >>"${WDIR}/log/log.txt" 2>&1 || fatal "Failed to repack boot.img\n"
        
        # Move new-boot.img to output directory as boot.img
        if [ -f "new-boot.img" ]; then
            mv -f "new-boot.img" "${WDIR}/output/boot.img"
            info "\n[SUCCESS]" "Boot image signature broken, saved to output/boot.img\n"
        else
            fatal "new-boot.img was not created after repacking\n"
        fi
        
        # Return to working directory and remove temp directory
        cd "${WDIR}/"
        rm -rf "${TEMP_DIR}"
        trap - EXIT
    else
        log "[INFO]" "No boot.img found, skipping boot image signature breaking\n"
    fi
}

# Create an ODIN-flashable tar
create_tar(){

    cd "${WDIR}/output/"

    lz4 -B6 --content-size ${IMAGE_NAME} ${IMAGE_NAME}.lz4 && \
        rm ${IMAGE_NAME}

    # Build tar command with recovery image
    local TAR_FILES="${IMAGE_NAME}.lz4"
    
    # Add boot.img to tar if it exists (compress it first)
    if [ -f "boot.img" ]; then
        log "[INFO]" "Compressing boot.img with lz4\n"
        lz4 -B6 --content-size boot.img boot.img.lz4 && \
            rm boot.img
        TAR_FILES="${TAR_FILES} boot.img.lz4"
        log "[INFO]" "Including boot.img.lz4 in tar archive\n"
    fi

    tar -cvf "${MODEL}-Fastbootd-patched-${IMAGE_NAME%.*}.tar" ${TAR_FILES} && \
        rm -f *.lz4

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
break_boot_image
create_tar
cleanup_source
