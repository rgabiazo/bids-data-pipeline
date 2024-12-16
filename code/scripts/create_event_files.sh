#!/bin/bash

# create_event_files.sh
#
# Description:
# Converts .tsv event files into .txt format for use in FSL FEAT, printing three columns:
# onset, duration, and amplitude (fixed at 1.000). Ensures consistent decimal formatting.
# Logs operations and prints output in a structured style similar to extract_slice_timing.sh.
#
# Arguments:
#   --base-dir BASE_DIR    The base project directory (required)
#   --num-runs NUM_RUNS    Number of runs (required)
#   --trial-types ...      A list of trial types (e.g., encoding_pair recog_pair)
#   --sessions ...         List of session IDs (e.g., ses-01, ses-02)
#   SUBJECTS               List of subject IDs (if none, all sub/pilot subjects are used)
#
# Requirements:
#   - Properly structured BIDS directory
#
# Outputs:
#  - For each run and each trial type, a .txt file is created in:
#    `derivatives/custom_events/<sub>/<ses>/<sub>_<ses>_run-XX_desc-<trial_type>_events.txt`
#  Each line contains three columns: onset duration amplitude(=1.000)
#
# If the output event file already exists, it notifies the user and skips it.
# If multiple event files match a run, the first matched file is used.

BASE_DIR=""
NUM_RUNS=""
TRIAL_TYPES=()
SESSIONS=()
SUBJECTS=()

usage() {
    echo "Usage: $0 --base-dir BASE_DIR --num-runs NUM_RUNS --trial-types TRIAL_TYPES... [--sessions SESSIONS...] [SUBJECTS...]"
    exit 1
}

if [ "$#" -eq 0 ]; then
    usage
fi

POSITIONAL_ARGS=()
PARSE_TRIAL_TYPES="no"

while [[ "$1" != "" ]]; do
    case $1 in
        --base-dir )
            shift
            BASE_DIR="$1"
            ;;
        --num-runs )
            shift
            NUM_RUNS="$1"
            ;;
        --trial-types )
            shift
            PARSE_TRIAL_TYPES="yes"
            while [[ "$1" != "" && "$1" != --* ]]; do
                TRIAL_TYPES+=("$1")
                shift
            done
            ;;
        --sessions )
            shift
            while [[ "$1" != "" && "$1" != --* ]]; do
                SESSIONS+=("$1")
                shift
            done
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
            SUBJECTS+=("$1")
            ;;
    esac
    [ "$PARSE_TRIAL_TYPES" = "yes" ] && [ "${#TRIAL_TYPES[@]}" -gt 0 ] && PARSE_TRIAL_TYPES="done"
    shift
done

if [ -z "$BASE_DIR" ]; then
    echo "Error: --base-dir is required"
    usage
fi

if [ -z "$NUM_RUNS" ]; then
    echo "Error: --num-runs is required"
    usage
fi

if [ ${#TRIAL_TYPES[@]} -eq 0 ]; then
    echo "Error: --trial-types is required"
    usage
fi

# Default sessions if none provided
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

echo "Starting event file creation at $(date)" >> "$LOG_FILE"
echo "Base directory: $BASE_DIR" >> "$LOG_FILE"
echo "Number of runs: $NUM_RUNS" >> "$LOG_FILE"
echo "Trial types: ${TRIAL_TYPES[@]}" >> "$LOG_FILE"
echo "Sessions: ${SESSIONS[@]}" >> "$LOG_FILE"
echo "Subjects: ${SUBJECTS[@]}" >> "$LOG_FILE"
echo "Log file: $LOG_FILE" >> "$LOG_FILE"

EVENTS_DIR="${BASE_DIR}/derivatives/custom_events"

SUBJECT_COUNT=${#SUBJECTS[@]}
echo ""
echo "Found $SUBJECT_COUNT subject directories."

for subj_dir in "${SUBJECTS[@]}"; do
    echo -e "\n--- Processing subject: $subj_dir ---"
    for ses in "${SESSIONS[@]}"; do
        echo "Session: $ses"
        echo ""

        func_dir="${BASE_DIR}/${subj_dir}/${ses}/func"
        if [ ! -d "$func_dir" ]; then
            echo "No func directory found for $subj_dir $ses at $func_dir"
            continue
        fi

        # Collect all event files for these runs
        EVENT_FILES=()
        for (( run=1; run<=$NUM_RUNS; run++ )); do
            run_str=$(printf "%02d" $run)
            # Find any events file for this run
            found_events=($(find "$func_dir" -type f -name "${subj_dir}_${ses}_*run-${run_str}_*events.tsv" | sort -V))
            if [ ${#found_events[@]} -gt 0 ]; then
                # Take the first matched events file if multiple found
                EVENT_FILES+=("${found_events[0]}")
            fi
        done

        if [ ${#EVENT_FILES[@]} -eq 0 ]; then
            echo "No event TSV files found for $subj_dir $ses."
            continue
        fi

        echo "  Found TSV files:"
        for ef in "${EVENT_FILES[@]}"; do
            echo "    - $(basename "$ef")"
        done
        echo ""

        # Now process each events file
        for events_file in "${EVENT_FILES[@]}"; do
            echo "  Extracting events from:"
            echo "    $events_file"
            echo ""

            output_dir="${EVENTS_DIR}/${subj_dir}/${ses}"
            mkdir -p "$output_dir"

            # Extract run number from filename
            run_str=$(echo "$events_file" | sed -E 's/.*_run-([0-9]+)_events\.tsv/\1/')

            echo "  Output files:"
            for trial_type in "${TRIAL_TYPES[@]}"; do
                output_file="${output_dir}/${subj_dir}_${ses}_run-${run_str}_desc-${trial_type}_events.txt"

                # If output file already exists, skip
                if [ -f "$output_file" ]; then
                    echo "    File already exists, skipping:"
                    echo "      $output_file"
                    echo ""
                    continue
                fi

                # Filter the events file for the given trial type and print onset, duration, amplitude=1.000
                awk -F '\t' -v tt="$trial_type" '
                    NR==1 {
                        for (i=1;i<=NF;i++){
                            if($i=="trial_type") c=i
                            if($i=="onset") oncol=1
                            if($i=="duration") durcol=2
                        }
                    } 
                    NR>1 && $c==tt {
                       # Print onset with one decimal, duration and amplitude with three decimals
                        printf "%.1f %.3f %.3f\n", $oncol, $durcol, 1.000
                    }' "$events_file" > "$output_file"

                echo "    Created events .txt file:"
                echo "      $output_file"
                echo ""
            done
        done
    done
done

echo "Event file creation completed at $(date)" >> "$LOG_FILE"
echo ""
echo "Event .txt files created."
echo "------------------------------------------------------------------------------"
