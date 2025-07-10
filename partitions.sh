#!/bin/bash

LOGFILE="partition_check.log"
> "$LOGFILE"  # Clear previous log file

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Define mount points with expected fs types and options
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

echo "🔍 Starting partition check with findmnt..."
echo "=== Partition Check Report === $(date)" >> "$LOGFILE"

for mount_point in "${!PARTITIONS[@]}"; do
  IFS=':' read -r fs_types expected_opts <<< "${PARTITIONS[$mount_point]}"

  # Check if mount point exists
  if ! findmnt --target "$mount_point" > /dev/null 2>&1; then
    echo -e "${RED}❌ $mount_point is NOT mounted!${NC}"
    echo "ERROR: $mount_point is not mounted." >> "$LOGFILE"
    continue
  fi

  # Get actual filesystem and mount options
  actual_fs=$(findmnt -n -o FSTYPE --target "$mount_point")
  actual_opts=$(findmnt -n -o OPTIONS --target "$mount_point")

  # Check filesystem type
  fs_ok=false
  IFS=',' read -ra allowed_fs <<< "$fs_types"
  for fs in "${allowed_fs[@]}"; do
    if [[ "$actual_fs" == "$fs" ]]; then
      fs_ok=true
      break
    fi
  done

  # Check mount options
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

  # Output result
  if $fs_ok && $opts_ok; then
    echo -e "${GREEN}✅ $mount_point: OK${NC}"
  else
    echo -e "${RED}❌ $mount_point: Not OK${NC}"
    if ! $fs_ok; then
      echo "ERROR: $mount_point wrong fs type: $actual_fs (expected: $fs_types)" >> "$LOGFILE"
      echo "   ❌ Filesystem type mismatch: $actual_fs (expected: $fs_types)"
    fi
    if ! $opts_ok; then
      echo "ERROR: $mount_point missing options: ${missing_opts[*]}" >> "$LOGFILE"
      for opt in "${missing_opts[@]}"; do
        echo "   ❌ Missing mount option: $opt"
      done

      # Prompt to update /etc/fstab
      echo -en "${RED}❓ Do you want to update /etc/fstab for $mount_point? [y/N]: ${NC}"
      read -r answer
      if [[ "$answer" =~ ^[Yy]$ ]]; then
        echo "🔧 Backing up /etc/fstab to /etc/fstab.bak..."
        sudo cp /etc/fstab /etc/fstab.bak

        # Find line number with matching mount point
        line_num=$(grep -nE "^[^#].*[[:space:]]$mount_point[[:space:]]" /etc/fstab | head -n 1 | cut -d: -f1)

        if [[ -n "$line_num" ]]; then
          old_line=$(sed -n "${line_num}p" /etc/fstab)
          old_opts=$(echo "$old_line" | awk '{print $4}')
          
          # Merge old and missing options
          IFS=',' read -ra old_opt_array <<< "$old_opts"
          combined_opts=("${old_opt_array[@]}")

          for opt in "${missing_opts[@]}"; do
            if [[ ! ",${old_opts}," =~ ",${opt}," ]]; then
              combined_opts+=("$opt")
            fi
          done

          new_opts=$(IFS=','; echo "${combined_opts[*]}")
          new_line=$(echo "$old_line" | awk -v opts="$new_opts" '{$4=opts; print $0}')

          # Update the line in /etc/fstab
          sudo sed -i "${line_num}s|.*|$new_line|" /etc/fstab
          echo "✅ Updated /etc/fstab entry for $mount_point."
        else
          echo "⚠️ Could not find $mount_point in /etc/fstab!"
        fi
      fi
    fi
  fi
done

echo -e "\n📝 Check complete. See '${LOGFILE}' for full details."
