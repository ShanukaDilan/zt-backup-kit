<h1 align="center">🔒 zt-backup-kit</h1>
<p align="center">
  <b>Zero-Trust Backup &amp; Restore Kit</b><br>
  Ransomware-resilient automated backup system for Linux servers
</p>

<p align="center">
  <a href="https://doi.org/10.5281/zenodo.19849290"><img alt="DOI" src="https://zenodo.org/badge/DOI/10.5281/zenodo.19849290.svg"></a>
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-blue.svg"></a>
  <img alt="Bash" src="https://img.shields.io/badge/shell-bash-89e051.svg">
  <img alt="Linux" src="https://img.shields.io/badge/platform-linux%20%7C%20macOS-lightgrey.svg">
  <img alt="Status" src="https://img.shields.io/badge/status-active-success.svg">
</p>

---

A practical, opinionated wrapper around [restic](https://restic.net) that turns
"I should set up backups" into a one-evening project — with a documented
recovery process you can actually use under pressure.

It is designed around a **Zero-Trust mindset**: backups should be encrypted
before leaving the server, the production host should not have write access
to old snapshots, and recovery should be possible from any clean machine
without trusting the original system's credentials.

> ⚠️ **Status:** v0.1 — works in production, but expect rough edges. Issues and
> PRs welcome.

## Why another backup tool?

Most "backup scripts" you find online stop at "the data is somewhere off-site."
That's only half the problem. The other half is *getting it back*, fast,
under stress, possibly on a different machine, possibly without the original
admin around. This kit provides:

- An automated, encrypted, deduplicated backup pipeline (`backup.sh`)
- An interactive, safe restore tool (`restore.sh`)
- A bootstrap recovery script that works on any clean Linux/macOS machine (`emergency-restore.sh`)
- A status inspector showing snapshots, sizes, and dedup ratio (`backup-status.sh`)
- A documented disaster recovery runbook (`docs/DR-RUNBOOK.md`)

You configure it once, it runs from cron, it emails you a styled HTML report,
and when you actually need to restore something, you have three documented
ways to do it.

## Features

| | |
|---|---|
| 🔐 **Encryption by default** | AES-256 via Restic. Cloud providers see encrypted blobs. |
| 🧬 **Deduplication** | Content-defined chunking. Daily backups of static data are nearly free. |
| ☁️ **Multi-target** | Google Drive, Backblaze B2, AWS S3, Wasabi, Azure, SFTP/NAS, local disk |
| 📧 **Reporting** | Styled HTML email reports per run, with logs attached |
| 🛡️ **Granular exit handling** | Distinguishes full success, partial success (unreadable files), real failures |
| 🚫 **Sensible exclusions** | Skips bash history, caches, logs, build artifacts, OS junk by default |
| 🔄 **Retention** | Configurable daily/weekly/monthly retention with weekly prune |
| 🔍 **Integrity checks** | Periodic sample verification of stored data |
| 🔒 **Locking** | `flock`-based; concurrent runs are detected and skipped |
| ⚙️ **Cron-friendly** | Hardened PATH, no interactive prompts, idempotent |
| 📋 **Documented recovery** | Three restore scenarios, paper-printable runbook |

## Quickstart

```bash
# 1. Get the code
git clone https://github.com/ShanukaDilan/zt-backup-kit.git
cd zt-backup-kit

# 2. Install dependencies (Debian/Ubuntu)
sudo apt install -y restic rclone jq msmtp gpg

# 3. Configure
cp config/config.example.sh config/config.sh
chmod 600 config/config.sh
nano config/config.sh   # edit sources, target, email, etc.

# 4. Set the encryption password
echo 'a-long-random-password-you-write-on-paper' > ~/.restic-pass
chmod 400 ~/.restic-pass

# 5. Set up your cloud target (e.g. Google Drive)
rclone config        # follow prompts to add your cloud remote

# 6. Validate
./bin/backup.sh --check

# 7. First run
./bin/backup.sh

# 8. Schedule with cron
crontab -e
# Add: 30 2 * * * /path/to/zt-backup-kit/bin/backup.sh
```

See [docs/INSTALL.md](docs/INSTALL.md) for detailed setup, including using
your own Google Cloud OAuth credentials to avoid shared-quota rate limits.

## Recovery

### Lost a file? Need yesterday's version?

```bash
./bin/restore.sh
# Pick: latest, mode 2 (Partial restore), enter the file path
```

### Server destroyed? Need to recover from another machine?

```bash
# On a clean Linux/Mac/WSL device:
./bin/emergency-restore.sh
# Walks you through tool install, rclone config, and restore
```

### Full server rebuild?

See [docs/DR-RUNBOOK.md](docs/DR-RUNBOOK.md) — Scenario B has the step-by-step.

## Status &amp; inspection

`backup-status.sh` is your at-a-glance health check. Run it anytime to see
the state of the repository:

```bash
./bin/backup-status.sh                # full report
./bin/backup-status.sh --short        # one-page summary
./bin/backup-status.sh --runs         # only the last 15 runs
./bin/backup-status.sh --json         # machine-readable JSON
```

It shows snapshot count, file count, logical vs. stored size, deduplication
ratio, freshness of the latest snapshot (color-coded), recent run history,
and whether your cron schedule is installed correctly.

The `--json` mode is suitable for monitoring integrations (Healthchecks.io,
Prometheus textfile, Grafana, custom dashboards).

## Architecture

zt-backup-kit can run in two architectural modes:

**Push mode (simple):** the server itself runs `backup.sh` from cron and
pushes encrypted data to a cloud target (Google Drive, S3, B2, etc.).
Adversary on the production server cannot delete remote backups directly,
but could potentially corrupt new snapshots before they upload.

**Pull mode (more secure):** a separate "vault" host pulls data from the
production server over SSH on a schedule. The production server has no
credentials to reach the vault. Even with full root compromise of production,
the historical snapshots on the vault remain immutable.

This kit currently ships with the push-mode setup. Pull-mode configuration
is on the roadmap (see Issues #1).

```
                        Push mode (default)
   ┌──────────────┐                       ┌────────────────┐
   │  Production  │  ── encrypted data ─▶ │ Cloud / NAS /  │
   │   Server     │                       │   Local disk   │
   │ (backup.sh)  │                       │ (Restic repo)  │
   └──────────────┘                       └────────────────┘

                        Pull mode (planned)
   ┌──────────────┐                       ┌────────────────┐
   │  Production  │  ◀── SSH read-only ── │  Vault host    │
   │   Server     │                       │ (backup.sh)    │
   │ (no creds)   │                       │ Restic repo    │
   └──────────────┘                       └────────────────┘
```

## Documentation

- [docs/INSTALL.md](docs/INSTALL.md) — full installation walkthrough
- [docs/USAGE.md](docs/USAGE.md) — day-to-day operations
- [docs/DR-RUNBOOK.md](docs/DR-RUNBOOK.md) — disaster recovery procedures
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — how it works under the hood
- [docs/FAQ.md](docs/FAQ.md) — common questions

## Repository layout

```
zt-backup-kit/
├── bin/                     # the four main scripts
│   ├── backup.sh            # automated backup
│   ├── restore.sh           # interactive restore
│   ├── emergency-restore.sh # bootstrap recovery anywhere
│   └── backup-status.sh     # snapshots / sizes / dedup / runs
├── config/
│   └── config.example.sh    # template; copy to config.sh and edit
├── docs/                    # documentation
├── examples/                # crontab samples, multi-target configs, etc.
├── scripts/                 # helpers (e.g. encrypt-credentials.sh)
└── tests/                   # smoke tests
```

## Background &amp; further reading

The Zero-Trust framing of backup repositories — treating the production host
as untrusted and isolating immutable snapshots from possible compromise — has
been explored in academic literature, including
[Optimizing Recovery Objectives (RTO &amp; RPO) in Secure Linux NAS
Environments](https://www.ajssmt.com) (Gomas &amp; Rathnayake, 2026), which
discusses the "Secure Pull" architecture in detail. This kit is one practical
implementation of that style of thinking, not a direct re-implementation of
any single paper.

## Contributing

Pull requests welcome! See [CONTRIBUTING.md](CONTRIBUTING.md).

Particularly interested in:
- Pull-mode setup scripts
- Healthchecks.io / ntfy.sh notification integrations
- Native B2/S3 backend examples
- Tests on additional Linux distros

## Security

If you discover a security issue, please **do not** open a public issue.
Email the maintainer instead. See [SECURITY.md](SECURITY.md) for details.

## License

[MIT](LICENSE) © 2026 A.S. Dilan Gomas

## Author

**A.S. Dilan Gomas**
Demonstrator, Department of Information Technology
Faculty of Social Sciences and Languages
Sabaragamuwa University of Sri Lanka

- 🌐 [dilangomas.dev](https://dilangomas.dev)
- 🔗 [LinkedIn](https://www.linkedin.com/in/shanukadilan/)
- 🆔 [ORCID: 0009-0007-5551-4411](https://orcid.org/0009-0007-5551-4411)
- 📚 [Google Scholar](https://scholar.google.com/citations?user=djAh6alAAAAJ)
- 📧 [hello@dilangomas.dev](mailto:hello@dilangomas.dev)

## Citation

If you use this software in research or production, please cite it.
A permanent DOI is provided by Zenodo:

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.19849290.svg)](https://doi.org/10.5281/zenodo.19849290)

```bibtex
@software{ztbackupkit2026,
  author       = {Gomas, A.S. Dilan},
  title        = {zt-backup-kit: Zero-Trust Backup \& Restore Kit},
  year         = {2026},
  publisher    = {Zenodo},
  version      = {v0.1.0},
  doi          = {10.5281/zenodo.19849290},
  url          = {https://doi.org/10.5281/zenodo.19849290}
}
```

GitHub also surfaces this via the "Cite this repository" button (powered by
[CITATION.cff](CITATION.cff)).
