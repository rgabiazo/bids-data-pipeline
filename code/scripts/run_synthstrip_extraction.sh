#!/bin/bash

# SynthStrip Skull Stripping Script (run_synthstrip_extraction.sh)

# Default values
BASE_DIR=""
REORIENT="no"
SESSIONS=()
SUBJECTS=()
SUBJECT_PREFIXES=("sub" "subj" "participant" "P" "pilot" "pilsub")

# Function to display help
usage() {
    echo "Usage: $0 --base-dir BASE_DIR [options] [--session SESSIONS...] [SUBJECTS...]"
    echo ""
    echo "Options:"
    echo "  --base-dir BASE_DIR       Base directory of the project (required)"
    echo "  --reorient                Apply fslreorient2std to T1w images"
    echo "  --session SESSIONS        Sessions to process (e.g., ses-01 ses-02)"
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
        --reorient )
            REORIENT="yes"
            ;;
        --session )
            shift
            if [[ "$1" == "" || "$1" == --* ]]; then
                echo "Error: --session requires an argument"
                usage
            fi
            SESSIONS+=("$1")
            ;;
        -h | --help )
            usage
            ;;
        -* )
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
    POSITIONAL_ARGS+=("$1")
    shift
done

# Assign positional arguments to SUBJECTS
SUBJECTS=("${POSITIONAL_ARGS[@]}")

if [ -z "$BASE_DIR" ]; then
    echo "Error: --base-dir is required"
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
LOG_FILE="${LOG_DIR}/run_synthstrip_extraction_$(date '+%Y-%m-%d_%H-%M-%S').log"

# Start the main script content
{
    echo "Running SynthStrip skull stripping with the following parameters:" >> "$LOG_FILE"
    echo "Base directory: $BASE_DIR" >> "$LOG_FILE"
    echo "Reorient: $REORIENT" >> "$LOG_FILE"
    if [ ${#SESSIONS[@]} -gt 0 ]; then
        echo "Sessions: ${SESSIONS[@]}"
    fi
    if [ ${#SUBJECTS[@]} -gt 0 ]; then
        echo "Subjects: ${SUBJECTS[@]}"
    fi

    echo "Logging to $LOG_FILE" >> "$LOG_FILE"

    # Get list of subject directories
    SUBJECT_DIRS=()

    if [ ${#SUBJECTS[@]} -gt 0 ]; then
        # Use specified subjects
        for subj in "${SUBJECTS[@]}"; do
            SUBJ_DIR="$BASE_DIR/$subj"
            if [ -d "$SUBJ_DIR" ]; then
                SUBJECT_DIRS+=("$SUBJ_DIR")
            else
                echo -e "\nWarning: Subject directory not found: $SUBJ_DIR"
            fi
        done
    else
        # Collect all subject directories into an array
        for prefix in "${SUBJECT_PREFIXES[@]}"; do
            for subj_dir in "$BASE_DIR"/${prefix}-*; do
                if [ -d "$subj_dir" ]; then
                    SUBJECT_DIRS+=("$subj_dir")
                fi
            done
        done
        # Remove duplicates and sort
        IFS=$'\n' SUBJECT_DIRS=($(printf "%s\n" "${SUBJECT_DIRS[@]}" | sort -uV))
    fi

    if [ ${#SUBJECT_DIRS[@]} -eq 0 ]; then
        echo -e "\nNo subject directories found."
        exit 1
    fi

    echo -e "\nFound ${#SUBJECT_DIRS[@]} subject directories."

    # Now process each subject and session
    for SUBJ_DIR in "${SUBJECT_DIRS[@]}"; do
        SUBJ_ID="$(basename "$SUBJ_DIR")"
        echo -e "\n--- Processing subject: $SUBJ_ID ---"

        # Find sessions
        SESSION_DIRS=()

        if [ ${#SESSIONS[@]} -gt 0 ]; then
            # Use specified sessions
            for ses in "${SESSIONS[@]}"; do
                SES_DIR="$SUBJ_DIR/$ses"
                if [ -d "$SES_DIR" ]; then
                    SESSION_DIRS+=("$SES_DIR")
                else
                    echo -e "\nWarning: Session directory not found: $SES_DIR"
                fi
            done
        else
            # Collect all session directories into an array
            SESSION_DIRS=()
            for ses_dir in "$SUBJ_DIR"/ses-*; do
                if [ -d "$ses_dir" ]; then
                    SESSION_DIRS+=("$ses_dir")
                fi
            done
            # Sort the session directories
            IFS=$'\n' SESSION_DIRS=($(printf "%s\n" "${SESSION_DIRS[@]}" | sort -V))
        fi

        if [ ${#SESSION_DIRS[@]} -eq 0 ]; then
            echo "No sessions found for subject $SUBJ_ID"
            continue
        fi

        for SES_DIR in "${SESSION_DIRS[@]}"; do
            SES_ID="$(basename "$SES_DIR")"
            echo -e "Session: $SES_ID\n"

            # Now process the T1w images
            ANAT_DIR="$SES_DIR/anat"
            if [ -d "$ANAT_DIR" ]; then
                T1W_FILE="$ANAT_DIR/${SUBJ_ID}_${SES_ID}_T1w.nii.gz"
                if [ ! -f "$T1W_FILE" ]; then
                    echo "T1w image not found for $SUBJ_ID $SES_ID: $T1W_FILE"
                    continue
                fi
                echo -e "T1w image:\n  - $T1W_FILE"

                # Apply fslreorient2std if selected
                if [ "$REORIENT" == "yes" ]; then
                    REORIENTED_T1W_FILE="${ANAT_DIR}/${SUBJ_ID}_${SES_ID}_T1w_reoriented.nii.gz"
                    echo -e "Applying fslreorient2std to:\n  - $T1W_FILE"
                    fslreorient2std "$T1W_FILE" "$REORIENTED_T1W_FILE"
                    if [ $? -ne 0 ]; then
                        echo "Error applying fslreorient2std for $SUBJ_ID $SES_ID"
                        continue
                    fi
                    echo -e "fslreorient2std completed:\n  - $REORIENTED_T1W_FILE"
                    T1W_FILE="$REORIENTED_T1W_FILE"
                else
                    echo "Skipping fslreorient2std for $T1W_FILE"
                fi

                # Set output directory
                DERIV_ANAT_DIR="$BASE_DIR/derivatives/freesurfer/$SUBJ_ID/$SES_ID/anat"
                mkdir -p "$DERIV_ANAT_DIR"

                # Prepare output file name
                OUTPUT_FILE="$DERIV_ANAT_DIR/${SUBJ_ID}_${SES_ID}_desc-synthstrip_T1w_brain.nii.gz"

                if [ -f "$OUTPUT_FILE" ]; then
                    echo -e "\nSkull-stripped T1w image already exists: $OUTPUT_FILE\n"
                else
                    echo -e "Running SynthStrip on:\n  - $T1W_FILE\n"
                    # Run SynthStrip
                    mri_synthstrip --i "$T1W_FILE" --o "$OUTPUT_FILE"
                    if [ $? -ne 0 ]; then
                        echo "Error during SynthStrip skull stripping for $SUBJ_ID $SES_ID"
                        continue
                    fi
                    
                    # Conditionally remove reoriented T1w file if reorientation was applied
		    if [ "$REORIENT" == "yes" ]; then
			rm "$REORIENTED_T1W_FILE"
			echo -e "Removed reoriented T1w file:\n  - $REORIENTED_T1W_FILE"
		    fi
		    
		    echo -e "\nSynthStrip skull stripping completed: $OUTPUT_FILE\n"
                    
                fi
            else
                echo "Anatomical directory not found: $ANAT_DIR"
            fi
        done
    done

    echo -e "\nSynthStrip skull stripping completed."
    echo "------------------------------------------------------------------------------"

} 2>&1 | tee -a "$LOG_FILE"

# End of script
