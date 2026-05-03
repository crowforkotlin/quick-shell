#!/bin/sh
set -eu

resolve_root_home() {
  if command -v getent >/dev/null 2>&1; then
    root_home=$(getent passwd root | awk -F: 'NR==1 { print $6 }')
  else
    root_home=$(awk -F: '$1 == "root" { print $6; exit }' /etc/passwd 2>/dev/null || true)
  fi

  if [ -z "${root_home:-}" ]; then
    root_home=/root
  fi

  printf '%s\n' "$root_home"
}

resolve_source_home() {
  local source_user source_home

  source_user="${QUICK_SHELL_SOURCE_USER:-}"
  if [ -z "$source_user" ] || [ "$source_user" = "root" ]; then
    source_user=$(stat -c '%U' "$SCRIPT_DIR" 2>/dev/null || true)
  fi

  if [ -z "$source_user" ] || [ "$source_user" = "root" ]; then
    return 1
  fi

  if command -v getent >/dev/null 2>&1; then
    source_home=$(getent passwd "$source_user" | awk -F: 'NR==1 { print $6 }')
  else
    source_home=$(awk -F: -v user="$source_user" '$1 == user { print $6; exit }' /etc/passwd 2>/dev/null || true)
  fi

  if [ -z "${source_home:-}" ] || [ ! -d "$source_home" ]; then
    return 1
  fi

  printf '%s\n' "$source_home"
}

sync_starship_config() {
  local source_home source_config target_config

  source_home=$(resolve_source_home || true)
  if [ -z "$source_home" ]; then
    return 0
  fi

  source_config="$source_home/.config/starship.toml"
  target_config="$ROOT_HOME/.config/starship.toml"

  if [ ! -f "$source_config" ]; then
    return 0
  fi

  mkdir -p "$(dirname "$target_config")"
  cp -f "$source_config" "$target_config"
  export STARSHIP_CONFIG="$target_config"
}

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
SOURCE_SCRIPT="$SCRIPT_DIR/init_zsh.sh"

if [ ! -f "$SOURCE_SCRIPT" ]; then
  printf '%s\n' "Missing sibling script: $SOURCE_SCRIPT" >&2
  exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
  printf '%s\n' "Please switch to root with su first, then run this script again." >&2
  exit 1
fi

if ! command -v bash >/dev/null 2>&1; then
  printf '%s\n' "bash is required, but it was not found in PATH." >&2
  exit 1
fi

ROOT_HOME=$(resolve_root_home)
export HOME="$ROOT_HOME"
export USER=root
export LOGNAME=root
export QUICK_SHELL_TARGET_DIR="$SCRIPT_DIR"

if [ "${QUICK_SHELL_KEEP_PROXY:-0}" != "1" ]; then
  unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
fi

if [ -z "${SHELL:-}" ] || [ ! -x "${SHELL}" ]; then
  export SHELL="$(command -v bash)"
fi

sync_starship_config

TMP_SCRIPT=$(mktemp "${TMPDIR:-/tmp}/init_zsh_root.XXXXXX")

cleanup() {
  rm -f "$TMP_SCRIPT"
}

trap cleanup EXIT HUP INT TERM

sed \
  -e 's|^TARGET_DIR="\$HOME/quick_shell"$|TARGET_DIR="${QUICK_SHELL_TARGET_DIR:-$HOME/quick_shell}"|' \
  -e 's|SUDO="sudo"|SUDO=""|g' \
  "$SOURCE_SCRIPT" >"$TMP_SCRIPT"

chmod +x "$TMP_SCRIPT"
exec bash "$TMP_SCRIPT"
