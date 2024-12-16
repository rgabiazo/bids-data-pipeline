#!/bin/bash

# This script performs second-level fixed effects analysis using FSL's FEAT tool.
# It allows the user to select first-level analysis directories, specify subjects, sessions, and runs,
# and generates design files for fixed effects analysis.
# It also handles cope counts and ensures consistency across inputs.

# Set the prompt for the select command
PS3="Please enter your choice: "

# Get the directory where the script is located
script_dir="$(cd "$(dirname "$0")" && pwd)"
# Set BASE_DIR to two levels up from the script directory
BASE_DIR="$(dirname "$(dirname "$script_dir")")"

# Define log file path
LOG_DIR="$BASE_DIR/code/logs"
mkdir -p "$LOG_DIR"
LOGFILE="$LOG_DIR/$(basename "$0" .sh)_$(date +'%Y%m%d_%H%M%S').log"

# Redirect stdout and stderr to the log file and console
exec > >(tee -a "$LOGFILE") 2>&1

# Define the full path to the analysis directory base
ANALYSIS_BASE_DIR="$BASE_DIR/derivatives/fsl/level-1"

# Define paths for base design file and template
BASE_DESIGN_FSF="$BASE_DIR/code/design_files/fixed-effects_design.fsf"
TEMPLATE="$BASE_DIR/derivatives/templates/MNI152_T1_2mm_brain.nii.gz"

# Check if the base design.fsf exists
if [ ! -f "$BASE_DESIGN_FSF" ]; then
    echo "Error: Base design file not found at $BASE_DESIGN_FSF"
    exit 1
fi

# Check if the template exists
if [ ! -f "$TEMPLATE" ]; then
    echo "Error: Template not found at $TEMPLATE"
    exit 1
fi

# Find directories containing "analysis" in their names within the analysis base directory
ANALYSIS_DIRS=($(find "$ANALYSIS_BASE_DIR" -maxdepth 1 -type d -name "*analysis*"))

# Check if any analysis directories were found
if [ ${#ANALYSIS_DIRS[@]} -eq 0 ]; then
    echo "No analysis directories found in $ANALYSIS_BASE_DIR."
    exit 1
fi

# Display a header
echo -e "\n=== First-Level Analysis Directory Selection ==="
echo "Please select a first-level analysis directory for second-level fixed effects processing from the options below:"
echo
echo ""

# Prompt user to select an analysis directory
select ANALYSIS_DIR in "${ANALYSIS_DIRS[@]}"; do
    if [ -n "$ANALYSIS_DIR" ]; then
        echo -e "\nYou have selected the following analysis directory for fixed effects:"
        echo "$ANALYSIS_DIR"
        break
    else
        echo -e "\nInvalid selection. Please try again."
    fi
done

# Define the level-2 analysis directory based on the selected level-1 directory
LEVEL_2_ANALYSIS_DIR="${BASE_DIR}/derivatives/fsl/level-2/$(basename "$ANALYSIS_DIR")"

# Define base path for shortening paths in output
BASE_PATH="$ANALYSIS_DIR"

# Find subject directories with multiple possible prefixes
SUBJECT_NAME_PATTERNS=("sub-*" "subject-*" "pilot-*" "subj-*" "subjpilot-*")
FIND_SUBJECT_EXPR=()
first_pattern=true
for pattern in "${SUBJECT_NAME_PATTERNS[@]}"; do
    if $first_pattern; then
        FIND_SUBJECT_EXPR+=( -name "$pattern" )
        first_pattern=false
    else
        FIND_SUBJECT_EXPR+=( -o -name "$pattern" )
    fi
done

# Find subject directories using the constructed expression
subject_dirs=($(find "$ANALYSIS_DIR" -mindepth 1 -maxdepth 1 -type d \( "${FIND_SUBJECT_EXPR[@]}" \)))

# Check if no subject directories are found
if [ ${#subject_dirs[@]} -eq 0 ]; then
    echo "No subject directories found in $ANALYSIS_DIR."
    exit 1
fi

# Sort the subject directories alphabetically
subject_dirs=($(printf "%s\n" "${subject_dirs[@]}" | sort))

# Initialize arrays to keep track of available subject-session combinations
available_subject_sessions=()

# Initialize arrays to store subject-session keys and cope counts
subject_session_keys=()
subject_session_cope_counts=()

# Initialize an array to store all valid feat directories after cope count check
all_valid_feat_dirs=()

# Function to count cope*.nii.gz files in the stats directory of a feat directory
count_cope_files() {
    local feat_dir="$1"
    local stats_dir="$feat_dir/stats"
    local cope_count=0

    # Check if the stats directory exists
    if [ -d "$stats_dir" ]; then
        # Count the number of cope*.nii.gz files within the stats directory
        cope_count=$(find "$stats_dir" -mindepth 1 -maxdepth 1 -type f -name "cope*.nii.gz" | wc -l | xargs)
    else
        echo "$feat_dir (Stats directory not found)"
    fi

    # Return the cope count
    echo "$cope_count"
}

# Function to calculate the most common cope count and filter feat directories
check_common_cope_count() {
    local feat_dirs=("$@")
    local cope_counts=()
    local valid_feat_dirs=()
    local warning_messages=""
    local total_runs=${#feat_dirs[@]}

    # Extract cope counts for each feat directory
    for feat_dir in "${feat_dirs[@]}"; do
        local cope_count=$(count_cope_files "$feat_dir")
        cope_counts+=("$cope_count")
    done

    # Find unique cope counts and their frequencies
    unique_cope_counts=()
    cope_counts_freq=()

    for cope_count in "${cope_counts[@]}"; do
        found=false
        for ((i=0; i<${#unique_cope_counts[@]}; i++)); do
            if [ "${unique_cope_counts[i]}" -eq "$cope_count" ]; then
                cope_counts_freq[i]=$(( ${cope_counts_freq[i]} + 1 ))
                found=true
                break
            fi
        done
        if [ "$found" = false ]; then
            unique_cope_counts+=("$cope_count")
            cope_counts_freq+=("1")
        fi
    done

    # Find the maximum frequency and corresponding cope counts
    max_freq=0
    common_cope_counts=()

    for ((i=0; i<${#unique_cope_counts[@]}; i++)); do
        freq=${cope_counts_freq[i]}
        if [ $freq -gt $max_freq ]; then
            max_freq=$freq
            common_cope_counts=("${unique_cope_counts[i]}")
        elif [ $freq -eq $max_freq ]; then
            common_cope_counts+=("${unique_cope_counts[i]}")
        fi
    done

    # Check if there is a tie in frequencies
    if [ ${#common_cope_counts[@]} -gt 1 ]; then
        # There is a tie in frequencies
        warning_messages="  - Unequal cope counts found across runs (${unique_cope_counts[*]})."
        echo "UNEQUAL_COPES_TIE"
        echo -e "$warning_messages"
        return
    fi

    common_cope_count="${common_cope_counts[0]}"

    # If the most common cope count appears in more than half of the runs, include those runs
    if [ "$max_freq" -gt $((total_runs / 2)) ]; then
        # Include runs with common cope count
        for idx in "${!feat_dirs[@]}"; do
            if [ "${cope_counts[$idx]}" -eq "$common_cope_count" ]; then
                valid_feat_dirs+=("${feat_dirs[$idx]}")
            else
                if [ -n "$warning_messages" ]; then
                    warning_messages="${warning_messages}\n  - $(basename "${feat_dirs[$idx]}") does not have the common cope count $common_cope_count and will be excluded."
                else
                    warning_messages="  - $(basename "${feat_dirs[$idx]}") does not have the common cope count $common_cope_count and will be excluded."
                fi
            fi
        done

        # Output the common cope count and valid feat directories
        echo "$common_cope_count"
        for dir in "${valid_feat_dirs[@]}"; do
            echo "$dir"
        done

        # Output warnings with a marker
        if [ -n "$warning_messages" ]; then
            echo "WARNINGS_START"
            echo -e "$warning_messages"
        fi
    else
        # Not enough runs have the same cope count; exclude the subject-session
        warning_messages="  - Unequal cope counts found across runs (${unique_cope_counts[*]}). Excluding this subject-session."
        echo "UNEQUAL_COPES"
        echo -e "$warning_messages"
    fi
}

# Display a header
echo -e "\n=== Listing First-Level Feat Directories ==="
echo -e "The following feat directories will be used as inputs for the second-level fixed effects analysis:\n"

# Loop over each subject directory
for subject_dir in "${subject_dirs[@]}"; do
    subject=$(basename "$subject_dir")

    # Find session directories within the subject directory
    SESSION_NAME_PATTERNS=("ses-*" "session-*" "ses_*" "session_*" "ses*" "session*" "baseline" "endpoint" "ses-001" "ses-002")
    FIND_SESSION_EXPR=()
    first_session_pattern=true
    for pattern in "${SESSION_NAME_PATTERNS[@]}"; do
        if $first_session_pattern; then
            FIND_SESSION_EXPR+=( -name "$pattern" )
            first_session_pattern=false
        else
            FIND_SESSION_EXPR+=( -o -name "$pattern" )
        fi
    done

    # Corrected find command for session directories
    session_dirs=($(find "$subject_dir" -mindepth 1 -maxdepth 1 -type d \( "${FIND_SESSION_EXPR[@]}" \)))

    # Sort session directories
    session_dirs=($(printf "%s\n" "${session_dirs[@]}" | sort))

    # Loop over each session directory
    for session_dir in "${session_dirs[@]}"; do
        session=$(basename "$session_dir")
        key="$subject:$session"
        available_subject_sessions+=("$key")

        # Find feat directories within the session directory
        feat_dirs=($(find "$session_dir/func" -mindepth 1 -maxdepth 1 -type d -name "*.feat"))
        feat_dirs=($(printf "%s\n" "${feat_dirs[@]}" | sort))

        # Check if there are feat directories
        if [ ${#feat_dirs[@]} -eq 0 ]; then
            echo -e "--- Subject: $subject | Session: $session ---\n"
            echo "No feat directories found."
        else
            # Display the "Listing feat directories" header
            echo -e "--- Subject: $subject | Session: $session ---\n"

            # Check for common cope count and filter feat directories
            check_result=()
            while IFS= read -r line; do
                check_result+=("$line")
            done < <(check_common_cope_count "${feat_dirs[@]}")

            # Initialize variables
            common_cope_count=""
            valid_feat_dirs=()
            warnings=()
            parsing_warnings=false
            unequal_copes=false
            unequal_copes_tie=false

            # Process check_result array
            for line in "${check_result[@]}"; do
                if [ "$parsing_warnings" = false ]; then
                    if [ "$line" = "UNEQUAL_COPES" ]; then
                        unequal_copes=true
                        parsing_warnings=true
                    elif [ "$line" = "UNEQUAL_COPES_TIE" ]; then
                        unequal_copes_tie=true
                        parsing_warnings=true
                    elif [ -z "$common_cope_count" ]; then
                        common_cope_count="$line"
                    elif [ "$line" = "WARNINGS_START" ]; then
                        parsing_warnings=true
                    else
                        valid_feat_dirs+=("$line")
                    fi
                else
                    warnings+=("$line")
                fi
            done

            # Handle unequal cope counts
            if [ "$unequal_copes" = true ] || [ "$unequal_copes_tie" = true ]; then
                echo -e "Warnings:"
                for warning in "${warnings[@]}"; do
                    echo "  [Warning] $warning"
                done
                if [ "$unequal_copes_tie" = true ]; then
                    echo -e "\nExcluding subject-session $subject:$session due to tie in cope counts."
                else
                    echo -e"\nExcluding subject-session $subject:$session due to insufficient runs with the same cope count."
                fi
                continue
            fi

            # If there are valid feat directories, display them
            if [ ${#valid_feat_dirs[@]} -gt 0 ]; then
                echo "Valid Feat Directories:"
                for feat_dir in "${valid_feat_dirs[@]}"; do
                    echo "  • ${feat_dir#$BASE_PATH/}"
                done

                # Store the common cope count for this subject-session
                subject_session_keys+=("$key")
                subject_session_cope_counts+=("$common_cope_count")

                # Add valid feat directories to the global array
                all_valid_feat_dirs+=("${valid_feat_dirs[@]}")

                # After printing valid feat directories, print any warnings
                if [ ${#warnings[@]} -gt 0 ]; then
                    echo -e "\nWarnings:"
                    for warning in "${warnings[@]}"; do
                        echo "  [Warning] $warning"
                    done
                fi
            else
                echo "  - No valid feat directories after cope count check."
            fi
        fi
        echo ""
    done
done

# Sort all_valid_feat_dirs before displaying
all_valid_feat_dirs=($(printf "%s\n" "${all_valid_feat_dirs[@]}" | sort))

# Prompt for subject, session, and run selections
echo -e "\n=== Subject, Session, and Run Selection ==="
echo "To include or exclude certain subjects, sessions, or runs, specify your selection using the format:"
echo "'subject[:session[:runs]]' to include, or '-subject[:session[:runs]]' to exclude."
echo -e "\nFor example:"
echo "  To include: 'sub-01:ses-01:02,03'"
echo "  To exclude: '-sub-03:ses-01 -sub-04'"
echo -e "\nPress Enter/Return to include all by default.\n"
echo -e "Enter subject, session, and run selections (or press Enter/Return for all): "
read -p "> " selection_input

# Parse selections into inclusion and exclusion arrays
inclusion_map_keys=()
inclusion_map_values=()
exclusion_map_keys=()
exclusion_map_values=()
invalid_selections=()

# Split selection_input into entries
IFS=' ' read -ra entries <<< "$selection_input"

for selection in "${entries[@]}"; do
    if [[ "$selection" == -* ]]; then
        # This is an exclusion
        selection="${selection#-}"  # Remove the leading '-'
        IFS=':' read -ra sel_parts <<< "$selection"
        sel_subject="${sel_parts[0]}"
        sel_session="${sel_parts[1]}"
        sel_runs="${sel_parts[2]}"

        # Validate as before
        subject_exists=false
        for subject_dir in "${subject_dirs[@]}"; do
            subject=$(basename "$subject_dir")
            if [ "$subject" == "$sel_subject" ]; then
                subject_exists=true
                break
            fi
        done
        if [ "$subject_exists" = false ]; then
            invalid_selections+=("-${selection} (Subject not found)")
            continue
        fi

        # No need to check session and runs for exclusions
        exclusion_map_keys+=("$sel_subject:$sel_session")
        exclusion_map_values+=("$sel_runs")
    else
        # This is an inclusion
        IFS=':' read -ra sel_parts <<< "$selection"
        sel_subject="${sel_parts[0]}"
        sel_session="${sel_parts[1]}"
        sel_runs="${sel_parts[2]}"

        # Validate as before
        subject_exists=false
        for subject_dir in "${subject_dirs[@]}"; do
            subject=$(basename "$subject_dir")
            if [ "$subject" == "$sel_subject" ]; then
                subject_exists=true
                break
            fi
        done
        if [ "$subject_exists" = false ]; then
            invalid_selections+=("$selection (Subject not found)")
            continue
        fi

        # No need to check session and runs here
        inclusion_map_keys+=("$sel_subject:$sel_session")
        inclusion_map_values+=("$sel_runs")
    fi
done

# If there are invalid selections, display warnings
if [ "${#invalid_selections[@]}" -gt 0 ]; then
    echo -e "\nWarning: The following selections are invalid:"
    for invalid in "${invalid_selections[@]}"; do
        echo "  - $invalid"
    done
    echo "Please check your input and run the script again."
    exit 1
fi

# Prompt for optional task name
echo -e "\n=== Customize Output Filename (Optional) ==="
echo "To add a task name to the second-level fixed effects output filenames, enter it here (e.g., 'taskname')."
echo -e "If left blank, output will use the default format: 'desc-fixed-effects.gfeat'.\n"
read -p "Enter task name (or press Enter for default): " task_name

# Prompt for Z threshold and Cluster P threshold
echo -e "\n=== FEAT Thresholding Options ==="
echo "You can specify the Z threshold and Cluster P threshold for the fixed effects analysis."
echo -e "Press Enter/Return to use default values (Z threshold: 2.3, Cluster P threshold: 0.05).\n"
read -p "Enter Z threshold (default 2.3): " z_threshold
read -p "Enter Cluster P threshold (default 0.05): " cluster_p_threshold

# Set default values if inputs are empty
z_threshold=${z_threshold:-2.3}
cluster_p_threshold=${cluster_p_threshold:-0.05}

# Function to check if a subject-session should be included
should_include_subject_session() {
    local subject="$1"
    local session="$2"

    local key="$subject:$session"

    # Check exclusions first
    for idx in "${!exclusion_map_keys[@]}"; do
        excl_key="${exclusion_map_keys[$idx]}"
        excl_subject="${excl_key%%:*}"
        excl_session="${excl_key#*:}"

        if [ "$excl_subject" = "$subject" ]; then
            if [ -z "$excl_session" ] || [ "$excl_session" = "$session" ]; then
                return 1  # Exclude
            fi
        fi
    done

    # Include by default
    return 0
}

# Define the path to the generate_design_fsf script
GENERATE_DESIGN_SCRIPT="$BASE_DIR/code/scripts/generate_fixed_effects_design_fsf.sh"

# Check if the script exists
if [ ! -f "$GENERATE_DESIGN_SCRIPT" ]; then
    echo "Error: generate_fixed_effects_design_fsf.sh script not found at $GENERATE_DESIGN_SCRIPT"
    exit 1
fi

# Display confirmation summary and generate output
echo -e "\n=== Confirm Your Selections for Fixed Effects Analysis ==="

# Initialize an array to store paths of generated design files
generated_design_files=()

# Loop over each subject directory again
for subject_dir in "${subject_dirs[@]}"; do
    subject=$(basename "$subject_dir")

    # Find session directories within the subject directory
    first_session_pattern=true
    FIND_SESSION_EXPR=()
    for pattern in "${SESSION_NAME_PATTERNS[@]}"; do
        if $first_session_pattern; then
            FIND_SESSION_EXPR+=( -name "$pattern" )
            first_session_pattern=false
        else
            FIND_SESSION_EXPR+=( -o -name "$pattern" )
        fi
    done

    # Corrected find command for session directories
    session_dirs=($(find "$subject_dir" -mindepth 1 -maxdepth 1 -type d \( "${FIND_SESSION_EXPR[@]}" \)))
    session_dirs=($(printf "%s\n" "${session_dirs[@]}" | sort))

    for session_dir in "${session_dirs[@]}"; do
        session=$(basename "$session_dir")

        # Determine if this subject-session should be included
        if ! should_include_subject_session "$subject" "$session"; then
            echo -e "\nSubject: $subject | Session: $session"
            echo "----------------------------------------"
            echo "  - Excluded based on your selections."
            continue
        fi

        # Determine if specific runs are selected for this subject-session combination
        sel_key="$subject:$session"
        specific_runs=""
        for idx in "${!inclusion_map_keys[@]}"; do
            if [ "${inclusion_map_keys[$idx]}" == "$sel_key" ]; then
                specific_runs="${inclusion_map_values[$idx]}"
                break
            fi
        done

        # Also handle run exclusions
        exclude_runs=""
        for idx in "${!exclusion_map_keys[@]}"; do
            if [ "${exclusion_map_keys[$idx]}" == "$sel_key" ]; then
                exclude_runs="${exclusion_map_values[$idx]}"
                break
            fi
        done

        echo -e "\nSubject: $subject | Session: $session"
        echo "----------------------------------------"

        # Initialize feat_dirs array
        feat_dirs=()

        # Filter all_valid_feat_dirs for entries that match the current subject and session
        for dir in "${all_valid_feat_dirs[@]}"; do
            # Construct pattern to match subject and session
            if [[ "$dir" == *"/$subject/$session/"* ]]; then
                feat_dirs+=("$dir")
            fi
        done

        # If specific runs were selected, further filter feat_dirs for those runs
        if [ -n "$specific_runs" ]; then
            selected_feat_dirs=()
            IFS=',' read -ra selected_runs <<< "$specific_runs"
            for run in "${selected_runs[@]}"; do
                run="${run//run-/}"   # Remove "run-" prefix if present
                run_num_no_zeros=$(echo "$run" | sed 's/^0*//')   # Remove leading zeros

                # Construct regex to match the run number with any number of leading zeros in the directory name
                run_regex=".*run-0*${run_num_no_zeros}\.feat$"

                for feat_dir in "${feat_dirs[@]}"; do
                    if [[ "$feat_dir" =~ $run_regex ]]; then
                        selected_feat_dirs+=("$feat_dir")
                    fi
                done
            done
            feat_dirs=("${selected_feat_dirs[@]}")
        fi

        # Exclude specific runs if specified
        if [ -n "$exclude_runs" ]; then
            IFS=',' read -ra runs_to_exclude <<< "$exclude_runs"
            for run in "${runs_to_exclude[@]}"; do
                run="${run//run-/}"   # Remove "run-" prefix if present
                run_num_no_zeros=$(echo "$run" | sed 's/^0*//')   # Remove leading zeros

                # Construct regex to match the run number with any number of leading zeros in the directory name
                run_regex=".*run-0*${run_num_no_zeros}\.feat$"

                for idx in "${!feat_dirs[@]}"; do
                    if [[ "${feat_dirs[$idx]}" =~ $run_regex ]]; then
                        unset 'feat_dirs[$idx]'
                    fi
                done
            done
            # Re-index the array
            feat_dirs=("${feat_dirs[@]}")
        fi

        # Sort the feat directories
        feat_dirs=($(printf "%s\n" "${feat_dirs[@]}" | sort))

        if [ ${#feat_dirs[@]} -eq 0 ]; then
            echo "  - No matching directories found."
            continue
        elif [ ${#feat_dirs[@]} -lt 2 ]; then
            echo "  - Not enough runs for fixed effects analysis (minimum 2 runs required). Skipping."
            continue
        fi

        # Print the feat directories
        echo "Selected Feat Directories:"
        for feat_dir in "${feat_dirs[@]}"; do
            echo "  • ${feat_dir#$BASE_PATH/}"
        done

        # Retrieve the common cope count for the current subject-session
        subject_session_key="${subject}:${session}"
        common_cope_count=""
        array_length=${#subject_session_keys[@]}
        idx=0
        while [ $idx -lt $array_length ]; do
            if [ "${subject_session_keys[$idx]}" = "$subject_session_key" ]; then
                common_cope_count="${subject_session_cope_counts[$idx]}"
                break
            fi
            idx=$((idx + 1))
        done

        # Only proceed if common cope count is found
        if [ -z "$common_cope_count" ]; then
            echo "Common cope count for $subject_session_key not found. Skipping."
            continue
        fi

        # Construct the output filename under level-2 directory
        if [ -n "$task_name" ]; then
            output_filename="${subject}_${session}_task-${task_name}_desc-fixed-effects"
        else
            output_filename="${subject}_${session}_desc-fixed-effects"
        fi
        output_path="$LEVEL_2_ANALYSIS_DIR/$subject/$session/$output_filename"

        echo -e "\nOutput Directory:"
        echo "- ${output_path}.gfeat"

        # **Check if output .gfeat directory already exists**
        if [ -d "${output_path}.gfeat" ]; then
            echo -e "\n[Notice] Output directory already exists. Skipping fixed effects analysis for this subject-session."
            continue
        fi

        # Generate design.fsf for this subject-session using filtered feat_dirs
        "$GENERATE_DESIGN_SCRIPT" "$output_path" "$common_cope_count" "$z_threshold" "$cluster_p_threshold" "${feat_dirs[@]}"

        echo -e "\nGenerated FEAT fixed-effects design file at:"
        echo "- ${output_path}/modified_fixed-effects_design.fsf"

        # Store the generated design file path in the array
        generated_design_files+=("$output_path/modified_fixed-effects_design.fsf")
    done
done

# Check if there are any design files to process
if [ ${#generated_design_files[@]} -eq 0 ]; then
    echo -e "\n=== No new analyses to run. All specified outputs already exist or were excluded. ===\n"
    exit 0
fi

echo -e "\nPress Enter/Return to confirm and proceed with second-level fixed effects analysis, or Ctrl+C to cancel and restart."

# Define trap function for Ctrl+C
trap_ctrl_c() {
    echo -e "\n\nProcess interrupted by user. Removing generated design files..."
    for design_file in "${generated_design_files[@]}"; do
        design_dir="$(dirname "$design_file")"
        rm -r "$design_dir"
        echo "Removed temporary design directory:"
        echo "- ${design_dir#$BASE_PATH/}"
    done
    exit 1
}

# Set trap
trap 'trap_ctrl_c' SIGINT

read -r

# Disable trap after confirmation
trap - SIGINT

# Run Feat on the generated design files
echo -e "\n=== Running Fixed Effects ==="

for design_file in "${generated_design_files[@]}"; do
    echo -e "\n--- Processing Design File ---\n"
    echo "File Path:"
    echo "- ${design_file#$BASE_PATH/}"

    # Define the expected .gfeat output directory based on the design file
    gfeat_dir="$(dirname "$design_file").gfeat"

    # Run feat on the design file
    feat "$design_file"
    echo -e "\nFinished running fixed effects with:"
    echo "- ${design_file#$BASE_PATH/}"

    # Get the parent directory of the design file
    design_dir="$(dirname "$design_file")"

    # Remove the entire directory after processing
    rm -r "$design_dir"
    echo -e "\nRemoved temporary design directory:"
    echo "- ${design_dir#$BASE_PATH/}"
done

echo -e "\n=== All processing is complete. Please check the output directories for results. ===\n"
