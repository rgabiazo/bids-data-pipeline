#!/bin/bash

# third_level_analysis.sh
# Author: Raphael Gabiazon
# Description:
# This script performs third-level mixed effects analysis (FLAME 1) using FSL. 
# It allows users to select and organize higher-level .gfeat directories
# for group analysis. The script dynamically finds, validates, and processes the directories,
# ensuring compatibility with custom Z-thresholds, cluster P-thresholds, and user-defined output folder names.

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

# Define the full path to the level-1 and level-2 analysis directories
LEVEL_1_ANALYSIS_BASE_DIR="$BASE_DIR/derivatives/fsl/level-1"
LEVEL_2_ANALYSIS_BASE_DIR="$BASE_DIR/derivatives/fsl/level-2"
LEVEL_3_ANALYSIS_BASE_DIR="$BASE_DIR/derivatives/fsl/level-3"

# Function to check for available analysis directories with lower-level FEAT directories
find_lower_level_analysis_dirs() {
    local base_dir="$1"
    ANALYSIS_DIRS=()
    while IFS= read -r -d $'\0' dir; do
        if find "$dir" -type d -name "*.feat" -print -quit | grep -q .; then
            ANALYSIS_DIRS+=("$dir")
        fi
    done < <(find "$base_dir" -mindepth 1 -maxdepth 1 -type d -print0)
}

# Function to check for available analysis directories with higher-level .gfeat directories
find_higher_level_analysis_dirs() {
    local base_dir="$1"
    ANALYSIS_DIRS=()
    while IFS= read -r -d $'\0' dir; do
        if find "$dir" -type d -name "*.gfeat" -print -quit | grep -q .; then
            ANALYSIS_DIRS+=("$dir")
        fi
    done < <(find "$base_dir" -mindepth 1 -maxdepth 1 -type d -print0)
}

# Function to clear the terminal and display selections
display_selections() {
    clear
    echo -e "\n=== Confirm Your Selections for Mixed Effects Analysis ==="
    echo "Session: $SESSION"

    echo

    # Collect and sort subjects
    sorted_subjects=($(printf "%s\n" "${subjects[@]}" | sort))

    # Display sorted selections
    for subject in "${sorted_subjects[@]}"; do
        # Find the corresponding data for this subject
        for idx in "${!subjects[@]}"; do
            if [ "${subjects[$idx]}" == "$subject" ]; then
                directories_str="${directories[$idx]}"
                directory_types_str="${directory_types[$idx]}"
                session="${sessions[$idx]}"
                break
            fi
        done

        # Sort directories within each subject
        IFS='::' read -ra directories_list <<< "$directories_str"
        IFS='::' read -ra directory_types_list <<< "$directory_types_str"

        # Since we have only one directory per subject in most cases, sorting is not necessary
        # But if there are multiple directories, we can sort them
        sorted_directories=($(printf "%s\n" "${directories_list[@]}" | sort))
        sorted_directory_types=()

        # Get corresponding directory types
        for dir in "${sorted_directories[@]}"; do
            for idx2 in "${!directories_list[@]}"; do
                if [ "${directories_list[$idx2]}" == "$dir" ]; then
                    sorted_directory_types+=("${directory_types_list[$idx2]}")
                    break
                fi
            done
        done

        echo "Subject: $subject | Session: $session"
        echo "----------------------------------------"

        for idx2 in "${!sorted_directories[@]}"; do
            dir="${sorted_directories[$idx2]}"
            dir_type="${sorted_directory_types[$idx2]}"

            # Display based on the directory type
            if [ "$dir_type" == "lower" ]; then
                echo "Selected Feat Directory:"
            else
                echo "Higher-level Feat Directory:"
            fi

            echo "  - ${dir#$BASE_DIR/}"
        done
        echo
    done

    echo "============================================"
    echo
    echo "Options:"
    echo "  • To exclude a single subject, type -subject (e.g., -sub-01). Only one subject can be excluded at a time."
    echo "  • To add or replace directories, type add."
    echo "  • Press Enter/Return to confirm and proceed with third-level mixed effects analysis if the selections are final."
    echo
    read -p "> " user_input
}

# Display the main menu
echo -e "\n=== Third Level Analysis: Mixed Effects Flame 1  ==="

# Now, we assume INPUT_TYPE="higher"

# Check for higher-level .gfeat directories
find_higher_level_analysis_dirs "$LEVEL_2_ANALYSIS_BASE_DIR"
if [ ${#ANALYSIS_DIRS[@]} -eq 0 ]; then
    echo -e "\nNo available directories for higher-level analysis found."
    echo "Please ensure that second-level fixed-effects analysis has been completed and the directories exist in the specified path."
    echo -e "Exiting...\n"
    exit 1
fi

INPUT_TYPE="higher"

ANALYSIS_BASE_DIR="$LEVEL_2_ANALYSIS_BASE_DIR"
echo -e "\n---- Higher level FEAT directories ----"
echo "Select analysis directory containing 3D cope images"
# ANALYSIS_DIRS is already set from find_higher_level_analysis_dirs

# Display analysis directories
echo
ANALYSIS_DIR_OPTIONS=()
for idx in "${!ANALYSIS_DIRS[@]}"; do
    echo "$((idx + 1))) ${ANALYSIS_DIRS[$idx]#$BASE_DIR/}"
    ANALYSIS_DIR_OPTIONS+=("$((idx + 1))")
done

# Prompt user to select an analysis directory
echo ""
read -p "Please enter your choice: " analysis_choice
while [[ ! " ${ANALYSIS_DIR_OPTIONS[@]} " =~ " ${analysis_choice} " ]]; do
    echo "Invalid selection. Please try again."
    read -p "Please enter your choice: " analysis_choice
done

ANALYSIS_DIR="${ANALYSIS_DIRS[$((analysis_choice - 1))]}"
echo -e "\nYou have selected the following analysis directory:"
echo "$ANALYSIS_DIR"

# Find available sessions in the selected analysis directory
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

# Find session directories
session_dirs=($(find "$ANALYSIS_DIR" -type d \( "${FIND_SESSION_EXPR[@]}" \)))
session_dirs=($(printf "%s\n" "${session_dirs[@]}" | sort))

# Extract unique session names
session_names=()
for session_dir in "${session_dirs[@]}"; do
    session_name=$(basename "$session_dir")
    if [[ ! " ${session_names[@]} " =~ " ${session_name} " ]]; then
        session_names+=("$session_name")
    fi
done

# Check if any sessions were found
if [ ${#session_names[@]} -eq 0 ]; then
    echo "No sessions found in $ANALYSIS_DIR."
    exit 1
fi

# Display available sessions
echo -e "\n--- Select session ---"
echo "Higher level FEAT directories"
echo -e "\nSelect available sessions:\n"

SESSION_OPTIONS=()
for idx in "${!session_names[@]}"; do
    echo "$((idx + 1))) ${session_names[$idx]}"
    SESSION_OPTIONS+=("$((idx + 1))")
done

# Prompt user to select a session
echo ""
read -p "Please enter your choice: " session_choice
while [[ ! " ${SESSION_OPTIONS[@]} " =~ " ${session_choice} " ]]; do
    echo "Invalid selection. Please try again."
    read -p "Please enter your choice: " session_choice
done

SESSION="${session_names[$((session_choice - 1))]}"
echo -e "\nYou have selected session: $SESSION"

# Initialize arrays to store selected directories, subjects, and sessions
subjects=()
directories=()
directory_types=()
sessions=()

# Find subject directories
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

# Find subject directories within the selected session
subject_dirs=($(find "$ANALYSIS_DIR" -mindepth 1 -maxdepth 1 -type d \( "${FIND_SUBJECT_EXPR[@]}" \)))
subject_dirs=($(printf "%s\n" "${subject_dirs[@]}" | sort))

# Check if any subject directories were found
if [ ${#subject_dirs[@]} -eq 0 ]; then
    echo "No subject directories found in session $SESSION."
    exit 1
fi

# Collect directories and subjects
for subject_dir in "${subject_dirs[@]}"; do
    subject=$(basename "$subject_dir")
    session_dir="$subject_dir/$SESSION"
    if [ ! -d "$session_dir" ]; then
        continue
    fi

    # Initialize directories for this subject
    directories_list=()
    directory_types_list=()
    # For higher-level .gfeat directories
    gfeat_dirs=($(find "$session_dir" -mindepth 1 -maxdepth 1 -type d -name "*.gfeat"))
    gfeat_dirs=($(printf "%s\n" "${gfeat_dirs[@]}" | sort))
    if [ ${#gfeat_dirs[@]} -eq 0 ]; then
        continue
    fi
    directories_list+=("${gfeat_dirs[@]}")
    for ((i=0; i<${#gfeat_dirs[@]}; i++)); do
        directory_types_list+=("higher")
    done

    # Remove empty entries from directories_list
    directories_list_filtered=()
    directory_types_list_filtered=()
    for idx in "${!directories_list[@]}"; do
        dir="${directories_list[$idx]}"
        if [ -n "$dir" ]; then
            directories_list_filtered+=("$dir")
            directory_types_list_filtered+=("${directory_types_list[$idx]}")
        fi
    done
    # Add to selected directories if there are any
    if [ ${#directories_list_filtered[@]} -gt 0 ]; then
        subjects+=("$subject")
        # Join the directories into a single string separated by '::'
        directories_str=$(printf "::%s" "${directories_list_filtered[@]}")
        directories_str="${directories_str:2}" # Remove leading '::'
        directories+=("$directories_str")
        # Similarly for directory types
        directory_types_str=$(printf "::%s" "${directory_types_list_filtered[@]}")
        directory_types_str="${directory_types_str:2}" # Remove leading '::'
        directory_types+=("$directory_types_str")
        sessions+=("$SESSION")
    fi
done

# Display initial selections and prompt for modifications
while true; do
    display_selections

    # Convert user input to lowercase using a method compatible with Bash 3.2
    user_input=$(echo "$user_input" | tr '[:upper:]' '[:lower:]')  # Convert to lowercase

    if [ -z "$user_input" ]; then
        # User confirmed selections
        break
    elif [[ "$user_input" == -* ]]; then
        # Exclude subjects
        subject_to_exclude="${user_input#-}"

        # Check if multiple subjects are provided
        if [[ "$subject_to_exclude" =~ [[:space:]] ]]; then
            echo -e "\nError: Only one subject can be removed at a time. Please try again."
            continue
        fi

        # Check if the input is empty or invalid after removing '-'
        if [[ -z "$subject_to_exclude" ]]; then
            echo -e "\nError: No valid subject provided. Please try again."
            continue
        fi

        # Check if the subject exists in the dataset or has already been removed
        if ! $(printf '%s\n' "${subjects[@]}" | sed 's|.*/||' | grep -qx "$subject_to_exclude"); then
            echo -e "\nError: Subject $subject_to_exclude is either not in the dataset or has already been excluded. Please check your input and try again."
            continue
        fi

        # Remove subject from subjects, directories, directory_types, and sessions arrays
        new_subjects=()
        new_directories=()
        new_directory_types=()
        new_sessions=()
        for idx in "${!subjects[@]}"; do
            if [ "${subjects[$idx]}" != "$subject_to_exclude" ]; then
                new_subjects+=("${subjects[$idx]}")
                new_directories+=("${directories[$idx]}")
                new_directory_types+=("${directory_types[$idx]}")
                new_sessions+=("${sessions[$idx]}")
            fi
        done
        subjects=("${new_subjects[@]}")
        directories=("${new_directories[@]}")
        directory_types=("${new_directory_types[@]}")
        sessions=("${new_sessions[@]}")
    elif [ "$user_input" == "add" ]; then
        # Add or replace directories
        echo -e "\nSelect input options:\n"
        echo "1) Inputs are lower-level FEAT directories"
        echo "2) Inputs are higher-level .gfeat directories"
        echo "3) Cancel"
        echo ""
        read -p "Please enter your choice: " add_choice
        if [ "$add_choice" == "3" ]; then
            continue
        elif [ "$add_choice" == "1" ]; then
            ADD_INPUT_TYPE="lower"
            ADD_ANALYSIS_BASE_DIR="$LEVEL_1_ANALYSIS_BASE_DIR"
        elif [ "$add_choice" == "2" ]; then
            ADD_INPUT_TYPE="higher"
            ADD_ANALYSIS_BASE_DIR="$LEVEL_2_ANALYSIS_BASE_DIR"
        else
            echo "Invalid selection. Please try again."
            continue
        fi

        # Ask for analysis directory
        echo -e "\nSelect analysis directory"
        if [ "$ADD_INPUT_TYPE" == "lower" ]; then
            # Find analysis directories with lower-level FEAT directories
            find_lower_level_analysis_dirs "$ADD_ANALYSIS_BASE_DIR"
        else
            # Find analysis directories with higher-level .gfeat directories
            find_higher_level_analysis_dirs "$ADD_ANALYSIS_BASE_DIR"
        fi

        # Check if any analysis directories were found
        if [ ${#ANALYSIS_DIRS[@]} -eq 0 ]; then
            echo "No analysis directories found."
            continue
        fi

        # Display analysis directories
        echo
        ANALYSIS_DIR_OPTIONS=()
        for idx in "${!ANALYSIS_DIRS[@]}"; do
            echo "$((idx + 1))) ${ANALYSIS_DIRS[$idx]#$BASE_DIR/}"
            ANALYSIS_DIR_OPTIONS+=("$((idx + 1))")
        done

        # Prompt user to select an analysis directory
        echo ""
        read -p "Please enter your choice: " analysis_choice
        while [[ ! " ${ANALYSIS_DIR_OPTIONS[@]} " =~ " ${analysis_choice} " ]]; do
            echo "Invalid selection. Please try again."
            read -p "Please enter your choice: " analysis_choice
        done

        ADD_ANALYSIS_DIR="${ANALYSIS_DIRS[$((analysis_choice - 1))]}"
        echo -e "\nYou have selected the following analysis directory:"
        echo "$ADD_ANALYSIS_DIR"

        # Ask for session
        echo -e "\nSelect available sessions:\n"

        # Find session directories
        session_dirs=($(find "$ADD_ANALYSIS_DIR" -type d \( "${FIND_SESSION_EXPR[@]}" \)))
        session_dirs=($(printf "%s\n" "${session_dirs[@]}" | sort))

        # Extract unique session names
        session_names=()
        for session_dir in "${session_dirs[@]}"; do
            session_name=$(basename "$session_dir")
            if [[ ! " ${session_names[@]} " =~ " ${session_name} " ]]; then
                session_names+=("$session_name")
            fi
        done

        if [ ${#session_names[@]} -eq 0 ]; then
            echo "No sessions found in $ADD_ANALYSIS_DIR."
            continue
        fi

        SESSION_OPTIONS=()
        for idx in "${!session_names[@]}"; do
            echo "$((idx + 1))) ${session_names[$idx]}"
            SESSION_OPTIONS+=("$((idx + 1))")
        done

        # Prompt user to select a session
        echo ""
        read -p "Please enter your choice: " session_choice
        while [[ ! " ${SESSION_OPTIONS[@]} " =~ " ${session_choice} " ]]; do
            echo "Invalid selection. Please try again."
            read -p "Please enter your choice: " session_choice
        done

        ADD_SESSION="${session_names[$((session_choice - 1))]}"
        echo -e "\nYou have selected session: $ADD_SESSION"

        # Ask for subject
        echo -e "\nSelect subject to add/replace:\n"
        ADD_SUBJECT_OPTIONS=()
        ADD_SUBJECT_DIRS=()
        subject_dirs=($(find "$ADD_ANALYSIS_DIR" -mindepth 1 -maxdepth 1 -type d \( "${FIND_SUBJECT_EXPR[@]}" \)))
        subject_dirs=($(printf "%s\n" "${subject_dirs[@]}" | sort))

        idx=0
        for dir in "${subject_dirs[@]}"; do
            subject_name=$(basename "$dir")
            session_dir="$dir/$ADD_SESSION"
            if [ ! -d "$session_dir" ]; then
                continue
            fi
            echo "$((idx + 1))) $subject_name"
            ADD_SUBJECT_OPTIONS+=("$((idx + 1))")
            ADD_SUBJECT_DIRS+=("$dir")
            idx=$((idx + 1))
        done

        if [ ${#ADD_SUBJECT_OPTIONS[@]} -eq 0 ]; then
            echo "No subjects found in session $ADD_SESSION."
            continue
        fi
        echo ""
        read -p "Please enter your choice: " subject_choice
        while (( subject_choice < 1 || subject_choice > ${#ADD_SUBJECT_OPTIONS[@]} )); do
            echo "Invalid selection. Please try again."
            read -p "Please enter your choice: " subject_choice
        done

        ADD_SUBJECT_DIR="${ADD_SUBJECT_DIRS[$((subject_choice - 1))]}"
        subject=$(basename "$ADD_SUBJECT_DIR")
        echo -e "\nListing directories for $subject in session $ADD_SESSION..."

        session_dir="$ADD_SUBJECT_DIR/$ADD_SESSION"

        # Initialize directories for this subject
        directories_list=()
        directory_types_list=()

        if [ "$ADD_INPUT_TYPE" == "lower" ]; then
            # For lower-level FEAT directories
            func_dir="$session_dir/func"
            if [ ! -d "$func_dir" ]; then
                echo "  - No func directory found for $subject in session $ADD_SESSION."
                continue
            fi
            feat_dirs=($(find "$func_dir" -mindepth 1 -maxdepth 1 -type d -name "*.feat"))
            feat_dirs=($(printf "%s\n" "${feat_dirs[@]}" | sort))
            if [ ${#feat_dirs[@]} -eq 0 ]; then
                echo "  - No feat directories found for $subject in session $ADD_SESSION."
                continue
            fi
            echo -e "\nFeat Directories:\n"
            for idx in "${!feat_dirs[@]}"; do
                echo "$((idx + 1))) ${feat_dirs[$idx]#$BASE_DIR/}"
            done
            # Prompt user to select feat directory
            echo -e "\nSelect the run corresponding to the lower-level FEAT directory to add/replace,\nby entering its number (e.g., 1):"
            read -p "> " feat_choice

            # Check if the input contains invalid characters or multiple numbers
            if [[ ! "$feat_choice" =~ ^[0-9]+$ ]]; then
                echo "Error: Please enter a single numeric value."
                continue
            fi

            if (( feat_choice < 1 || feat_choice > ${#feat_dirs[@]} )); then
                echo "Invalid selection: $feat_choice. Please try again."
                continue
            fi

            selected_feat="${feat_dirs[$((feat_choice - 1))]}"
            directories_list+=("$selected_feat")
            directory_types_list+=("lower")

        else
            # For higher-level .gfeat directories
            gfeat_dirs=($(find "$session_dir" -mindepth 1 -maxdepth 1 -type d -name "*.gfeat"))
            gfeat_dirs=($(printf "%s\n" "${gfeat_dirs[@]}" | sort))
            if [ ${#gfeat_dirs[@]} -eq 0 ]; then
                echo "  - No .gfeat directories found for $subject in session $ADD_SESSION."
                continue
            fi
            echo -e "\ngfeat Directories:\n"
            for idx in "${!gfeat_dirs[@]}"; do
                echo "$((idx + 1))) ${gfeat_dirs[$idx]#$BASE_DIR/}"
            done
            # Prompt user to select a single gfeat directory
            echo -e "\nSelect the number corresponding to the .gfeat directory to add/replace (e.g., 1):"
            read -p "> " gfeat_choice

            # Check if the input is a single valid number
            if [[ ! "$gfeat_choice" =~ ^[0-9]+$ ]]; then
                echo "Error: Please enter a single numeric value."
                continue
            fi

            # Corrected conditional expression using arithmetic evaluation
            if (( gfeat_choice < 1 || gfeat_choice > ${#gfeat_dirs[@]} )); then
                echo "Invalid selection: $gfeat_choice. Please try again."
                continue
            fi

            selected_gfeat="${gfeat_dirs[$((gfeat_choice - 1))]}"
            directories_list+=("$selected_gfeat")
            directory_types_list+=("higher")
        fi

        # Remove empty entries from directories_list
        directories_list_filtered=()
        directory_types_list_filtered=()
        for idx in "${!directories_list[@]}"; do
            dir="${directories_list[$idx]}"
            if [ -n "$dir" ]; then
                directories_list_filtered+=("$dir")
                directory_types_list_filtered+=("${directory_types_list[$idx]}")
            fi
        done

        # Join the directories into a single string separated by '::'
        directories_str=$(printf "::%s" "${directories_list_filtered[@]}")
        directories_str="${directories_str:2}" # Remove leading '::'

        directory_types_str=$(printf "::%s" "${directory_types_list_filtered[@]}")
        directory_types_str="${directory_types_str:2}" # Remove leading '::'

        # Replace or add the directories for the subject
        subject_found=false
        for idx in "${!subjects[@]}"; do
            if [ "${subjects[$idx]}" == "$subject" ]; then
                directories[$idx]="$directories_str"
                directory_types[$idx]="$directory_types_str"
                sessions[$idx]="$ADD_SESSION"
                subject_found=true
                break
            fi
        done
        if [ "$subject_found" == false ]; then
            subjects+=("$subject")
            directories+=("$directories_str")
            directory_types+=("$directory_types_str")
            sessions+=("$ADD_SESSION")
        fi
    else
        echo "Invalid input. Please try again."
    fi
done

# Check if at least 3 directories are selected
total_directories=0
for idx in "${!subjects[@]}"; do
    directories_str="${directories[$idx]}"
    # Split directories_str into an array
    IFS='::' read -a directories_list <<< "$directories_str"
    total_directories=$((total_directories + ${#directories_list[@]}))
done

if [ "$total_directories" -lt 3 ]; then
    echo -e "\nError: At least 3 directories are required for mixed effects analysis."
    echo "You have selected only $total_directories directories."
    exit 1
fi

# Collect cope numbers from the directories
cope_numbers_per_directory=()
all_cope_numbers=()

dir_index=0
for idx in "${!subjects[@]}"; do
    directories_str="${directories[$idx]}"
    directory_types_str="${directory_types[$idx]}"
    IFS='::' read -a directories_list <<< "$directories_str"
    IFS='::' read -a directory_types_list <<< "$directory_types_str"

    for dir_idx in "${!directories_list[@]}"; do
        dir="${directories_list[$dir_idx]}"
        dir_type="${directory_types_list[$dir_idx]}"

        if [ "$dir_type" == "lower" ]; then
            # For lower-level FEAT directories, check stats/cope*.nii.gz
            cope_files=($(find "$dir/stats" -maxdepth 1 -name "cope*.nii.gz"))
            cope_numbers=()
            for cope_file in "${cope_files[@]}"; do
                filename=$(basename "$cope_file")
                if [[ "$filename" =~ ^cope([0-9]+)\.nii\.gz$ ]]; then
                    cope_num="${BASH_REMATCH[1]}"
                    cope_numbers+=("$cope_num")
                fi
            done
        else
            # For higher-level .gfeat directories, check for cope*.feat directories
            cope_dirs=($(find "$dir" -maxdepth 1 -type d -name "cope*.feat"))
            cope_numbers=()
            for cope_dir in "${cope_dirs[@]}"; do
                dirname=$(basename "$cope_dir")
                if [[ "$dirname" =~ ^cope([0-9]+)\.feat$ ]]; then
                    cope_num="${BASH_REMATCH[1]}"
                    cope_numbers+=("$cope_num")
                fi
            done
        fi

        # Remove duplicates
        cope_numbers=($(printf "%s\n" "${cope_numbers[@]}" | sort -n | uniq))

        # Store the cope numbers for this directory as a space-separated string
        cope_numbers_str=$(printf "%s " "${cope_numbers[@]}")
        cope_numbers_per_directory[$dir_index]="$cope_numbers_str"

        # Add to all_cope_numbers
        all_cope_numbers+=("${cope_numbers[@]}")

        dir_index=$((dir_index + 1))
    done
done

# Get all unique cope numbers
unique_cope_numbers=($(printf "%s\n" "${all_cope_numbers[@]}" | sort -n | uniq))

# Initialize common_cope_numbers as unique_cope_numbers
common_cope_numbers=("${unique_cope_numbers[@]}")

# Now, for each directory's cope numbers, intersect with common_cope_numbers
dir_index=0
for cope_numbers_str in "${cope_numbers_per_directory[@]}"; do
    cope_numbers=($cope_numbers_str)  # Convert string to array

    # Intersect common_cope_numbers with cope_numbers
    temp_common=()
    for cope in "${common_cope_numbers[@]}"; do
        for dir_cope in "${cope_numbers[@]}"; do
            if [ "$cope" == "$dir_cope" ]; then
                temp_common+=("$cope")
                break
            fi
        done
    done
    # Remove duplicates from temp_common
    common_cope_numbers=($(printf "%s\n" "${temp_common[@]}" | sort -n | uniq))

    dir_index=$((dir_index + 1))
done

if [ ${#common_cope_numbers[@]} -eq 0 ]; then
    echo -e "\nError: No common copes found across all selected directories."
    exit 1
fi

# Now display the final selected directories grouped by cope
echo -e "\n=== Final Selected Directories ===\n"

# Sort subjects
sorted_subjects=($(printf "%s\n" "${subjects[@]}" | sort))

for cope_num in "${common_cope_numbers[@]}"; do
    echo "=== Cope image: cope$cope_num ==="

    for subject in "${sorted_subjects[@]}"; do
        # Find the corresponding data for this subject
        for idx in "${!subjects[@]}"; do
            if [ "${subjects[$idx]}" == "$subject" ]; then
                directories_str="${directories[$idx]}"
                directory_types_str="${directory_types[$idx]}"
                session="${sessions[$idx]}"
                break
            fi
        done

        IFS='::' read -a directories_list <<< "$directories_str"
        IFS='::' read -a directory_types_list <<< "$directory_types_str"

        # Sort directories and their types together
        sorted_pairs=($(paste -d ':' <(printf "%s\n" "${directories_list[@]}") <(printf "%s\n" "${directory_types_list[@]}") | sort))
        directories_list=()
        directory_types_list=()
        for pair in "${sorted_pairs[@]}"; do
            IFS=':' read -r dir dir_type <<< "$pair"
            directories_list+=("$dir")
            directory_types_list+=("$dir_type")
        done 

        for dir_idx in "${!directories_list[@]}"; do
            dir="${directories_list[$dir_idx]}"
            dir_type="${directory_types_list[$dir_idx]}"
            echo -e "\n--- Subject: $subject | Session: $session ---"
            echo "Cope file:"
            if [ "$dir_type" == "lower" ]; then
                cope_file="$dir/stats/cope${cope_num}.nii.gz"
                if [ -f "$cope_file" ]; then
                    echo "  - $cope_file"
                else
                    echo "  - Cope file not found: $cope_file"
                    echo "Error: Missing cope$cope_num for subject $subject in directory $dir."
                    exit 1
                fi
            else
                cope_dir="$dir/cope${cope_num}.feat"
                cope_file="$cope_dir/stats/cope1.nii.gz"
                if [ -d "$cope_dir" ] && [ -f "$cope_file" ]; then
                    echo "  - $cope_file"
                else
                    echo "  - Cope directory or file not found: $cope_dir"
                    echo "Error: Missing cope$cope_num for subject $subject in directory $dir."
                    exit 1
                fi
            fi
        done
        echo
    done
done

# Prompt for Z threshold and Cluster P threshold
echo -e "\n=== FEAT Thresholding Options ==="
echo "You can specify the Z threshold and Cluster P threshold for the mixed effects analysis flame 1."
echo -e "Press Enter/Return to use default values (Z threshold: 2.3, Cluster P threshold: 0.05).\n"

read -p "Enter Z threshold (default 2.3): " z_threshold
z_threshold=${z_threshold:-2.3}

read -p "Enter Cluster P threshold (default 0.05): " cluster_p_threshold
cluster_p_threshold=${cluster_p_threshold:-0.05}

# Prompt for optional output folder customization
echo -e "\n=== Customize Output Folder Name (Optional) ===\n"
echo "Task Name:"
echo "  • Enter a task name (e.g., \"memory\") to include in the group analysis output folder."
echo -e "  • Press Enter/Return to skip the task name.\n"
echo -n "Task name (leave blank for no task): "
read task_name

# Prompt for optional descriptor
echo -e "\nDescriptor:"
echo "  • Enter a descriptor (e.g., \"postICA\" for post-ICA analysis) to customize the group analysis output folder."
echo "  • Press Enter/Return to use the default format."
echo -e "    Default: /level-3/desc-group/cope*.gfeat\n"
echo -n "Descriptor (e.g., postICA or leave blank for default): "
read custom_desc

# Determine the output directory based on task name and descriptor
if [ -z "$task_name" ]; then
    # No task name provided
    if [ -z "$custom_desc" ]; then
        OUTPUT_DIR="$LEVEL_3_ANALYSIS_BASE_DIR/desc-group"
    else
        OUTPUT_DIR="$LEVEL_3_ANALYSIS_BASE_DIR/desc-${custom_desc}_group"
    fi
else
    # Task name provided
    if [ -z "$custom_desc" ]; then
        OUTPUT_DIR="$LEVEL_3_ANALYSIS_BASE_DIR/task-${task_name}_desc-group"
    else
        OUTPUT_DIR="$LEVEL_3_ANALYSIS_BASE_DIR/task-${task_name}_desc-${custom_desc}_group"
    fi
fi

# Display the chosen output directory
echo -e "\nOutput directory will be set to: $OUTPUT_DIR"

# Create the output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Define the template path
TEMPLATE="$BASE_DIR/derivatives/templates/MNI152_T1_2mm_brain.nii.gz"

# Loop over each common cope number
for cope_num in "${common_cope_numbers[@]}"; do

    echo -e "\n--- Processing cope $cope_num ---"

    # Define paths for the design template and temporary design file
    design_template="$BASE_DIR/code/design_files/mixed-effects_design.fsf"
    temp_design_file="$OUTPUT_DIR/cope${cope_num}_design.fsf"

    # Ensure the template exists
    if [ ! -f "$design_template" ]; then
        echo "Error: Design template file not found at $design_template"
        exit 1
    fi

    # Define the specific output directory for this cope
    cope_output_dir="$OUTPUT_DIR/cope${cope_num}"

    # Check if the output directory exists 
    if [ -d "${cope_output_dir}.gfeat" ]; then
        echo "Output directory already exists at:"
        echo "  - ${cope_output_dir}.gfeat"
        echo -e "\nSkipping..."
        continue
    fi

    # Initialize variables for input lines, group membership, and EV values
    input_lines=""
    group_membership=""
    ev_values=""
    num_inputs=0
    input_index=0

    # Prepare inputs ordered by subject
    for subject in "${sorted_subjects[@]}"; do
        # Find the corresponding data for this subject
        for idx in "${!subjects[@]}"; do
            if [ "${subjects[$idx]}" == "$subject" ]; then
                directories_str="${directories[$idx]}"
                directory_types_str="${directory_types[$idx]}"
                break
            fi
        done

        IFS='::' read -a directories_list <<< "$directories_str"
        IFS='::' read -a directory_types_list <<< "$directory_types_str"

        # Sort directories and their types together
        sorted_pairs=($(paste -d ':' <(printf "%s\n" "${directories_list[@]}") <(printf "%s\n" "${directory_types_list[@]}") | sort))
        directories_list=()
        directory_types_list=()
        for pair in "${sorted_pairs[@]}"; do
            IFS=':' read -r dir dir_type <<< "$pair"
            directories_list+=("$dir")
            directory_types_list+=("$dir_type")
        done 

        for dir_idx in "${!directories_list[@]}"; do
            dir="${directories_list[$dir_idx]}"
            dir_type="${directory_types_list[$dir_idx]}"
            input_index=$((input_index + 1))
            num_inputs=$((num_inputs + 1))

            if [ "$dir_type" == "lower" ]; then
                cope_file="$dir/stats/cope${cope_num}.nii.gz"
            else
                cope_file="$dir/cope${cope_num}.feat/stats/cope1.nii.gz"
            fi

            # Escape double quotes and backslashes
            cope_file_escaped=$(printf '%s\n' "$cope_file" | sed 's/["\\]/\\&/g')
            input_lines+="set feat_files($input_index) \"$cope_file_escaped\"\n"

            # Group membership and EV values
            group_membership+="set fmri(groupmem.$input_index) 1\n"
            ev_values+="set fmri(evg$input_index.1) 1\n"
        done
    done

    # Set environment variables for envsubst
    export COPE_OUTPUT_DIR="$cope_output_dir"
    export Z_THRESHOLD="$z_threshold"
    export CLUSTER_P_THRESHOLD="$cluster_p_threshold"
    export STANDARD_IMAGE="$TEMPLATE"
    export NUM_INPUTS="$num_inputs"

    # Generate the design file using envsubst
    envsubst < "$design_template" > "$temp_design_file"

    # Append multi-line input variables directly to the design file
    echo -e "$input_lines" >> "$temp_design_file"
    echo -e "$ev_values" >> "$temp_design_file"
    echo -e "$group_membership" >> "$temp_design_file"

    # Run FEAT

    echo -e "Running FEAT for cope $cope_num with temporary design file:"
    echo "  - $temp_design_file"
    feat "$temp_design_file"

    # Remove the design file after FEAT completes
    echo -e "\nRemoving temporary design file:"
    echo -e "  - $temp_design_file"
    rm -f "$temp_design_file"

    echo -e "\nCompleted FEAT for cope $cope_num."
done

echo -e "\n=== Third-level analysis completed ===\n."
