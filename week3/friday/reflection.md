# Reflection

## 1. Conflicting Requirements
During this project, I encountered a conflict between the requirement to use `ProtectSystem=strict` for the payments service and the need for the service to read its environment configuration file. Initially, placing the config in `/etc/kijanikiosk/` caused the service to fail because `ProtectSystem=strict` makes `/etc` read-only. I resolved this by moving the configuration files to `/opt/kijanikiosk/config/`, which satisfied both the security requirement and the application's need to read its environment.

## 2. Audience Translation
**Original (for Nia):** "The payments service is locked down using over 15 kernel-level restrictions, making the operating system filesystem read-only and hiding system processes."
**Technical (for Tendo):** "The kk-payments systemd unit implements ProtectSystem=strict, ProtectProc=invisible, ProcSubset=pid, and SystemCallFilter=@system-service ~@privileged ~@resources to minimize the attack surface and achieve an exposure score of 1.3."
**Lost:** The technical version loses the business context of *why* this matters (protecting financial data and limiting blast radius).
**Gained:** The technical version gains precise, actionable directives that another engineer can audit and verify programmatically.

## 3. Most Fragile Part
The most fragile part of the provisioning script is the logrotate access model verification. While the script sets default ACLs on the `/opt/kijanikiosk/shared/logs/` directory, logrotate's behavior can be unpredictable if the `su` directive is missing or if the parent directory permissions change. To make this more robust in the future, I would add an explicit `su root kijanikiosk` directive (which I did) and potentially add a post-rotation verification step that actively checks the ACLs of the newly rotated file rather than just relying on the `create` directive.