# Integration Challenges Resolution

## Challenge A: ProtectSystem=strict vs EnvironmentFile
**Conflict:** ProtectSystem=strict makes the entire /etc directory read-only. Our initial design placed environment files in /etc/kijanikiosk/, which caused the service to fail on startup because it could not read its configuration.
**Options considered:**
1. Add ReadWritePaths=/etc/kijanikiosk to the systemd unit.
2. Move the configuration files to /opt/kijanikiosk/config/.
**Decision:** Option 2. Moving the files to /opt is cleaner, keeps application-specific config with the application, and requires zero relaxation of the strict systemd security profile.

## Challenge B: Health Directory Access Model
**Conflict:** The health check JSON file needs to be written by the root provisioning script, but must be readable by the kk-logs service (and the broader kijanikiosk group) for monitoring, without allowing the service to modify it.
**Decision:** The /opt/kijanikiosk/health directory is owned by kk-logs:kijanikiosk with 750 permissions. The file is created by root with 640 permissions. This ensures the provisioning script can write it, the kk-logs user can read it, and no other users on the system can access it.

## Challenge C: logrotate postrotate vs PrivateTmp
**Conflict:** Using systemctl reload in the logrotate postrotate script can fail or behave unpredictably if the service has PrivateTmp=yes enabled, as the reload signal might not reach the correct process namespace.
**Decision:** We use systemctl try-reload-or-restart with error suppression (2>/dev/null || true). This ensures logrotate completes successfully even if the service is temporarily in a state where it cannot accept a reload signal, preventing the log rotation job from failing and leaving logs unrotated.

## Challenge D: Package Holds on Dirty VM
**Conflict:** The VM had stale or missing package holds from previous labs, which could cause an apt upgrade to silently upgrade pinned packages, breaking the verified security baseline.
**Decision:** The script explicitly checks for and clears any existing holds on nginx and curl before verifying the installed version. It then explicitly re-applies the hold to the exact version string discovered during the pre-provisioning audit, ensuring the state converges to the known-good version regardless of the VM prior state.
