#!/usr/bin/env zsh
# =============================================================================
# move-mountpoints.sh - Safely migrate mountpoints on macOS with config updates
# =============================================================================
# Usage: ./move-mountpoints.sh <old_path> <new_path>
# Example: ./move-mountpoints.sh ~/nw ~/git/nw
#
# What this script does:
#   1. Validates source/destination paths
#   2. Creates timestamped backups of all affected config files
#   3. Moves the directory
#   4. Updates all config file references (shell configs, LaunchAgents, ~/.config)
#   5. Flags system files needing sudo (fstab, AutoFS)
#   6. Verifies the migration
#   7. Rolls back on any error
# =============================================================================

set -e
set -o pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly BACKUP_DIR="${HOME}/.mountpoints-backups"
readonly DATE="$(date +%Y%m%d_%H%M%S)"

# Files/directories to scan for path references
CONFIG_SCAN_FILES=(
    "${HOME}/.zprofile"
    "${HOME}/.zshrc"
    "${HOME}/.bash_profile"
    "${HOME}/.bashrc"
)

CONFIG_SCAN_DIRS=(
    "${HOME}/.config"
    "${HOME}/Library/LaunchAgents"
)

SYSTEM_FILES_READONLY=(
    "/etc/fstab"
    "/etc/auto_master"
    "/etc/auto_direct"
    "/etc/auto_home"
)

# =============================================================================
# Logging
# =============================================================================

log_info()    { print "  [INFO] $*"; }
log_warn()    { print "  [WARN] $*" >&2; }
log_error()   { print " [ERROR] $*" >&2; exit 1; }
log_success() { print "    [OK] $*"; }
log_header()  { print "\n==> $*"; }

confirm() {
    local prompt="$1"
    local response
    read -q "response?    ${prompt} Continue? [y/N] " || { echo; exit 1; }
    echo
}

# =============================================================================
# Backup
# =============================================================================

create_backup() {
    local path="$1"
    [[ ! -f "${path}" ]] && return 0
    local backup_path="${BACKUP_DIR}/${DATE}${path}"
    mkdir -p "$(dirname "${backup_path}")"
    cp -p "${path}" "${backup_path}"
    log_info "Backed up: ${path}"
}

backup_all_configs() {
    log_header "Creating backups"
    mkdir -p "${BACKUP_DIR}/${DATE}"

    for f in "${CONFIG_SCAN_FILES[@]}"; do
        create_backup "${f}"
    done

    for d in "${CONFIG_SCAN_DIRS[@]}"; do
        [[ -d "${d}" ]] && find "${d}" -type f 2>/dev/null | while read -r file; do
            grep -qF "${OLD_PATH}" "${file}" 2>/dev/null && create_backup "${file}"
        done
    done

    log_success "Backups stored at: ${BACKUP_DIR}/${DATE}"
}

# =============================================================================
# Path Replacement
# =============================================================================

update_file_paths() {
    local file="$1" old="$2" new="$3"
    [[ ! -f "${file}" ]] && return 0
    grep -qF "${old}" "${file}" 2>/dev/null || return 0

    local count
    count=$(grep -cF "${old}" "${file}" 2>/dev/null || echo 0)
    sed -i '' "s|${old}|${new}|g" "${file}"
    log_info "Updated ${count} reference(s) in: ${file}"
}

update_all_config_files() {
    log_header "Updating configuration files"

    for f in "${CONFIG_SCAN_FILES[@]}"; do
        update_file_paths "${f}" "${OLD_PATH}" "${NEW_PATH}"
        # Also handle tilde-form if applicable
        local tilde_old="${OLD_PATH/#${HOME}/~}"
        local tilde_new="${NEW_PATH/#${HOME}/~}"
        [[ "${tilde_old}" != "${OLD_PATH}" ]] && update_file_paths "${f}" "${tilde_old}" "${tilde_new}"
    done

    for d in "${CONFIG_SCAN_DIRS[@]}"; do
        [[ ! -d "${d}" ]] && continue
        find "${d}" -type f 2>/dev/null | while read -r file; do
            update_file_paths "${file}" "${OLD_PATH}" "${NEW_PATH}"
        done
    done

    log_success "Config files updated"
}

# =============================================================================
# LaunchAgents
# =============================================================================

fix_launch_agents() {
    log_header "Checking LaunchAgents"
    local found=0

    for launch_dir in "${HOME}/Library/LaunchAgents" "/Library/LaunchAgents" "/Library/LaunchDaemons"; do
        [[ ! -d "${launch_dir}" ]] && continue
        find "${launch_dir}" -name "*.plist" 2>/dev/null | while read -r plist; do
            if grep -qF "${OLD_PATH}" "${plist}" 2>/dev/null; then
                found=1
                create_backup "${plist}"
                update_file_paths "${plist}" "${OLD_PATH}" "${NEW_PATH}"

                # Reload the agent
                local label
                label=$(defaults read "${plist}" Label 2>/dev/null || true)
                if [[ -n "${label}" ]]; then
                    log_info "Reloading LaunchAgent: ${label}"
                    launchctl unload "${plist}" 2>/dev/null || true
                    launchctl load "${plist}" 2>/dev/null || true
                fi
            fi
        done
    done

    [[ ${found} -eq 0 ]] && log_info "No LaunchAgents references found"
    log_success "LaunchAgents checked"
}

# =============================================================================
# System Files (require sudo)
# =============================================================================

check_system_files() {
    log_header "Checking system-protected files"
    local needs_sudo=0

    for sysfile in "${SYSTEM_FILES_READONLY[@]}"; do
        [[ ! -f "${sysfile}" ]] && continue
        if grep -qF "${OLD_PATH}" "${sysfile}" 2>/dev/null; then
            needs_sudo=1
            log_warn "Old path found in ${sysfile} — requires manual update:"
            log_warn "  sudo sed -i '' 's|${OLD_PATH}|${NEW_PATH}|g' ${sysfile}"
        fi
    done

    if [[ ${needs_sudo} -eq 1 ]]; then
        log_warn "Run the above sudo commands manually, then restart automountd:"
        log_warn "  sudo automount -vc"
    else
        log_info "No system file references found"
    fi
}

# =============================================================================
# Move
# =============================================================================

move_directory() {
    log_header "Moving directory"
    [[ ! -d "${OLD_PATH}" ]] && log_error "Source does not exist: ${OLD_PATH}"

    local parent_dir="$(dirname "${NEW_PATH}")"
    if [[ ! -d "${parent_dir}" ]]; then
        log_info "Creating parent directory: ${parent_dir}"
        mkdir -p "${parent_dir}"
    fi

    if [[ -d "${NEW_PATH}" ]]; then
        log_warn "Destination already exists: ${NEW_PATH}"
        confirm "Merge/overwrite destination?"
    fi

    mv -v "${OLD_PATH}" "${NEW_PATH}"
    log_success "Moved: ${OLD_PATH} -> ${NEW_PATH}"
}

# =============================================================================
# Verify
# =============================================================================

verify_migration() {
    log_header "Verifying migration"
    [[ ! -d "${NEW_PATH}" ]] && log_error "New path does not exist: ${NEW_PATH}"
    [[ -d "${OLD_PATH}" ]]   && log_error "Old path still exists: ${OLD_PATH}"
    local count
    count=$(find "${NEW_PATH}" -maxdepth 2 -type f 2>/dev/null | wc -l | tr -d ' ')
    log_success "New path exists with ${count} files (up to depth 2)"
}

# =============================================================================
# Rollback
# =============================================================================

rollback() {
    print "\n  [ROLLBACK] Error detected — attempting rollback"
    local backup_path="${BACKUP_DIR}/${DATE}"

    # Move directory back
    if [[ -d "${NEW_PATH}" && ! -d "${OLD_PATH}" ]]; then
        print "  [ROLLBACK] Moving ${NEW_PATH} back to ${OLD_PATH}"
        mv -v "${NEW_PATH}" "${OLD_PATH}" || print "  [ROLLBACK] WARNING: Directory move back failed"
    fi

    # Restore config files
    if [[ -d "${backup_path}" ]]; then
        find "${backup_path}" -type f 2>/dev/null | while read -r backup_file; do
            local original="/${backup_file#${backup_path}/}"
            if [[ -f "${original}" ]]; then
                cp -p "${backup_file}" "${original}"
                print "  [ROLLBACK] Restored: ${original}"
            fi
        done
        print "  [ROLLBACK] Config files restored from backup"
    fi

    print "  [ROLLBACK] Complete. Review the output above for any manual fixes needed."
    exit 1
}

# =============================================================================
# Main
# =============================================================================

main() {
    if [[ $# -ne 2 ]]; then
        print "Usage: ${SCRIPT_NAME} <old_path> <new_path>"
        print "Example: ${SCRIPT_NAME} ~/nw ~/git/nw"
        exit 1
    fi

    # Resolve old path (must exist)
    OLD_PATH="$(cd "$1" 2>/dev/null && pwd)" || log_error "Source path does not exist: $1"
    # Expand ~ in new path (may not exist yet)
    NEW_PATH="${${2}/#\~/${HOME}}"

    print "\n====================================================="
    print "  macOS Mountpoint Migration"
    print "====================================================="
    print "  From: ${OLD_PATH}"
    print "    To: ${NEW_PATH}"
    print "  Time: ${DATE}"
    print "=====================================================\n"

    confirm "Ready to proceed?"

    trap 'rollback' ERR

    backup_all_configs
    move_directory
    update_all_config_files
    fix_launch_agents
    check_system_files
    verify_migration

    trap - ERR

    print "\n====================================================="
    print "  Migration complete!"
    print "====================================================="
    log_info "Backup: ${BACKUP_DIR}/${DATE}"
    log_info "Next steps:"
    log_info "  1. source ~/.zshrc  (reload shell config)"
    log_info "  2. Check for any [WARN] messages above requiring sudo"
    log_info "  3. Run: sudo automount -vc  (if AutoFS/fstab were changed)"
    print
}

main "$@"
