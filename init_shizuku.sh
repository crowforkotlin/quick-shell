#!/data/data/com.termux/files/usr/bin/bash

# ==============================================================================
# Script Name: Shizuku + Rish + ADB Setup Script (Ultimate Fix)
# Platform   : Android (Termux)
# Description: Automates Shizuku startup and Rish shell deployment.
# Fixes      : Dynamic pathing, multi-device errors, ELF execution, and Aborted error.
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

  log_info "Verifying 'rish_shizuku.dex' file..."
  if [ ! -f "${SOURCE_DEX}" ]; then
    log_error "File not found: ${SOURCE_DEX}"
    log_warn "Please ensure 'rish_shizuku.dex' is in the same folder as this script."
    exit 1
  fi

  log_info "Updating packages and installing android-tools..."
  pkg update -y >/dev/null 2>&1
  pkg install android-tools -y >/dev/null 2>&1
}

# --- 3. Generate Startup Script (shizuku) ---

gen_shizuku_script() {
  print_step 2 $TOTAL_STEPS "Generating Service Launcher (shizuku)"

  local TARGET_FILE="${BIN_DIR}/shizuku"
  log_info "Creating script: ${TARGET_FILE}"

  # Use single quotes around 'EOF' to prevent local shell from expanding variables
  tee "${TARGET_FILE}" >/dev/null <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

# Configuration
PORT=$1
TARGET_SERIAL="localhost:5555"

# Input Validation
if [ -z "$PORT" ]; then
    echo -e "\033[1;31m[ERROR]\033[0m Missing port number!"
    echo "Usage: shizuku <PORT>"
    exit 1
fi

# Fix Termux temp directory permissions
export TMPDIR=/data/data/com.termux/files/home/tmp
mkdir -p $TMPDIR

echo "🔄 Connecting to Wireless Debugging on port ${PORT}..."
adb connect "localhost:${PORT}"

# Handle multiple devices by forcing connection to 5555
echo "⚙️ Setting TCP/IP to 5555..."
adb -s "localhost:${PORT}" tcpip 5555
sleep 1
adb connect $TARGET_SERIAL

# --- Dynamic Path Resolution ---
echo "🚀 Locating Shizuku installation..."
PKG_PATH=$(adb -s $TARGET_SERIAL shell pm path moe.shizuku.privileged.api | cut -d':' -f2)

if [ -z "$PKG_PATH" ]; then
    echo -e "\033[1;31m[FAIL]\033[0m Shizuku app not found. Please install it first."
    exit 1
fi

echo "📦 Found Shizuku APK at: $PKG_PATH"

# --- Execute Shizuku via app_process (Fixed logic for 'Aborted' error) ---
echo "🚀 Sending start command via app_process..."

# Combining CLASSPATH export and app_process in a single string for execution
# This avoids the 'Aborted' error and correctly launches the Java class
START_CMD="export CLASSPATH=$PKG_PATH; exec app_process /system/bin rikka.shizuku.privileged.api.ShizukuLauncher"

adb -s $TARGET_SERIAL shell "$START_CMD"

# Verify if service is actually running
sleep 2
if adb -s $TARGET_SERIAL shell ps -A | grep -q "shizuku_server"; then
    echo -e "\033[1;32m[SUCCESS]\033[0m Shizuku service is now running."
else
    echo -e "\033[1;31m[FAIL]\033[0m Shizuku service failed to start or aborted."
    echo "Tip: Ensure 'Disable adb authorization timeout' is ON in Developer Options."
fi
EOF
  log_success "Launcher script created."
}

# --- 4. Generate Shortcut Script (wf) ---

gen_wf_script() {
  print_step 3 $TOTAL_STEPS "Generating Settings Shortcut (wf)"

  local TARGET_FILE="${BIN_DIR}/wf"
  log_info "Creating script: ${TARGET_FILE}"

  tee "${TARGET_FILE}" >/dev/null <<EOF
#!/data/data/com.termux/files/usr/bin/bash
echo "⚙️ Opening Wireless Debugging Settings..."
# Intent to open developer options and scroll to Wireless Debugging
am start -a android.settings.APPLICATION_DEVELOPMENT_SETTINGS \\
  --es ":settings:fragment_args_key" "toggle_adb_wireless" > /dev/null 2>&1
EOF
  log_success "Shortcut script created."
}

# --- 5. Generate Rish Shell & Finalize ---

finalize_setup() {
  print_step 4 $TOTAL_STEPS "Deploying Rish & Finalizing"

  # 1. Generate 'rish' wrapper
  local RISH_FILE="${BIN_DIR}/rish"
  log_info "Generating wrapper: ${RISH_FILE}"

  tee "${RISH_FILE}" >/dev/null <<EOF
#!/data/data/com.termux/files/usr/bin/bash
# Rish configuration
export RISH_APPLICATION_ID="com.termux"
/system/bin/app_process -Djava.class.path="${TARGET_DEX}" /system/bin --nice-name=rish rikka.shizuku.shell.ShizukuShellLoader "\${@}"
EOF

  # 2. Deploy Dex File
  log_info "Deploying Dex file..."
  cp -f "${SOURCE_DEX}" "${TARGET_DEX}"

  # 3. Set Permissions
  log_info "Setting executable permissions..."
  chmod +x "${BIN_DIR}/shizuku" "${BIN_DIR}/rish" "${BIN_DIR}/wf"

  log_success "All scripts installed."
}

# --- Main Entry Point ---

main() {
  clear
  printf "${CYAN}====================================================${NC}\n"
  printf "${CYAN}    ✨ Shizuku + Rish + ADB Deployment Tool ✨      ${NC}\n"
  printf "${CYAN}====================================================${NC}\n"

  check_env
  gen_shizuku_script
  gen_wf_script
  finalize_setup

  echo ""
  log_success "🎉 Deployment Completed Successfully!"
  echo ""
  printf "${YELLOW}Usage Guide:${NC}\n"
  printf "  1. Type ${WHITE}wf${NC}            -> Go to Settings, enable Wireless Debugging.\n"
  printf "  2. Type ${WHITE}shizuku <PORT>${NC} -> Start the Shizuku service.\n"
  printf "  3. Type ${WHITE}rish${NC}          -> Enter Shizuku Root Shell.\n"
}

main
