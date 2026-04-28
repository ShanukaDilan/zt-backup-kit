# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Pull-mode setup scripts (planned)
- Healthchecks.io integration (planned)
- Slack/ntfy.sh notifications (planned)
- Native B2/S3 backend examples (planned)
- systemd timer alternative to cron (planned)

## [0.1.0] - 2026-04-28

### Added
- Initial public release.
- `bin/backup.sh` — automated Restic backup with multi-target support, retention,
  integrity checks, and HTML email reports.
- `bin/restore.sh` — interactive restore with full / partial / mount / list modes.
- `bin/emergency-restore.sh` — bootstrap recovery on a clean Linux/Mac/WSL machine.
- `config/config.example.sh` — template configuration with extensive comments.
- Documentation: `INSTALL.md`, `USAGE.md`, `ARCHITECTURE.md`, `DR-RUNBOOK.md`, `FAQ.md`.
- Granular Restic exit-code handling (distinguishes partial-success warnings from
  hard failures).
- Default exclusion patterns for shell history, caches, logs, build artifacts.
- Cron-safe PATH handling and `flock` overlap protection.
- Configurable rclone throttling for Google Drive API quota friendliness.

### Security
- Credentials and config files are git-ignored by default.
- Restic password file enforced to mode 400 in setup instructions.
- All sensitive identifiers removed from default config template.

[Unreleased]: https://github.com/ShanukaDilan/zt-backup-kit/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ShanukaDilan/zt-backup-kit/releases/tag/v0.1.0
