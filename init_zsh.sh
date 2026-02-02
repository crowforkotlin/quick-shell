#!/bin/bash

# ==============================================================================
# Script Name: Zsh + OMZ + QuickShell Automated Deployment
# Platform   : Windows (MSYS2/Git Bash), Linux, macOS, Android (Termux)
# ==============================================================================

# ==============================================================================
# [USER CONFIG] .zshrc Template
# ==============================================================================
get_zshrc_template() {
  cat <<EOF
# Path to your oh-my-zsh installation.
export ZSH="\$HOME/.oh-my-zsh"

# Theme settings
ZSH_THEME="powerlevel10k/powerlevel10k"

# Plugins
plugins=(git zsh-syntax-highlighting zsh-autosuggestions z extract fzf)

# 解决 Java/Gradle 等输出乱码问题
export JAVA_TOOL_OPTIONS="-Duser.language=en -Duser.country=US"

source \$ZSH/oh-my-zsh.sh

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

# --- Quick Functions ---
lt() {
    local depth=10  # 默认深度
    local target="." # 默认路径

    # 逻辑：遍历所有参数
    for arg in "$@"; do
        if [[ "$arg" =~ ^[0-9]+$ ]]; then
            # 如果是纯数字，赋值给深度
            depth=$arg
        elif [ -d "$arg" ] || [ -f "$arg" ]; then
            # 如果是存在的目录或文件，赋值给目标路径
            target="$arg"
        else
            # 兼容处理：如果路径不存在但也不是数字（如打错字），也传给 lsd 让其报错
            target="$arg"
        fi
    done

    # 检查 lsd 命令是否存在
    if ! command -v lsd &> /dev/null; then
        echo "Error: 'lsd' is not installed or not in PATH."
        return 1
    fi

    # 执行命令
    lsd --tree --depth "$depth" --blocks name "$target"
}
cdw() {
    local target=$(which "$1" 2>/dev/null)
    if [ -n "$target" ]; then
        # pushd 会把当前目录压入“栈”中，然后跳转
        pushd "$(dirname "$target")" > /dev/null
    else
        echo "找不到程序: $1"
    fi
}


# --- Environment ---
export MSYS=winsymlinks:nativestrict
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
export no_proxy="localhost,127.0.0.1,google.com,pub.dev"
export NO_PROXY="localhost,127.0.0.1,google.com,pub.dev"


# --- Aliases ---
alias ls=lsd
alias ll='lsd -l'
alias la='lsd -a'
alias cat=bat
alias catAll=bat --paging=never
alias gitpm='git -c core.quotepath=false fetch origin --recurse-submodules=no --progress --prune'


EOF
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
    rm -rf "$HOME/.zshrc" "$HOME/.oh-my-zsh"

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

# --- 5. Plugin Installation (OMZ & Plugins) ---

install_plugins() {
  print_step 4 $TOTAL_STEPS "Plugin Deployment"

  # Install Oh My Zsh Core
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    log_info "Installing Oh My Zsh Framework..."
    export RUNZSH=no
    export KEEP_ZSHRC=yes
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended >/dev/null
  fi

  ZSH_CUSTOM=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}

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

  echo "Processing Plugin List..."
  manage_plugin "Powerlevel10k" "https://github.com/romkatv/powerlevel10k.git" "${ZSH_CUSTOM}/themes/powerlevel10k"
  manage_plugin "Syntax Highlighting" "https://github.com/zsh-users/zsh-syntax-highlighting" "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"
  manage_plugin "Auto Suggestions" "https://github.com/zsh-users/zsh-autosuggestions" "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"

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
  printf "${MAGENTA}   ✨ Zsh + OMZ + QuickShell Setup Script ✨      ${NC}\n"
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

