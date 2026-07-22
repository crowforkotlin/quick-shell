#!/bin/bash

# ==============================================================================
# Script Name: Zsh + Zinit + QuickShell Automated Deployment
# Platform   : Windows (MSYS2/Git Bash), Linux, macOS, Android (Termux)
# ==============================================================================

# Resolve the directory where this script resides
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
  DIM=$(tput dim 2>/dev/null || printf '')
  NC=$(tput sgr0)
else
  RED=$(printf '\033[1;31m')
  GREEN=$(printf '\033[1;32m')
  YELLOW=$(printf '\033[1;33m')
  BLUE=$(printf '\033[1;34m')
  MAGENTA=$(printf '\033[1;35m')
  CYAN=$(printf '\033[1;36m')
  WHITE=$(printf '\033[1;37m')
  DIM=$(printf '\033[2m')
  NC=$(printf '\033[0m')
fi

# Logging Tools (With Icons)
log_info() { printf "${BLUE} 🔵 [INFO]${NC} %s\n" "$1"; }
log_success() { printf "${GREEN} 🟢 [PASS]${NC} %s\n" "$1"; }
log_warn() { printf "${YELLOW} 🟡 [WARN]${NC} %s\n" "$1"; }
log_error() { printf "${RED} 🔴 [FAIL]${NC} %s\n" "$1"; }

# Cross-platform sed in-place (macOS requires '' after -i)
sed_inplace() {
  if [ "$(uname)" = "Darwin" ]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# Cross-platform git clone with curl tarball fallback
git_clone_fallback() {
  local url="$1"   # https://github.com/owner/repo.git
  local dest="$2"

  # Clean up any partial directory from a previous failed attempt
  rm -rf "$dest" 2>/dev/null

  # Try git clone first
  if git clone --depth=1 "$url" "$dest" -q 2>/dev/null; then
    return 0
  fi

  log_warn "git clone failed, trying curl tarball fallback..."
  # Convert git URL to base: https://github.com/owner/repo.git -> https://github.com/owner/repo
  local base_url="${url%.git}"
  local tmp_tar="/tmp/qs_clone_$$.tar.gz"
  local branch

  # Try common default branch names
  for branch in main master; do
    if curl -fsSL "${base_url}/archive/refs/heads/${branch}.tar.gz" -o "$tmp_tar" 2>/dev/null; then
      mkdir -p "$dest"
      if tar -xzf "$tmp_tar" -C "$dest" --strip-components=1 2>/dev/null; then
        rm -f "$tmp_tar"
        return 0
      fi
      rm -rf "$dest"
    fi
  done

  rm -f "$tmp_tar"
  return 1
}

# Step Divider
print_step() {
  echo ""
  printf "${CYAN}┌──────────────────────────────────────────────────────────────┐${NC}\n"
  printf "${CYAN}│ 🚀 STEP %d/%d : %-43s │${NC}\n" "$1" "$2" "$3"
  printf "${CYAN}└──────────────────────────────────────────────────────────────┘${NC}\n"
}

disable_root_local_proxy() {
  local proxy_var proxy_value

  if [ "$(id -u)" -ne 0 ] || [ "${QUICK_SHELL_KEEP_PROXY:-0}" = "1" ]; then
    return 0
  fi

  for proxy_var in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY; do
    proxy_value="${!proxy_var}"
    case "$proxy_value" in
    http://127.0.0.1:* | https://127.0.0.1:* | socks5://127.0.0.1:* | http://localhost:* | https://localhost:* | socks5://localhost:*)
      log_warn "Detected inherited localhost proxy in $proxy_var. Disabling proxy for this root session."
      unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
      return 0
      ;;
    esac
  done
}

# Variable Initialization
OS_TYPE=""
INSTALL_CMD=""
UPDATE_CMD=""
SUDO=""
TARGET_DIR="$HOME/quick_shell"
TOTAL_STEPS=5
STARSHIP_CONFIG_URL="https://raw.githubusercontent.com/crowforkotlin/crowforkotlin.config.starship/mac/starship.toml"

# Default Packages
PACKAGES_COMMON="zsh curl git"
# Extended Packages (lsd, bat, fzf)
PACKAGES_EXT="lsd bat fzf"
STARSHIP_PACKAGE="starship"

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
      # Git Bash pacman repos are limited; ext packages handled individually below
      PACKAGES_EXT=""
      STARSHIP_PACKAGE="mingw-w64-x86_64-starship"
    fi
    # Always add Windows package manager paths to PATH (scoop/choco may install starship etc.)
    export PATH="$PATH:/c/Users/$USER/scoop/shims:/c/ProgramData/chocolatey/bin:/c/ProgramData/chocolatey/lib/starship/tools:/c/Program Files/starship"
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

  if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
  fi

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

  log_info "Installing packages: ${WHITE}$PACKAGES_COMMON${NC}"
  eval "$SUDO $INSTALL_CMD $PACKAGES_COMMON"

  # Try optional/extended packages individually (repos may not carry them, especially on Git Bash)
  local ext_pkgs="$PACKAGES_EXT"
  if [ "$OS_TYPE" = "Windows" ]; then
    ext_pkgs="$ext_pkgs mingw-w64-x86_64-lsd mingw-w64-x86_64-bat mingw-w64-x86_64-fzf"
  fi
  for opt_pkg in $ext_pkgs; do
    if ! eval "$SUDO $INSTALL_CMD $opt_pkg" >/dev/null 2>&1; then
      log_warn "Optional package $opt_pkg not available, skipping."
    fi
  done

  if ! command -v starship >/dev/null 2>&1; then
    log_info "Installing starship prompt..."
    if ! eval "$SUDO $INSTALL_CMD $STARSHIP_PACKAGE" >/dev/null 2>&1; then
      log_warn "Package manager install for starship failed, trying alternative methods."

      if [ "$OS_TYPE" = "Windows" ]; then
        # Windows: ensure all package manager paths are in PATH
        local scoop_shims="$HOME/scoop/shims"
        local winget_dir="/c/Users/$USER/AppData/Local/Microsoft/WindowsApps"
        local choco_bin="/c/ProgramData/chocolatey/bin"
        local starship_choco="/c/Program Files/starship"
        export PATH="$PATH:$scoop_shims:$winget_dir:$choco_bin:$starship_choco"

        # Check if starship is already installed (e.g., via choco in a previous session)
        if command -v starship >/dev/null 2>&1 || [ -f "/c/Program Files/starship/starship.exe" ]; then
          log_success "Starship already installed, skipping."
          installed=true
        else
          installed=false
        fi

        if [ "$installed" = false ] && command -v scoop >/dev/null 2>&1; then
          log_info "Installing starship via scoop..."
          if scoop install starship 2>/dev/null; then
            installed=true
          fi
        fi
        if [ "$installed" = false ] && command -v choco >/dev/null 2>&1; then
          log_info "Installing starship via chocolatey..."
          if choco install starship -y 2>/dev/null; then
            # choco installs to C:\Program Files\starship\
            export PATH="$PATH:/c/Program Files/starship"
            installed=true
          fi
        fi
        if [ "$installed" = false ] && command -v winget.exe >/dev/null 2>&1; then
          log_info "Installing starship via winget..."
          if winget.exe install --id Starship.Starship -e --accept-source-agreements --accept-package-agreements 2>/dev/null; then
            installed=true
          fi
        fi
        if [ "$installed" = false ]; then
          # Resolve version inside cmd.exe (avoids \r issues in bash)
          local starship_version
          starship_version=$(cmd.exe /c "for /f \"tokens=2 delims=/\" %a in ('curl.exe -sIL https://github.com/starship/starship/releases/latest ^| findstr /i location') do @echo %a" 2>/dev/null | tr -d '\r\n ' | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)

          if [ -n "$starship_version" ]; then
            log_info "Resolved starship version: $starship_version"
            local starship_bin="$HOME/.local/bin"
            mkdir -p "$starship_bin"
            local tmp_zip="$HOME/.cache/starship-download.zip"
            mkdir -p "$HOME/.cache"
            local dl_url="https://github.com/starship/starship/releases/download/${starship_version}/starship-x86_64-pc-windows-msvc.zip"
            log_info "Downloading starship $starship_version..."

            local win_zip
            if command -v cygpath >/dev/null 2>&1; then
              win_zip=$(cygpath -w "$tmp_zip")
            else
              win_zip="$tmp_zip"
            fi

            if cmd.exe /c "curl.exe -fSL \"$dl_url\" -o \"$win_zip\"" 2>/dev/null; then
              if [ -f "$tmp_zip" ] && [ -s "$tmp_zip" ]; then
                # Use Windows native tar.exe to extract (handles zip reliably in Git Bash)
                local win_bin
                if command -v cygpath >/dev/null 2>&1; then
                  win_bin=$(cygpath -w "$starship_bin")
                else
                  win_bin="$starship_bin"
                fi
                cmd.exe /c "tar.exe -xf \"$win_zip\" -C \"$win_bin\"" 2>/dev/null
                rm -f "$tmp_zip"
                if [ -f "$starship_bin/starship.exe" ] || [ -f "$starship_bin/starship" ]; then
                  installed=true
                  export PATH="$starship_bin:$PATH"
                  log_success "Starship installed to $starship_bin"
                fi
              fi
            fi
          else
            log_warn "Could not resolve starship version."
          fi
        fi
        if [ "$installed" = false ]; then
          log_error "Failed to install starship."
          log_info "Please install manually: choco install starship  (or)  scoop install starship  (or)  winget install Starship.Starship"
          exit 1
        fi
      else
        # Linux/macOS: use official install.sh with BIN_DIR
        local starship_bin="$HOME/.local/bin"
        if [ -d "/usr/local/bin" ] && [ -w "/usr/local/bin" ]; then
          starship_bin="/usr/local/bin"
        fi
        mkdir -p "$starship_bin"
        log_info "Installing starship to $starship_bin via official installer..."
        if ! curl -fsSL https://starship.rs/install.sh | BIN_DIR="$starship_bin" sh -s -- -y; then
          log_error "Failed to install starship."
          exit 1
        fi
        case ":$PATH:" in
        *":$starship_bin:"*) ;;
        *) export PATH="$starship_bin:$PATH" ;;
        esac
      fi
    fi
  fi

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

# --- 3. Configuration Generation (.zshrc) ---

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
    rm -rf "$HOME/.zshrc" "$HOME/.p10k.zsh" "${XDG_DATA_HOME:-$HOME/.local/share}/zinit"

    if [ "$OS_TYPE" = "Android" ]; then
      log_info "Creating Quick Shell directory..."
      mkdir -p "$TARGET_DIR"
    fi

    log_info "Installing ~/.zshrc from template..."

    if [ ! -f "$SCRIPT_DIR/zshrc.template" ]; then
      log_error "Template file not found: $SCRIPT_DIR/zshrc.template"
      exit 1
    fi

    cp "$SCRIPT_DIR/zshrc.template" "$HOME/.zshrc"
    # Replace placeholder with actual TARGET_DIR (cross-platform sed)
    sed_inplace "s|__QS_TARGET_DIR__|${TARGET_DIR}|g" "$HOME/.zshrc"

    log_success ".zshrc installed successfully."
  else
    log_info "Skipping .zshrc generation. Existing config preserved."
  fi

  # Download starship config if starship is available
  if command -v starship >/dev/null 2>&1; then
    log_info "Syncing Starship config..."
    mkdir -p "$HOME/.config"
    if curl -fsSL "$STARSHIP_CONFIG_URL" -o "$HOME/.config/starship.toml" 2>/dev/null; then
      log_success "Starship config updated."
    else
      log_warn "Failed to download starship config, keeping existing config."
    fi
  fi
}

# --- 4. Plugin Installation (Zinit & Plugins) ---

install_plugins() {
  print_step 4 $TOTAL_STEPS "Plugin Deployment"

  local plugin_failures=0
  ZINIT_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"

  # Install Zinit Core (check for actual file, not just directory)
  if [ ! -f "$ZINIT_HOME/zinit.zsh" ]; then
    log_info "Installing Zinit Plugin Manager..."
    mkdir -p "$(dirname "$ZINIT_HOME")"
    if ! git_clone_fallback "https://github.com/zdharma-continuum/zinit.git" "$ZINIT_HOME"; then
      log_error "Failed to install Zinit Plugin Manager."
      return 1
    fi
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
        if ! git_clone_fallback "$url" "$path"; then
          echo "    ❌ Reinstall Failed"
          return 1
        fi
      else
        printf "  📦 %-25s : ${BLUE}Updating...${NC}\n" "$name"
        if ! git -C "$path" pull -q >/dev/null 2>&1; then
          echo "    ❌ Update Failed (Check Network)"
          return 1
        fi
      fi
    else
      printf "  📦 %-25s : ${GREEN}Installing...${NC}\n" "$name"
      if ! git_clone_fallback "$url" "$path"; then
        echo "    ❌ Install Failed"
        return 1
      fi
    fi
  }

  # Zinit stores plugins under its own data directory
  ZINIT_PLUGINS="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/plugins"

  echo "Processing Plugin List..."
  manage_plugin "Syntax Highlighting" "https://github.com/zsh-users/zsh-syntax-highlighting" "${ZINIT_PLUGINS}/zsh-users---zsh-syntax-highlighting" || plugin_failures=$((plugin_failures + 1))
  manage_plugin "Auto Suggestions" "https://github.com/zsh-users/zsh-autosuggestions" "${ZINIT_PLUGINS}/zsh-users---zsh-autosuggestions" || plugin_failures=$((plugin_failures + 1))
  manage_plugin "zsh-z" "https://github.com/agkozak/zsh-z" "${ZINIT_PLUGINS}/agkozak---zsh-z" || plugin_failures=$((plugin_failures + 1))
  manage_plugin "fzf-tab" "https://github.com/Aloxaf/fzf-tab" "${ZINIT_PLUGINS}/Aloxaf---fzf-tab" || plugin_failures=$((plugin_failures + 1))
  manage_plugin "fzf" "https://github.com/junegunn/fzf" "${ZINIT_PLUGINS}/junegunn---fzf" || plugin_failures=$((plugin_failures + 1))

  if [ "$plugin_failures" -gt 0 ]; then
    log_error "Plugin deployment finished with ${plugin_failures} failure(s). Check network or proxy settings and rerun."
    return 1
  fi

  log_success "All plugins deployed successfully."
  return 0
}

# --- 5. Set Default Shell ---

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
      if ! chsh -s zsh; then
        log_warn "Auto-switch failed. Please run manually after fixing your shell config."
        return 1
      fi
    else
      log_info "Attempting to switch shell using 'chsh'..."
      ZSH_PATH=$(command -v zsh 2>/dev/null)
      if [ -n "$ZSH_PATH" ]; then
        # macOS: ensure the shell is listed in /etc/shells
        if [ "$OS_TYPE" = "MacOS" ]; then
          if ! grep -qx "$ZSH_PATH" /etc/shells 2>/dev/null; then
            log_info "Adding $ZSH_PATH to /etc/shells (requires sudo)..."
            echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
          fi
        fi
        if ! chsh -s "$ZSH_PATH"; then
          log_warn "Auto-switch failed. Please run manually: chsh -s $ZSH_PATH"
          return 1
        fi
      else
        log_error "Zsh path not found. Skipping default shell setup."
        return 1
      fi
    fi
  fi

  return 0
}

# --- Main Entry Point ---

main() {
  local plugin_status=0
  local shell_status=0

  # Clear screen
  printf "${MAGENTA}====================================================${NC}\n"
  printf "${MAGENTA}   ✨ Zsh + Zinit + QuickShell Setup Script ✨     ${NC}\n"
  printf "${MAGENTA}====================================================${NC}\n"

  detect_env
  disable_root_local_proxy
  install_pkgs
  config_zshrc
  install_plugins || plugin_status=$?
  set_default_shell || shell_status=$?

  echo ""
  if [ "$plugin_status" -eq 0 ] && [ "$shell_status" -eq 0 ]; then
    log_success "🎉 All tasks completed successfully!"
  else
    log_warn "Setup completed with warnings."
  fi

  if [ "$OS_TYPE" = "Windows" ]; then
    log_info "Please restart your Git Bash terminal to apply changes."
  elif [ "$plugin_status" -ne 0 ]; then
    log_warn "Skipping automatic Zsh launch because plugin setup failed."
  else
    log_info "Entering Zsh now..."
    exec zsh -l
  fi
}

main
