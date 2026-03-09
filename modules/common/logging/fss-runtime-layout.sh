#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# shellcheck shell=bash
# shellcheck disable=SC2034

# Shared helpers for discovering the runtime FSS layout on a deployed system.
#
# These helpers intentionally model the runtime layout used by the FSS module:
# - sealing keys live under /var/log/journal/<machine-id>/fss (or /run/... for volatile storage)
# - the setup service writes /var/log/journal/<machine-id>/fss-config with the authoritative key dir
# - verification keys live under /persist/common/journal-fss/<component> on host
# - verification keys live under /etc/common/journal-fss/<component> in VMs
#
# Runtime hostname and shared hardware-derived hostname can differ. The FSS key
# directory is keyed by the configured component name, not by the shared dynamic
# Ghaf identity. Prefer fss-config over hostname-based inference whenever possible.

fss_reset_runtime_layout() {
  FSS_RUNTIME_HOSTNAME=""
  FSS_KERNEL_HOSTNAME=""
  FSS_MACHINE_ID=""
  FSS_JOURNAL_DIR=""
  FSS_ACTIVE_SYSTEM_JOURNAL=""
  FSS_SEALING_KEY_PATH=""
  FSS_FSS_CONFIG_PATH=""
  FSS_FSS_ROTATED_PATH=""
  FSS_KEY_DIR=""
  FSS_KEY_DIR_SOURCE=""
  FSS_KEY_DIR_CANDIDATES=""
  FSS_COMPONENT_SCOPE="unknown"
  FSS_COMPONENT_NAME=""
  FSS_VERIFY_KEY_PATH=""
  FSS_INITIALIZED_PATH=""
}

fss_first_existing_path() {
  local candidate

  for candidate in "$@"; do
    if [ -e "$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done

  return 1
}

fss_discover_runtime_layout() {
  local candidate

  fss_reset_runtime_layout

  FSS_KERNEL_HOSTNAME="$(cat /proc/sys/kernel/hostname 2>/dev/null || true)"
  FSS_RUNTIME_HOSTNAME="$FSS_KERNEL_HOSTNAME"
  FSS_MACHINE_ID="$(cat /etc/machine-id 2>/dev/null || true)"

  if [ -n "$FSS_MACHINE_ID" ]; then
    for candidate in \
      "/var/log/journal/$FSS_MACHINE_ID" \
      "/run/log/journal/$FSS_MACHINE_ID"; do
      if [ -d "$candidate" ]; then
        FSS_JOURNAL_DIR="$candidate"
        break
      fi
    done

    FSS_ACTIVE_SYSTEM_JOURNAL="$(
      fss_first_existing_path \
        "/var/log/journal/$FSS_MACHINE_ID/system.journal" \
        "/run/log/journal/$FSS_MACHINE_ID/system.journal" ||
        true
    )"
    FSS_SEALING_KEY_PATH="$(
      fss_first_existing_path \
        "/var/log/journal/$FSS_MACHINE_ID/fss" \
        "/run/log/journal/$FSS_MACHINE_ID/fss" ||
        true
    )"
    FSS_FSS_CONFIG_PATH="$(
      fss_first_existing_path \
        "/var/log/journal/$FSS_MACHINE_ID/fss-config" \
        "/run/log/journal/$FSS_MACHINE_ID/fss-config" ||
        true
    )"
    FSS_FSS_ROTATED_PATH="$(
      fss_first_existing_path \
        "/var/log/journal/$FSS_MACHINE_ID/fss-rotated" \
        "/run/log/journal/$FSS_MACHINE_ID/fss-rotated" ||
        true
    )"
  fi

  if [ -n "$FSS_RUNTIME_HOSTNAME" ]; then
    FSS_KEY_DIR_CANDIDATES="$(printf '%s\n%s' \
      "/persist/common/journal-fss/$FSS_RUNTIME_HOSTNAME" \
      "/etc/common/journal-fss/$FSS_RUNTIME_HOSTNAME")"
  fi

  if [ -n "$FSS_FSS_CONFIG_PATH" ] && [ -s "$FSS_FSS_CONFIG_PATH" ]; then
    FSS_KEY_DIR="$(cat "$FSS_FSS_CONFIG_PATH")"
    FSS_KEY_DIR_SOURCE="fss-config"
  else
    for candidate in \
      "/persist/common/journal-fss/$FSS_RUNTIME_HOSTNAME" \
      "/etc/common/journal-fss/$FSS_RUNTIME_HOSTNAME"; do
      if [ -d "$candidate" ]; then
        FSS_KEY_DIR="$candidate"
        FSS_KEY_DIR_SOURCE="hostname-fallback"
        break
      fi
    done
  fi

  if [ -n "$FSS_KEY_DIR" ]; then
    FSS_COMPONENT_NAME="$(basename "$FSS_KEY_DIR")"
    FSS_VERIFY_KEY_PATH="$FSS_KEY_DIR/verification-key"
    FSS_INITIALIZED_PATH="$FSS_KEY_DIR/initialized"

    case "$FSS_KEY_DIR" in
    /persist/common/journal-fss/*)
      FSS_COMPONENT_SCOPE="host"
      ;;
    /etc/common/journal-fss/*)
      FSS_COMPONENT_SCOPE="vm"
      ;;
    esac
  fi
}
