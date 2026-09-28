# KijaniKiosk Production Server Foundation

A complete, idempotent Infrastructure-as-Code provisioning script that transforms a dirty Ubuntu 26.04 VM into a hardened, production-ready server for the KijaniKiosk platform.

## Overview

This project was built as the Week 3 Friday deliverable for the KijaniKiosk DevOps Foundation course. It demonstrates the mental model behind Infrastructure as Code: idempotency, desired state, declarative configuration, and verification phases. The provisioning script serves as the manual baseline that will later be compared against a Terraform configuration in Week 4.

## Repository Structure

kijanikiosk-devops-foundation/
└── week3/
└── friday/
├── kijanikiosk-provision.sh # 8-phase idempotent provisioning script
├── pre-provisioning-audit.txt # Dirty state audit output
├── provision-run-dirty.log # First run on dirty VM
├── provision-run-clean.log # Second run (idempotency proof)
├── kk-payments-hardening.md # Iterative hardening log
├── hardening-decisions.md # Security posture document for leadership
├── integration-notes.md # Resolution of 4 integration challenges
├── post-remediation-verification.txt # Logrotate + ACL verification
└── reflection.md # Engineering reflection


## The 8-Phase Provisioning Script

The script (`kijanikiosk-provision.sh`) is the core deliverable. It runs in 8 phases:

| Phase | Purpose |
|-------|---------|
| **Phase 1** | Package management and version pinning (nginx, curl) |
| **Phase 2** | Users, groups, and directory structure creation |
| **Phase 3** | ACLs and access model configuration |
| **Phase 4** | Environment files for all three services |
| **Phase 5** | Firewall reset to baseline with CIDR-scoped rules |
| **Phase 6** | Inline systemd unit files for kk-api, kk-payments, kk-logs |
| **Phase 7** | Journal persistence (500MB cap) and logrotate with ACL preservation |
| **Phase 8** | Health check JSON written to `/opt/kijanikiosk/health/` |

Each phase is idempotent — safe to run multiple times on a dirty VM.

## Security Scores Achieved

| Service | Target | Achieved | Status |
|---------|--------|----------|--------|
| kk-api | < 3.5 | 3.2 | passed |
| kk-payments | < 2.5 | 1.3 | passed |
| kk-logs | < 3.5 | 3.2 | passed |

The payments service uses `ProtectSystem=strict`, `PrivateUsers=yes`, `CapabilityBoundingSet=` (empty), and a strict system call filter to achieve an exposure score of 1.3.

## Integration Challenges Resolved

1. **ProtectSystem=strict vs EnvironmentFile** — Moved config from `/etc/kijanikiosk/` to `/opt/kijanikiosk/config/` to avoid read-only filesystem conflicts.
2. **Health Directory Access Model** — Designed ownership (`kk-logs:kijanikiosk`, 750) so the provisioning script can write but the monitoring user can read.
3. **logrotate postrotate vs PrivateTmp** — Used `systemctl try-reload-or-restart` with error suppression instead of `systemctl reload`.
4. **Package Holds on Dirty VM** — Script clears stale holds before verifying and re-pinning versions.

## How to Run

```bash
# 1. Run the pre-provisioning audit
sudo bash pre-provisioning-audit.sh  # (or run the audit commands manually)

# 2. Run the provisioning script
sudo bash kijanikiosk-provision.sh 2>&1 | tee provision-run-dirty.log

# 3. Run again to verify idempotency
sudo bash kijanikiosk-provision.sh 2>&1 | tee provision-run-clean.log

Both runs should exit with code 0 and print ✓ ALL CHECKS PASSED.
Key Design Decisions
Config under /opt, not /etc: Avoids conflicts with ProtectSystem=strict.
UFW reset to baseline: Prevents accumulation of ad-hoc rules from previous labs.
Pinned package versions: nginx 1.28.3-2ubuntu1.11, curl 8.18.0-1ubuntu2.7.
Logrotate su root kijanikiosk: Prevents "insecure permissions" errors on group-writable log directories.
Health check records "down": Services may not be running during provisioning; a missing file is a script failure, but a file containing "down" is an expected result.
Branch Strategy
main — Default branch (clean baseline)
develop — Integration branch
feature/week3-production-foundation — Feature branch with all deliverables
Author
Built for the KijaniKiosk DevOps Foundation course, Week 3.
