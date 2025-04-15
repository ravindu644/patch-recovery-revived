#!/bin/bash

####################################
# Copyright (c) [2025] [@ravindu644]
####################################

set -e

export SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export RECOVERY_LINK="$1" MODEL="$2"
source "${SCRIPT_DIR}/binaries/colors" 
source "${SCRIPT_DIR}/binaries/gofile.sh"

mkdir -p "recovery" "unpacked" "output"

# Clean-up is required
rm -rf "${SCRIPT_DIR}/recovery/"* \
    "${SCRIPT_DIR}/unpacked/"*

# Define magiskboot,avbtool and signing key paths
AVB_KEY="${SCRIPT_DIR}/signing-keys/testkey_rsa2048.pem"
AVBTOOL="${SCRIPT_DIR}/binaries/avbtool"
MAGISKBOOT="${SCRIPT_DIR}/binaries/magiskboot"

# Define the usage
usage() {
  echo -e "${BOLD}${RED}Usage:${RESET} ${BOLD}./patch-recovery.sh <URL/Path> <Model Number>${RESET}"
  exit 1
}

[[ -z "$RECOVERY_LINK" || -z "$MODEL" ]] && usage

# Welcome banner, Install requirements if not installed
init_patch_recovery(){
    echo -e "\n${BLUE}patch-recovery-revived - By @ravindu644${RESET}\n"

    # Install the requirements for building the kernel when running the script for the first time
    if [ ! -f ".requirements" ]; then
        echo -e "\n\t${UNBOLD_GREEN}Installing requirements...${RESET}\n"
        {
            sudo apt update
            sudo apt install -y lz4 curl
        } && touch .requirements
    fi
}

# Downloading/copying the recovery
download_recovery(){
    if [[ "${RECOVERY_LINK}" =~ ^https?:// ]]; then

    echo -e "${LIGHT_YELLOW}[INFO] Downloading:${RESET} ${BOLD}${RECOVERY_LINK}${RESET}\n"

    curl -L "${RECOVERY_LINK}" -o "${SCRIPT_DIR}/recovery/$(basename "${RECOVERY_LINK}")"
    elif [ -f "${RECOVERY_LINK}" ]; then
    cp "${RECOVERY_LINK}" "${SCRIPT_DIR}/recovery/"
    else
    echo -e "${BOLD}${RED}Invalid input: not a URL or file.${RESET}\n"
    echo -e "${BOLD}${RED}If you entered a URL, make sure it begins with 'http://' or 'https://'${RESET}\n"
    exit 1
    fi
}

# Check if the downloaded/copied file an archive
unarchive_recovery(){

    set -x 
    cd "${SCRIPT_DIR}/recovery/"
    local FILE=$(ls)
    [[ "$FILE" == *.zip ]] && unzip "$FILE" && rm "$FILE"
    [[ "$FILE" == *.lz4 ]] && lz4 -d "$FILE" "${FILE%.lz4}" && rm "$FILE"

    # Only rename if recovery.img doesn't exists
    if [ ! -f recovery.img ]; then
        mv "$(ls *.img)" "recovery.img"
    fi

    cd "${SCRIPT_DIR}/"

    export RECOVERY_FILE="${SCRIPT_DIR}/recovery/recovery.img"
    export RECOVERY_SIZE=$(stat -c%s "${SCRIPT_DIR}/recovery/recovery.img")
    set +x
}

# Extract recovery.img
extract_recovery_image(){
    cd "${SCRIPT_DIR}/unpacked/"

    echo -e "${LIGHT_YELLOW}[INFO] Extracting:${RESET} ${BOLD}${RECOVERY_FILE}${RESET}\n"

	${MAGISKBOOT} unpack ${RECOVERY_FILE}
	${MAGISKBOOT} cpio ramdisk.cpio extract
    cd "${SCRIPT_DIR}/"
}

# Hex patch the "recovery" binary to get fastbootd mode back
hexpatch_recovery_image(){
    cd "${SCRIPT_DIR}/unpacked/"

    echo -e "${LIGHT_YELLOW}[INFO] Hex-patching:${RESET} ${BOLD}system/bin/recovery${RESET}\n"

    set +e

	${MAGISKBOOT} hexpatch system/bin/recovery e10313aaf40300aa6ecc009420010034 e10313aaf40300aa6ecc0094 # 20 01 00 35
	${MAGISKBOOT} hexpatch system/bin/recovery eec3009420010034 eec3009420010035
	${MAGISKBOOT} hexpatch system/bin/recovery 3ad3009420010034 3ad3009420010035
	${MAGISKBOOT} hexpatch system/bin/recovery 50c0009420010034 50c0009420010035
	${MAGISKBOOT} hexpatch system/bin/recovery 080109aae80000b4 080109aae80000b5
	${MAGISKBOOT} hexpatch system/bin/recovery 20f0a6ef38b1681c 20f0a6ef38b9681c
	${MAGISKBOOT} hexpatch system/bin/recovery 23f03aed38b1681c 23f03aed38b9681c
	${MAGISKBOOT} hexpatch system/bin/recovery 20f09eef38b1681c 20f09eef38b9681c
	${MAGISKBOOT} hexpatch system/bin/recovery 26f0ceec30b1681c 26f0ceec30b9681c
	${MAGISKBOOT} hexpatch system/bin/recovery 24f0fcee30b1681c 24f0fcee30b9681c
	${MAGISKBOOT} hexpatch system/bin/recovery 27f02eeb30b1681c 27f02eeb30b9681c
	${MAGISKBOOT} hexpatch system/bin/recovery b4f082ee28b1701c b4f082ee28b970c1
	${MAGISKBOOT} hexpatch system/bin/recovery 9ef0f4ec28b1701c 9ef0f4ec28b9701c

	${MAGISKBOOT} hexpatch system/bin/recovery 9ef00ced28b1701c 9ef00ced28b9701c
	${MAGISKBOOT} hexpatch system/bin/recovery 2001597ae0000054 2001597ae1000054

    ${MAGISKBOOT} hexpatch system/bin/recovery 50860494f3031f2a 5086049433008052

    set -e

    cd "${SCRIPT_DIR}/"
}

# Repack the fastbootd patched recovery image
repack_recovery_image(){
    cd "${SCRIPT_DIR}/unpacked/"

    ${MAGISKBOOT}  cpio ramdisk.cpio 'add 0755 system/bin/recovery system/bin/recovery'

    echo -e "${LIGHT_YELLOW}[INFO] Repacking to:${RESET} ${BOLD}${SCRIPT_DIR}/output/patched-recovery.img${RESET}\n"

	${MAGISKBOOT}  repack ${RECOVERY_FILE} "${SCRIPT_DIR}/output/patched-recovery.img"

    cd "${SCRIPT_DIR}/"
}

# Sign the patched-recovery.img with Google's RSA private test key
sign_recovery_image(){

    echo -e "${LIGHT_YELLOW}[INFO] Signing with Google's RSA private test key:${RESET} ${BOLD}${SCRIPT_DIR}/output/patched-recovery.img${RESET}\n"

    ${AVBTOOL} \
        add_hash_footer \
        --partition_name recovery \
        --partition_size ${RECOVERY_SIZE} \
        --image "${SCRIPT_DIR}/output/patched-recovery.img" \
        --key ${AVB_KEY} \
        --algorithm SHA256_RSA2048
}

# Create an ODIN-flashable tar
create_tar(){
    cd "${SCRIPT_DIR}/output/"

    mv patched-recovery.img recovery.img && \
        lz4 -B6 --content-size recovery.img recovery.img.lz4 && \
        rm recovery.img

    tar -cvf "${MODEL}-Fastbootd-patched-recovery.tar" recovery.img.lz4 && \
        rm recovery.img.lz4

    echo -e "\n${LIGHT_YELLOW}[INFO] Created ODIN-flashable tar:${RESET} ${BOLD}${PWD}/${MODEL}-Fastbootd-patched-recovery.tar${RESET}\n"

    # Optional GoFile upload
    if [[ "$GOFILE" == "1" ]]; then
        upload_to_gofile "${MODEL}-Fastbootd-patched-recovery.tar"
    fi
    
    cd "${SCRIPT_DIR}/"
}

cleanup_source(){
    rm -rf "${SCRIPT_DIR}/recovery/"* \
        "${SCRIPT_DIR}/unpacked/"*   
}

init_patch_recovery
download_recovery
unarchive_recovery
extract_recovery_image
hexpatch_recovery_image
repack_recovery_image
sign_recovery_image
create_tar
cleanup_source
