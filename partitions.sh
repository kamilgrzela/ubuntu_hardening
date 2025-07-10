#!/bin/bash

LOGFILE="partition_check.log"
> "$LOGFILE"  # Clear log file

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Define required mount points: [mount_point]="fs1,fs2:option1,option2"
declare -A PARTITIONS=(
  ["/"]="ext4:rw"
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

  if ! findmnt --target "$mount_point" > /dev/null 2>&1; then
    echo -e "${RED}❌ $mount_point is NOT mounted!${NC}"
    echo "ERROR: $mount_point is not mounted." >> "$LOGFILE"
    continue
  fi

  actual_fs=$(findmnt -n -o FSTYPE --target "$mount_point")
  actual_opts=$(findmnt -n -o OPTIONS --target "$mount_point")

  fs_ok=false
  IFS=',' read -ra allowed_fs <<< "$fs_types"
  for fs in "${allowed_fs[@]}"; do
    if [[ "$actual_fs" == "$fs" ]]; then
      fs_ok=true
      break
    fi
  done

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

  # Output result summary
  if $fs_ok && $opts_ok; then
    echo -e "${GREEN}✅ $mount_point: OK${NC}"
    echo "OK: $mount_point is mounted correctly with FSTYPE=$actual_fs and OPTIONS=$actual_opts" >> "$LOGFILE"
  else
    echo -e "${RED}❌ $mount_point: Not OK${NC}"
    echo "ISSUE: $mount_point has problems:" >> "$LOGFILE"

    if ! $fs_ok; then
      echo "  ❌ Filesystem type mismatch: $actual_fs (expected: $fs_types)" | tee -a "$LOGFILE"
    else
      echo "  ✅ Filesystem type OK: $actual_fs" >> "$LOGFILE"
    fi

    if ! $opts_ok; then
      echo "  ❌ Missing options: ${missing_opts[*]}" | tee -a "$LOGFILE"
    else
      echo "  ✅ Mount options OK" >> "$LOGFILE"
    fi

    # Skip remount suggestion for excluded points
    if [[ "$mount_point" == "/dev/shm" || "$mount_point" == "swap" ]]; then
      echo "  ⚠️  Skipping /etc/fstab update and remount for $mount_point (excluded)" >> "$LOGFILE"
      continue
    fi

    echo -en "${RED}❓ Do you want to update /etc/fstab and remount $mount_point? [y/N]: ${NC}"
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      echo "🔧 Backing up /etc/fstab to /etc/fstab.bak..."
      sudo cp /etc/fstab /etc/fstab.bak

      # Find matching uncommented line in /etc/fstab
      line_num=$(grep -nE "^[^#].*[[:space:]]$mount_point[[:space:]]" /etc/fstab | head -n 1 | cut -d: -f1)

      if [[ -n "$line_num" ]]; then
        old_line=$(sed -n "${line_num}p" /etc/fstab)
        old_opts=$(echo "$old_line" | awk '{print $4}')

        IFS=',' read -ra old_opt_array <<< "$old_opts"
        combined_opts=("${old_opt_array[@]}")

        for opt in "${missing_opts[@]}"; do
          if [[ ! ",${old_opts}," =~ ",${opt}," ]]; then
            combined_opts+=("$opt")
          fi
        done

        new_opts=$(IFS=','; echo "${combined_opts[*]}")
        new_line=$(echo "$old_line" | awk -v opts="$new_opts" '{$4=opts; print $0}')

        sudo sed -i "${line_num}s|.*|$new_line|" /etc/fstab
        echo "✅ Updated /etc/fstab entry for $mount_point." | tee -a "$LOGFILE"

        # Attempt remount
        echo "🔄 Remounting $mount_point with options: $new_opts"
        if sudo mount -o remount,"$new_opts" "$mount_point"; then
          echo -e "${GREEN}✅ Successfully remounted $mount_point.${NC}"
          echo "REMOUNTED: $mount_point with options: $new_opts" >> "$LOGFILE"
        else
          echo -e "${RED}❌ Remount failed for $mount_point.${NC}"
          echo "ERROR: Remount failed for $mount_point" >> "$LOGFILE"
        fi
      else
        echo "⚠️ Could not find a valid /etc/fstab entry for $mount_point." | tee -a "$LOGFILE"
      fi
    fi
  fi
done

echo -e "\n📄 Full log written to: ${LOGFILE}"
