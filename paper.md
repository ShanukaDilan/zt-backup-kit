---
title: 'zt-backup-kit: A Zero-Trust Restic Orchestration Toolkit for Ransomware-Resilient Linux NAS Environments'
tags:
  - bash
  - linux
  - backup
  - ransomware
  - disaster-recovery
  - restic
  - zero-trust
  - NAS
authors:
  - name: A.S. Dilan Gomas
    orcid: 0009-0007-5551-4411
    corresponding: true
    affiliation: 1
  - name: R.M.N.B. Rathnayake
    orcid: 0009-0003-5760-4171
    affiliation: 1
affiliations:
  - name: Department of Information Technology, Faculty of Social Sciences and Languages, Sabaragamuwa University of Sri Lanka, Belihuloya 70140, Sri Lanka
    index: 1
date: 2 May 2026
bibliography: paper.bib
---

# Summary

`zt-backup-kit` is an open-source Bash orchestration toolkit that implements
a **"Secure Pull"** backup architecture for Linux Network-Attached Storage
(NAS) appliances. Rather than allowing the production server (the client) to
push data onto a backup repository — the conventional model that exposes the
repository to any ransomware running on the client — `zt-backup-kit` inverts
the trust boundary: the NAS server initiates an outbound SSH connection to
the client, reads source data using `restic`, and writes immutable,
AES-256-encrypted snapshots to a local repository that the client can never
reach or overwrite. This "pull" topology creates a software-defined air gap
without requiring specialised hardware, cloud connectivity, or proprietary
appliances.

The toolkit ships four scripts under `bin/`:

- **`backup.sh`** — the primary enterprise wrapper around `restic`. It
  performs deduplicated, encrypted backups to one or more configurable
  targets (local NAS via SFTP, Google Drive via `rclone`, S3-compatible
  object storage, or any combination), enforces a configurable snapshot
  retention policy, runs a periodic random integrity check, serialises
  concurrent runs with a `flock` lock, and dispatches a structured HTML
  status report by email via `msmtp`.
- **`restore.sh`** — an interactive restore tool supporting full restore,
  partial path restore, FUSE snapshot mounting, and snapshot content listing.
- **`emergency-restore.sh`** — a bootstrap recovery script that installs
  `restic` and `rclone` on a clean Linux or macOS machine and walks the
  operator through restoring a chosen snapshot with no prior setup required.
- **`backup-status.sh`** — a repository inspector showing snapshot count,
  logical vs stored size, deduplication ratio, snapshot freshness, and recent
  run history. Supports `--json` output for monitoring integrations.

Together the scripts satisfy the **3-2-1-0** backup rule [@veeam2023] —
three copies of data, two different storage media, one offsite copy, and
**zero trust** granted to the local backup client.

# Statement of Need

More than 90 % of ransomware attacks now specifically target backup
repositories before encrypting production data [@etciosea2023]. Conventional
NAS configurations using NFS or SMB mounts give the backup client write
access to the repository; when the client is compromised, the backup is lost
alongside the primary data [@chandramouli2020]. Commercial immutability
solutions (WORM drives, object-lock cloud storage) address this threat but
require expensive proprietary hardware or introduce high Recovery Time
Objectives (RTO) due to WAN bandwidth constraints.

`zt-backup-kit` addresses this gap for **small- to medium-scale enterprises
(SMEs)** and research computing facilities operating standard Linux
infrastructure. By wrapping `restic` [@restic2015] and OpenSSH in a
pull-oriented orchestration layer, the toolkit achieves:

- **RPO ≤ 15 minutes** using high-frequency incremental snapshots over a
  Gigabit LAN (mean incremental transfer: 38 s).
- **RTO < 2 minutes** to restore a 10 GB reference dataset from the local
  NAS — 21× faster than a cloud-only alternative (35 min over a 50 Mbps WAN
  link) [@gomas2026].
- **Zero data loss** in laboratory ransomware attack simulations: the attack
  script found no mounted backup volumes on the client and was unable to
  reach the NAS repository.

The Zero-Trust Backup Ontology underpinning the toolkit treats the backup
client as a potentially hostile entity at all times [@bavendiek2022;
@zheng2023]. This is in contrast to existing open-source wrappers such as
plain `restic` cron jobs or `rsnapshot`, which assume the client and server
share mutual trust. `zt-backup-kit` is the first openly published
orchestration layer that operationalises the pull paradigm together with
automated retention, integrity verification, a paper-printable disaster
recovery runbook, and operator notification in a single deployable package.

# Implementation

The core security mechanism is the **inversion of network directionality**.
In a standard push configuration the client mounts the NAS share (NFS/SMB)
and writes directly; ransomware executing as root on the client inherits
those write permissions and can encrypt or delete the repository. In
`zt-backup-kit` the NAS server holds an SSH key that authorises it to read
from the client via `restic`'s `sftp` backend. The client exposes no
writable share and has no knowledge of the backup server's address or
repository path, as illustrated in \autoref{fig:arch}.

![Logical data flow comparison. **Left (Push):** the client mounts the NAS and writes; ransomware inherits write permissions. **Right (Secure Pull):** only the NAS initiates SSH; the client has no path to the repository.\label{fig:arch}](architecture.png)

All repository data is encrypted by `restic` using AES-256-CTR with
Poly1305-MAC authentication before leaving the client [@restic2015].
Content-Defined Chunking (CDC) [@gregoriadis2024] ensures that only changed
sub-file blocks transfer on each incremental run, keeping the per-snapshot
network footprint small enough to sustain a 15-minute RPO window on a
standard Gigabit LAN.

Operational concerns handled inside `backup.sh` include: granular `restic`
exit-code parsing (distinguishing full success, partial-success with
unreadable files, and genuine failure), `flock`-based concurrency control,
structured JSON log extraction via `jq`, MIME multipart email construction,
`ssh-agent` lifecycle management, and automatic log rotation. External
dependencies are intentionally minimal: `restic`, `rclone`, `openssh-client`,
`msmtp`, `jq`, and standard GNU coreutils.

# State of the Field

Several tools address automated Linux backup, but none combines pull-based
network isolation with `restic`'s structural immutability and a fully
documented disaster recovery workflow:

| Tool | Pull-based | Immutable snapshots | HTML reports | Multi-target | Open source |
|---|---|---|---|---|---|
| `zt-backup-kit` | ✓ | ✓ (`restic`) | ✓ | ✓ | ✓ |
| Plain `restic` cron | ✗ (push) | ✓ | ✗ | partial | ✓ |
| `rsnapshot` | ✗ (push) | ✗ | ✗ | ✗ | ✓ |
| Veeam Agent (free) | ✗ | ✓ | ✓ | ✓ | ✗ |
| Bacula | ✓ (pull option) | ✗ | partial | ✓ | ✓ |

Bacula supports pull-mode but relies on a database daemon and a proprietary
catalogue format, making it unsuitable for lightweight SME deployments.
`zt-backup-kit` occupies the niche between single-purpose `restic` cron
snippets and full enterprise backup suites, providing the operational layer
(locking, reporting, recovery tooling, runbooks) that the former lacks while
remaining deployable on any standard Ubuntu/Debian server in under an hour.

# Research Context

The Secure Pull architecture was designed and empirically evaluated using
the Design Science Research Methodology (DSRM) [@peffers2007]. A virtualised
testbed of two Ubuntu 22.04 LTS VMs connected over a virtual Gigabit switch
was used to compare three scenarios: cloud-only backup, standard NFS-based
local NAS, and the Secure Pull NAS. Simulated ransomware executing with root
privileges achieved 100 % data destruction of the NFS-mounted repository,
while the Secure Pull repository remained entirely unaffected. `zt-backup-kit`
is the open-source release of the artifact produced by that study; full
experimental methodology and results are reported in @gomas2026.

# Acknowledgements

The authors thank the Department of Information Technology, Faculty of Social
Sciences and Languages, Sabaragamuwa University of Sri Lanka, for supporting
the laboratory infrastructure used in the evaluation of this software.

# AI Usage Disclosure

Generative AI assistance (Anthropic Claude, Sonnet 4 family) was used in the
following aspects of this submission: (1) drafting and copy-editing of this
manuscript (`paper.md`); (2) generation of the BibTeX bibliography
(`paper.bib`); (3) scaffolding of documentation files (`docs/`, `README.md`,
`CONTRIBUTING.md`). All AI-assisted outputs were reviewed, edited, and
validated by the human authors. Core design decisions — the pull-based
security architecture, the Zero-Trust Backup Ontology, experimental
methodology, and implementation choices — are entirely the work of the
authors. The software scripts in `bin/` were written and iteratively refined
by the authors independently of AI assistance.

# References
