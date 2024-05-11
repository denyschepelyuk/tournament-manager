#!/bin/bash

parse_config() {
    local config_file=$1

    # shellcheck disable=SC1090
    if [ -f "$config_file" ]; then
        . "$config_file"
        if [ -n "$title" ]; then
            INDEX_TITLE=$title
        fi
        if [ -n "$output" ]; then
            OUTPUT_DIR=$output
        fi
    fi
}

# Checking if the required arguments are provided
# If not, print an error message and exit
check_args() {
    if [ -z "$OUTPUT_DIR" ]; then
        echo "Output directory not specified" >&2
        exit 1
    fi
    if [ -z "$INDEX_TITLE" ]; then
        echo "Index title not specified" >&2
        exit 1
    fi
}

# Parsing command line arguments
# Supported options:
# -o <output_dir> (-o<output_dir>)
# -t <index_title> (-t<index_title>)
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -o)
                OUTPUT_DIR="$2"
                shift;;
            -o*)
                OUTPUT_DIR="${1#-o}";;
            -t)
                INDEX_TITLE="$2"
                shift;;
            -t*)
                INDEX_TITLE="${1#-t}";;
            *)
                echo "Unknown option $1" >&2
                exit 1;;
        esac
        shift
    done

    check_args
}

# Function to process items
# and write them to a file
process_items() {
    local item_list=$1
    local output_file=$2
    local suffix=$3

    for item in $item_list; do
        processed_item=$(basename "$item" "$suffix")
        echo "$processed_item" >> "$output_file"
    done

    sort "$output_file" | uniq > "${output_file}.uniq"
    mv "${output_file}.uniq" "$output_file"
}

# Extracting module names from the tasks directory
# and writing them to a temporary file
process_modules() {
    MODULE_NAMES_TMP=$(find $TASK_DIR -type d -mindepth 1 -maxdepth 1| sort)
    process_items "$MODULE_NAMES_TMP" "$MODULE_NAMES" ""
}

# Extracting team names from the tasks directory
# Setting initial score to 0
# and writing them to a temporary file
process_teams() {
    TEAM_NAMES_TMP=$(find $TASK_DIR -type f -name "*.log.gz"| sort)
    process_items "$TEAM_NAMES_TMP" "$TEAM_NAMES" ".log.gz"

    cat "$TEAM_NAMES" > "$SCORES"
    sed 's/$/ 0 0/' "$SCORES" > temp && mv temp "$SCORES"
}

# Function to check the properties
# Is not used in the final version
check_properties(){
    echo "------"
    echo "MODULES:"
    cat "$MODULE_NAMES"
    echo "------"
    echo "TEAMS:"
    cat "$TEAM_NAMES"
    echo "------"
    echo "SCORES:"
    cat "$SCORES"
    echo "------"
    echo "LOGS:"
    cat "$LOG_ARCHIVE"
    echo "------"
}

# Function to update team points
# Usage: update_team_points <passes> <team> <scores_file>
update_team_points() {
    local PASSES=$1
    local TEAM=$2
    SCORES=$3

    while IFS= read -r LINE; do

        CUR_TEAM=$(echo "$LINE" | cut -d" " -f1)

        if [ "$TEAM" != "$CUR_TEAM" ]; then
            echo "$LINE" >> "${SCORES}.tmp"
            continue
        fi

        PREV_PASSES=$(echo "$LINE" | cut -d" " -f2)
        NEW_PASSES=$((PREV_PASSES + PASSES))
        echo "$TEAM $NEW_PASSES" >> "${SCORES}.tmp"

    done < "$SCORES"
    mv "${SCORES}.tmp" "$SCORES"
}

# Function to get the module name
# Usage: get_module_name <module>
# Argument <module> is the default module name which will be changed if the module has a name in its meta.rc file
get_module_name(){
    local MODULE=$1
    local MODULE_NAME=$MODULE
    if [ -f "$TASK_DIR/$MODULE/meta.rc" ]; then
        # shellcheck disable=SC1090
        . "$TASK_DIR/$MODULE/meta.rc"
        if [ -n "$name" ]; then
            MODULE_NAME=$name
        fi
    fi
    echo "$MODULE_NAME"
}

# Function to create a directory if it doesn't exist
create_directory_if_not_exists() {
    local DIR=$1
    if [ ! -d "$DIR" ]; then
        mkdir -p "$DIR"
    fi
}

# Function to process a log file
# Usage: process_log_file <log> <curr_team_dir> <module> <team>
process_log_file() {
    local LOG=$1
    local CURR_TEAM_DIR=$2
    local MODULE=$3
    local TEAM=$4

    local MODULE_NAME

    if [ ! -f "$LOG" ]; then
        echo "Log not available." > "$CURR_TEAM_DIR/${MODULE}.log"
        MODULE_NAME=$(get_module_name "$MODULE")
        echo "$TEAM $MODULE $MODULE_NAME 0 0" >> "$LOG_ARCHIVE"
        return
    fi

    gzip -dc "$LOG" > "$CURR_TEAM_DIR/${MODULE}.log"

    local passes_count
    passes_count=$(gzip -cd "$LOG" | grep -c '^pass')

    local fails_count
    fails_count=$(gzip -cd "$LOG" | grep -c '^fail')
    
    update_team_points "$passes_count" "$TEAM" "$SCORES"

    MODULE_NAME=$(get_module_name "$MODULE")
    
    echo "$TEAM $MODULE $MODULE_NAME $passes_count $fails_count" >> "$LOG_ARCHIVE"
}

# Function to calculate scores
# and update the scores file
calculate_and_update_scores(){
    while IFS= read -r MODULE; do
        while IFS= read -r TEAM; do
            local LOG="${TASK_DIR}/${MODULE}/${TEAM}.log.gz"
            local CURR_TEAM_DIR="$OUTPUT_DIR/team-$TEAM/"

            create_directory_if_not_exists "$OUTPUT_DIR"
            create_directory_if_not_exists "$CURR_TEAM_DIR"

            process_log_file "$LOG" "$CURR_TEAM_DIR" "$MODULE" "$TEAM"
        done < "$TEAM_NAMES"
    done < "$MODULE_NAMES"
}

# Function to create and initialize an index file
# Usage: create_and_initialize_index_file <index_file> <team>
create_and_initialize_index_file() {
    local INDEX_FILE=$1
    local TEAM=$2

    if [ ! -f "$INDEX_FILE" ]; then
        touch "$INDEX_FILE"
    fi

    echo "# Team $TEAM" > "$INDEX_FILE"
    echo "" >> "$INDEX_FILE"
    echo "$TABLE_TEMP_HAT" >> "$INDEX_FILE"
}

# Function to process a line from the log archive
# Usage: process_log_archive_line <line> <team> <index_file>
process_log_archive_line() {
    local LINE=$1
    local TEAM=$2
    local INDEX_FILE=$3

    local TEAM_NAME
    TEAM_NAME=$(echo "$LINE" | awk '{print $1}')

    local MODULE_FILE_NAME
    MODULE_FILE_NAME=$(echo "$LINE" | awk '{print $2}')

    local MODULE_NAME
    MODULE_NAME=$(echo "$LINE" | awk '{for(i=3;i<=NF-2;i++) printf $i" "; print ""}')

    local PASSED
    PASSED=$(echo "$LINE" | awk '{print $(NF-1)}')

    local FAILED
    FAILED=$(echo "$LINE" | awk '{print $NF}')

    if [ "$TEAM" != "$TEAM_NAME" ]; then
        return
    fi

    printf "| %-18s | %6s | %6s | %-36s |\n" "$MODULE_NAME" "$PASSED" "$FAILED" "[Complete log]($MODULE_FILE_NAME.log)." >> "$INDEX_FILE"
}

# Function to set the team's index.md
# Usage: set_team_md <team>
set_team_md(){
    local TEAM=$1
    local INDEX_FILE="$OUTPUT_DIR/team-$TEAM/index.md"

    create_directory_if_not_exists "$OUTPUT_DIR/team-$TEAM"
    create_and_initialize_index_file "$INDEX_FILE" "$TEAM"

    while IFS= read -r LINE; do
        process_log_archive_line "$LINE" "$TEAM" "$INDEX_FILE"
    done < "$LOG_ARCHIVE"

    echo "$TABLE_TEMP_DIVIDER" >> "$INDEX_FILE"
    echo "" >> "$INDEX_FILE"
}

# Function to set the index.md
# Usage: set_index_md
set_index_md(){
    local INDEX_FILE="$OUTPUT_DIR/index.md"
    
    if [ ! -f "$INDEX_FILE" ]; then
        touch "$INDEX_FILE"
    fi

    echo "# $INDEX_TITLE" > "$INDEX_FILE"
    echo "" >> "$INDEX_FILE"

    local cnt=1
    while IFS= read -r LINE; do
        TEAM_NAME=$(echo "$LINE" | cut -d" " -f1)
        TEAM_POINTS=$(echo "$LINE" | cut -d" " -f2)
        echo " $cnt. $TEAM_NAME ($TEAM_POINTS points)" >> "$INDEX_FILE"
        cnt=$((cnt+1))
    done < <(sort -k2 -n -r "$SCORES")
    echo "" >> "$INDEX_FILE"
}

# Function to generate md files
# Usage: generate_mds
generate_mds(){
    while IFS= read -r TEAM; do
        set_team_md "$TEAM"
    done < "$TEAM_NAMES"

    set_index_md
} 

# Function to define properties
define_properties() {
    OUTPUT_DIR="out"
    INDEX_TITLE="My tournament"
    TASK_DIR="tasks"
    CONFIG_FILE="config.rc"
}

# Function to define table-building templates
define_table_templates() {
    TABLE_TEMP_DIVIDER="+--------------------+--------+--------+--------------------------------------+"
    TABLE_TEMP_TITLE="| Task               | Passed | Failed | Links                                |"
    TABLE_TEMP_HAT=$(printf "%s\n%s\n%s\n" "$TABLE_TEMP_DIVIDER" "$TABLE_TEMP_TITLE" "$TABLE_TEMP_DIVIDER")
}

# Function to create temporary files
create_temp_files() {
    MODULE_NAMES=$(mktemp)
    TEAM_NAMES=$(mktemp)
    SCORES=$(mktemp)
    LOG_ARCHIVE=$(mktemp)
}

# Function to clean up temporary files
clean_up_temp_files() {
    rm "$MODULE_NAMES"
    rm "$TEAM_NAMES"
    rm "$SCORES"
    rm "$LOG_ARCHIVE"
}

# Main function
# Handles the main logic and manages function calls
# Usage: main "$@"
main(){
    define_properties
    define_table_templates
    create_temp_files

    parse_config "$CONFIG_FILE"
    parse_args "$@"

    create_directory_if_not_exists "$OUTPUT_DIR"

    process_modules
    process_teams

    calculate_and_update_scores

    generate_mds

    clean_up_temp_files
}
main "$@"