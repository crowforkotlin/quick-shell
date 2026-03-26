#!/bin/bash

# ==============================================================================
# Script Name: Zsh + Zinit + QuickShell Automated Deployment
# Platform   : Windows (MSYS2/Git Bash), Linux, macOS, Android (Termux)
# ==============================================================================

# ==============================================================================
# [USER CONFIG] .zshrc Template
# ==============================================================================
get_zshrc_template() {
  # ⚠️  heredoc 分三段：
  #     1. 'ZSHRC_EOF'  单引号 → 原样输出，$var 不展开（函数体、别名等）
  #     2. ZSHRC_TARGET 双引号 → 展开 TARGET_DIR（安装脚本注入）
  #     3. 'ZSHRC_EOF2' 单引号 → 原样输出剩余内容

  cat <<'ZSHRC_EOF'
# ==============================================================================
# Zinit Core Initialization
# ==============================================================================
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

# Auto-install zinit if missing
if [ ! -d "$ZINIT_HOME" ]; then
    mkdir -p "$(dirname $ZINIT_HOME)"
    git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

source "${ZINIT_HOME}/zinit.zsh"

# ==============================================================================
# Theme: Powerlevel10k
# ==============================================================================
zinit ice depth=1
zinit light romkatv/powerlevel10k

# ==============================================================================
# Plugins
# ==============================================================================
# Syntax Highlighting (must be loaded last or near last)
# Only apply this block in Windows environments (Git Bash / MSYS2)
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    
    # Disable syntax highlighting in VS Code integrated terminal 
    # to prevent input lag and UI stuttering on Windows.
    if [[ "$TERM_PROGRAM" != "vscode" ]]; then
        zinit light zsh-users/zsh-syntax-highlighting
    fi

fi

# Auto Suggestions
zinit light zsh-users/zsh-autosuggestions

# z - jump to frecent directories
zinit light agkozak/zsh-z

# fzf tab completion
zinit light Aloxaf/fzf-tab

# OMZ snippets (git aliases, extract, etc.)
zinit snippet OMZP::git
zinit snippet OMZP::extract

# fzf key bindings (Ctrl+R / Ctrl+T / Alt+C)
# wait'0' 异步加载，避免阻塞 instant prompt
zinit ice lucid wait'0' multisrc'shell/key-bindings.zsh shell/completion.zsh'
zinit light junegunn/fzf

# ==============================================================================
# Completion System
# ==============================================================================
autoload -Uz compinit
compinit

# Replay all cached completions (zinit optimization)
zinit cdreplay -q

# 解决 Java/Gradle 等输出乱码问题
export JAVA_TOOL_OPTIONS="-Duser.language=en -Duser.country=US"

ZSHRC_EOF

  # TARGET_DIR 需要从安装脚本展开，单独输出这一段
  cat <<ZSHRC_TARGET
# --- Quick Shell Auto-Loader ---
QS_DIR="${TARGET_DIR}"
if [ -d "\$QS_DIR" ]; then
    for script in "\$QS_DIR"/*(N); do
        if [ -f "\$script" ]; then
            filename=\$(basename "\$script")
            alias_name="\${filename%.*}"
            alias "\$alias_name"="bash '\$script'"
        fi
    done
fi

ZSHRC_TARGET

  # 剩余内容：函数体和别名，全部原样输出
  cat <<'ZSHRC_EOF2'
# --- Quick Functions ---
lt(){ d=10; t="."; for a in "$@"; do [[ "$a" =~ ^[0-9]+$ ]] && d="$a" || { [[ -e "$a" ]] && t="$a"; }; done; lsd --tree --depth "$d" --blocks name "$t"; }
cdw(){ t=$(which "$1" 2>/dev/null); [[ -n "$t" ]] && { pushd "$(dirname "$t")" > /dev/null; } || echo "找不到程序: $1"; }

gitdc(){ o=$(git -p diff HEAD;echo "---";git status); echo "$o" | { pbcopy || clip.exe || xclip -sel c || xsel -b; } && echo "✅ Copied ($(echo "$o" | wc -l) lines)"; }
gitdf(){ o=$(git -p diff HEAD;echo "---";git status); echo "$o" > "${1:-commit_message.txt}" && echo "✅ Saved to ${1:-commit_message.txt} ($(echo "$o" | wc -l) lines)"; }
stowlink() { [ -z "$2" ] && echo "Usage: stowlink <dir> <pkg>" || (mkdir -p "$1" && stow -t "$1" "$2"); }
stowlink-auto() { [ -z "$2" ] && echo "Usage: stowlink-auto <parent_path> <pkg>" || (T="${1%/}/$2" && mkdir -p "$T" && stow -t "$T" "$2"); }
stowlink-dir() { [ -z "$2" ] && echo "Usage: stowlink-dir <parent> <pkg>" || { [ -d "$PWD/$2" ] && mkdir -p "$1" && ln -sfn "$PWD/$2" "${1%/}/$2" && echo "Linked: ${1%/}/$2 -> $PWD/$2"; } }
mf() { local dir="${1:-.}"; [[ "$dir" != /* ]] && dir="$PWD/$dir"; local out=""; local files=(); while IFS= read -r -d '' f; do files+=("$f"); done < <(find "$dir" -type f -print0 | sort -z); for f in "${files[@]}"; do out+="--- $(basename "$f") ---"$'\n'"$(cat "$f")"$'\n\n'; done; if [ ${#out} -gt 1000 ]; then echo "$out" > contents.txt; echo "Saved to contents.txt"; else echo "$out" | tee /dev/clipboard 2>/dev/null || echo "$out" | { command -v pbcopy &>/dev/null && pbcopy || command -v xclip &>/dev/null && xclip -selection clipboard || command -v xsel &>/dev/null && xsel --clipboard --input || clip; }; echo "Copied to clipboard"; fi; }

# --- History ---
HISTFILE="$HOME/.zsh_history"
HISTSIZE=15000
SAVEHIST=20000
setopt HIST_IGNORE_DUPS      # Skip duplicate commands
setopt HIST_IGNORE_SPACE     # Skip commands prefixed with space
setopt INC_APPEND_HISTORY    # Write to history immediately, not on exit
setopt SHARE_HISTORY         # Share history across all open sessions

# --- Environment ---
export MSYS=winsymlinks:nativestrict
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
export no_proxy="localhost,127.0.0.1"
export NO_PROXY="localhost,127.0.0.1"


# --- Aliases ---
alias ls=lsd
alias ll='lsd -l'
alias la='lsd -a'
alias batall='bat --paging=never'
alias gitpm='git -c core.quotepath=false fetch origin --recurse-submodules=no --progress --prune'

# Fix Ctrl+Arrow in Git Bash / Windows Terminal
# Fix arrow keys
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
  bindkey "^[[A" up-line-or-history    # Up
  bindkey "^[[B" down-line-or-history  # Down
  bindkey "^[[C" forward-char          # Right
  bindkey "^[[D" backward-char         # Left

  # Fix Ctrl+Arrow
  bindkey "^[[1;5C" forward-word       # Ctrl+Right
  bindkey "^[[1;5D" backward-word      # Ctrl+Left
  bindkey "^[[1;5A" up-line-or-history # Ctrl+Up
  bindkey "^[[1;5B" down-line-or-history # Ctrl+Down
fi
ZSHRC_EOF2
}

# ==============================================================================
# --- 1. Global Config & Utility Functions ---
# ==============================================================================

# Color Definitions (Fixed for Git Bash/Windows)
if command -v tput >/dev/null 2>&1; then
  RED=$(
    tput setaf 1
    tput bold
  )
  GREEN=$(
    tput setaf 2
    tput bold
  )
  YELLOW=$(
    tput setaf 3
    tput bold
  )
  BLUE=$(
    tput setaf 4
    tput bold
  )
  MAGENTA=$(
    tput setaf 5
    tput bold
  )
  CYAN=$(
    tput setaf 6
    tput bold
  )
  WHITE=$(
    tput setaf 7
    tput bold
  )
  NC=$(tput sgr0)
else
  RED=$(printf '\033[1;31m')
  GREEN=$(printf '\033[1;32m')
  YELLOW=$(printf '\033[1;33m')
  BLUE=$(printf '\033[1;34m')
  MAGENTA=$(printf '\033[1;35m')
  CYAN=$(printf '\033[1;36m')
  WHITE=$(printf '\033[1;37m')
  NC=$(printf '\033[0m')
fi

# Logging Tools (With Icons)
log_info() { printf "${BLUE} 🔵 [INFO]${NC} %s\n" "$1"; }
log_success() { printf "${GREEN} 🟢 [PASS]${NC} %s\n" "$1"; }
log_warn() { printf "${YELLOW} 🟡 [WARN]${NC} %s\n" "$1"; }
log_error() { printf "${RED} 🔴 [FAIL]${NC} %s\n" "$1"; }

# Step Divider
print_step() {
  echo ""
  printf "${CYAN}┌──────────────────────────────────────────────────────────────┐${NC}\n"
  printf "${CYAN}│ 🚀 STEP %d/%d : %-43s │${NC}\n" "$1" "$2" "$3"
  printf "${CYAN}└──────────────────────────────────────────────────────────────┘${NC}\n"
}

# Variable Initialization
OS_TYPE=""
INSTALL_CMD=""
UPDATE_CMD=""
SUDO=""
TARGET_DIR="$HOME/quick_shell"
TOTAL_STEPS=5

# Default Packages
PACKAGES_COMMON="zsh curl git"
# Extended Packages (lsd, bat, fzf)
PACKAGES_EXT="lsd bat fzf"

# --- 2. Environment Detection ---

detect_env() {
  print_step 1 $TOTAL_STEPS "Environment & Package Manager Check"

  # Get Kernel Info (Lower case)
  OS_UNAME=$(uname -a | tr '[:upper:]' '[:lower:]')

  case "$OS_UNAME" in
  *android*)
    OS_TYPE="Android"
    INSTALL_CMD="pkg install -y"
    UPDATE_CMD="pkg update -y"
    if [ -d "/sdcard" ]; then
      TARGET_DIR="/sdcard/0.file/shell"
    fi
    ;;

  *msys* | *mingw* | *cygwin*)
    OS_TYPE="Windows"
    TARGET_DIR="$HOME/quick_shell"

    # Check pacman
    if command -v pacman >/dev/null 2>&1; then
      log_success "Detected MSYS2/Git Bash (Pacman available)."
      INSTALL_CMD="pacman -S --noconfirm"
      UPDATE_CMD="pacman -Sy"
      # Windows specific packages
      PACKAGES_EXT="mingw-w64-x86_64-lsd mingw-w64-x86_64-bat mingw-w64-x86_64-fzf"
    else
      log_error "Pacman package manager not found!"
      log_warn "This script relies on MSYS2 environment. Please ensure you are using full MSYS2 or Git Bash with Pacman."
      log_info "Download: https://github.com/msys2/msys2-installer/releases"
      exit 1
    fi
    ;;

  *darwin*)
    OS_TYPE="MacOS"
    INSTALL_CMD="brew install"
    UPDATE_CMD="brew update"
    ;;

  *)
    OS_TYPE="Linux"
    # Auto-detect Linux Distro
    if command -v apt >/dev/null 2>&1; then
      INSTALL_CMD="apt install -y"
      UPDATE_CMD="apt update -y"
      SUDO="sudo"
    elif command -v pacman >/dev/null 2>&1; then
      INSTALL_CMD="pacman -S --noconfirm"
      UPDATE_CMD="pacman -Sy"
      SUDO="sudo"
    elif command -v dnf >/dev/null 2>&1; then
      INSTALL_CMD="dnf install -y"
      UPDATE_CMD="dnf update -y"
      SUDO="sudo"
    elif command -v yum >/dev/null 2>&1; then
      INSTALL_CMD="yum install -y"
      UPDATE_CMD="yum update -y"
      SUDO="sudo"
    else
      # Fallback manual selection
      log_warn "Package manager auto-detection failed. Please select manually:"
      echo " 1. apt (Debian/Ubuntu/Kali)"
      echo " 2. pacman (Arch/Manjaro)"
      echo " 3. dnf/yum (Fedora/CentOS)"
      read -p "Select [1-3]: " pm_choice
      case $pm_choice in
      1)
        INSTALL_CMD="apt install -y"
        UPDATE_CMD="apt update -y"
        SUDO="sudo"
        ;;
      2)
        INSTALL_CMD="pacman -S --noconfirm"
        UPDATE_CMD="pacman -Sy"
        SUDO="sudo"
        ;;
      3)
        INSTALL_CMD="dnf install -y"
        UPDATE_CMD="dnf update -y"
        SUDO="sudo"
        ;;
      *)
        INSTALL_CMD="apt install -y"
        UPDATE_CMD="apt update -y"
        SUDO="sudo"
        ;;
      esac
    fi
    ;;
  esac

  log_info "Platform Detected : ${MAGENTA}${OS_TYPE}${NC}"
  log_info "Target Directory  : ${WHITE}${TARGET_DIR}${NC}"
}

# --- 3. Software Installation ---

install_pkgs() {
  print_step 2 $TOTAL_STEPS "Core Software Installation"

  log_info "Updating package repositories..."
  # Suppress output, show error if failed
  if ! eval "$SUDO $UPDATE_CMD" >/dev/null 2>&1; then
    log_warn "Repository update returned warnings. Attempting to proceed..."
  fi

  log_info "Installing packages: ${WHITE}$PACKAGES_COMMON $PACKAGES_EXT${NC}"
  # Windows pacman might take time
  eval "$SUDO $INSTALL_CMD $PACKAGES_COMMON $PACKAGES_EXT"

  # Refresh hash
  hash -r 2>/dev/null

  # Verify Zsh
  if ! command -v zsh >/dev/null 2>&1; then
    log_error "Zsh installation failed! Please check network or source config."
    exit 1
  fi

  # Linux: batcat -> bat mapping
  if [ "$OS_TYPE" = "Linux" ]; then
    if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
      log_info "Creating symlink: batcat -> bat"
      mkdir -p "$HOME/.local/bin"
      ln -s "$(command -v batcat)" "$HOME/.local/bin/bat"
      export PATH="$HOME/.local/bin:$PATH"
    fi
  fi

  log_success "Core dependencies installed successfully."
}

# --- 4. Configuration Generation (.zshrc) ---

config_zshrc() {
  print_step 3 $TOTAL_STEPS "Configuration Setup"

  printf "${WHITE}Please select an installation mode:${NC}\n"
  printf "  ${CYAN}[1]${NC} Clean Install   ${DIM}(Removes old config, Recommended)${NC}\n"
  printf "  ${CYAN}[2]${NC} Update Only     ${DIM}(Keeps config, Updates plugins)${NC}\n"
  printf "  ${CYAN}[3]${NC} Force Reinstall Plugins ${DIM}(Keeps config, Re-clones plugins)${NC}\n"
  read -p "Enter Selection [1-3]: " choice

  CLEAN_INSTALL=false
  FORCE_RECLONE=false

  case "$choice" in
  1) CLEAN_INSTALL=true ;;
  2) FORCE_RECLONE=false ;;
  3) FORCE_RECLONE=true ;;
  *) log_warn "Invalid input. Defaulting to Update Only." ;;
  esac

  if [ "$CLEAN_INSTALL" = true ]; then
    log_info "Cleaning up old configurations..."
    # Remove old .zshrc and zinit data directory
    rm -rf "$HOME/.zshrc" "${XDG_DATA_HOME:-$HOME/.local/share}/zinit"

    log_info "Creating Quick Shell directory..."
    mkdir -p "$TARGET_DIR"

    log_info "Generating new ~/.zshrc ..."

    # 🟢 HERE: Call the top function to write the file
    get_zshrc_template >"$HOME/.zshrc"

    log_success ".zshrc generated successfully."
  else
    log_info "Skipping .zshrc generation. Existing config preserved."
  fi
}

# --- 5. Plugin Installation (Zinit & Plugins) ---

install_plugins() {
  print_step 4 $TOTAL_STEPS "Plugin Deployment"

  ZINIT_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"

  # Install Zinit Core
  if [ ! -d "$ZINIT_HOME" ]; then
    log_info "Installing Zinit Plugin Manager..."
    mkdir -p "$(dirname "$ZINIT_HOME")"
    git clone --depth=1 https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME" -q
  fi

  # Plugin Manager
  manage_plugin() {
    local name=$1
    local url=$2
    local path=$3

    if [ -d "$path" ]; then
      if [ "$FORCE_RECLONE" = true ] || [ "$CLEAN_INSTALL" = true ]; then
        printf "  📦 %-25s : ${YELLOW}Reinstalling...${NC}\n" "$name"
        rm -rf "$path"
        git clone --depth=1 "$url" "$path" -q
      else
        printf "  📦 %-25s : ${BLUE}Updating...${NC}\n" "$name"
        git -C "$path" pull -q >/dev/null 2>&1 || echo "    ❌ Update Failed (Check Network)"
      fi
    else
      printf "  📦 %-25s : ${GREEN}Installing...${NC}\n" "$name"
      git clone --depth=1 "$url" "$path" -q
    fi
  }

  # Zinit stores plugins under its own data directory
  ZINIT_PLUGINS="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/plugins"

  echo "Processing Plugin List..."
  manage_plugin "Powerlevel10k" "https://github.com/romkatv/powerlevel10k.git" "${ZINIT_PLUGINS}/romkatv---powerlevel10k"
  manage_plugin "Syntax Highlighting" "https://github.com/zsh-users/zsh-syntax-highlighting" "${ZINIT_PLUGINS}/zsh-users---zsh-syntax-highlighting"
  manage_plugin "Auto Suggestions" "https://github.com/zsh-users/zsh-autosuggestions" "${ZINIT_PLUGINS}/zsh-users---zsh-autosuggestions"
  manage_plugin "zsh-z" "https://github.com/agkozak/zsh-z" "${ZINIT_PLUGINS}/agkozak---zsh-z"
  manage_plugin "fzf-tab" "https://github.com/Aloxaf/fzf-tab" "${ZINIT_PLUGINS}/Aloxaf---fzf-tab"
  manage_plugin "fzf" "https://github.com/junegunn/fzf" "${ZINIT_PLUGINS}/junegunn---fzf"

  log_success "All plugins deployed successfully."
}

# --- 6. Set Default Shell ---

set_default_shell() {
  print_step 5 $TOTAL_STEPS "Default Shell Configuration"

  # Zsh Launch Code (For Windows .bashrc)
  local ZSH_LAUNCH_CODE='
# [QuickShell] Auto-launch Zsh
if [ -t 1 ]; then
    exec zsh
fi
'

  if [ "$OS_TYPE" = "Windows" ]; then
    # Windows Logic
    local BASHRC="$HOME/.bashrc"

    log_warn "Windows Environment Detected: 'chsh' is unavailable."
    log_info "Modifying .bashrc to auto-launch Zsh when Git Bash starts."
    echo ""
    printf "Target File: ${WHITE}%s${NC}\n" "$BASHRC"
    printf "Please select configuration method:\n"
    printf "  ${CYAN}[1]${NC} %-20s : %s\n" "Append (Recommended)" "Safe, preserves existing config."
    printf "  ${CYAN}[2]${NC} %-20s : %s\n" "Overwrite" "Clears old config (Backups made)."
    printf "  ${CYAN}[3]${NC} %-20s : %s\n" "Skip" "Manual configuration later."

    read -p "Enter Selection [1-3]: " win_choice

    case $win_choice in
    1)
      log_info "Appending configuration..."
      if grep -q "exec zsh" "$BASHRC" 2>/dev/null; then
        log_info "Configuration already exists. Skipping."
      else
        echo "$ZSH_LAUNCH_CODE" >>"$BASHRC"
        log_success "Appended successfully! Zsh will start automatically next time."
      fi
      ;;
    2)
      log_warn "Overwriting configuration..."
      cp "$BASHRC" "${BASHRC}.bak" 2>/dev/null && log_info "Backup created at .bashrc.bak"
      echo "$ZSH_LAUNCH_CODE" >"$BASHRC"
      log_success "Overwrite successful!"
      ;;
    3)
      log_info "Auto-configuration skipped."
      echo ""
      printf "${YELLOW}Tip: For Windows issues, visit:\nhttps://gist.github.com/glenkusuma/7d7df65a89e485ec2f4690fdc88fffd6${NC}\n"
      ;;
    *) log_warn "Invalid input. Skipping." ;;
    esac

  else
    # Linux / Mac / Android Logic
    if [ "$OS_TYPE" = "Android" ]; then
      log_info "Termux environment detected. Switching shell..."
      chsh -s zsh
    else
      log_info "Attempting to switch shell using 'chsh'..."
      ZSH_PATH=$(command -v zsh 2>/dev/null)
      if [ -n "$ZSH_PATH" ]; then
        chsh -s "$ZSH_PATH" || log_warn "Auto-switch failed. Please run manually: chsh -s $ZSH_PATH"
      else
        log_error "Zsh path not found. Skipping default shell setup."
      fi
    fi
  fi
}

# --- Main Entry Point ---

main() {
  # Clear screen
  printf "${MAGENTA}====================================================${NC}\n"
  printf "${MAGENTA}   ✨ Zsh + Zinit + QuickShell Setup Script ✨     ${NC}\n"
  printf "${MAGENTA}====================================================${NC}\n"

  detect_env
  install_pkgs
  config_zshrc
  install_plugins
  set_default_shell

  echo ""
  log_success "🎉 All tasks completed successfully!"

  if [ "$OS_TYPE" = "Windows" ]; then
    log_info "Please restart your Git Bash terminal to apply changes."
  else
    log_info "Entering Zsh now..."
    exec zsh -l
  fi
}

main
