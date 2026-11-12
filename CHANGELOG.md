# Changelog

## v1.0.0 - 2026-11-11

- RT Kit GUI with dark theme and sidebar navigation
- Technician login with encrypted cloud vault (PBKDF2 + AES-256 + HMAC)
- USB Backup module (robocopy) with per-client reports
- Backup Agent: nightly rclone sync as a SYSTEM scheduled task, 30-day version archive, healthchecks.io support
- Virus Scan (Microsoft Defender), Disk Cleaner, Network checker with diagnosis, Firewall control
- `backup.bat` for WinRE / Advanced Startup
- `build-exe.ps1` to compile RTKit.exe with ps2exe
