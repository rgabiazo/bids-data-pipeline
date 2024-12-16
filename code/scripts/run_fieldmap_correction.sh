#!/bin/bash

# Field Map Correction Script (run_fieldmap_correction.sh)

# This script applies field map correction using FSL's topup tool.
# It accounts for both task-based and resting-state fMRI data, adjusting file searches and processing accordingly.
# It also renames relevant output files to comply with BIDS format and removes unnecessary intermediate files.

# Default values
BASE_DIR=""
SESSIONS=()
SUBJECTS=()
PREPROCESSING_TYPE=""
SUBJECT_PREFIXES=("sub" "subj" "participant" "P" "pilot" "pilsub")

# Function to display help
usage() {
    echo "Usage: $0 --base-dir BASE_DIR [options] [--session SESSIONS...] [--preproc-type task|rest] [SUBJECTS...]"
    echo ""
    echo "Options:"
    echo "  --base-dir BASE_DIR       Base directory of the project (required)"
    echo "  --session SESSIONS        Sessions to process (e.g., ses-01 ses-02)"
    echo "  --preproc-type TYPE       Preprocessing type: 'task' or 'rest' (required)"
    echo "  SUBJECTS                  Subjects to process (e.g., sub-01 sub-02)"
    exit 1
}

# Parse arguments
POSITIONAL_ARGS=()
while [[ "$1" != "" ]]; do
    case $1 in
        -- )
            shift
            break
            ;;
        --base-dir )
            shift
            BASE_DIR="$1"
            ;;
        --session )
            shift
            if [[ "$1" == "" || "$1" == --* ]]; then
                echo "Error: --session requires an argument"
                usage
            fi
            SESSIONS+=("$1")
            ;;
        --preproc-type )
            shift
            if [[ "$1" != "task" && "$1" != "rest" ]]; then
                echo "Error: --preproc-type must be 'task' or 'rest'"
                usage
            fi
            PREPROCESSING_TYPE="$1"
            ;;
        -h | --help )
            usage
            ;;
        --* )
            echo "Unknown option: $1"
            usage
            ;;
        * )
            break
            ;;
    esac
    shift
done

# Remaining arguments are positional arguments (subjects)
while [[ "$1" != "" ]]; do
    SUBJECTS+=("$1")
    shift
done

# Check required arguments
if [ -z "$BASE_DIR" ]; then
    echo "Error: --base-dir is required"
    usage
fi

if [ -z "$PREPROCESSING_TYPE" ]; then
    echo "Error: --preproc-type is required and must be 'task' or 'rest'"
    usage
fi

# Prompt until a valid base directory is provided
while [ ! -d "$BASE_DIR" ]; do
    echo "Error: Base directory '$BASE_DIR' does not exist."
    read -p "Please enter a valid base directory: " BASE_DIR
done

# Set up logging
LOG_DIR="${BASE_DIR}/code/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/run_fieldmap_correction_$(date '+%Y-%m-%d_%H-%M-%S').log"

# Enable extended globbing
shopt -s extglob

# Start the main script content
{
    echo "Running fieldmap correction with the following parameters:" >> "$LOG_FILE"
    echo "Base directory: $BASE_DIR" >> "$LOG_FILE"
    echo "Preprocessing type: $PREPROCESSING_TYPE" >> "$LOG_FILE"
    if [ ${#SESSIONS[@]} -gt 0 ]; then
        echo "Sessions: ${SESSIONS[@]}" >> "$LOG_FILE"
    else
        echo "Sessions: All sessions" >> "$LOG_FILE"
    fi
    if [ ${#SUBJECTS[@]} -gt 0 ]; then
        echo "Subjects: ${SUBJECTS[@]}" >> "$LOG_FILE"
    else
        echo "Subjects: All subjects" >> "$LOG_FILE"
    fi
    echo "Logging to $LOG_FILE" >> "$LOG_FILE"

    # Function to collect and sort subject directories
    collect_subject_dirs() {
        SUBJECT_DIRS=()
        for prefix in "${SUBJECT_PREFIXES[@]}"; do
            for subj_dir in "$BASE_DIR"/${prefix}-*; do
                if [ -d "$subj_dir" ]; then
                    SUBJECT_DIRS+=("$subj_dir")
                fi
            done
        done
        # Remove duplicates and sort
        IFS=$'\n' SUBJECT_DIRS=($(printf "%s\n" "${SUBJECT_DIRS[@]}" | sort -uV))
    }

    # Get list of subject directories
    SUBJECT_DIRS=()

    if [ ${#SUBJECTS[@]} -gt 0 ]; then
        # Use specified subjects
        for subj in "${SUBJECTS[@]}"; do
            SUBJECT_DIR="$BASE_DIR/$subj"
            if [ -d "$SUBJECT_DIR" ]; then
                SUBJECT_DIRS+=("$SUBJECT_DIR")
            else
                echo "Warning: Subject directory not found: $SUBJECT_DIR"
            fi
        done
    else
        # Collect all subject directories into an array
        collect_subject_dirs
    fi

    if [ ${#SUBJECT_DIRS[@]} -eq 0 ]; then
        echo "No subject directories found."
        exit 1
    fi

    echo -e "\nFound ${#SUBJECT_DIRS[@]} subject directories."

    # Now process each subject and session
    for SUBJ_DIR in "${SUBJECT_DIRS[@]}"; do
        SUBJ_ID="$(basename "$SUBJ_DIR")"
        echo -e "\n--- Processing subject: $SUBJ_ID ---" | tee -a "$LOG_FILE"

        # Function to collect and sort session directories
        collect_session_dirs() {
            SESSION_DIRS=()
            for ses_dir in "$SUBJ_DIR"/ses-*; do
                if [ -d "$ses_dir" ]; then
                    SESSION_DIRS+=("$ses_dir")
                fi
            done
            # Sort the session directories
            IFS=$'\n' SESSION_DIRS=($(printf "%s\n" "${SESSION_DIRS[@]}" | sort -V))
        }

        # Find sessions
        SESSION_DIRS=()

        if [ ${#SESSIONS[@]} -gt 0 ]; then
            # Use specified sessions
            for ses in "${SESSIONS[@]}"; do
                SES_DIR="$SUBJ_DIR/$ses"
                if [ -d "$SES_DIR" ]; then
                    SESSION_DIRS+=("$SES_DIR")
                else
                    echo "Warning: Session directory not found: $SES_DIR"
                fi
            done
        else
            # Collect all session directories into an array
            collect_session_dirs
        fi

        if [ ${#SESSION_DIRS[@]} -eq 0 ]; then
            echo "No sessions found for subject $SUBJ_ID"
            continue
        fi

        for SES_DIR in "${SESSION_DIRS[@]}"; do
            SES_ID="$(basename "$SES_DIR")"
            echo -e "Session: $SES_ID\n"

            # Process functional data
            FUNC_DIR="$SES_DIR/func"
            if [ -d "$FUNC_DIR" ]; then
                # Find BOLD files
                BOLD_FILES=()
                if [ "$PREPROCESSING_TYPE" == "task" ]; then
                    # For task-based fMRI, exclude 'task-rest' data
                    while IFS= read -r line; do
                        BOLD_FILES+=("$line")
                    done < <(find "$FUNC_DIR" -type f -name "*_task-*_bold.nii.gz" ! -name "*_task-rest_bold.nii.gz" | sort -V)
                else
                    # For resting-state fMRI
                    while IFS= read -r line; do
                        BOLD_FILES+=("$line")
                    done < <(find "$FUNC_DIR" -type f -name "*_task-rest_bold.nii.gz" | sort -V)
                fi

                if [ ${#BOLD_FILES[@]} -eq 0 ]; then
                    echo "No BOLD files found in $FUNC_DIR"
                else
                    for BOLD_FILE in "${BOLD_FILES[@]}"; do
                        BOLD_BASENAME="$(basename "$BOLD_FILE" .nii.gz)"
                        echo -e "BOLD file:\n  - $BOLD_FILE"

                        # Extract run number
                        RUN_NUMBER=$(echo "$BOLD_BASENAME" | grep -o 'run-[0-9]\+')
                        if [ -z "$RUN_NUMBER" ]; then
                            RUN_NUMBER=""
                            RUN_ENTITY=""
                        else
                            RUN_ENTITY="_${RUN_NUMBER}"
                        fi

                        # Extract task name
                        TASK_NAME=$(echo "$BOLD_BASENAME" | grep -o 'task-[^_]\+' | sed 's/task-//')

                        DERIV_TOPUP_DIR="$BASE_DIR/derivatives/fsl/topup/$SUBJ_ID/$SES_ID"

                        # Set up directories
                        FUNC_DERIV_DIR="$DERIV_TOPUP_DIR/func"
                        FMAP_DERIV_DIR="$DERIV_TOPUP_DIR/fmap"
                        mkdir -p "$FUNC_DERIV_DIR" "$FMAP_DERIV_DIR"

                        # Check if topup has already been applied
                        # Insert 'desc-topupcorrected' before '_bold' in the filename
                        CORRECTED_BOLD="$FUNC_DERIV_DIR/${BOLD_BASENAME/_bold/_desc-topupcorrected_bold}.nii.gz"

                        if [ -f "$CORRECTED_BOLD" ]; then
                            if [ -n "$RUN_NUMBER" ]; then
                                echo "  Topup correction has already been applied for $SUBJ_ID $SES_ID $RUN_NUMBER. Skipping topup." | tee -a "$LOG_FILE"
                            else
                                echo "  Topup correction has already been applied for $SUBJ_ID $SES_ID. Skipping topup." | tee -a "$LOG_FILE"
                            fi
                            continue
                        else
                            if [ -n "$RUN_NUMBER" ]; then
                                echo "  Correcting BOLD data for susceptibility distortions using topup for $SUBJ_ID $SES_ID $RUN_NUMBER." | tee -a "$LOG_FILE"
                            else
                                echo "  Correcting BOLD data for susceptibility distortions using topup for $SUBJ_ID $SES_ID." | tee -a "$LOG_FILE"
                            fi

                            # Determine if TASK_NAME is empty and adjust filenames accordingly
                            if [ -n "$TASK_NAME" ]; then
                                TASK_ENTITY="_task-${TASK_NAME}"
                            else
                                TASK_ENTITY=""
                            fi

                            # Construct filenames
                            AP_IMAGE="$FMAP_DERIV_DIR/${SUBJ_ID}_${SES_ID}${TASK_ENTITY}${RUN_ENTITY}_acq-AP_epi.nii.gz"

                            # Extract first volume of BOLD (AP)
                            echo -e "\nExtracting first volume of BOLD (AP):\n  - Input BOLD file: $BOLD_FILE\n  - Output AP image: $AP_IMAGE" | tee -a "$LOG_FILE"
                            fslroi "$BOLD_FILE" "$AP_IMAGE" 0 1

                            # Get corresponding JSON file
                            BOLD_JSON="${BOLD_FILE%.nii.gz}.json"
                            if [ ! -f "$BOLD_JSON" ]; then
                                echo "  JSON file not found for $BOLD_FILE" | tee -a "$LOG_FILE"
                                continue
                            fi

                            # Read PhaseEncodingDirection and TotalReadoutTime from JSON
                            PHASE_DIR=$(jq -r '.PhaseEncodingDirection' "$BOLD_JSON")
                            READOUT_TIME=$(jq -r '.TotalReadoutTime' "$BOLD_JSON")

                            # Acquisition parameters file
                            ACQ_PARAMS_FILE="$FMAP_DERIV_DIR/${SUBJ_ID}_${SES_ID}${TASK_ENTITY}${RUN_ENTITY}_acq-params.txt"

                            if [[ "$PHASE_DIR" == "j-" ]]; then
                                echo "0 -1 0 $READOUT_TIME" > "$ACQ_PARAMS_FILE"
                            elif [[ "$PHASE_DIR" == "j" ]]; then
                                echo "0 1 0 $READOUT_TIME" > "$ACQ_PARAMS_FILE"
                            else
                                echo "  Unsupported PhaseEncodingDirection: $PHASE_DIR" | tee -a "$LOG_FILE"
                                continue
                            fi

                            # Find corresponding PA image
                            PA_FILE=""
                            if [ "$PREPROCESSING_TYPE" == "task" ]; then
                                # For task-based fMRI, exclude 'task-rest' PA images
                                if [ -n "$TASK_NAME" ]; then
                                    # First, try to find a PA image with the same task name
                                    PA_FILE=$(find "$FUNC_DIR" -type f -name "*task-${TASK_NAME}_dir-PA_epi.nii.gz" ! -name "*_task-rest*_dir-PA_epi.nii.gz" | sort -V | head -n 1)
                                fi
                                if [ -z "$PA_FILE" ]; then
                                    # If not found, try to find a general PA image without task name
                                    PA_FILE=$(find "$FUNC_DIR" -type f -name "*_dir-PA_epi.nii.gz" ! -name "*_task-rest*_dir-PA_epi.nii.gz" | sort -V | head -n 1)
                                fi
                            else
                                # For resting-state fMRI
                                PA_FILE=$(find "$FUNC_DIR" -type f -name "*_task-rest_dir-PA_epi.nii.gz" | sort -V | head -n 1)
                                if [ -z "$PA_FILE" ]; then
                                    # Try general PA image
                                    PA_FILE=$(find "$FUNC_DIR" -type f -name "*_dir-PA_epi.nii.gz" | sort -V | head -n 1)
                                fi
                            fi

                            # Extract first volume of PA
                            PA_IMAGE="$FMAP_DERIV_DIR/${SUBJ_ID}_${SES_ID}${TASK_ENTITY}${RUN_ENTITY}_acq-PA_epi.nii.gz"
                            echo -e "\nExtracting first volume of PA:" | tee -a "$LOG_FILE"
                            if [ -z "$PA_FILE" ]; then
                                echo "  - No PA image found for $SUBJ_ID $SES_ID" | tee -a "$LOG_FILE"
                                continue
                            else
                                echo -e "  - Input PA image: $PA_FILE\n  - Output PA image: $PA_IMAGE" | tee -a "$LOG_FILE"
                                fslroi "$PA_FILE" "$PA_IMAGE" 0 1
                            fi

                            # Read PA JSON file
                            PA_JSON="${PA_FILE%.nii.gz}.json"
                            if [ ! -f "$PA_JSON" ]; then
                                echo "  JSON file not found for PA image $PA_FILE" | tee -a "$LOG_FILE"
                                continue
                            fi

                            # Read PhaseEncodingDirection and TotalReadoutTime from JSON
                            PA_PHASE_DIR=$(jq -r '.PhaseEncodingDirection' "$PA_JSON")
                            PA_READOUT_TIME=$(jq -r '.TotalReadoutTime' "$PA_JSON")

                            # Append to ACQ_PARAMS_FILE
                            if [[ "$PA_PHASE_DIR" == "j" ]]; then
                                echo "0 1 0 $PA_READOUT_TIME" >> "$ACQ_PARAMS_FILE"
                            elif [[ "$PA_PHASE_DIR" == "j-" ]]; then
                                echo "0 -1 0 $PA_READOUT_TIME" >> "$ACQ_PARAMS_FILE"
                            else
                                echo "  Unsupported PhaseEncodingDirection for PA: $PA_PHASE_DIR" | tee -a "$LOG_FILE"
                                continue
                            fi

                            # Merge AP and PA images
                            MERGED_AP_PA="$FMAP_DERIV_DIR/${SUBJ_ID}_${SES_ID}${TASK_ENTITY}${RUN_ENTITY}_acq-AP_PA_merged.nii.gz"
                            echo -e "\nMerging AP and PA images:\n  - Input AP: $AP_IMAGE\n  - Input PA: $PA_IMAGE\n  - Output: $MERGED_AP_PA" | tee -a "$LOG_FILE"
                            fslmerge -t "$MERGED_AP_PA" "$AP_IMAGE" "$PA_IMAGE"

                            # Run topup
                            TOPUP_OUTPUT_BASE="$FMAP_DERIV_DIR/${SUBJ_ID}_${SES_ID}${TASK_ENTITY}${RUN_ENTITY}_topup"

                            echo -e "\nEstimating susceptibility:" | tee -a "$LOG_FILE"
                            echo -e "  - Input (merged AP and PA): $MERGED_AP_PA" | tee -a "$LOG_FILE"
                            echo -e "  - Acquisition parameters file: $ACQ_PARAMS_FILE" | tee -a "$LOG_FILE"
                            echo -e "  - Output base: ${TOPUP_OUTPUT_BASE}_results" | tee -a "$LOG_FILE"
                            echo -e "  - Fieldmap output: ${TOPUP_OUTPUT_BASE}_fieldmap.nii.gz" | tee -a "$LOG_FILE"
                            topup --imain="$MERGED_AP_PA" --datain="$ACQ_PARAMS_FILE" --config=b02b0.cnf --out="${TOPUP_OUTPUT_BASE}_results" --fout="${TOPUP_OUTPUT_BASE}_fieldmap.nii.gz"

                            # Apply topup to the BOLD data
                            echo -e "\nApplying topup to BOLD data:\n  - Input: $BOLD_FILE\n  - Output: $CORRECTED_BOLD\n" | tee -a "$LOG_FILE"
                            applytopup --imain="$BOLD_FILE" --topup="${TOPUP_OUTPUT_BASE}_results" --datain="$ACQ_PARAMS_FILE" --inindex=1 --method=jac --out="$CORRECTED_BOLD"

                            # Rename fieldmap output to BIDS format
                            if [ "$PREPROCESSING_TYPE" == "task" ]; then
                                if [ -n "$TASK_NAME" ]; then
                                    FIELD_MAP="$FMAP_DERIV_DIR/${SUBJ_ID}_${SES_ID}_task-${TASK_NAME}${RUN_ENTITY}_fieldmap.nii.gz"
                                else
                                    FIELD_MAP="$FMAP_DERIV_DIR/${SUBJ_ID}_${SES_ID}${RUN_ENTITY}_fieldmap.nii.gz"
                                fi
                            else
                                FIELD_MAP="$FMAP_DERIV_DIR/${SUBJ_ID}_${SES_ID}_task-rest${RUN_ENTITY}_fieldmap.nii.gz"
                            fi
                            mv "${TOPUP_OUTPUT_BASE}_fieldmap.nii.gz" "$FIELD_MAP"

                            # Remove unnecessary intermediate files
                            rm -f "$AP_IMAGE" "$PA_IMAGE" "$MERGED_AP_PA" "${TOPUP_OUTPUT_BASE}_results_fieldcoef.nii.gz" "${TOPUP_OUTPUT_BASE}_results_movpar.txt"

                            # Optionally, you can remove the ACQ_PARAMS_FILE if not needed
                            # rm -f "$ACQ_PARAMS_FILE"
                        fi
                    done
                fi
            else
                echo "Functional directory not found: $FUNC_DIR"
            fi
        done
    done

    echo -e "\nFieldmap correction completed."
    echo "------------------------------------------------------------------------------"

} 2>&1 | tee -a "$LOG_FILE"

# End of script
