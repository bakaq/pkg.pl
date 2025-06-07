#!/bin/sh

print_test_result() {
    test_name="$1"
    result="$2"

    case "$result" in
        success)
            color_code="\033[1;32m"  # Bold green
            status_label="succeeded"
            ;;
        failure)
            color_code="\033[1;31m"  # Bold red
            status_label="failed"
            ;;
        *)
            exit 1
    esac

    printf '\ttest "%s" ... %b%s%b\n' "$test_name" "$color_code" "$status_label" "\033[0m"
}
