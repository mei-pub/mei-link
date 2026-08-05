#!/usr/bin/env bash

# Extract a single file from a compressed tar archive without relying on GNU
# tar extensions. macOS ships BSD tar, which does not support --wildcards.
extract_tar_member() {
    local archive_path="$1"
    local member_name="$2"
    local archive_member

    archive_member="$(tar -tzf "$archive_path" | awk -F/ -v name="$member_name" '$NF == name { print; exit }')"
    if [ -z "$archive_member" ]; then
        echo "Archive member '$member_name' not found in $archive_path" >&2
        return 1
    fi

    tar -xOzf "$archive_path" "$archive_member"
}
