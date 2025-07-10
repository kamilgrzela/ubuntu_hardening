#!/bin/bash

LOGFILE="partition_check.log"
> "$LOGFILE"  # Clear previous log file

# ANSI color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Define required mount points, expected filesystem types, and required mount options
# Format: [mount_point]="fs_type1,fs_type2:required_option1,required_option2"
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

echo "🔍 Checking partition mount status and options..."
echo "=== Partition Check Report === $(date)" >> "$LOGFILE"

# Loop through each defined partition
for mount_point in "${!PARTITIONS[@]}"; do
  # Split values: filesystem types and expected mount options
  IFS=':' read -r fs_types expected_opts <<< "${PARTITIONS[$mount_point]}"

  # Search for the mount point in /proc/mounts
  line=$(grep -E "[[:space:]]$mount_point[[:space:]]" /proc/mounts | head -n 1)

  # If not found, report missing mount
  if [ -z "$line" ]; then
    echo -e "${RED}❌ $mount_point is NOT mounted!${NC}"
    echo "ERROR: $mount_point is not mounted." >> "$LOGFILE"
    continue
  fi

  # Extract actual filesystem type and mount options
  actual_fs=$(echo "$line" | awk '{print $3}')
  actual_opts=$(echo "$line" | awk '{print $4}')

  # Check if the actual filesystem matches any of the expected types
  fs_ok=false
  IFS=',' read -ra allowed_fs <<< "$fs_types"
  for fs in "${allowed_fs[@]}"; do
    if [[ "$actual_fs" == "$fs" ]]; then
      fs_ok=true
      break
    fi
  done

  # Check if all required mount options are present
  opts_ok=true
  if [[ -n "$expected_opts" ]]; then
    IFS=',' read -ra required_opts <<< "$expected_opts"
    for opt in "${required_opts[@]}"; do
      if [[ ! ",$actual_opts," =~ ",$opt," ]]; then
        opts_ok=false
        echo "ERROR: $mount_point missing option: $opt" >> "$LOGFILE"
      fi
    done
  fi

  # Summary: print OK or Not OK and log errors if any
  if $fs_ok && $opts_ok; then
    echo -e "${GREEN}✅ $mount_point: OK${NC}"
  else
    echo -e "${RED}❌ $mount_point: Not OK${NC}"
    if ! $fs_ok; then
      echo "ERROR: $mount_point has incorrect filesystem type: $actual_fs (expected: $fs_types)" >> "$LOGFILE"
    fi
  fi
done

echo "📝 Check complete. See $LOGFILE for details."
