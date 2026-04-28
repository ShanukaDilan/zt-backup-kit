---
name: Bug report
about: Something isn't working as documented
title: '[BUG] '
labels: bug
assignees: ''
---

## What happened?

A clear description of the bug.

## What did you expect?

What should have happened instead.

## Steps to reproduce

1. Configure as: ...
2. Run: `./bin/backup.sh ...`
3. See: ...

## Environment

- OS and version: (e.g. Ubuntu 22.04)
- restic version: (output of `restic version`)
- rclone version: (output of `rclone version`)
- zt-backup-kit version / commit: (output of `git rev-parse HEAD`)
- Backup target type: (Google Drive / B2 / S3 / SFTP / local)

## Logs

Paste relevant excerpts from `~/.zt-backup-kit/logs/backup-*.log`.

⚠️ **DO NOT paste credentials, OAuth tokens, or restic passwords.**
Redact them with `[REDACTED]` before pasting.

```
(log excerpt)
```

## Configuration

Paste the relevant section of your `config.sh` (with secrets redacted).

```bash
SRC_PATHS_RAW="..."
TARGETS=( "..." )
```

## Additional context

Anything else that might help.
