#!/bin/bash

# Dotfiles init script
# Symlinks dotfiles from this repo to their respective locations

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            ;;
    esac
done

log_info() {
    echo -e "\033[0;34m[INFO]\033[0m $1"
}

log_success() {
    echo -e "\033[0;32m[OK]\033[0m $1"
}

log_warn() {
    echo -e "\033[0;33m[WARN]\033[0m $1"
}

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
}

log_dry_run() {
    echo -e "\033[0;36m[DRY-RUN]\033[0m $1"
}

# Symlink items from source dir to target dir
# $1: source directory (in repo)
# $2: target directory (in $HOME)
symlink_dir_contents() {
    local source_dir="$1"
    local target_dir="$2"
    local dir_name="$(basename "$source_dir")"
    
    if [[ ! -d "$source_dir" ]]; then
        log_info "Directory $dir_name does not exist in repo, skipping..."
        return 0
    fi
    
    # Create target directory if it doesn't exist
    if [[ ! -d "$target_dir" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            log_dry_run "Would create directory: $target_dir"
        else
            log_info "Creating $target_dir"
            mkdir -p "$target_dir"
        fi
    fi
    
    # Symlink each item in the source directory
    for item in "$source_dir"/*; do
        [[ ! -e "$item" ]] && continue
        
        local item_name="$(basename "$item")"
        local target="$target_dir/$item_name"
        
        # If target exists and is not a symlink to our source, back it up
        if [[ -e "$target" && ! -L "$target" ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                log_dry_run "Would backup: $target -> $target.backup"
            else
                log_warn "Backing up existing $target to $target.backup"
                mv "$target" "$target.backup"
            fi
        fi
        
        # Remove existing symlink if it points elsewhere
        if [[ -L "$target" ]]; then
            local current_link="$(readlink "$target")"
            if [[ "$current_link" != "$item" ]]; then
                if [[ "$DRY_RUN" == true ]]; then
                    log_dry_run "Would remove existing symlink: $target -> $current_link"
                else
                    log_warn "Removing existing symlink $target -> $current_link"
                    rm "$target"
                fi
            else
                log_success "Already linked: $target"
                continue
            fi
        fi
        
        # Create symlink
        if [[ "$DRY_RUN" == true ]]; then
            log_dry_run "Would create symlink: $target -> $item"
        else
            ln -s "$item" "$target"
            log_success "Linked: $target -> $item"
        fi
    done
}

# Symlink items from root directory to $HOME
symlink_root_files() {
    local root_dir="$SCRIPT_DIR/root"
    
    if [[ ! -d "$root_dir" ]]; then
        log_info "root directory does not exist, skipping..."
        return 0
    fi
    
    for item in "$root_dir"/* "$root_dir"/.*; do
        [[ ! -e "$item" ]] && continue
        [[ "$(basename "$item")" == "." ]] && continue
        [[ "$(basename "$item")" == ".." ]] && continue
        
        local item_name="$(basename "$item")"
        local target="$HOME/$item_name"
        
        # If target exists and is not a symlink to our source, back it up
        if [[ -e "$target" && ! -L "$target" ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                log_dry_run "Would backup: $target -> $target.backup"
            else
                log_warn "Backing up existing $target to $target.backup"
                mv "$target" "$target.backup"
            fi
        fi
        
        # Remove existing symlink if it points elsewhere
        if [[ -L "$target" ]]; then
            local current_link="$(readlink "$target")"
            if [[ "$current_link" != "$item" ]]; then
                if [[ "$DRY_RUN" == true ]]; then
                    log_dry_run "Would remove existing symlink: $target -> $current_link"
                else
                    log_warn "Removing existing symlink $target -> $current_link"
                    rm "$target"
                fi
            else
                log_success "Already linked: $target"
                continue
            fi
        fi
        
        # Create symlink
        if [[ "$DRY_RUN" == true ]]; then
            log_dry_run "Would create symlink: $target -> $item"
        else
            ln -s "$item" "$target"
            log_success "Linked: $target -> $item"
        fi
    done
}

main() {
    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY RUN MODE - No changes will be made"
        echo ""
    fi
    
    log_info "Setting up dotfiles..."
    log_info "Source: $SCRIPT_DIR"
    log_info "Target: $HOME"
    echo ""
    
    # Link .config contents
    log_info "Processing .config..."
    symlink_dir_contents "$SCRIPT_DIR/.config" "$HOME/.config"
    echo ""
    
    # Link .local contents  
    log_info "Processing .local..."
    symlink_dir_contents "$SCRIPT_DIR/.local" "$HOME/.local"
    echo ""
    
    # Link root files
    log_info "Processing root files..."
    symlink_root_files
    echo ""
    
    if [[ "$DRY_RUN" == true ]]; then
        log_success "Dry run complete! No changes were made."
    else
        log_success "Dotfiles setup complete!"
    fi
}

main "$@"
