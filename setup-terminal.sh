#!/bin/bash
#===============================================================================
# Terminal Setup Script for Debian/Ubuntu
#===============================================================================
# This script installs and configures a powerful terminal environment including:
#   - Zsh with Oh My Zsh framework
#   - Powerlevel10k theme
#   - zsh-autosuggestions and zsh-syntax-highlighting plugins
#   - fzf fuzzy finder with custom preview function
#   - bat (batcat on Ubuntu) with alias
#
# It provides an interactive menu to:
#   1. Install everything
#   2. Uninstall (revert) changes - selectively or completely
#
# All changes are tracked in a state file so the uninstaller knows exactly
# what was modified.
#===============================================================================

set -e  # Exit on error

#-------------------------------------------
# Color definitions for output
#-------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#-------------------------------------------
# Paths and variables
#-------------------------------------------
USER_HOME="$HOME"
USER_NAME=$(whoami)
STATE_FILE="$USER_HOME/.term_setup_state"
BACKUP_DIR="$USER_HOME/.term_setup_backups"
ZSH_CUSTOM="${ZSH_CUSTOM:-$USER_HOME/.oh-my-zsh/custom}"

#-------------------------------------------
# Helper functions
#-------------------------------------------
# Print a success message
success_msg() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Print an error message and exit
error_msg() {
    echo -e "${RED}✗ $1${NC}"
    exit 1
}

# Print a warning message
warning_msg() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Print an informational message
info_msg() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Check if previous command succeeded, otherwise exit
check_success() {
    if [ $? -eq 0 ]; then
        success_msg "$1"
    else
        error_msg "$1 failed!"
    fi
}

# Write current state to the state file
save_state() {
    {
        echo "# Terminal setup state - generated $(date)"
        echo "OMZ_INSTALLED=$OMZ_INSTALLED"
        echo "AUTOSUGGESTIONS_INSTALLED=$AUTOSUGGESTIONS_INSTALLED"
        echo "SYNTAX_HIGHLIGHTING_INSTALLED=$SYNTAX_HIGHLIGHTING_INSTALLED"
        echo "P10K_INSTALLED=$P10K_INSTALLED"
        echo "ZSHRC_BACKUP=\"$ZSHRC_BACKUP\""
        echo "P10K_BACKUP=\"$P10K_BACKUP\""
        echo "SHELL_CHANGED=$SHELL_CHANGED"
        echo "PREVIOUS_SHELL=\"$PREVIOUS_SHELL\""
        echo "INSTALLED_PACKAGES=(${INSTALLED_PACKAGES[@]})"
    } > "$STATE_FILE"
    chmod 600 "$STATE_FILE"
}

# Load state from state file (if exists)
load_state() {
    if [ -f "$STATE_FILE" ]; then
        # Source the state file to get variables
        source "$STATE_FILE"
        # Ensure arrays are properly initialized
        if [ -z "${INSTALLED_PACKAGES+x}" ]; then
            INSTALLED_PACKAGES=()
        fi
    else
        # Default values
        OMZ_INSTALLED=0
        AUTOSUGGESTIONS_INSTALLED=0
        SYNTAX_HIGHLIGHTING_INSTALLED=0
        P10K_INSTALLED=0
        ZSHRC_BACKUP=""
        P10K_BACKUP=""
        SHELL_CHANGED=0
        PREVIOUS_SHELL=""
        INSTALLED_PACKAGES=()
    fi
}

#-------------------------------------------
# Installation functions
#-------------------------------------------

# Install required packages and record which ones were newly added
install_packages() {
    info_msg "Updating package list..."
    sudo apt update -qq
    check_success "Package list updated"

    info_msg "Checking currently installed packages..."
    # Create a snapshot of installed packages
    local before_list=$(mktemp)
    dpkg-query -W -f='${Package}\n' | sort > "$before_list"

    info_msg "Installing required packages (zsh git fzf bat curl wget)..."
    sudo apt install -y zsh git fzf bat curl wget
    check_success "Packages installed"

    local after_list=$(mktemp)
    dpkg-query -W -f='${Package}\n' | sort > "$after_list"

    # Find newly installed packages
    local new_packages=()
    while IFS= read -r pkg; do
        if ! grep -qx "$pkg" "$before_list"; then
            new_packages+=("$pkg")
        fi
    done < <(comm -13 "$before_list" "$after_list")

    # Store the list of newly installed packages (may be empty if all were present)
    INSTALLED_PACKAGES=("${new_packages[@]}")

    # Clean up temp files
    rm -f "$before_list" "$after_list"

    if [ ${#INSTALLED_PACKAGES[@]} -gt 0 ]; then
        info_msg "Newly installed packages: ${INSTALLED_PACKAGES[*]}"
    else
        info_msg "All required packages were already installed."
    fi
}

# Install Oh My Zsh
install_ohmyzsh() {
    if [ ! -d "$USER_HOME/.oh-my-zsh" ]; then
        info_msg "Installing Oh My Zsh..."
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        check_success "Oh My Zsh installed"
        OMZ_INSTALLED=1
    else
        warning_msg "Oh My Zsh already installed, skipping."
        OMZ_INSTALLED=0
    fi
}

# Install zsh-autosuggestions plugin
install_autosuggestions() {
    local plugin_dir="$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    if [ ! -d "$plugin_dir" ]; then
        info_msg "Installing zsh-autosuggestions..."
        git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$plugin_dir" 2>/dev/null
        check_success "zsh-autosuggestions installed"
        AUTOSUGGESTIONS_INSTALLED=1
    else
        warning_msg "zsh-autosuggestions already installed, skipping."
        AUTOSUGGESTIONS_INSTALLED=0
    fi
}

# Install zsh-syntax-highlighting plugin
install_syntax_highlighting() {
    local plugin_dir="$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
    if [ ! -d "$plugin_dir" ]; then
        info_msg "Installing zsh-syntax-highlighting..."
        git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$plugin_dir" 2>/dev/null
        check_success "zsh-syntax-highlighting installed"
        SYNTAX_HIGHLIGHTING_INSTALLED=1
    else
        warning_msg "zsh-syntax-highlighting already installed, skipping."
        SYNTAX_HIGHLIGHTING_INSTALLED=0
    fi
}

# Install Powerlevel10k theme
install_powerlevel10k() {
    local theme_dir="$ZSH_CUSTOM/themes/powerlevel10k"
    if [ ! -d "$theme_dir" ]; then
        info_msg "Installing Powerlevel10k..."
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$theme_dir" 2>/dev/null
        check_success "Powerlevel10k installed"
        P10K_INSTALLED=1
    else
        warning_msg "Powerlevel10k already installed, skipping."
        P10K_INSTALLED=0
    fi
}

# Configure .zshrc (backup existing, then write new)
configure_zshrc() {
    info_msg "Configuring .zshrc..."

    # Create backup directory if needed
    mkdir -p "$BACKUP_DIR"

    # Backup existing .zshrc if it exists
    if [ -f "$USER_HOME/.zshrc" ]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        ZSHRC_BACKUP="$BACKUP_DIR/zshrc.backup.$timestamp"
        cp "$USER_HOME/.zshrc" "$ZSHRC_BACKUP"
        success_msg "Backed up existing .zshrc to $ZSHRC_BACKUP"
    else
        ZSHRC_BACKUP=""
        info_msg "No existing .zshrc found, will create new one."
    fi

    # Write new .zshrc
    cat > "$USER_HOME/.zshrc" << 'EOF'
# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Path to Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"

# Theme
ZSH_THEME="powerlevel10k/powerlevel10k"

# Plugins
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)

source $ZSH/oh-my-zsh.sh

# Aliases
# Ubuntu uses batcat, Debian uses bat; we handle both
if command -v batcat &> /dev/null; then
    alias bat=batcat
elif command -v bat &> /dev/null; then
    alias bat=bat
fi

# Custom function: fzf file finder with preview
ff() {
    local bat_cmd="batcat"
    if ! command -v batcat &> /dev/null; then
        bat_cmd="bat"
    fi
    find . -type f | fzf --preview "$bat_cmd --color=always --line-range :500 {}" --preview-window 'right:60%,border-left'
}

# Load Powerlevel10k config
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Load fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
EOF
    check_success ".zshrc configured"
}

# Configure Powerlevel10k (backup existing, then write new)
configure_p10k() {
    info_msg "Configuring Powerlevel10k (.p10k.zsh)..."

    mkdir -p "$BACKUP_DIR"

    if [ -f "$USER_HOME/.p10k.zsh" ]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        P10K_BACKUP="$BACKUP_DIR/p10k.zsh.backup.$timestamp"
        cp "$USER_HOME/.p10k.zsh" "$P10K_BACKUP"
        success_msg "Backed up existing .p10k.zsh to $P10K_BACKUP"
    else
        P10K_BACKUP=""
        info_msg "No existing .p10k.zsh found, will create new one."
    fi

    # Write .p10k.zsh (using the same content as original script)
    cat > "$USER_HOME/.p10k.zsh" << 'EOF'
# Generated by Powerlevel10k configuration wizard on 2026-08-17 at 19:12 UTC.
# Based on romkatv/powerlevel10k/config/p10k-classic.zsh, checksum 08429.
# Wizard options: powerline, classic, ascii, dark, 24h time, 1 line, compact, concise,
# transient_prompt, instant_prompt=verbose.
# Type `p10k configure` to generate another config.

# Temporarily change options.
'builtin' 'local' '-a' 'p10k_config_opts'
[[ ! -o 'aliases'         ]] || p10k_config_opts+=('aliases')
[[ ! -o 'sh_glob'         ]] || p10k_config_opts+=('sh_glob')
[[ ! -o 'no_brace_expand' ]] || p10k_config_opts+=('no_brace_expand')
'builtin' 'setopt' 'no_aliases' 'no_sh_glob' 'brace_expand'

() {
  emulate -L zsh -o extended_glob

  # Unset all configuration options.
  unset -m '(POWERLEVEL9K_*|DEFAULT_USER)~POWERLEVEL9K_GITSTATUS_DIR'

  # Zsh >= 5.1 is required.
  [[ $ZSH_VERSION == (5.<1->*|<6->.*) ]] || return

  # The list of segments shown on the left.
  typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(
    dir                     # current directory
    vcs                     # git status
  )

  # The list of segments shown on the right.
  typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(
    status                  # exit code of the last command
    command_execution_time  # duration of the last command
    background_jobs         # presence of background jobs
    context                 # user@hostname
    time                    # current time
  )

  # Defines character set used by powerlevel10k.
  typeset -g POWERLEVEL9K_MODE=ascii
  typeset -g POWERLEVEL9K_ICON_PADDING=none
  typeset -g POWERLEVEL9K_ICON_BEFORE_CONTENT=

  # Add an empty line before each prompt.
  typeset -g POWERLEVEL9K_PROMPT_ADD_NEWLINE=false

  # Connect left prompt lines with these symbols.
  typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_PREFIX='%240F╭-'
  typeset -g POWERLEVEL9K_MULTILINE_NEWLINE_PROMPT_PREFIX='%240F├-'
  typeset -g POWERLEVEL9K_MULTILINE_LAST_PROMPT_PREFIX='%240F╰-'
  # Connect right prompt lines with these symbols.
  typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_SUFFIX='%240F-╮'
  typeset -g POWERLEVEL9K_MULTILINE_NEWLINE_PROMPT_SUFFIX='%240F-┤'
  typeset -g POWERLEVEL9K_MULTILINE_LAST_PROMPT_SUFFIX='%240F-╯'

  # Filler between left and right prompt on the first prompt line.
  typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_CHAR=' '
  typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_BACKGROUND=
  typeset -g POWERLEVEL9K_MULTILINE_NEWLINE_PROMPT_GAP_BACKGROUND=
  if [[ $POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_CHAR != ' ' ]]; then
    typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_FOREGROUND=240
    typeset -g POWERLEVEL9K_EMPTY_LINE_LEFT_PROMPT_FIRST_SEGMENT_END_SYMBOL='%{%}'
    typeset -g POWERLEVEL9K_EMPTY_LINE_RIGHT_PROMPT_FIRST_SEGMENT_START_SYMBOL='%{%}'
  fi

  # Default background color.
  typeset -g POWERLEVEL9K_BACKGROUND=236

  # Separators
  typeset -g POWERLEVEL9K_LEFT_SUBSEGMENT_SEPARATOR='%244F|'
  typeset -g POWERLEVEL9K_RIGHT_SUBSEGMENT_SEPARATOR='%244F|'
  typeset -g POWERLEVEL9K_LEFT_SEGMENT_SEPARATOR=''
  typeset -g POWERLEVEL9K_RIGHT_SEGMENT_SEPARATOR=''
  typeset -g POWERLEVEL9K_LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL=''
  typeset -g POWERLEVEL9K_RIGHT_PROMPT_FIRST_SEGMENT_START_SYMBOL=''
  typeset -g POWERLEVEL9K_LEFT_PROMPT_FIRST_SEGMENT_START_SYMBOL=''
  typeset -g POWERLEVEL9K_RIGHT_PROMPT_LAST_SEGMENT_END_SYMBOL=''
  typeset -g POWERLEVEL9K_EMPTY_LINE_LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL=

  # Directory
  typeset -g POWERLEVEL9K_DIR_FOREGROUND=31
  typeset -g POWERLEVEL9K_SHORTEN_STRATEGY=truncate_to_unique
  typeset -g POWERLEVEL9K_SHORTEN_DELIMITER=
  typeset -g POWERLEVEL9K_DIR_SHORTENED_FOREGROUND=103
  typeset -g POWERLEVEL9K_DIR_ANCHOR_FOREGROUND=39
  typeset -g POWERLEVEL9K_DIR_ANCHOR_BOLD=true
  typeset -g POWERLEVEL9K_DIR_MAX_LENGTH=80
  typeset -g POWERLEVEL9K_DIR_MIN_COMMAND_COLUMNS=40
  typeset -g POWERLEVEL9K_DIR_MIN_COMMAND_COLUMNS_PCT=50
  typeset -g POWERLEVEL9K_DIR_HYPERLINK=false
  typeset -g POWERLEVEL9K_DIR_SHOW_WRITABLE=v3
  typeset -g POWERLEVEL9K_DIR_CLASSES=()

  # Git status
  typeset -g POWERLEVEL9K_VCS_BRANCH_ICON=
  typeset -g POWERLEVEL9K_VCS_UNTRACKED_ICON='?'
  typeset -g POWERLEVEL9K_VCS_MAX_INDEX_SIZE_DIRTY=-1
  typeset -g POWERLEVEL9K_VCS_DISABLED_WORKDIR_PATTERN='~'
  typeset -g POWERLEVEL9K_VCS_DISABLE_GITSTATUS_FORMATTING=true
  typeset -g POWERLEVEL9K_VCS_CONTENT_EXPANSION='${$((my_git_formatter(1)))+${my_git_format}}'
  typeset -g POWERLEVEL9K_VCS_LOADING_CONTENT_EXPANSION='${$((my_git_formatter(0)))+${my_git_format}}'
  typeset -g POWERLEVEL9K_VCS_{STAGED,UNSTAGED,UNTRACKED,CONFLICTED,COMMITS_AHEAD,COMMITS_BEHIND}_MAX_NUM=-1
  typeset -g POWERLEVEL9K_VCS_VISUAL_IDENTIFIER_COLOR=76
  typeset -g POWERLEVEL9K_VCS_LOADING_VISUAL_IDENTIFIER_COLOR=244
  typeset -g POWERLEVEL9K_VCS_VISUAL_IDENTIFIER_EXPANSION=
  typeset -g POWERLEVEL9K_VCS_BACKENDS=(git)
  typeset -g POWERLEVEL9K_VCS_CLEAN_FOREGROUND=76
  typeset -g POWERLEVEL9K_VCS_UNTRACKED_FOREGROUND=76
  typeset -g POWERLEVEL9K_VCS_MODIFIED_FOREGROUND=178

  function my_git_formatter() {
    emulate -L zsh
    if [[ -n $P9K_CONTENT ]]; then
      typeset -g my_git_format=$P9K_CONTENT
      return
    fi
    if (( $1 )); then
      local       meta='%246F'
      local      clean='%76F'
      local   modified='%178F'
      local  untracked='%39F'
      local conflicted='%196F'
    else
      local       meta='%244F'
      local      clean='%244F'
      local   modified='%244F'
      local  untracked='%244F'
      local conflicted='%244F'
    fi
    local res
    if [[ -n $VCS_STATUS_LOCAL_BRANCH ]]; then
      local branch=${(V)VCS_STATUS_LOCAL_BRANCH}
      (( $#branch > 32 )) && branch[13,-13]=".."
      res+="${clean}${(g::)POWERLEVEL9K_VCS_BRANCH_ICON}${branch//\%/%%}"
    fi
    if [[ -n $VCS_STATUS_TAG && -z $VCS_STATUS_LOCAL_BRANCH ]]; then
      local tag=${(V)VCS_STATUS_TAG}
      (( $#tag > 32 )) && tag[13,-13]=".."
      res+="${meta}#${clean}${tag//\%/%%}"
    fi
    [[ -z $VCS_STATUS_LOCAL_BRANCH && -z $VCS_STATUS_TAG ]] &&
      res+="${meta}@${clean}${VCS_STATUS_COMMIT[1,8]}"
    if [[ -n ${VCS_STATUS_REMOTE_BRANCH:#$VCS_STATUS_LOCAL_BRANCH} ]]; then
      res+="${meta}:${clean}${(V)VCS_STATUS_REMOTE_BRANCH//\%/%%}"
    fi
    if [[ $VCS_STATUS_COMMIT_SUMMARY == (|*[^[:alnum:]])(wip|WIP)(|[^[:alnum:]]*) ]]; then
      res+=" ${modified}wip"
    fi
    if (( VCS_STATUS_COMMITS_AHEAD || VCS_STATUS_COMMITS_BEHIND )); then
      (( VCS_STATUS_COMMITS_BEHIND )) && res+=" ${clean}<${VCS_STATUS_COMMITS_BEHIND}"
      (( VCS_STATUS_COMMITS_AHEAD && !VCS_STATUS_COMMITS_BEHIND )) && res+=" "
      (( VCS_STATUS_COMMITS_AHEAD  )) && res+="${clean}>${VCS_STATUS_COMMITS_AHEAD}"
    fi
    (( VCS_STATUS_PUSH_COMMITS_BEHIND )) && res+=" ${clean}<-${VCS_STATUS_PUSH_COMMITS_BEHIND}"
    (( VCS_STATUS_PUSH_COMMITS_AHEAD && !VCS_STATUS_PUSH_COMMITS_BEHIND )) && res+=" "
    (( VCS_STATUS_PUSH_COMMITS_AHEAD  )) && res+="${clean}->${VCS_STATUS_PUSH_COMMITS_AHEAD}"
    (( VCS_STATUS_STASHES        )) && res+=" ${clean}*${VCS_STATUS_STASHES}"
    [[ -n $VCS_STATUS_ACTION     ]] && res+=" ${conflicted}${VCS_STATUS_ACTION}"
    (( VCS_STATUS_NUM_CONFLICTED )) && res+=" ${conflicted}~${VCS_STATUS_NUM_CONFLICTED}"
    (( VCS_STATUS_NUM_STAGED     )) && res+=" ${modified}+${VCS_STATUS_NUM_STAGED}"
    (( VCS_STATUS_NUM_UNSTAGED   )) && res+=" ${modified}!${VCS_STATUS_NUM_UNSTAGED}"
    (( VCS_STATUS_NUM_UNTRACKED  )) && res+=" ${untracked}${(g::)POWERLEVEL9K_VCS_UNTRACKED_ICON}${VCS_STATUS_NUM_UNTRACKED}"
    (( VCS_STATUS_HAS_UNSTAGED == -1 )) && res+=" ${modified}-"
    typeset -g my_git_format=$res
  }
  functions -M my_git_formatter 2>/dev/null

  # Status
  typeset -g POWERLEVEL9K_STATUS_EXTENDED_STATES=true
  typeset -g POWERLEVEL9K_STATUS_OK=true
  typeset -g POWERLEVEL9K_STATUS_OK_FOREGROUND=70
  typeset -g POWERLEVEL9K_STATUS_OK_VISUAL_IDENTIFIER_EXPANSION='ok'
  typeset -g POWERLEVEL9K_STATUS_OK_PIPE=true
  typeset -g POWERLEVEL9K_STATUS_OK_PIPE_FOREGROUND=70
  typeset -g POWERLEVEL9K_STATUS_OK_PIPE_VISUAL_IDENTIFIER_EXPANSION='ok'
  typeset -g POWERLEVEL9K_STATUS_ERROR=true
  typeset -g POWERLEVEL9K_STATUS_ERROR_FOREGROUND=160
  typeset -g POWERLEVEL9K_STATUS_ERROR_VISUAL_IDENTIFIER_EXPANSION='err'
  typeset -g POWERLEVEL9K_STATUS_ERROR_SIGNAL=true
  typeset -g POWERLEVEL9K_STATUS_ERROR_SIGNAL_FOREGROUND=160
  typeset -g POWERLEVEL9K_STATUS_VERBOSE_SIGNAME=false
  typeset -g POWERLEVEL9K_STATUS_ERROR_SIGNAL_VISUAL_IDENTIFIER_EXPANSION=
  typeset -g POWERLEVEL9K_STATUS_ERROR_PIPE=true
  typeset -g POWERLEVEL9K_STATUS_ERROR_PIPE_FOREGROUND=160
  typeset -g POWERLEVEL9K_STATUS_ERROR_PIPE_VISUAL_IDENTIFIER_EXPANSION='err'

  # Command execution time
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_THRESHOLD=3
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_PRECISION=0
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_FOREGROUND=248
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_FORMAT='d h m s'
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_VISUAL_IDENTIFIER_EXPANSION=

  # Background jobs
  typeset -g POWERLEVEL9K_BACKGROUND_JOBS_VERBOSE=false
  typeset -g POWERLEVEL9K_BACKGROUND_JOBS_FOREGROUND=37

  # Context (user@hostname)
  typeset -g POWERLEVEL9K_CONTEXT_ROOT_FOREGROUND=178
  typeset -g POWERLEVEL9K_CONTEXT_{REMOTE,REMOTE_SUDO}_FOREGROUND=180
  typeset -g POWERLEVEL9K_CONTEXT_FOREGROUND=180
  typeset -g POWERLEVEL9K_CONTEXT_ROOT_TEMPLATE='%B%n@%m'
  typeset -g POWERLEVEL9K_CONTEXT_{REMOTE,REMOTE_SUDO}_TEMPLATE='%n@%m'
  typeset -g POWERLEVEL9K_CONTEXT_TEMPLATE='%n@%m'
  typeset -g POWERLEVEL9K_CONTEXT_{DEFAULT,SUDO}_{CONTENT,VISUAL_IDENTIFIER}_EXPANSION=

  # Time
  typeset -g POWERLEVEL9K_TIME_FOREGROUND=66
  typeset -g POWERLEVEL9K_TIME_FORMAT='%D{%H:%M:%S}'
  typeset -g POWERLEVEL9K_TIME_UPDATE_ON_COMMAND=false
  typeset -g POWERLEVEL9K_TIME_VISUAL_IDENTIFIER_EXPANSION=

  # Transient prompt
  typeset -g POWERLEVEL9K_TRANSIENT_PROMPT=always

  # Instant prompt
  typeset -g POWERLEVEL9K_INSTANT_PROMPT=verbose

  # Hot reload
  typeset -g POWERLEVEL9K_DISABLE_HOT_RELOAD=true

  (( ! $+functions[p10k] )) || p10k reload
}

# Tell `p10k configure` which file it should overwrite.
typeset -g POWERLEVEL9K_CONFIG_FILE=${${(%):-%x}:a}

(( ${#p10k_config_opts} )) && setopt ${p10k_config_opts[@]}
'builtin' 'unset' 'p10k_config_opts'
EOF
    check_success ".p10k.zsh configured"
}

# Set Zsh as default shell
set_default_shell() {
    local zsh_path=$(which zsh)
    if [[ "$SHELL" != "$zsh_path" ]]; then
        info_msg "Changing default shell to $zsh_path..."
        chsh -s "$zsh_path"
        check_success "Default shell changed (requires logout/login to take effect)"
        SHELL_CHANGED=1
        PREVIOUS_SHELL="$SHELL"
    else
        info_msg "Zsh is already the default shell."
        SHELL_CHANGED=0
        PREVIOUS_SHELL=""
    fi
}

#-------------------------------------------
# Uninstall / revert functions
#-------------------------------------------

# Remove Oh My Zsh if it was installed by this script
uninstall_ohmyzsh() {
    if [ "$OMZ_INSTALLED" -eq 1 ]; then
        if [ -d "$USER_HOME/.oh-my-zsh" ]; then
            warning_msg "Removing Oh My Zsh directory..."
            rm -rf "$USER_HOME/.oh-my-zsh"
            success_msg "Oh My Zsh removed."
        else
            info_msg "Oh My Zsh directory not found (maybe already removed)."
        fi
    else
        info_msg "Oh My Zsh was pre-existing; not removed."
    fi
}

# Remove a plugin directory if it was installed by this script
uninstall_plugin() {
    local name="$1"
    local flag_var="$2"
    local dir="$3"
    if [ "${!flag_var}" -eq 1 ]; then
        if [ -d "$dir" ]; then
            warning_msg "Removing $name..."
            rm -rf "$dir"
            success_msg "$name removed."
        else
            info_msg "$name directory not found."
        fi
    else
        info_msg "$name was pre-existing; not removed."
    fi
}

# Remove Powerlevel10k theme if installed by this script
uninstall_powerlevel10k() {
    uninstall_plugin "Powerlevel10k" "P10K_INSTALLED" "$ZSH_CUSTOM/themes/powerlevel10k"
}

# Restore .zshrc from backup
restore_zshrc() {
    if [ -n "$ZSHRC_BACKUP" ] && [ -f "$ZSHRC_BACKUP" ]; then
        warning_msg "Restoring .zshrc from backup $ZSHRC_BACKUP..."
        cp "$ZSHRC_BACKUP" "$USER_HOME/.zshrc"
        success_msg ".zshrc restored."
        # Optionally keep backup, but we'll leave it
    elif [ -z "$ZSHRC_BACKUP" ]; then
        # No backup means .zshrc didn't exist before, so we should remove the one we created
        if [ -f "$USER_HOME/.zshrc" ]; then
            warning_msg "No backup found; .zshrc was created by this script. Removing it..."
            rm -f "$USER_HOME/.zshrc"
            success_msg ".zshrc removed."
        fi
    else
        warning_msg "Backup file $ZSHRC_BACKUP not found. Cannot restore .zshrc automatically."
    fi
}

# Restore .p10k.zsh from backup
restore_p10k() {
    if [ -n "$P10K_BACKUP" ] && [ -f "$P10K_BACKUP" ]; then
        warning_msg "Restoring .p10k.zsh from backup $P10K_BACKUP..."
        cp "$P10K_BACKUP" "$USER_HOME/.p10k.zsh"
        success_msg ".p10k.zsh restored."
    elif [ -z "$P10K_BACKUP" ]; then
        if [ -f "$USER_HOME/.p10k.zsh" ]; then
            warning_msg "No backup found; .p10k.zsh was created by this script. Removing it..."
            rm -f "$USER_HOME/.p10k.zsh"
            success_msg ".p10k.zsh removed."
        fi
    else
        warning_msg "Backup file $P10K_BACKUP not found. Cannot restore .p10k.zsh automatically."
    fi
}

# Restore default shell (if changed)
restore_shell() {
    if [ "$SHELL_CHANGED" -eq 1 ]; then
        if [ -n "$PREVIOUS_SHELL" ] && [ -x "$PREVIOUS_SHELL" ]; then
            warning_msg "Reverting default shell to $PREVIOUS_SHELL..."
            chsh -s "$PREVIOUS_SHELL"
            check_success "Default shell reverted."
        else
            warning_msg "Previous shell not available. Please change manually with chsh."
        fi
    else
        info_msg "Default shell was not changed by this script."
    fi
}

# Remove packages installed by this script (with individual choice)
remove_packages_menu() {
    if [ ${#INSTALLED_PACKAGES[@]} -eq 0 ]; then
        info_msg "No packages were newly installed by this script."
        return
    fi

    echo -e "\n${YELLOW}Select packages to remove (these were installed by the script):${NC}"
    local i=1
    local selections=()
    for pkg in "${INSTALLED_PACKAGES[@]}"; do
        echo "  $i) $pkg"
        selections+=("$pkg")
        i=$((i+1))
    done
    echo "  $i) All of the above"
    echo "  $((i+1))) None (skip)"
    echo -n "Enter your choice [1-$((i+1))]: "
    read choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le $((i+1)) ]; then
        if [ "$choice" -eq $i ]; then
            # Remove all
            for pkg in "${selections[@]}"; do
                sudo apt remove -y "$pkg"
                check_success "Package $pkg removed"
            done
        elif [ "$choice" -eq $((i+1)) ]; then
            info_msg "No packages removed."
        else
            # Remove selected single package
            local idx=$((choice-1))
            local pkg="${selections[$idx]}"
            sudo apt remove -y "$pkg"
            check_success "Package $pkg removed"
        fi
    else
        warning_msg "Invalid choice. No packages removed."
    fi
}

#-------------------------------------------
# Main installation routine
#-------------------------------------------
run_install() {
    echo -e "\n${GREEN}Starting installation...${NC}"

    # Initialize state variables (will be overwritten if state file exists)
    load_state

    # Perform installation steps
    install_packages
    install_ohmyzsh
    install_autosuggestions
    install_syntax_highlighting
    install_powerlevel10k
    configure_zshrc
    configure_p10k
    set_default_shell

    # Save state
    save_state

    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}  Installation Complete!               ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "Please log out and back in for changes to take effect."
    echo -e "Run ${YELLOW}p10k configure${NC} if the wizard doesn't start automatically."
}

#-------------------------------------------
# Main uninstall menu
#-------------------------------------------
run_uninstall_menu() {
    # Load current state
    load_state

    while true; do
        clear
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}  Uninstall / Revert Changes Menu      ${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo "Select components to revert/remove:"
        echo "  1) Oh My Zsh"
        echo "  2) zsh-autosuggestions plugin"
        echo "  3) zsh-syntax-highlighting plugin"
        echo "  4) Powerlevel10k theme"
        echo "  5) Restore .zshrc (from backup or remove if created)"
        echo "  6) Restore .p10k.zsh (from backup or remove if created)"
        echo "  7) Restore default shell"
        echo "  8) Remove installed packages (selective)"
        echo "  9) Revert ALL changes (combination of all above)"
        echo "  0) Return to main menu"
        echo -n "Enter your choice [0-9]: "
        read choice

        case $choice in
            1)
                uninstall_ohmyzsh
                ;;
            2)
                uninstall_plugin "zsh-autosuggestions" "AUTOSUGGESTIONS_INSTALLED" "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
                ;;
            3)
                uninstall_plugin "zsh-syntax-highlighting" "SYNTAX_HIGHLIGHTING_INSTALLED" "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
                ;;
            4)
                uninstall_powerlevel10k
                ;;
            5)
                restore_zshrc
                ;;
            6)
                restore_p10k
                ;;
            7)
                restore_shell
                ;;
            8)
                remove_packages_menu
                ;;
            9)
                echo -e "${YELLOW}This will revert all changes made by the script.${NC}"
                echo -n "Are you sure? (y/N): "
                read confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    uninstall_ohmyzsh
                    uninstall_plugin "zsh-autosuggestions" "AUTOSUGGESTIONS_INSTALLED" "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
                    uninstall_plugin "zsh-syntax-highlighting" "SYNTAX_HIGHLIGHTING_INSTALLED" "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
                    uninstall_powerlevel10k
                    restore_zshrc
                    restore_p10k
                    restore_shell
                    remove_packages_menu
                    info_msg "All changes reverted. You may need to log out and back in."
                    # Optionally remove state file after full uninstall
                    rm -f "$STATE_FILE"
                    info_msg "State file removed."
                else
                    info_msg "Full uninstall cancelled."
                fi
                ;;
            0)
                return
                ;;
            *)
                warning_msg "Invalid option. Please try again."
                ;;
        esac

        echo -e "\nPress Enter to continue..."
        read
    done
}

#-------------------------------------------
# Main menu
#-------------------------------------------
main_menu() {
    while true; do
        clear
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}  Terminal Setup Script for Debian/Ubuntu${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo "Please choose an option:"
        echo "  1) Install / Configure terminal environment"
        echo "  2) Uninstall / Revert changes"
        echo "  3) Exit"
        echo -n "Enter your choice [1-3]: "
        read choice

        case $choice in
            1)
                run_install
                ;;
            2)
                run_uninstall_menu
                ;;
            3)
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                warning_msg "Invalid option. Please enter 1, 2, or 3."
                sleep 1
                ;;
        esac
    done
}

#-------------------------------------------
# Script entry point
#-------------------------------------------

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    error_msg "Do not run this script as root! Run as a normal user with sudo privileges."
fi

# Start the main menu
main_menu