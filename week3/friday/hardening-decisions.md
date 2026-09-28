# KijaniKiosk Production Server Security Posture

**Prepared for:** Nia, Engineering Leadership
**Date:** September 28, 2026
**Author:** [Your Name]

## Executive Summary

This document outlines the security foundation for the new KijaniKiosk production server. The infrastructure has been designed to provision itself automatically from a single, version-controlled definition. This eliminates manual configuration errors, ensures every server is built identically, and allows for rapid recovery in the event of a compromise. The controls detailed below are specifically designed to protect customer payment data and ensure the resilience of our core services.

## Security Controls

| Control | What it does | Risk mitigated |
|---------|--------------|----------------|
| Automated Idempotent Provisioning | The server configuration is defined in code and can be run repeatedly without causing errors or duplicating settings. | Eliminates configuration drift and human error during manual server setup. |
| Dedicated Service Accounts | Each of the three services (API, Payments, Logs) runs under its own isolated, non-privileged user account. | If one service is compromised, the attacker cannot access the files or memory of the other services. |
| Strict Firewall Baseline Reset | The provisioning script completely wipes existing firewall rules and rebuilds them from a known, minimal state. | Prevents the accumulation of forgotten, ad-hoc firewall rules that could expose internal ports to the public internet. |
| Network Segmentation via UFW | External access to the payments service (port 3001) is explicitly denied. Only the local machine and the designated monitoring subnet (10.0.1.0/24) can reach it. | Protects the internal payments API from direct external probing or attacks. |
| Systemd Sandboxing (Payments) | The payments service is locked down using over 15 kernel-level restrictions, making the operating system filesystem read-only and hiding system processes. | Severely limits the damage an attacker can do if they manage to execute malicious code within the payments service. |
| Principle of Least Privilege (ACLs) | File access is managed via Access Control Lists, ensuring services can only read or write to the specific directories they absolutely need. | Prevents a compromised service from modifying configuration files or reading sensitive logs belonging to other services. |
| Pinned Package Versions | Critical software versions are explicitly defined and locked, preventing unexpected upgrades. | Protects against supply chain attacks or breaking changes introduced by automatic background updates. |
| Capped Log Retention | System journals are capped at 500MB, and application logs are rotated and compressed daily. | Prevents a denial-of-service condition where an attacker fills the server disk with log data, causing the system to crash. |

## Honest Gaps

While this foundation is highly secure, it is important to acknowledge its limitations. This posture protects the server environment, but it does not protect against vulnerabilities within the application code itself (such as SQL injection or logic flaws in the Node.js applications). Additionally, the current setup relies on local file-based logging; in a true enterprise environment, logs should be shipped in real-time to a centralized, immutable logging service to prevent an attacker from covering their tracks by deleting local log files. Finally, this configuration does not include automated vulnerability scanning of the underlying OS packages, which should be added to our CI/CD pipeline in the next quarter.
