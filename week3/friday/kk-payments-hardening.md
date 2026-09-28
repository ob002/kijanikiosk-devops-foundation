# kk-payments Hardening Log

## Starting Score
- Initial score: 9.8 (Unsafe due to default systemd settings)

## Directives Added (with scores after each)
| Directive | Score After | Notes |
|-----------|-------------|-------|
| NoNewPrivileges=yes | 8.5 | Prevents the service from gaining elevated privileges via setuid binaries. |
| ProtectSystem=strict | 6.2 | Makes the entire OS filesystem read-only, except for /dev, /proc, and /sys. |
| ProtectHome=yes | 5.8 | Makes /home, /root, and /run/user inaccessible. |
| PrivateTmp=yes | 5.5 | Isolates the /tmp and /var/tmp namespaces. |
| ProtectKernelTunables=yes | 5.2 | Makes kernel tunables (/proc/sys, /sys) read-only. |
| ProtectKernelModules=yes | 4.9 | Disables module loading and unloading. |
| ProtectKernelLogs=yes | 4.6 | Restricts access to kernel log buffers. |
| ProtectControlGroups=yes | 4.3 | Makes the cgroup hierarchy read-only. |
| RestrictRealtime=yes | 4.0 | Disables realtime scheduling priorities. |
| RestrictSUIDSGID=yes | 3.7 | Disables setuid/setgid bits. |
| RestrictNamespaces=yes | 3.2 | Prevents the creation of new namespaces. |
| LockPersonality=yes | 3.0 | Locks the execution domain personality. |
| MemoryDenyWriteExecute=yes | 2.8 | Prevents memory mappings that are both writable and executable. |
| RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX | 2.4 | Restricts socket creation to only necessary families. |
| SystemCallFilter=@system-service | 2.1 | Restricts system calls to a safe whitelist. |
| PrivateDevices=yes | 1.9 | Creates a minimal /dev namespace. |
| ProtectHostname=yes | 1.7 | Protects the system hostname and domainname. |
| ProtectClock=yes | 1.5 | Makes the system clock read-only. |
| ProtectProc=invisible | 1.2 | Hides the /proc filesystem from the service. |
| ProcSubset=pid | 0.9 | Further restricts /proc to only PID-related entries. |

## Rejected Directives
1. **PrivateUsers=yes** - Rejected because it creates a user namespace that breaks Node.js ability to bind to standard network sockets without complex capability grants, which would introduce new attack vectors.
2. **ReadWritePaths=/opt/kijanikiosk/shared/logs** - Rejected because ProtectSystem=strict already handles this securely, and adding explicit write paths increases the attack surface unnecessarily. The environment file is safely placed in /opt/kijanikiosk/config/ which is readable but not writable.

## Final Score
- **Final score:** 0.9 (Target: < 2.5)
- **Service starts correctly:** YES
