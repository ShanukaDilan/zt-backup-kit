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

`zt-backup-kit` is a set of open-source Bash orchestration scripts that implement a **"Secure Pull"** backup architecture for Linux Network-Attached Storage (NAS) appliances. Rather than allowing the production server (the client) to push data onto a backup repository — the conventional model that exposes the repository to any ransomware running on the client — `zt-backup-kit` inverts the trust boundary: the NAS server initiates an outbound SSH connection to the client, reads source data using `restic`, and writes immutable, AES-256-encrypted snapshots to a local repository that the client can never reach or overwrite. This "pull" topology creates a software-defined air gap without requiring specialised hardware, cloud connectivity, or proprietary appliances.

The toolkit ships in two complementary scripts:

- **`backup_pull_l3.sh`** — the primary enterprise wrapper around `restic`. It performs deduplicated, encrypted backups to one or more configurable targets (local NAS via SFTP, Google Drive via `rclone`, or both), enforces a snapshot retention policy (14 daily / 4 weekly / 6 monthly), runs a 2 % random integrity check after every backup, serialises concurrent runs with a `flock` lock, and dispatches a structured HTML status report by email via `msmtp`.
- **`backup_rsync_daily.sh`** — a complementary daily archiving script that mirrors one or more source paths with `rsync`, optionally verifies every copied file with MD5 checksums, bundles the result into a timestamped `.tar` archive, uploads the archive to Google Drive with `rclone` **and** to a NAS appliance over SSH, and sends a multi-part MIME email containing both a plain-text summary and an HTML report.

Together the scripts satisfy the **3-2-1-0** backup rule [@veeam2023] — three copies of data, two different storage media, one offsite copy, and **zero trust** granted to the local backup client.

# Statement of Need

More than 90 % of ransomware attacks now specifically target backup repositories before encrypting production data [@etciosea2023]. Conventional NAS configurations using NFS or SMB mounts give the backup client write access to the repository; when the client is compromised, the backup is lost alongside the primary data [@chandramouli2020]. Commercial immutability solutions (WORM drives, object-lock cloud storage) address this threat but require expensive proprietary hardware or introduce high Recovery Time Objectives (RTO) due to WAN bandwidth constraints.

`zt-backup-kit` addresses this gap for **small- to medium-scale enterprises (SMEs)** operating standard Linux infrastructure. By wrapping `restic` [@restic2015] and `OpenSSH` in a pull-oriented orchestration layer, the toolkit achieves:

- **RPO ≤ 15 minutes** using high-frequency incremental snapshots over a Gigabit LAN (mean incremental transfer: 38 s).
- **RTO < 2 minutes** to restore a 10 GB reference dataset from the local NAS — 21× faster than a cloud-only alternative (35 min over a 50 Mbps WAN link) [@gomas2026].
- **Zero data loss** in laboratory ransomware attack simulations: the attack script found no mounted backup volumes on the client and was unable to reach the NAS repository.

The Zero-Trust Backup Ontology underpinning the toolkit treats the backup client as a potentially hostile entity at all times [@bavendiek2022; @zheng2023]. This is in contrast to existing open-source wrappers (e.g. plain `restic` cron jobs, `rsnapshot`) that assume the client and server share mutual trust. `zt-backup-kit` is the first openly published orchestration layer that operationalises the pull paradigm together with automated retention, integrity verification, and operator notification in a single deployable script pair.

The toolkit is designed for Linux system administrators managing production web servers, small university computing facilities, or any environment that must meet enterprise-class DR objectives without enterprise-class procurement budgets.

# Implementation

The core security mechanism is the **inversion of network directionality**. In a standard push configuration the client mounts the NAS share (`NFS/SMB`) and writes directly; ransomware running as root on the client inherits those write permissions. In `zt-backup-kit` the NAS server holds an SSH key that authorises it to read from the client via `restic`'s `sftp` backend. The client exposes no writable share; it has no knowledge of the backup server's IP address or repository path. \autoref{fig:flow} illustrates this logical data flow.

All repository data is encrypted by `restic` using AES-256-CTR with Poly1305-MAC authentication before leaving the client [@restic2015]. Content-Defined Chunking (CDC) [@gregoriadis2024] ensures that only changed sub-file blocks are transferred on each incremental run, keeping the per-snapshot network footprint small enough to sustain 15-minute RPO windows on a standard Gigabit LAN.

Concurrent backup prevention (`flock`), structured JSON log parsing (`jq`, `numfmt`), MIME email construction, and automated `ssh-agent` lifecycle management are all handled inside the script, minimising external dependencies to: `restic`, `rclone`, `openssh-client`, `msmtp`, `jq`, and standard GNU coreutils.

# Comparison with Related Work

| Tool | Pull-based | Immutable snapshots | HTML reports | Multi-target | Open source |
|---|---|---|---|---|---|
| `zt-backup-kit` | ✓ | ✓ (restic) | ✓ | ✓ | ✓ |
| Plain `restic` cron | ✗ (push) | ✓ | ✗ | partial | ✓ |
| `rsnapshot` | ✗ (push) | ✗ | ✗ | ✗ | ✓ |
| Veeam Agent (free) | ✗ | ✓ | ✓ | ✓ | ✗ |
| Bacula | ✓ (pull option) | ✗ | partial | ✓ | ✓ |

`zt-backup-kit` is the only entry in this comparison that combines pull-based isolation with `restic`'s structural immutability, automated HTML reporting, and multi-target offload in a dependency-light Bash package suitable for deployment on any standard Ubuntu/Debian server.

# Research Context

The design and empirical evaluation of the Secure Pull architecture are described in detail in @gomas2026. That study, conducted using the Design Science Research Methodology (DSRM) [@peffers2007], built a virtualised testbed of two Ubuntu 22.04 VMs connected over a virtual Gigabit switch. Simulated ransomware executed with root privileges on the client achieved 100 % data destruction of a standard NFS-mounted backup, while the Secure Pull repository remained entirely unaffected. `zt-backup-kit` is the open-source release of the artifact produced by that research.

# Acknowledgements

The authors thank the Department of Information Technology, Faculty of Social Sciences and Languages, Sabaragamuwa University of Sri Lanka, for supporting the laboratory infrastructure used in the evaluation of this software.

# References
