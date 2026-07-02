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
# --- 1. 修复 tmux 下的 UTF-8 和色彩问题 ---
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# 只在 tmux 外部设置，tmux 内部不覆盖
if [[ -z "$TMUX" ]]; then
    export TERM=xterm-256color
fi

# ==============================================================================
# Zinit Core Initialization
# ==============================================================================
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

# Auto-install zinit if missing
if [ ! -f "${ZINIT_HOME}/zinit.zsh" ]; then
    mkdir -p "$(dirname $ZINIT_HOME)"
    if ! git clone --depth=1 https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME" >/dev/null 2>&1; then
        echo "[quick-shell] Warning: failed to install zinit; skipping zinit plugins." >&2
    fi
fi

if [ -f "${ZINIT_HOME}/zinit.zsh" ]; then
    source "${ZINIT_HOME}/zinit.zsh"
ZSHRC_EOF

  get_prompt_zinit_block

  cat <<'ZSHRC_EOF'

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
    # wait'0' 异步加载，避免阻塞 shell 启动
    zinit ice lucid wait'0' multisrc'shell/key-bindings.zsh shell/completion.zsh'
    zinit light junegunn/fzf

    # ==============================================================================
    # Completion System
    # ==============================================================================
    autoload -Uz compinit
    compinit -u

    # Replay all cached completions (zinit optimization)
    zinit cdreplay -q
else
    echo "[quick-shell] Warning: zinit is unavailable; shell started without zinit plugins." >&2
fi

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

gitdc(){ o=$(git -p diff HEAD;echo "---";git status); echo "$o" | { wl-copy 2>/dev/null || pbcopy || clip.exe || xclip -sel c || xsel -b; } && echo "✅ Copied ($(echo "$o" | wc -l) lines)"; }
gitdf(){ o=$(git -p diff HEAD;echo "---";git status); echo "$o" > "${1:-commit_message.txt}" && echo "✅ Saved to ${1:-commit_message.txt} ($(echo "$o" | wc -l) lines)"; }
stowlink() { [ -z "$2" ] && echo "Usage: stowlink <dir> <pkg>" || (mkdir -p "$1" && stow -t "$1" "$2"); }
stowlink-auto() { [ -z "$2" ] && echo "Usage: stowlink-auto <parent_path> <pkg>" || (T="${1%/}/$2" && mkdir -p "$T" && stow -t "$T" "$2"); }
stowlink-dir() { [ -z "$2" ] && echo "Usage: stowlink-dir <parent> <pkg>" || { [ -d "$PWD/$2" ] && mkdir -p "$1" && ln -sfn "$PWD/$2" "${1%/}/$2" && echo "Linked: ${1%/}/$2 -> $PWD/$2"; } }
mf() { local dir="${1:-.}"; [[ "$dir" != /* ]] && dir="$PWD/$dir"; local out=""; local files=(); while IFS= read -r -d '' f; do files+=("$f"); done < <(find "$dir" -type f -print0 | sort -z); for f in "${files[@]}"; do out+="--- $(basename "$f") ---"$'\n'"$(cat "$f")"$'\n\n'; done; if [ ${#out} -gt 1000 ]; then echo "$out" > contents.txt; echo "Saved to contents.txt"; else echo "$out" | tee /dev/clipboard 2>/dev/null || echo "$out" | { command -v pbcopy &>/dev/null && pbcopy || command -v xclip &>/dev/null && xclip -selection clipboard || command -v xsel &>/dev/null && xsel --clipboard --input || clip; }; echo "Copied to clipboard"; fi; }
gitmerge() { git -c log.showSignature=false merge "origin/${1:-$(git branch --show-current)}" --no-stat -v; }
# --- History ---
HISTFILE="$HOME/.zsh_history"
HISTSIZE=15000
SAVEHIST=20000
setopt HIST_IGNORE_DUPS      # Skip duplicate commands
setopt HIST_IGNORE_SPACE     # Skip commands prefixed with space
setopt INC_APPEND_HISTORY    # Write to history immediately, not on exit
setopt SHARE_HISTORY         # Share history across all open sessions

# --- Environment ---
#export http_proxy=http://127.0.0.1:7890
#export https_proxy=http://127.0.0.1:7890
#export NO_PROXY="localhost,127.0.0.1"


# --- Aliases ---
alias ls='command -v lsd &>/dev/null && lsd || ls'
alias ll='command -v lsd &>/dev/null && lsd -l || ls -l'
alias la='command -v lsd &>/dev/null && lsd -a || ls -a'
alias batall='command -v bat &>/dev/null && bat --paging=never || cat'
alias gitfetch='git -c log.showSignature=false -c core.quotepath=false fetch origin --recurse-submodules=no --progress --prune'

# Fix Ctrl+Arrow in Git Bash / Windows Terminal
# Fix arrow keys
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
  bindkey "^[[A" up-line-or-history    # Up
  bindkey "^[[1;5B" down-line-or-history # Ctrl+Down
  # 1. 强制 Zsh 使用 Emacs 风格键位 (防 nvim 篡改)
  bindkey -e

  # 2. 修复基础编辑键 (删除与退格)
  bindkey "^[[3~" delete-char              # Delete (向后删除单个字符)
  bindkey "^[[3;5~" kill-word              # Ctrl + Delete (向后删除整个单词)
  bindkey "^[[3;3~" kill-word              # Alt + Delete (向后删除整个单词)

  bindkey '^[^?' backward-kill-word        # Alt + Backspace (向前删除单词)
  bindkey '^[^H' backward-kill-word        # Alt + Backspace (变种)

  # 3. 修复 Home 和 End 键
  bindkey "^[[H" beginning-of-line
  bindkey "^[[F" end-of-line

  # 4. 修复基础方向键
  bindkey "^[[A" up-line-or-history
  bindkey "^[[B" down-line-or-history
  bindkey "^[[C" forward-char
  bindkey "^[[D" backward-char

  # 5. 修复 Ctrl + 左右方向键 (跳过单词)
  bindkey "^[[1;5C" forward-word           # Windows Terminal 标准 Ctrl+Right
  bindkey "^[[1;5D" backward-word          # Windows Terminal 标准 Ctrl+Left
  bindkey "^[O5C"   forward-word           # Tmux 变种 Ctrl+Right
  bindkey "^[O5D"   backward-word          # Tmux 变种 Ctrl+Left
  bindkey "^[Oc"    forward-word           # rxvt 变种 Ctrl+Right
  bindkey "^[Od"    backward-word          # rxvt 变种 Ctrl+Left

  # 6. 修复 Alt + 左右方向键 (跳过单词)
  bindkey "^[[1;3C" forward-word           # 标准 Alt+Right
  bindkey "^[[1;3D" backward-word          # 标准 Alt+Left
  bindkey "^[^[[C"  forward-word           # Git Bash 嵌套 Alt+Right (输出C的元凶)
  bindkey "^[^[[D"  backward-word          # Git Bash 嵌套 Alt+Left (输出D的元凶)
fi
# ------------------

# alias sys-update='sudo pacman -Syu --noconfirm && yay -Sua --noconfirm && paru -Sua --noconfirm'
# alias aur-clean='sudo pacman -Scc --noconfirm && yay -Scc --noconfirm && paru -Scc --noconfirm'

source /usr/share/nvm/init-nvm.sh

export JENV_ROOT="$HOME/.jenv"
export ZVM_INSTALL="$HOME/.zvm/self"

# yay -S gvm-bin
PATH_ENTRIES=(
  "$HOME/.local/bin"
  "$HOME/.gvm/bin"
  "$JENV_ROOT/bin"
  "$HOME/.zvm/bin"
  "$ZVM_INSTALL"
  "$PATH"
)

export PATH="$(IFS=:; echo "${PATH_ENTRIES[*]}")"

eval "$(jenv init -)"

export JAVA_TOOL_OPTIONS="-XX:-HeapDumpOnOutOfMemoryError"
ZSHRC_EOF2

  get_prompt_init_block
}

get_prompt_zinit_block() {
  cat <<'PROMPT_ZINIT_EOF'
    # >>> quick-shell prompt plugin >>>
PROMPT_ZINIT_EOF

  if [ "$PROMPT_THEME" = "p10k" ]; then
    cat <<'PROMPT_ZINIT_EOF'
    zinit ice depth=1
    zinit light romkatv/powerlevel10k
PROMPT_ZINIT_EOF
  fi

  cat <<'PROMPT_ZINIT_EOF'
    # <<< quick-shell prompt plugin <<<
PROMPT_ZINIT_EOF
}

get_prompt_init_block() {
  case "$PROMPT_THEME" in
  p10k)
    cat <<'PROMPT_INIT_EOF'
# >>> quick-shell prompt init >>>
export POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
if [ -f "$HOME/.p10k.zsh" ]; then
  source "$HOME/.p10k.zsh"
else
  echo "[quick-shell] Warning: ~/.p10k.zsh is missing; prompt theme not loaded." >&2
fi
# <<< quick-shell prompt init >>>
PROMPT_INIT_EOF
    ;;
  *)
    cat <<'PROMPT_INIT_EOF'
# >>> quick-shell prompt init >>>
if command -v starship >/dev/null 2>&1; then
  _starship_bin="$(command -v starship)"

  # Source init.zsh if available (functions/hooks), otherwise define manually
  _starship_init="${_starship_bin:h}/init.zsh"
  if [ -f "$_starship_init" ]; then
    source "$_starship_init"
  else
    # --- Manual init (replaces starship init zsh, avoids quoted-path issues on Windows) ---
    zmodload zsh/parameter
    if [[ $ZSH_VERSION == ([1-4]*) ]]; then
      __starship_get_time() { STARSHIP_CAPTURED_TIME=$("${_starship_bin}" time); }
    else
      zmodload zsh/datetime zsh/mathfunc
      __starship_get_time() { (( STARSHIP_CAPTURED_TIME = int(rint(EPOCHREALTIME * 1000)) )); }
    fi
    prompt_starship_precmd() {
      STARSHIP_CMD_STATUS=$? STARSHIP_PIPE_STATUS=(${pipestatus[@]})
      if (( ${+STARSHIP_START_TIME} )); then
        __starship_get_time && STARSHIP_DURATION=$(( STARSHIP_CAPTURED_TIME - STARSHIP_START_TIME ))
        unset STARSHIP_START_TIME
      else
        unset STARSHIP_DURATION STARSHIP_CMD_STATUS STARSHIP_PIPE_STATUS
      fi
      STARSHIP_JOBS_COUNT="${#jobstates[*]}"
    }
    prompt_starship_preexec() {
      __starship_get_time && STARSHIP_START_TIME=$STARSHIP_CAPTURED_TIME
    }
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd prompt_starship_precmd
    add-zsh-hook preexec prompt_starship_preexec
    starship_zle-keymap-select() { zle reset-prompt; }
    if [[ -v widgets[zle-keymap-select] ]]; then
      __starship_preserved_zle_keymap_select=${widgets[zle-keymap-select]#user:}
    fi
    if [[ -z ${__starship_preserved_zle_keymap_select:-} ]]; then
      zle -N zle-keymap-select starship_zle-keymap-select
    else
      starship_zle-keymap-select-wrapped() {
        $__starship_preserved_zle_keymap_select "$@"
        starship_zle-keymap-select "$@"
      }
      zle -N zle-keymap-select starship_zle-keymap-select-wrapped
    fi
    export STARSHIP_SHELL="zsh"
    STARSHIP_SESSION_KEY="$RANDOM$RANDOM$RANDOM$RANDOM$RANDOM"
    STARSHIP_SESSION_KEY="${STARSHIP_SESSION_KEY}0000000000000000"
    export STARSHIP_SESSION_KEY=${STARSHIP_SESSION_KEY:0:16}
    VIRTUAL_ENV_DISABLE_PROMPT=1
    # --- End manual init ---
  fi
  unset _starship_init

  # PROMPT vars: use 'path' quoting inside $() — safe even when path contains spaces
  PROMPT="\$('${_starship_bin}' prompt --terminal-width=\"\$COLUMNS\" --keymap=\"\${KEYMAP:-}\" --status=\"\${STARSHIP_CMD_STATUS:-}\" --pipestatus=\"\${STARSHIP_PIPE_STATUS[*]:-}\" --cmd-duration=\"\${STARSHIP_DURATION:-}\" --jobs=\"\$STARSHIP_JOBS_COUNT\")"
  RPROMPT="\$('${_starship_bin}' prompt --right --terminal-width=\"\$COLUMNS\" --keymap=\"\${KEYMAP:-}\" --status=\"\${STARSHIP_CMD_STATUS:-}\" --pipestatus=\"\${STARSHIP_PIPE_STATUS[*]:-}\" --cmd-duration=\"\${STARSHIP_DURATION:-}\" --jobs=\"\$STARSHIP_JOBS_COUNT\")"
  PROMPT2="\$('${_starship_bin}' prompt --continuation)"
  setopt promptsubst
else
  echo "[quick-shell] Warning: starship is unavailable; prompt theme not loaded." >&2
fi
# <<< quick-shell prompt init >>>
PROMPT_INIT_EOF
    ;;
  esac
}

get_p10k_config_template() {
  cat <<'P10K_EOF'
# Generated by quick-shell. Customize as needed.
typeset -g POWERLEVEL9K_MODE=nerdfont-complete
typeset -g POWERLEVEL9K_PROMPT_ON_NEWLINE=true
typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(os_icon dir vcs newline prompt_char)
typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status command_execution_time background_jobs time)
typeset -g POWERLEVEL9K_DIR_MAX_LENGTH=80
typeset -g POWERLEVEL9K_SHORTEN_STRATEGY=truncate_to_unique
typeset -g POWERLEVEL9K_STATUS_OK=false
typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_THRESHOLD=3
typeset -g POWERLEVEL9K_BACKGROUND_JOBS_VERBOSE=false
typeset -g POWERLEVEL9K_TIME_FORMAT='%D{%H:%M:%S}'
typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_CHAR=' '
typeset -g POWERLEVEL9K_OS_ICON_CONTENT_EXPANSION='⭐'
typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_VIINS_CONTENT_EXPANSION='❯'
typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_VIINS_CONTENT_EXPANSION='❯'
typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_VIINS_FOREGROUND=76
typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_VIINS_FOREGROUND=196
P10K_EOF
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
TOTAL_STEPS=6
PROMPT_THEME="starship"
STARSHIP_CONFIG_URL="https://raw.githubusercontent.com/crowforkotlin/crowforkotlin.config.starship/mac/starship.toml"
PROMPT_ZINIT_BEGIN="    # >>> quick-shell prompt plugin >>>"
PROMPT_ZINIT_END="    # <<< quick-shell prompt plugin <<<"
PROMPT_INIT_BEGIN="# >>> quick-shell prompt init >>>"
PROMPT_INIT_END="# <<< quick-shell prompt init <<<"
STARSHIP_CONFIG_BEGIN="# >>> quick-shell managed starship config >>>"
STARSHIP_CONFIG_END="# <<< quick-shell managed starship config <<<"

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

select_prompt_theme() {
  print_step 2 $TOTAL_STEPS "Prompt Theme Selection"

  printf "${WHITE}Please select a prompt theme:${NC}\n"
  printf "  ${CYAN}[1]${NC} Starship       ${DIM}(Recommended, cross-shell)${NC}\n"
  printf "  ${CYAN}[2]${NC} Powerlevel10k  ${DIM}(Zsh-only, richer prompt)${NC}\n"
  read -p "Enter Selection [1-2]: " prompt_choice

  case "$prompt_choice" in
  2)
    PROMPT_THEME="p10k"
    ;;
  "" | 1)
    PROMPT_THEME="starship"
    ;;
  *)
    PROMPT_THEME="starship"
    log_warn "Invalid input. Defaulting to Starship."
    ;;
  esac

  if [ "$PROMPT_THEME" = "p10k" ]; then
    log_info "Prompt Theme      : ${WHITE}Powerlevel10k${NC}"
  else
    log_info "Prompt Theme      : ${WHITE}Starship${NC}"
  fi
}

# --- 3. Software Installation ---

install_pkgs() {
  print_step 3 $TOTAL_STEPS "Core Software Installation"

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

  if [ "$PROMPT_THEME" = "starship" ] && ! command -v starship >/dev/null 2>&1; then
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

# --- 4. Configuration Generation (.zshrc) ---

replace_managed_block_in_file() {
  local target_file=$1
  local begin_marker=$2
  local end_marker=$3
  local block_file=$4
  local tmp_file

  tmp_file=$(qs_mktemp "quick-shell-block")

  if ! awk -v begin="$begin_marker" -v end="$end_marker" -v block_file="$block_file" '
    function print_block(   line) {
      while ((getline line < block_file) > 0) {
        print line
      }
      close(block_file)
    }

    $0 == begin {
      if (!replaced) {
        print_block()
        replaced = 1
      }
      skipping = 1
      next
    }

    $0 == end {
      skipping = 0
      next
    }

    !skipping {
      print
    }

    END {
      if (!replaced) {
        exit 1
      }
    }
  ' "$target_file" >"$tmp_file"; then
    rm -f "$tmp_file"
    return 1
  fi

  mv "$tmp_file" "$target_file"
}

insert_block_after_anchor() {
  local target_file=$1
  local anchor=$2
  local block_file=$3
  local tmp_file

  tmp_file=$(qs_mktemp "quick-shell-block")

  if ! awk -v anchor="$anchor" -v block_file="$block_file" '
    function print_block(   line) {
      while ((getline line < block_file) > 0) {
        print line
      }
      close(block_file)
    }

    {
      print
    }

    $0 == anchor && !inserted {
      print_block()
      inserted = 1
    }

    END {
      if (!inserted) {
        exit 1
      }
    }
  ' "$target_file" >"$tmp_file"; then
    rm -f "$tmp_file"
    return 1
  fi

  mv "$tmp_file" "$target_file"
}

append_block_from_file() {
  local target_file=$1
  local block_file=$2

  if [ -f "$target_file" ] && [ -s "$target_file" ]; then
    printf '\n' >>"$target_file"
  fi

  cat "$block_file" >>"$target_file"
  printf '\n' >>"$target_file"
}

# Utility: create a temp file with fallback for Git Bash (mktemp may fail)
qs_mktemp() {
  local prefix="${1:-quick-shell}"
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/${prefix}.XXXXXX" 2>/dev/null)
  if [ -z "$tmp" ] || [ ! -f "$tmp" ]; then
    tmp="${HOME}/.cache/${prefix}.$$.tmp"
    mkdir -p "$(dirname "$tmp")" 2>/dev/null
    : > "$tmp"
  fi
  printf '%s' "$tmp"
}

remove_legacy_starship_prompt_block() {
  local target_file=$1
  local tmp_file

  if [ ! -f "$target_file" ] || ! grep -Fq '[quick-shell] Warning: starship is unavailable; prompt theme not loaded.' "$target_file"; then
    return 0
  fi

  tmp_file=$(qs_mktemp "quick-shell-block")

  awk '
    $0 == "if command -v starship >/dev/null 2>&1; then" {
      skipping = 1
      next
    }

    skipping && $0 == "fi" {
      skipping = 0
      next
    }

    !skipping {
      print
    }
  ' "$target_file" >"$tmp_file"

  mv "$tmp_file" "$target_file"
}

ensure_prompt_zinit_block() {
  local target_file=$1
  local block_file

  if [ ! -f "$target_file" ]; then
    return 0
  fi

  block_file=$(qs_mktemp "quick-shell-block")
  get_prompt_zinit_block >"$block_file"

  if grep -Fq "$PROMPT_ZINIT_BEGIN" "$target_file"; then
    replace_managed_block_in_file "$target_file" "$PROMPT_ZINIT_BEGIN" "$PROMPT_ZINIT_END" "$block_file" || {
      rm -f "$block_file"
      return 1
    }
  elif [ "$PROMPT_THEME" = "p10k" ]; then
    insert_block_after_anchor "$target_file" '    source "${ZINIT_HOME}/zinit.zsh"' "$block_file" || {
      rm -f "$block_file"
      return 1
    }
  fi

  rm -f "$block_file"
}

ensure_prompt_init_block() {
  local target_file=$1
  local block_file

  if [ ! -f "$target_file" ]; then
    return 0
  fi

  remove_legacy_starship_prompt_block "$target_file"

  block_file=$(qs_mktemp "quick-shell-block")
  get_prompt_init_block >"$block_file"

  if grep -Fq "$PROMPT_INIT_BEGIN" "$target_file"; then
    replace_managed_block_in_file "$target_file" "$PROMPT_INIT_BEGIN" "$PROMPT_INIT_END" "$block_file" || {
      rm -f "$block_file"
      return 1
    }
  else
    append_block_from_file "$target_file" "$block_file"
  fi

  rm -f "$block_file"
}

ensure_starship_config() {
  local target_config="$HOME/.config/starship.toml"
  local downloaded_config managed_block

  mkdir -p "$(dirname "$target_config")"
  downloaded_config=$(qs_mktemp "quick-shell-starship")
  managed_block=$(qs_mktemp "quick-shell-starship")

  if ! curl -fsSL "$STARSHIP_CONFIG_URL" >"$downloaded_config"; then
    rm -f "$downloaded_config" "$managed_block"
    return 1
  fi

  {
    printf '%s\n' "$STARSHIP_CONFIG_BEGIN"
    cat "$downloaded_config"
    printf '\n%s\n' "$STARSHIP_CONFIG_END"
  } >"$managed_block"

  if [ -f "$target_config" ] && grep -Fq "$STARSHIP_CONFIG_BEGIN" "$target_config"; then
    replace_managed_block_in_file "$target_config" "$STARSHIP_CONFIG_BEGIN" "$STARSHIP_CONFIG_END" "$managed_block" || {
      rm -f "$downloaded_config" "$managed_block"
      return 1
    }
  else
    append_block_from_file "$target_config" "$managed_block"
  fi

  rm -f "$downloaded_config" "$managed_block"
}

ensure_p10k_config() {
  local target_config="$HOME/.p10k.zsh"

  if [ -f "$target_config" ]; then
    return 0
  fi

  get_p10k_config_template >"$target_config"
}

configure_prompt_assets() {
  local zshrc_file="$HOME/.zshrc"

  case "$PROMPT_THEME" in
  p10k)
    log_info "Preparing Powerlevel10k config..."
    ensure_p10k_config || {
      log_error "Failed to create ~/.p10k.zsh."
      exit 1
    }
    ;;
  *)
    log_info "Syncing Starship config..."
    ensure_starship_config || {
      log_error "Failed to update ~/.config/starship.toml."
      exit 1
    }
    ;;
  esac

  ensure_prompt_zinit_block "$zshrc_file" || log_warn "Failed to update prompt plugin block in ~/.zshrc. Clean Install may be required."
  ensure_prompt_init_block "$zshrc_file" || log_warn "Failed to update prompt init block in ~/.zshrc."
}

config_zshrc() {
  print_step 4 $TOTAL_STEPS "Configuration Setup"

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
    # Remove old .zshrc, zinit data directory and legacy Powerlevel10k config
    rm -rf "$HOME/.zshrc" "$HOME/.p10k.zsh" "${XDG_DATA_HOME:-$HOME/.local/share}/zinit"

    if [ "$OS_TYPE" = "Android" ]; then
      log_info "Creating Quick Shell directory..."
      mkdir -p "$TARGET_DIR"
    fi

    log_info "Generating new ~/.zshrc ..."

    # 🟢 HERE: Call the top function to write the file
    get_zshrc_template >"$HOME/.zshrc"

    log_success ".zshrc generated successfully."
  else
    log_info "Skipping .zshrc generation. Existing config preserved."
  fi

  configure_prompt_assets
}

# --- 5. Plugin Installation (Zinit & Plugins) ---

install_plugins() {
  print_step 5 $TOTAL_STEPS "Plugin Deployment"

  local plugin_failures=0
  ZINIT_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"

  # Install Zinit Core
  if [ ! -d "$ZINIT_HOME" ]; then
    log_info "Installing Zinit Plugin Manager..."
    mkdir -p "$(dirname "$ZINIT_HOME")"
    if ! git clone --depth=1 https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME" -q; then
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
        if ! git clone --depth=1 "$url" "$path" -q; then
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
      if ! git clone --depth=1 "$url" "$path" -q; then
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
  if [ "$PROMPT_THEME" = "p10k" ]; then
    manage_plugin "Powerlevel10k" "https://github.com/romkatv/powerlevel10k" "${ZINIT_PLUGINS}/romkatv---powerlevel10k" || plugin_failures=$((plugin_failures + 1))
  fi

  if [ "$plugin_failures" -gt 0 ]; then
    log_error "Plugin deployment finished with ${plugin_failures} failure(s). Check network or proxy settings and rerun."
    return 1
  fi

  log_success "All plugins deployed successfully."
  return 0
}

# --- 6. Set Default Shell ---

set_default_shell() {
  print_step 6 $TOTAL_STEPS "Default Shell Configuration"

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
  select_prompt_theme
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
