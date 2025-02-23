#!/usr/bin/env bash
set -euo pipefail

LOG_MODE="per-instance"
LOG_FORMAT="json"
LOG_DIR="/var/log/incus-backup"
LOG_MAX_SIZE="10MB"
LOG_ROTATE_COUNT=5
DEFAULT_BACKUP_DIR="/backups"
DEFAULT_COMPRESSION="gzip"
DEFAULT_RETENTION=7

get_timestamp() {
    date +'%d-%m-%Y %H:%M:%S'
}

get_file_timestamp() {
    date +'%d%m%Y_%H%M%S'
}

parse_size() {
    local size="$1"
    local value
    local unit

    if [[ $size =~ ^([0-9]+)([KMGTkmgt][Bb])?$ ]]; then
        value="${BASH_REMATCH[1]}"
        unit="${BASH_REMATCH[2]^^}"

        case "$unit" in
            KB) echo $((value * 1024)) ;;
            MB) echo $((value * 1024 * 1024)) ;;
            GB) echo $((value * 1024 * 1024 * 1024)) ;;
            TB) echo $((value * 1024 * 1024 * 1024 * 1024)) ;;
            "") echo "$value" ;;
            *) echo "Invalid size format: $size" >&2; return 1 ;;
        esac
    else
        echo "Invalid size format: $size" >&2
        return 1
    fi
}

check_log_rotation() {
    local log_file="$1"
    local max_size

    max_size=$(parse_size "$LOG_MAX_SIZE") || {
        echo "Error parsing LOG_MAX_SIZE" >&2
        return 1
    }

    [[ ! -f "$log_file" ]] && return 0

    local size
    size=$(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file")

    if [[ "$size" -gt "$max_size" ]]; then
        for i in $(seq $((LOG_ROTATE_COUNT-1)) -1 1); do
            if [[ -f "${log_file}.$i" ]]; then
                mv "${log_file}.$i" "${log_file}.$((i+1))"
            fi
        done

        mv "$log_file" "${log_file}.1"
        touch "$log_file"

        log "INFO" "log_rotation" "Rotation performed. Previous size: ${size} bytes, max size: ${max_size} bytes"

        if [[ -f "${log_file}.$((LOG_ROTATE_COUNT+1))" ]]; then
            rm "${log_file}.$((LOG_ROTATE_COUNT+1))"
        fi
        return 0
    fi
}

log() {
    local level="$1"
    local action="$2"
    shift 2
    local msg="$*"
    local current_instance="${CURRENT_INSTANCE:-global}"
    local timestamp
    timestamp="$(get_timestamp)"

    if [[ "$LOG_MODE" == "per-instance" ]]; then
        mkdir -p "$LOG_DIR"
        local log_file="$LOG_DIR/${current_instance}.log"
    else
        mkdir -p "$(dirname "$LOG_DIR")"
        local log_file="$LOG_DIR/incus-backup.log"
    fi

    check_log_rotation "$log_file"

    if [[ "$LOG_FORMAT" == "json" ]]; then
        echo "{\"timestamp\": \"$timestamp\", \"level\": \"$level\", \"action\": \"$action\", \"instance\": \"$current_instance\", \"message\": \"$msg\"}" >> "$log_file"
    else
        echo "$timestamp [$level] [$action] [$current_instance] $msg" >> "$log_file"
    fi
}

retention_cleanup() {
    local instance="$1"
    local dest="$2"
    local prefix="$3"
    local suffix="$4"
    local retention="$5"

    local backups
    mapfile -t backups < <(ls -1t "$dest"/"${prefix}${instance}"*.tar.* 2>/dev/null || true)
    local count=${#backups[@]}

    if [[ "$count" -le "$retention" ]]; then
        log "INFO" "retention_check" "$count backup(s) found (limit: $retention)"
        return 0
    fi

    log "INFO" "retention_cleanup" "Cleaning up old backups ($count found, limit: $retention)"

    for (( i=retention; i<count; i++ )); do
        if rm -f "${backups[$i]}"; then
            log "INFO" "retention_cleanup" "Deleted backup: ${backups[$i]}"
        else
            log "ERROR" "retention_cleanup" "Failed to delete: ${backups[$i]}"
        fi
    done
}

do_export() {
    local instance="$1"
    local dest="$2"
    local compression="$3"
    local prefix="$4"
    local suffix="$5"
    local optimized_storage="$6"
    local instance_only="$7"
    local project_arg="$8"

    local timestamp
    timestamp="$(get_file_timestamp)"

    # Debug pour voir la valeur de compression
    log "INFO" "export_debug" "Compression value: $compression"

    local output_file="${dest}/${prefix}${instance}${suffix}-${timestamp}.tar.${compression}"

    # Debug pour voir le nom de fichier construit
    log "INFO" "export_debug" "Output file: $output_file"

    local export_options=("--compression=${compression}")
    [[ "$optimized_storage" == "true" ]] && export_options+=("--optimized-storage")
    [[ "$instance_only" == "true" ]] && export_options+=("--instance-only")

    log "INFO" "export_start" "Starting export"

    if ! incus export "$instance" "$output_file" "${export_options[@]}" ${project_arg}; then
        log "ERROR" "export_error" "Export failed"
        return 1
    fi

    log "INFO" "export_complete" "Export completed => $output_file"
}

process_instance() {
    local instance="$1"
    local project_arg="$2"

    export CURRENT_INSTANCE="$instance"

    local enabled
    enabled=$(incus config get -e "$instance" "user.incus-export.enabled" $project_arg 2>/dev/null || echo "false")
    if [[ "$enabled" != "true" ]]; then
        log "INFO" "config_check" "Export not enabled for instance '$instance'"
        return 0
    fi  # <- Il manquait ce 'fi'

    local dest
    dest=$(incus config get -e "$instance" "user.incus-export.dest" $project_arg 2>/dev/null || echo "$DEFAULT_BACKUP_DIR")
    local compression
    compression=$(incus config get -e "$instance" "user.incus-export.compression" $project_arg 2>/dev/null | grep -v '^$' || echo "$DEFAULT_COMPRESSION")
    local retention
    retention=$(incus config get -e "$instance" "user.incus-export.retention" $project_arg 2>/dev/null || echo "$DEFAULT_RETENTION")
    local prefix
    prefix=$(incus config get -e "$instance" "user.incus-export.prefix" $project_arg 2>/dev/null || echo "")
    local suffix
    suffix=$(incus config get -e "$instance" "user.incus-export.suffix" $project_arg 2>/dev/null || echo "")
    local optimized_storage
    optimized_storage=$(incus config get -e "$instance" "user.incus-export.optimized-storage" $project_arg 2>/dev/null || echo "false")
    local instance_only
    instance_only=$(incus config get -e "$instance" "user.incus-export.instance-only" $project_arg 2>/dev/null || echo "true")

    mkdir -p "$dest"

    log "INFO" "config_load" "Instance config loaded: dest=$dest, compression=$compression, retention=$retention"

    log "INFO" "instance_process" "Starting instance processing"
    retention_cleanup "$instance" "$dest" "$prefix" "$suffix" "$retention"
    do_export "$instance" "$dest" "$compression" "$prefix" "$suffix" "$optimized_storage" "$instance_only" "$project_arg"
    retention_cleanup "$instance" "$dest" "$prefix" "$suffix" "$retention"
    log "INFO" "instance_process" "Instance processing completed"
}

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [PROJECT]

Backup tool for Incus instances/containers.

Options:
    --help      Show this help message

Arguments:
    PROJECT     Optional project name to backup (defaults to all projects)

Instance Configuration:
    Set the following properties on your instances to configure their backup:

    user.incus-export.enabled          Enable backup for this instance (true/false)
    user.incus-export.dest            Backup destination path (default: /backups)
    user.incus-export.compression     Compression type (gzip, none, xz - default: gzip)
    user.incus-export.retention       Number of backups to keep (default: 7)
    user.incus-export.prefix          Backup filename prefix
    user.incus-export.suffix          Backup filename suffix
    user.incus-export.optimized-storage   Use optimized storage (true/false)
    user.incus-export.instance-only   Backup instance only (true/false)

Examples:
    # Backup all instances in all projects
    $(basename "$0")

    # Backup instances in specific project
    $(basename "$0") myproject

    # Configure an instance for backup
    incus config set myinstance user.incus-export.enabled true
    incus config set myinstance user.incus-export.dest /path/to/backups
    incus config set myinstance user.incus-export.retention 10

Configuration:
    LOG_MODE            Logging mode (per-instance or global)
    LOG_FORMAT          Log format (json or text)
    LOG_DIR            Log directory
    LOG_MAX_SIZE       Max log file size (ex: 10MB)
    LOG_ROTATE_COUNT   Number of log files to keep
    DEFAULT_BACKUP_DIR  Default backup directory
    DEFAULT_COMPRESSION Default compression type
    DEFAULT_RETENTION   Default retention count
EOF
    exit 0
}

main() {
    # Check for help flag
    if [[ "${1:-}" == "--help" ]]; then
        show_help
    fi

    export CURRENT_INSTANCE="global"
    log "INFO" "startup" "Starting backup script"

    local project_filter="${1:-}"
    local project_arg=""
    if [[ -n "$project_filter" ]]; then
        project_arg="--project $project_filter"
        log "INFO" "config_load" "Project filter: $project_filter"
    fi

    local instances
    if [[ -n "$project_arg" ]]; then
        instances=$(incus list $project_arg --format csv -c n)
    else
        instances=$(incus list --format csv -c n)
    fi

    while IFS= read -r instance; do
        [[ -z "$instance" ]] && continue
        process_instance "$instance" "$project_arg"
    done <<< "$instances"

    log "INFO" "shutdown" "Backup script finished"
}

main "$@"