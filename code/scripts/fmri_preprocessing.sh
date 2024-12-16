#!/bin/bash

# fmri_preprocessing.sh
#
# Description:
# This script orchestrates fMRI preprocessing steps including:
#   - Skull stripping (BET or SynthStrip)
#   - Field map correction (topup)
#   - Conversion of events from TSV to TXT for FEAT (task-based only)
#   - Slice timing extraction from BOLD JSON files
#
# It leverages modular helper scripts:
#   - run_bet_extraction.sh
#   - run_synthstrip_extraction.sh
#   - run_fieldmap_correction.sh
#   - create_event_files.sh
#   - extract_slice_timing.sh
#
# Requirements:
#   - Homebrew for managing packages
#   - FSL (installed at /usr/local/fsl)
#   - FreeSurfer (if using SynthStrip)
#   - jq for JSON parsing (brew install jq)
#
# Usage:
#   1. Place this script in `code/scripts` of your BIDS project.
#   2. Run: ./fmri_preprocessing.sh
#   3. Follow interactive prompts.
#
# Outputs:
#   - Logs in `code/logs`.
#   - Skull-stripped images in `derivatives/fsl` or `derivatives/freesurfer`.
#   - Field map corrected data in `derivatives/fsl/topup`.
#   - Event files in `derivatives/custom_events`.
#   - Slice timing files in `derivatives/slice_timing`.

# Set up base directory
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
BASE_DIR_DEFAULT="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo -e "\n=== fMRI Preprocessing Pipeline ==="

# Prompt for base directory
echo -e "\nPlease enter the base directory for the project or hit Enter/Return to use the default [$BASE_DIR_DEFAULT]:"
read -p "> " BASE_DIR_INPUT

if [ -z "$BASE_DIR_INPUT" ]; then
    BASE_DIR="$BASE_DIR_DEFAULT"
else
    BASE_DIR="$BASE_DIR_INPUT"
fi

echo -e "Using base directory: $BASE_DIR\n"

LOG_DIR="${BASE_DIR}/code/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/task_fmri_preprocessing_$(date '+%Y-%m-%d_%H-%M-%S').log"

# Start logging
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting preprocessing pipeline at $(date)" >> "$LOG_FILE"
echo "Base directory: $BASE_DIR" >> "$LOG_FILE"
echo "Script directory: $SCRIPT_DIR" >> "$LOG_FILE"
echo "Log file: $LOG_FILE" >> "$LOG_FILE"

# Preprocessing type: task or rest (with numeric menu)
while true; do
    echo "Is the preprocessing for task-based fMRI or resting-state fMRI?"
    echo "1. Task-based"
    echo "2. Resting-state"
    read -p "Enter the number corresponding to your choice: " PREPROC_CHOICE
    case $PREPROC_CHOICE in
        1 )
            PREPROCESSING_TYPE="task"
            break;;
        2 )
            PREPROCESSING_TYPE="rest"
            break;;
        * )
            echo "Please enter 1 for task-based or 2 for resting-state."
            ;;
    esac
done

# Apply skull stripping?
while true; do
    echo ""
    read -p "Apply skull stripping? (y/n): " APPLY_SKULL_STRIP
    case $APPLY_SKULL_STRIP in
        [Yy]* )
            APPLY_SKULL_STRIP="yes"
            break;;
        [Nn]* )
            APPLY_SKULL_STRIP="no"
            break;;
        * )
            echo "Please answer y or n.";;
    esac
done

# If yes, choose skull stripping tool
if [ "$APPLY_SKULL_STRIP" == "yes" ]; then
    echo "Please select a skull stripping tool:"
    echo "1. BET (FSL)"
    echo "2. SynthStrip (FreeSurfer)"
    echo ""
    while true; do
        read -p "Enter the number corresponding to your choice: " SKULL_STRIP_TOOL_CHOICE
        case $SKULL_STRIP_TOOL_CHOICE in
            1|BET|bet )
                SKULL_STRIP_TOOL="BET"
                break;;
            2|SynthStrip|synthstrip )
                SKULL_STRIP_TOOL="SynthStrip"
                break;;
            * )
                echo "Please enter 1 for BET or 2 for SynthStrip."
                ;;
        esac
    done

    echo "Selected skull stripping tool: $SKULL_STRIP_TOOL"

    if [ "$SKULL_STRIP_TOOL" == "BET" ]; then
        echo "Please select a BET option:"
        echo ""
        echo "1. Standard brain extraction (bet2)"
        echo "2. Robust brain center estimation (-R)"
        echo "3. Eye and optic nerve cleanup (-S)"
        echo "4. Bias field and neck cleanup (-B)"
        echo "5. Improve BET for small FOV in Z-direction (-Z)"
        echo "6. Apply to 4D fMRI data (-F)"
        echo "7. bet2 followed by betsurf (-A)"
        echo ""

        while true; do
            read -p "Enter the number corresponding to your choice: " BET_OPTION_CHOICE
            case $BET_OPTION_CHOICE in
                1 )
                    BET_OPTION=""
                    BET_OPTION_DESC="Standard brain extraction"
                    break;;
                2 )
                    BET_OPTION="-R"
                    BET_OPTION_DESC="Robust brain center estimation"
                    break;;
                3 )
                    BET_OPTION="-S"
                    BET_OPTION_DESC="Eye and optic nerve cleanup"
                    break;;
                4 )
                    BET_OPTION="-B"
                    BET_OPTION_DESC="Bias field and neck cleanup"
                    break;;
                5 )
                    BET_OPTION="-Z"
                    BET_OPTION_DESC="Improve BET for small FOV in Z-direction"
                    break;;
                6 )
                    BET_OPTION="-F"
                    BET_OPTION_DESC="Apply to 4D fMRI data"
                    break;;
                7 )
                    BET_OPTION="-A"
                    BET_OPTION_DESC="bet2 followed by betsurf"
                    break;;
                * )
                    echo "Please enter a valid number.";;
            esac
        done

        echo "Selected BET option: $BET_OPTION_DESC"

        while true; do
            read -p "Please enter the fractional intensity threshold (0 to 1, default 0.5): " FRAC_INTENSITY
            if [[ -z "$FRAC_INTENSITY" ]]; then
                FRAC_INTENSITY=0.5
                break
            elif [[ "$FRAC_INTENSITY" =~ ^0(\.[0-9]+)?$|^1(\.0+)?$ ]]; then
                break
            else
                echo "Please enter a number between 0 and 1."
            fi
        done
        echo "Using fractional intensity threshold: $FRAC_INTENSITY"
    fi
fi

# Apply fslreorient2std?
while true; do
    read -p "Do you want to apply fslreorient2std to all T1w images? (y/n): " APPLY_REORIENT_ALL
    case $APPLY_REORIENT_ALL in
        [Yy]* )
            APPLY_REORIENT_ALL="yes"
            break;;
        [Nn]* )
            APPLY_REORIENT_ALL="no"
            break;;
        * )
            echo "Please answer y or n.";;
    esac
done

# Fieldmap correction?
while true; do
    echo ""
    read -p "Do you want to apply fieldmap correction using topup? (y/n): " APPLY_TOPUP
    echo ""
    case $APPLY_TOPUP in
        [Yy]* )
            APPLY_TOPUP="yes"
            break;;
        [Nn]* )
            APPLY_TOPUP="no"
            break;;
        * )
            echo "Please answer y or n.";;
    esac
done

# If task-based, ask about event files
if [ "$PREPROCESSING_TYPE" == "task" ]; then
    while true; do
        read -p "Would you like to create .txt event files from .tsv files? (y/n): " CREATE_TXT_EVENTS
        case $CREATE_TXT_EVENTS in
            [Yy]* )
                CREATE_TXT_EVENTS="yes"
                break;;
            [Nn]* )
                CREATE_TXT_EVENTS="no"
                break;;
            * )
                echo "Please answer y or n.";;
        esac
    done

    if [ "$CREATE_TXT_EVENTS" == "yes" ]; then
        read -p "Enter the number of runs: " NUM_RUNS
        while ! [[ "$NUM_RUNS" =~ ^[0-9]+$ ]]; do
            echo "Please enter a valid number."
            read -p "Enter the number of runs: " NUM_RUNS
        done
        echo "Enter the trial types separated by spaces (e.g., encoding_pair recog_pair):"
        read -a TRIAL_TYPES_ARRAY
    fi

    # Ask if user wants to extract slice timing
    while true; do
        echo ""
        read -p "Do you want to extract slice timing information from BOLD JSON files? (y/n): " EXTRACT_SLICE_TIMING
        case $EXTRACT_SLICE_TIMING in
            [Yy]* )
                EXTRACT_SLICE_TIMING="yes"
                break;;
            [Nn]* )
                EXTRACT_SLICE_TIMING="no"
                break;;
            * )
                echo "Please answer y or n.";;
        esac
    done

else
    CREATE_TXT_EVENTS="no"
    EXTRACT_SLICE_TIMING="no"
fi

# Subjects and sessions
echo -e "\nEnter the subject IDs to process (e.g., sub-01 sub-02), or press Enter/Return to process all subjects:"
read -p "> " -a SUBJECTS_ARRAY

echo "Enter the session IDs to process (e.g., ses-01 ses-02), or press Enter/Return to process all sessions:"
read -p "> " -a SESSIONS_ARRAY

# Run skull stripping if chosen
if [ "$APPLY_SKULL_STRIP" == "yes" ]; then
    if [ "$SKULL_STRIP_TOOL" == "BET" ]; then
        echo -e "\n=== Running BET skull stripping ==="
        BET_ARGS=("--base-dir" "$BASE_DIR")
        if [ "$APPLY_REORIENT_ALL" == "yes" ]; then
            BET_ARGS+=("--reorient")
        fi
        if [ -n "$BET_OPTION" ]; then
            BET_ARGS+=("--bet-option" "$BET_OPTION")
        fi
        if [ -n "$FRAC_INTENSITY" ]; then
            BET_ARGS+=("--frac" "$FRAC_INTENSITY")
        fi
        for session in "${SESSIONS_ARRAY[@]}"; do
            BET_ARGS+=("--session" "$session")
        done
        if [ ${#SUBJECTS_ARRAY[@]} -gt 0 ]; then
            BET_ARGS+=("--")
            BET_ARGS+=("${SUBJECTS_ARRAY[@]}")
        fi
        "${SCRIPT_DIR}/run_bet_extraction.sh" "${BET_ARGS[@]}"
    else
        echo -e "\n=== Running SynthStrip skull stripping ==="
        SYNTHSTRIP_ARGS=("--base-dir" "$BASE_DIR")
        if [ "$APPLY_REORIENT_ALL" == "yes" ]; then
            SYNTHSTRIP_ARGS+=("--reorient")
        fi
        for session in "${SESSIONS_ARRAY[@]}"; do
            SYNTHSTRIP_ARGS+=("--session" "$session")
        done
        if [ ${#SUBJECTS_ARRAY[@]} -gt 0 ]; then
            SYNTHSTRIP_ARGS+=("--")
            SYNTHSTRIP_ARGS+=("${SUBJECTS_ARRAY[@]}")
        fi
        "${SCRIPT_DIR}/run_synthstrip_extraction.sh" "${SYNTHSTRIP_ARGS[@]}"
    fi
fi

# Run fieldmap correction if chosen
if [ "$APPLY_TOPUP" == "yes" ]; then
    echo -e "\n=== Applying fieldmap correction ==="
    TOPUP_ARGS=("--base-dir" "$BASE_DIR" "--preproc-type" "$PREPROCESSING_TYPE")
    for session in "${SESSIONS_ARRAY[@]}"; do
        TOPUP_ARGS+=("--session" "$session")
    done
    if [ ${#SUBJECTS_ARRAY[@]} -gt 0 ]; then
        TOPUP_ARGS+=("--")
        TOPUP_ARGS+=("${SUBJECTS_ARRAY[@]}")
    fi
    "${SCRIPT_DIR}/run_fieldmap_correction.sh" "${TOPUP_ARGS[@]}"
fi

# Create event files if chosen
if [ "$CREATE_TXT_EVENTS" == "yes" ]; then
    echo -e "\n=== Creating event files ==="
    EVENT_ARGS=("--base-dir" "$BASE_DIR" "--num-runs" "$NUM_RUNS" "--trial-types" "${TRIAL_TYPES_ARRAY[@]}")
    for session in "${SESSIONS_ARRAY[@]}"; do
        EVENT_ARGS+=("--session" "$session")
    done
    if [ ${#SUBJECTS_ARRAY[@]} -gt 0 ]; then
        EVENT_ARGS+=("--")
        EVENT_ARGS+=("${SUBJECTS_ARRAY[@]}")
    fi
    "${SCRIPT_DIR}/create_event_files.sh" "${EVENT_ARGS[@]}"
fi

# Extract slice timing if chosen
if [ "$EXTRACT_SLICE_TIMING" == "yes" ]; then
    echo -e "\n=== Extracting slice timing ==="
    ST_ARGS=("--base-dir" "$BASE_DIR")
    for session in "${SESSIONS_ARRAY[@]}"; do
        ST_ARGS+=("--session" "$session")
    done
    if [ ${#SUBJECTS_ARRAY[@]} -gt 0 ]; then
        ST_ARGS+=("--")
        ST_ARGS+=("${SUBJECTS_ARRAY[@]}")
    fi
    "${SCRIPT_DIR}/extract_slice_timing.sh" "${ST_ARGS[@]}"
fi

echo -e "\n=== Preprocessing pipeline completed ===\n"
echo -e "\n=== Preprocessing pipeline completed at $(date) ===\n" >> "$LOG_FILE"
