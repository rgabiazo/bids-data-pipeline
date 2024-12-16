#!/bin/bash

# extract_slice_timing.sh
#
# Description:
# Extracts slice timing information from BOLD JSON sidecar files and saves them as .txt files.
#
# Modified to accept --session arguments instead of --sessions.
# Each --session argument should be followed by exactly one session ID.
# Example usage:
#   ./extract_slice_timing.sh --base-dir /path/to/BIDS --session ses-01 sub-01 sub-02
#
# Requirements:
#   - jq must be installed (brew install jq)
#
# Outputs:
#  - For each BOLD JSON file found, a corresponding slice timing .txt file is created:
#    `derivatives/slice_timing/<sub>/<ses>/func/<...>_slice_timing.txt`.
#
# If the output file already exists, it notifies the user and skips processing.

BASE_DIR=""
SUBJECTS=()
SESSIONS=()

usage() {
    echo "Usage: $0 --base-dir BASE_DIR [--session ses-XX]... [SUBJECTS...]"
    echo ""
    echo "Arguments:"
    echo "  --base-dir BASE_DIR    The base project directory (required)"
    echo "  --session ses-XX       Specify one or more sessions (e.g., --session ses-01 --session ses-02)."
    echo "                         If none provided, defaults to ses-01."
    echo "  SUBJECTS...            One or more subject IDs (e.g., sub-01). If none are provided, all sub-*/pilot-* directories in BASE_DIR are processed."
    exit 1
}

if [ "$#" -eq 0 ]; then
    usage
fi

POSITIONAL_ARGS=()
while [[ "$1" != "" ]]; do
    case $1 in
        --base-dir )
            shift
            BASE_DIR="$1"
            ;;
        --session )
            shift
            if [[ "$1" == "" || "$1" == --* ]]; then
                echo "Error: --session requires a session ID argument"
                usage
            fi
            SESSIONS+=("$1")
            ;;
        --help | -h )
            usage
            ;;
        -- )
            shift
            while [[ "$1" != "" ]]; do
                SUBJECTS+=("$1")
                shift
            done
            ;;
        -* )
            echo "Unknown option: $1"
            usage
            ;;
        * )
            # Non-option argument, assume subject
            SUBJECTS+=("$1")
            ;;
    esac
    shift
done

if [ -z "$BASE_DIR" ]; then
    echo "Error: --base-dir is required"
    usage
fi

# Default session if not provided
if [ ${#SESSIONS[@]} -eq 0 ]; then
    SESSIONS=("ses-01")
fi

# If no subjects provided, find all sub-* or pilot-* directories
if [ ${#SUBJECTS[@]} -eq 0 ]; then
    SUBJECTS=($(find "$BASE_DIR" -maxdepth 1 -type d -name "sub-*" -exec basename {} \;))
    PILOT_SUBJS=($(find "$BASE_DIR" -maxdepth 1 -type d -name "pilot-*" -exec basename {} \;))
    SUBJECTS+=("${PILOT_SUBJS[@]}")
    # Remove duplicates and sort
    IFS=$'\n' SUBJECTS=($(printf "%s\n" "${SUBJECTS[@]}" | sort -uV))
fi

LOG_DIR="${BASE_DIR}/code/logs"
mkdir -p "$LOG_DIR"
SCRIPT_NAME=$(basename "$0")
LOG_FILE="${LOG_DIR}/${SCRIPT_NAME%.*}_$(date '+%Y-%m-%d_%H-%M-%S').log"

# Start logging
exec > >(tee -i "$LOG_FILE") 2>&1

echo "Starting slice timing extraction at $(date)" >> "$LOG_FILE"
echo "Base directory: $BASE_DIR" >> "$LOG_FILE"
echo "Subjects: ${SUBJECTS[@]}" >> "$LOG_FILE"
echo "Sessions: ${SESSIONS[@]}" >> "$LOG_FILE"
echo "Log file: $LOG_FILE" >> "$LOG_FILE"

if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install jq (brew install jq) and re-run."
    exit 1
fi

DERIVATIVES_DIR="${BASE_DIR}/derivatives/slice_timing"

SUBJECT_COUNT=${#SUBJECTS[@]}
echo ""
echo "Found $SUBJECT_COUNT subjects."

for subj in "${SUBJECTS[@]}"; do
    echo -e "\n--- Processing subject: $subj ---"
    for sess in "${SESSIONS[@]}"; do
        echo "Session: $sess"
        echo ""

        func_dir="${BASE_DIR}/${subj}/${sess}/func"
        if [ ! -d "$func_dir" ]; then
            echo "No func directory found for $subj $sess at $func_dir"
            continue
        fi

        json_files=($(find "$func_dir" -type f -name "*_bold.json" | sort -V))

        if [ ${#json_files[@]} -eq 0 ]; then
            echo "No BOLD JSON files found for $subj $sess."
            continue
        fi

        echo "  Found BOLD JSON files:"
        for jf in "${json_files[@]}"; do
            echo "    - $(basename "$jf")"
        done
        echo ""

        for json_file in "${json_files[@]}"; do
            json_filename=$(basename "$json_file" .json)
            output_dir="${DERIVATIVES_DIR}/${subj}/${sess}/func"
            mkdir -p "$output_dir"
            slice_timing_file="${output_dir}/${json_filename}_slice_timing.txt"

            # Check if slice timing file already exists
            if [ -f "$slice_timing_file" ]; then
                echo "  Slice timing file already exists, skipping:"
                echo "    $slice_timing_file"
                echo ""
                continue
            fi

            echo "  Extracting slice timing from:"
            echo "    $json_file"
            echo "  Output:"
            echo "    $slice_timing_file"
            echo ""

            jq '.SliceTiming[]' "$json_file" > "$slice_timing_file"

            if [[ ! -s "$slice_timing_file" ]]; then
                echo "SliceTiming field is missing or empty in $json_file"
                rm -f "$slice_timing_file"
            fi
        done
    done
done

echo "Slice timing extraction completed at $(date)" >> "$LOG_FILE"
