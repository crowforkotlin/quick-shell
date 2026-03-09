#!/data/data/com.termux/files/usr/bin/bash

# ==============================================================================
# Script Name: Shizuku + Rish + ADB Setup Script (Official Path Fix)
# Platform   : Android (Termux)
# Description: Automates Shizuku startup using the internal .so shell script.
# Fixes      : Dynamic pathing, ELF syntax error, and Phantom Process termination.
# ==============================================================================

# --- 1. Global Config & Utility Functions ---

BASEDIR=$(dirname "${0}")
BIN_DIR="/data/data/com.termux/files/usr/bin"
HOME_DIR="/data/data/com.termux/files/home"
SOURCE_DEX="${BASEDIR}/rish_shizuku.dex"
TARGET_DEX="${HOME_DIR}/rish_shizuku.dex"
TOTAL_STEPS=4

# Color Definitions
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
  CYAN=$(
    tput setaf 6
    tput bold
  )
  NC=$(tput sgr0)
else
  RED='\033[1;31m'
  GREEN='\033[1;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[1;34m'
  CYAN='\033[1;36m'
  NC='\033[0m'
fi

log_info() { printf "${BLUE} 🔵 [INFO]${NC} %s\n" "$1"; }
log_success() { printf "${GREEN} 🟢 [PASS]${NC} %s\n" "$1"; }
log_warn() { printf "${YELLOW} 🟡 [WARN]${NC} %s\n" "$1"; }
log_error() { printf "${RED} 🔴 [FAIL]${NC} %s\n" "$1"; }

print_step() {
  echo ""
  printf "${CYAN}┌──────────────────────────────────────────────────────────────┐${NC}\n"
  printf "${CYAN}│ 🚀 STEP %d/%d : %-43s │${NC}\n" "$1" "$2" "$3"
  printf "${CYAN}└──────────────────────────────────────────────────────────────┘${NC}\n"
}

# --- 2. Environment Check ---

check_env() {
  print_step 1 $TOTAL_STEPS "Environment & Dependency Check"

  log_info "Verifying 'rish_shizuku.dex'..."
  if [ ! -f "${SOURCE_DEX}" ]; then
    log_error "File not found: ${SOURCE_DEX}"
    exit 1
  fi

  log_info "Ensuring ADB is installed..."
  pkg update -y >/dev/null 2>&1
  pkg install android-tools -y >/dev/null 2>&1
}

# --- 3. Generate Startup Script (shizuku) ---

gen_shizuku_script() {
  print_step 2 $TOTAL_STEPS "Generating Service Launcher (shizuku)"

  local TARGET_FILE="${BIN_DIR}/shizuku"
  log_info "Creating script: ${TARGET_FILE}"

  # Use 'EOF' to prevent local variable expansion
  tee "${TARGET_FILE}" >/dev/null <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

PORT=$1
TARGET_SERIAL="localhost:5555"

if [ -z "$PORT" ]; then
    echo -e "\033[1;31m[ERROR]\033[0m Missing port number!"
    echo "Usage: shizuku <PORT>"
    exit 1
fi

export TMPDIR=/data/data/com.termux/files/home/tmp
mkdir -p $TMPDIR

echo "🔄 Connecting to Wireless Debugging on port ${PORT}..."
adb connect "localhost:${PORT}"

echo "⚙️ Setting TCP/IP to 5555..."
adb -s "localhost:${PORT}" tcpip 5555
sleep 1
adb connect $TARGET_SERIAL

# --- Dynamic Path Resolution (Finding that .so file) ---
echo "🚀 Locating Shizuku starter..."
PKG_PATH=$(adb -s $TARGET_SERIAL shell pm path moe.shizuku.privileged.api | cut -d':' -f2 | sed 's/base.apk//g')

if [ -z "$PKG_PATH" ]; then
    echo -e "\033[1;31m[FAIL]\033[0m Shizuku app not found."
    exit 1
fi

# Construct the official .so starter path
STARTER="${PKG_PATH}lib/arm64/libshizuku.so"
# Fallback for 32-bit devices
if ! adb -s $TARGET_SERIAL shell ls "$STARTER" > /dev/null 2>&1; then
    STARTER="${PKG_PATH}lib/arm/libshizuku.so"
fi

echo "📦 Found starter at: $STARTER"

# --- The Crucial Execution Step ---
echo "🚀 Executing Shizuku via official starter..."

# 1. We use 'sh' to tell the system this .so is a script (Fixes ELF error)
# 2. We use 'nohup' and '&' to detach from the terminal (Fixes Aborted error)
adb -s $TARGET_SERIAL shell "nohup sh $STARTER start > /dev/null 2>&1 &"

# Final Verification
echo "🔍 Checking service status..."
sleep 3
if adb -s $TARGET_SERIAL shell ps -A | grep -q "shizuku_server"; then
    echo -e "\033[1;32m[SUCCESS]\033[0m Shizuku is now running in the background."
else
    echo -e "\033[1;31m[FAIL]\033[0m Service did not stay alive."
    echo "Tip: Check 'Disable adb authorization timeout' in Developer Options."
fi
EOF
  log_success "Launcher script created."
}

# --- 4. Generate Settings Shortcut (wf) ---

gen_wf_script() {
  print_step 3 $TOTAL_STEPS "Generating Settings Shortcut (wf)"
  local TARGET_FILE="${BIN_DIR}/wf"
  tee "${TARGET_FILE}" >/dev/null <<EOF
#!/data/data/com.termux/files/usr/bin/bash
echo "⚙️ Opening Wireless Debugging Settings..."
am start -a android.settings.APPLICATION_DEVELOPMENT_SETTINGS \\
  --es ":settings:fragment_args_key" "toggle_adb_wireless" > /dev/null 2>&1
EOF
  log_success "Shortcut script created."
}

# --- 5. Finalize Rish Shell ---

finalize_setup() {
  print_step 4 $TOTAL_STEPS "Deploying Rish & Finalizing"
  local RISH_FILE="${BIN_DIR}/rish"
  tee "${RISH_FILE}" >/dev/null <<EOF
#!/data/data/com.termux/files/usr/bin/bash
export RISH_APPLICATION_ID="com.termux"
/system/bin/app_process -Djava.class.path="${TARGET_DEX}" /system/bin --nice-name=rish rikka.shizuku.shell.ShizukuShellLoader "\${@}"
EOF
  cp -f "${SOURCE_DEX}" "${TARGET_DEX}"
  chmod +x "${BIN_DIR}/shizuku" "${BIN_DIR}/rish" "${BIN_DIR}/wf"
  log_success "All scripts installed."
}

# --- Main Entry ---

main() {
  printf "${CYAN}====================================================${NC}\n"
  printf "${CYAN}    ✨ Shizuku + Rish + ADB Deployment Tool ✨      ${NC}\n"
  printf "${CYAN}====================================================${NC}\n"
  check_env
  gen_shizuku_script
  gen_wf_script
  finalize_setup
  echo ""
  log_success "🎉 Done! Use 'wf', then 'shizuku <PORT>', then 'rish'."
}

main
