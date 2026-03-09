#!/data/data/com.termux/files/usr/bin/bash

# ==============================================================================
# Script Name: Shizuku + Rish + ADB Setup Script (Fixed)
# Platform   : Android (Termux)
# Description: Automates Shizuku startup. Fixed ELF execution and process keep-alive.
# Fix Notes  :
#   - libshizuku.so is a native ELF binary, NOT a shell script. Never use "sh" on it.
#   - The correct launch method is direct execution or via the internal app_process call.
#   - To survive Phantom Process Killer, we use a foreground adb shell approach.
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

  # Use 'EOF' (quoted) to prevent local variable expansion inside heredoc
  tee "${TARGET_FILE}" >/dev/null <<'SHIZUKU_EOF'
#!/data/data/com.termux/files/usr/bin/bash

PORT=$1
TARGET_SERIAL="localhost:5555"

if [ -z "$PORT" ]; then
    echo -e "\033[1;31m[ERROR]\033[0m Missing port number!"
    echo "Usage: shizuku <PORT>"
    exit 1
fi

# Create a temp dir for adb/shizuku runtime use
export TMPDIR=/data/data/com.termux/files/home/tmp
mkdir -p "$TMPDIR"

echo "🔄 Connecting to Wireless Debugging on port ${PORT}..."
adb connect "localhost:${PORT}"

echo "⚙️  Setting TCP/IP mode to port 5555..."
adb -s "localhost:${PORT}" tcpip 5555
sleep 1
adb connect "$TARGET_SERIAL"

# --- Dynamic Path Resolution: locate the Shizuku APK install path ---
echo "🔍 Locating Shizuku package path..."
PKG_PATH=$(adb -s "$TARGET_SERIAL" shell pm path moe.shizuku.privileged.api \
    | tr -d '\r' \
    | cut -d':' -f2 \
    | sed 's/base\.apk[[:space:]]*//')

if [ -z "$PKG_PATH" ]; then
    echo -e "\033[1;31m[FAIL]\033[0m Shizuku app not installed or not found."
    exit 1
fi

echo "📦 Package base path: ${PKG_PATH}"

# --- Locate the native ELF starter binary ---
# libshizuku.so is a real ELF executable, NOT a shell script.
# Try arm64 first, fall back to arm (32-bit devices).
STARTER_ARM64="${PKG_PATH}lib/arm64/libshizuku.so"
STARTER_ARM32="${PKG_PATH}lib/arm/libshizuku.so"

if adb -s "$TARGET_SERIAL" shell "[ -f '${STARTER_ARM64}' ]" 2>/dev/null; then
    STARTER="$STARTER_ARM64"
    echo "📐 Architecture: arm64"
elif adb -s "$TARGET_SERIAL" shell "[ -f '${STARTER_ARM32}' ]" 2>/dev/null; then
    STARTER="$STARTER_ARM32"
    echo "📐 Architecture: arm (32-bit fallback)"
else
    echo -e "\033[1;31m[FAIL]\033[0m libshizuku.so not found in either arm64 or arm path."
    exit 1
fi

echo "📦 Starter ELF: ${STARTER}"

# --- The Crucial Fix: Execute the ELF binary directly ---
#
# WHY THIS WORKS:
#   libshizuku.so is an ELF native executable that starts the Shizuku server.
#   It must be called directly — using "sh libshizuku.so" causes an ELF syntax
#   error because sh tries to interpret binary bytes as shell commands.
#
# HOW WE BEAT THE PHANTOM PROCESS KILLER:
#   Android 12+ kills background processes forked from adb shell.
#   Solution: run it with setsid to create a new session, detached from the
#   adb shell's process group. This prevents SIGHUP from killing the server
#   when the adb connection drops.
#
# The command breakdown:
#   setsid         → detach from terminal session (new process group)
#   $STARTER start → execute the ELF binary with "start" argument
#   </dev/null     → disconnect stdin
#   >/dev/null 2>&1 → suppress all output
#   &              → run in background immediately
#
echo "🚀 Executing Shizuku server (direct ELF execution)..."
adb -s "$TARGET_SERIAL" shell "setsid '${STARTER}' start </dev/null >/dev/null 2>&1 &"

# Give the server time to initialize before we check
echo "⏳ Waiting for server to initialize..."
sleep 4

# --- Final Verification ---
echo "🔍 Checking for running shizuku_server process..."
if adb -s "$TARGET_SERIAL" shell ps -A 2>/dev/null | grep -q "shizuku_server"; then
    echo -e "\033[1;32m[SUCCESS]\033[0m Shizuku server is running in the background! ✅"
    echo ""
    echo "  👉 Now run: rish"
else
    echo -e "\033[1;31m[FAIL]\033[0m Shizuku server did not stay alive."
    echo ""
    echo "  Troubleshooting tips:"
    echo "  1. Enable 'Disable adb authorization timeout' in Developer Options."
    echo "  2. Make sure Wireless Debugging is still enabled."
    echo "  3. On MIUI/HyperOS: disable 'MIUI optimization' and reboot."
    echo "  4. Try opening the Shizuku app manually and tapping 'Start via adb'."
    echo "  5. Check: adb -s localhost:5555 shell ls '${STARTER}'"
fi
SHIZUKU_EOF

  log_success "Launcher script created."
}

# --- 4. Generate Settings Shortcut (wf) ---

gen_wf_script() {
  print_step 3 $TOTAL_STEPS "Generating Settings Shortcut (wf)"
  local TARGET_FILE="${BIN_DIR}/wf"

  # Note: Variables ARE expanded here (no quotes on EOF), which is intentional
  # since this script has no dynamic variables to protect.
  tee "${TARGET_FILE}" >/dev/null <<'WF_EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Open Developer Options settings page directly (shortcut for enabling Wireless Debugging)
echo "⚙️  Opening Developer Options / Wireless Debugging Settings..."
am start -a android.settings.APPLICATION_DEVELOPMENT_SETTINGS \
  --es ":settings:fragment_args_key" "toggle_adb_wireless" > /dev/null 2>&1
WF_EOF

  log_success "Settings shortcut (wf) created."
}

# --- 5. Finalize Rish Shell ---

finalize_setup() {
  print_step 4 $TOTAL_STEPS "Deploying Rish & Finalizing"
  local RISH_FILE="${BIN_DIR}/rish"

  # Write the rish launcher — this uses app_process to load the dex shell loader.
  # TARGET_DEX is expanded here intentionally (no single-quotes on EOF marker).
  tee "${RISH_FILE}" >/dev/null <<EOF
#!/data/data/com.termux/files/usr/bin/bash
# rish: Shizuku-powered elevated shell via app_process + dex class loader
export RISH_APPLICATION_ID="com.termux"
/system/bin/app_process \\
    -Djava.class.path="${TARGET_DEX}" \\
    /system/bin \\
    --nice-name=rish \\
    rikka.shizuku.shell.ShizukuShellLoader "\${@}"
EOF

  # Copy the dex file to home directory (app_process needs a stable path)
  cp -f "${SOURCE_DEX}" "${TARGET_DEX}"

  # Make all three scripts executable
  chmod +x "${BIN_DIR}/shizuku" "${BIN_DIR}/rish" "${BIN_DIR}/wf"

  log_success "All scripts installed and marked executable."
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
  log_success "🎉 Setup complete!"
  echo ""
  echo "  Usage:"
  echo "  1. Run ${CYAN}wf${NC}               → Open Developer Options"
  echo "  2. Enable Wireless Debugging, note the PORT"
  echo "  3. Run ${CYAN}shizuku <PORT>${NC}    → Start Shizuku server"
  echo "  4. Run ${CYAN}rish${NC}              → Enter elevated shell"
  echo ""
}

main
