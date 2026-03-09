#!/data/data/com.termux/files/usr/bin/bash

# ==============================================================================
# Script Name: Shizuku + Rish + ADB Setup Script (Fixed)
# Platform   : Android (Termux)
# Description: Automates Shizuku startup and Rish shell deployment.
# Fixes      : Dynamic pathing, multi-device errors, and ELF binary execution.
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
    log_warn "Please ensure the .dex file is in the same folder as this script."
    exit 1
  fi

  log_info "Installing/Updating android-tools..."
  pkg update -y >/dev/null 2>&1
  pkg install android-tools -y >/dev/null 2>&1
}

# --- 3. Generate Startup Script (shizuku) ---

gen_shizuku_script() {
  print_step 2 $TOTAL_STEPS "Generating Service Launcher (shizuku)"

  local TARGET_FILE="${BIN_DIR}/shizuku"
  log_info "Creating script: ${TARGET_FILE}"

  # Use single quotes around 'EOF' to prevent local variable expansion
  tee "${TARGET_FILE}" >/dev/null <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

# Configuration
PORT=$1
TARGET_SERIAL="localhost:5555"

# Validation
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

# Resolve "more than one device" conflict by switching to 5555
echo "⚙️ Setting TCP/IP to 5555..."
adb -s "localhost:${PORT}" tcpip 5555
sleep 1
adb connect $TARGET_SERIAL

# --- Dynamic Path Resolution ---
echo "🚀 Locating Shizuku installation..."

# Query the system for the APK path (Fixes "inaccessible or not found")
PKG_PATH=$(adb -s $TARGET_SERIAL shell pm path moe.shizuku.privileged.api | cut -d':' -f2)

if [ -z "$PKG_PATH" ]; then
    echo -e "\033[1;31m[FAIL]\033[0m Shizuku app not found on device."
    exit 1
fi

echo "📦 Found Shizuku APK at: $PKG_PATH"

# --- Execute Shizuku via app_process (Fixes ELF Syntax Error) ---
echo "🚀 Sending start command via app_process..."

# Modern Shizuku starting method using Java class loader
adb -s $TARGET_SERIAL shell "CLASSPATH=$PKG_PATH app_process /system/bin rikka.shizuku.privileged.api.ShizukuLauncher"

if [ $? -eq 0 ]; then
    echo -e "\033[1;32m[SUCCESS]\033[0m Shizuku service started."
else
    echo -e "\033[1;31m[FAIL]\033[0m Failed to start Shizuku service."
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
am start -a android.settings.APPLICATION_DEVELOPMENT_SETTINGS \\
  --es ":settings:fragment_args_key" "toggle_adb_wireless" > /dev/null 2>&1
EOF
  log_success "Shortcut script created."
}

# --- 5. Generate Rish Shell & Finalize ---

finalize_setup() {
  print_step 4 $TOTAL_STEPS "Deploying Rish & Finalizing"

  # Generate 'rish' wrapper
  local RISH_FILE="${BIN_DIR}/rish"
  log_info "Generating wrapper: ${RISH_FILE}"

  tee "${RISH_FILE}" >/dev/null <<EOF
#!/data/data/com.termux/files/usr/bin/bash
export RISH_APPLICATION_ID="com.termux"
/system/bin/app_process -Djava.class.path="${TARGET_DEX}" /system/bin --nice-name=rish rikka.shizuku.shell.ShizukuShellLoader "\${@}"
EOF

  # Deploy Dex file
  log_info "Deploying Dex file..."
  cp -f "${SOURCE_DEX}" "${TARGET_DEX}"

  # Set Permissions
  log_info "Setting executable permissions..."
  chmod +x "${BIN_DIR}/shizuku" "${BIN_DIR}/rish" "${BIN_DIR}/wf"

  log_success "All scripts installed."
}

# --- Main Entry Point ---

main() {
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
  printf "  1. Type ${WHITE}wf${NC}            -> Enable Wireless Debugging (check the port).\n"
  printf "  2. Type ${WHITE}shizuku <PORT>${NC} -> Connect and start Shizuku service.\n"
  printf "  3. Type ${WHITE}rish${NC}          -> Enter Shizuku Root Shell.\n"
}

main
