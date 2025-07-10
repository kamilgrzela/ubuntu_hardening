#!/bin/bash

LOGFILE="partition_check.log"
> "$LOGFILE"  # Clear the log file

# ANSI color codes for colored output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Define mount points with expected filesystem types and required mount options
# Format: [mount_point]="fs1,fs2:opt1,opt2,opt3"
declare -A PARTITIONS=(
  ["/"]="ext4:defaults"
  ["/boot"]="ext4:nodev,nosuid"
  ["/home"]="ext4:nodev"
  ["/var"]="ext4:nodev,nosuid"
  ["/var/log"]="ext4:nodev,nosuid,noexec"
  ["/var/tmp"]="ext4:nodev,nosuid,noexec"
  ["/tmp"]="ext4,tmpfs:nodev,nosuid,noexec"
  ["/opt"]="ext4:nodev"
  ["/srv"]="ext4:nodev,nosuid"
  ["/dev/shm"]="tmpfs:nodev,nosuid,noexec"
  ["swap"]="swap:"
)

echo "🔍 Checking partition status, filesystem types, and mount options..."
echo "=== Partition Check Report === $(date)" >> "$LOGFILE"

# Iterate over each mount point
for mount_point in "${!PARTITIONS[@]}"; do
  IFS=':' read -r fs_types expected_opts <<< "${PARTITIONS[$mount_point]}"

  # Find line in /proc/mounts
  line=$(grep -E "[[:space:]]$mount_point[[:space:]]" /proc/mounts | head -n 1)

  if [ -z "$line" ]; then
    echo -e "${RED}❌ $mount_point is NOT mounted!${NC}"
    echo "ERROR: $mount_point is not mounted." >> "$LOGFILE"
    continue
  fi

  actual_fs=$(echo "$line" | awk '{print $3}')
  actual_opts=$(echo "$line" | awk '{print $4}')

  # Validate filesystem type
  fs_ok=false
  IFS=',' read -ra allowed_fs <<< "$fs_types"
  for fs in "${allowed_fs[@]}"; do
    if [[ "$actual_fs" == "$fs" ]]; then
      fs_ok=true
      break
    fi
  done

  # Validate required mount options
  opts_ok=true
  missing_opts=()

  if [[ -n "$expected_opts" ]]; then
    IFS=',' read -ra required_opts <<< "$expected_opts"
    for opt in "${required_opts[@]}"; do
      if [[ ! ",$actual_opts," =~ ",$opt," ]]; then
        opts_ok=false
        missing_opts+=("$opt")
      fi
    done
  fi

  # Report result
  if $fs_ok && $opts_ok; then
    echo -e "${GREEN}✅ $mount_point: OK${NC}"
  else
    echo -e "${RED}❌ $mount_point: Not OK${NC}"

    # Log details
    if ! $fs_ok; then
      echo "ERROR: $mount_point has wrong filesystem type: $actual_fs (expected: $fs_types)" >> "$LOGFILE"
      echo "   ❌ Filesystem type mismatch (got: $actual_fs, expected: $fs_types)"
    fi

    if ! $opts_ok; then
      echo "ERROR: $mount_point missing options: ${missing_opts[*]}" >> "$LOGFILE"
      for opt in "${missing_opts[@]}"; do
        echo "   ❌ Missing mount option: $opt"
      done
    fi
  fi
done

echo -e "\n📝 Check complete. See '${LOGFILE}' for full details."
