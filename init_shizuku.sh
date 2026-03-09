#!/data/data/com.termux/files/usr/bin/bash

# ==============================================================================
# Script Name: Shizuku + Rish + ADB Setup Script (Official Path Fix)
# Platform   : Android (Termux)
# Description: Automates Shizuku startup using the internal .so shell script.
# Fixes      : Stripped ADB carriage returns (\r), fixed execution syntax.
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
    RED=$(tput setaf 1; tput bold)
    GREEN=$(tput setaf 2; tput bold)
    YELLOW=$(tput setaf 3; tput bold)
    BLUE=$(tput setaf 4; tput bold)
    CYAN=$(tput setaf 6; tput bold)
    NC=$(tput sgr0)
else
    RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'
    BLUE='\033[1;34m'; CYAN='\033[1;36m'; NC='\033[0m'
fi

log_info()    { printf "${BLUE} 🔵 [INFO]${NC} %s\n" "$1"; }
log_success() { printf "${GREEN} 🟢 [PASS]${NC} %s\n" "$1"; }
log_warn()    { printf "${YELLOW} 🟡 [WARN]${NC} %s\n" "$1"; }
log_error()   { printf "${RED} 🔴 [FAIL]${NC} %s\n" "$1"; }

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
    pkg update -y > /dev/null 2>&1
    pkg install android-tools -y > /dev/null 2>&1
}

# --- 3. Generate Startup Script (shizuku) ---

gen_shizuku_script() {
    print_step 2 $TOTAL_STEPS "Generating Service Launcher (shizuku)"

    local TARGET_FILE="${BIN_DIR}/shizuku"
    log_info "Creating script: ${TARGET_FILE}"

    # Use 'EOF' to prevent local variable expansion
    tee "${TARGET_FILE}" > /dev/null << 'EOF'
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

# Give ADB daemon time to restart, then reconnect
sleep 3
adb connect $TARGET_SERIAL
sleep 1

# --- Dynamic Path Resolution (Finding that .so file) ---
echo "🚀 Locating Shizuku starter..."

# [FIX 1]: Added "tr -d '\r'" to remove carriage returns from ADB output.
# Without this, the string concatenation for STARTER will be corrupted.
PKG_PATH=$(adb -s $TARGET_SERIAL shell pm path moe.shizuku.privileged.api | grep base.apk | cut -d':' -f2 | sed 's/base.apk//g' | tr -d '\r')

if [ -z "$PKG_PATH" ]; then
    echo -e "\033[1;31m[FAIL]\033[0m Shizuku app not found. Is it installed?"
    exit 1
fi

# Construct the official .so starter path
STARTER="${PKG_PATH}lib/arm64/libshizuku.so"

# Fallback for 32-bit devices: strictly check if arm64 file is missing
if adb -s $TARGET_SERIAL shell "[ ! -f '$STARTER' ]"; then
    STARTER="${PKG_PATH}lib/arm/libshizuku.so"
fi

echo "📦 Found starter at: $STARTER"

# --- The Crucial Execution Step ---
echo "🚀 Executing Shizuku via official starter..."

#[FIX 2]: Execute cleanly using 'sh'. 
# REMOVED: 'nohup', '&', and 'start' argument.
# The libshizuku.so script handles its own daemonization automatically.
adb -s $TARGET_SERIAL shell "sh \"$STARTER\""

# Final Verification
echo "🔍 Checking service status..."
sleep 3
if adb -s $TARGET_SERIAL shell ps -A | grep -q "shizuku_server"; then
    echo -e "\033[1;32m[SUCCESS]\033[0m Shizuku is now running in the background."
else
    echo -e "\033[1;31m[FAIL]\033
