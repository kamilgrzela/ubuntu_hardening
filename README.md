# ubuntu_hardening
Scripts which helps harden Ubuntu System (version 22.04) according to CIS Benchmark + Test Cases

Partition structure

Mount Point      Filesystem Type    Suggested Size    Mount Options    Purpose / Notes
/                ext4                15–25 GB          defaults        Root filesystem
/boot            ext4                512 MB – 1 GB     nodev,nosuid    Kernel, bootloader
/home            ext4              Varies by users      nodev          User data
/var             ext4                20 GB             nodev,nosuid    Logs, mail, APT cache
/var/log         ext4                10 GB          nodev,nosuid,noexec  System logs (separate to prevent log flooding)
/var/tmp         ext4                 4 GB          nodev,nosuid,noexec  Temporary files across reboots
/tmp          ext4 or tmpfs           4 GB          nodev,nosuid,noexec   Session-based temp files
/opt             ext4              Optional            nodev              third-party apps
/srv             ext4              Optional          nodev,nosuid      Public services (e.g., www, ftp)
/dev/shm         tmpfs        RAM-based (dynamic)  nodev,nosuid,noexec  Shared memory (IPC); must be restricted
swap             swap          2x RAM or 4–8 GB     (no mount options)    System memory support


Source CIS Ubuntu Benchmark
