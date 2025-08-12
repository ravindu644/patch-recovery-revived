#!/bin/bash

####################################
# Hex Patches Database
# Copyright (c) [2025] [@ravindu644]
####################################

# Define hex patches as an array of "search_pattern:replace_pattern" pairs
# Each patch should be on a separate line for better readability

declare -a HEX_PATCHES=(

    # Original Patches from phh
    "e10313aaf40300aa6ecc009420010034:e10313aaf40300aa6ecc0094"
    "eec3009420010034:eec3009420010035"
    "3ad3009420010034:3ad3009420010035"
    "50c0009420010034:50c0009420010035"
    "080109aae80000b4:080109aae80000b5"
    "20f0a6ef38b1681c:20f0a6ef38b9681c"
    "23f03aed38b1681c:23f03aed38b9681c"
    "20f09eef38b1681c:20f09eef38b9681c"
    "26f0ceec30b1681c:26f0ceec30b9681c"
    "24f0fcee30b1681c:24f0fcee30b9681c"
    "27f02eeb30b1681c:27f02eeb30b9681c"
    "b4f082ee28b1701c:b4f082ee28b970c1"
    "9ef0f4ec28b1701c:9ef0f4ec28b9701c"
    "9ef00ced28b1701c:9ef00ced28b9701c"
    "2001597ae0000054:2001597ae1000054"
    
    # --[ Copyright & Permission Notice ]--
    #
    # These hex patches were discovered and are maintained by @ravindu644.
    #
    # You may not copy, reuse, or include these patches in your own projects,
    # public or private, without obtaining direct, written permission from the author.
    #
    # All rights reserved.
    #

    # One UI 7 - Galaxy A16 5G patches, Issue #4
    "9b880494e0031f2a:9b88049420008052"
    "38880494f3031f2a:3888049433008052"

    # One UI 6 - Galaxy A16 5G patches
    "b3860494e0031f2a:b386049420008052"
    "50860494f3031f2a:5086049433008052"

    # Galaxy S25, Issue #7
    "7abb0594e0031f2a:7abb059420008052"

    # Galaxy S24, Issue #5
    "86940494e0031f2a:8694049420008052"
    "2c940494f3031f2a:2c94049433008052"
    
    # Galaxy S23fe
    "a81640f9a9835ff81f0109eb21010054e003142a:a81640f9a9835ff81f0109eb2101005420008052"

    # A556E
    "47a00494e0031f2a:47a0049420008052"
    "e89f0494f3031f2a:e89f049433008052"

    # SM-M145F, UI 6.1
    "21010054e003142af44f48a9:2101005420008052f44f48a9"
    "0ef70394f4031f2a:0ef7039434008052"
    "f4031f2a737a2491:34008052737a2491"
    "f4031f2a73e62191:3400805273e62191"
    "f4031f2a0c000014:340080520c000014"

    # SM-M215F
    "13faffb0f4031f2a:13faffb034008052"
    "f3f9fff0f4031f2a:f3f9fff034008052"
    "cafdff54f4031f2a:cafdff5434008052"
    "ab4a0394f4031f2a:ab4a039434008052"

    # SM-A015F (32-Bit)
    "884203d1284609b0:884203d1012009b0"
    "2548002578442ce0:2548012578442ce0"
    "28480025784430e0:28480125784430e0"
    "1a29efda002511e0:1a29efda012511e0"
    "7844b4f0a0ed0025:7844b4f0a0ed0125"

    # Add more patches here as needed
    # Format: "search_pattern:replace_pattern"
)

# Function to get total number of patches
get_patch_count() {
    echo ${#HEX_PATCHES[@]}
}

# Function to get a specific patch by index
get_patch_by_index() {
    local index=$1
    if [[ $index -ge 0 && $index -lt ${#HEX_PATCHES[@]} ]]; then
        echo "${HEX_PATCHES[$index]}"
    else
        return 1
    fi
}

# Function to list all patches (for debugging)
list_all_patches() {
    local i=0
    for patch in "${HEX_PATCHES[@]}"; do
        echo "[$i] $patch"
        ((i++))
    done
}

export HEX_PATCHES
