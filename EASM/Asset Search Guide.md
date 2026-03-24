# Defender EASM Filter/Search Guide — How to Discover Your Attack Surface

Microsoft Defender EASM continuously maps your external attack surface across domains, hosts, IP addresses, SSL certificates, web pages, IP blocks, ASNs, and contacts. The inventory search lets you combine multiple filters to isolate exactly the assets that need attention. By default, the Inventory screen shows only **Approved** assets — remove that filter when you need to review Candidates or assets requiring investigation (see Category 6).

**How to use this guide:** Copy the filter block for the search you want, enter each condition in the EASM Inventory filter UI, and save the query for recurring use. Filters are applied with AND logic unless otherwise noted.

## Asset Filter Reference Links

- Inventory filters overview: https://learn.microsoft.com/en-us/azure/external-attack-surface-management/inventory-filters
- ASN asset filters: https://learn.microsoft.com/en-us/azure/external-attack-surface-management/asn-asset-filters
- Contact asset filters: https://learn.microsoft.com/en-us/azure/external-attack-surface-management/contact-asset-filters
- Domain asset filters: https://learn.microsoft.com/en-us/azure/external-attack-surface-management/domain-asset-filters
- Host asset filters: https://learn.microsoft.com/en-us/azure/external-attack-surface-management/host-asset-filters
- IP address asset filters: https://learn.microsoft.com/en-us/azure/external-attack-surface-management/ip-address-asset-filters
- IP block asset filters: https://learn.microsoft.com/en-us/azure/external-attack-surface-management/ip-block-asset-filters
- Page asset filters: https://learn.microsoft.com/en-us/azure/external-attack-surface-management/page-asset-filters
- SSL certificate asset filters: https://learn.microsoft.com/en-us/azure/external-attack-surface-management/ssl-certificate-asset-filters

---

## Category 1 — Critical Vulnerabilities (CVE / CVSS)

> These searches surface assets with known exploitable vulnerabilities. Start here — a CVSS v3 score of 9.0+ indicates a critical, often remotely exploitable flaw.

---

### Search 1 — Critical CVEs on Hosts

**Finds:** Approved host assets carrying at least one CVE with a CVSS v3 score of 9.0 or higher.

```
kind equals Host
and
state equals Approved
and
Affected CVSS v3 Score >= 9.0
```

> **Analyst note:** These are your highest-urgency findings. Cross-reference with your vulnerability management program and prioritize patching or isolation for any internet-facing hosts returned.

---

### Search 2 — Critical CVEs on IP Addresses

**Finds:** Approved IP address assets carrying at least one CVE with a CVSS v3 score of 9.0 or higher.

```
kind equals IP Address
and
state equals Approved
and
Affected CVSS v3 Score >= 9.0
```

> **Analyst note:** Some CVEs attach to IPs rather than hostnames depending on how EASM resolved the asset. Run this alongside Search 1 to avoid gaps in your critical finding coverage.

---

### Search 3 — High-Severity CVEs on Web Pages

**Finds:** Approved page assets with a CVSS v3 score of 7.0 or higher (High or Critical).

```
kind equals Page
and
state equals Approved
and
Affected CVSS v3 Score >= 7.0
```

> **Analyst note:** Page-level CVEs often indicate vulnerable web frameworks or CMS versions. Pair this with Search 21 (Vulnerable Web Components) to identify the specific technology driving the finding.

---

### Search 4 — SQL Injection Exposure (CWE-89)

**Finds:** Approved hosts, IP addresses, and pages flagged with CWE-89 (SQL Injection).

```
kind in [Host, IP Address, Page]
and
state equals Approved
and
CWE ID contains CWE-89
```

> **Analyst note:** SQL injection is a top-tier OWASP risk. Any result here warrants immediate escalation to the application security team for validation and remediation.

---

## Category 2 — SSL / TLS Certificate Risk

> Expired or weak certificates break trust chains, expose users to MitM attacks, and may indicate unmaintained infrastructure. These searches help you stay ahead of certificate hygiene.

---

### Search 5 — Expired SSL Certificates

**Finds:** Approved SSL certificate assets that have already passed their expiration date.

```
kind equals SSL Cert
and
state equals Approved
and
Cert Expiration equals Expired
```

> **Analyst note:** An expired cert on a customer-facing property is an active incident. Expired certs on internal or staging assets may indicate forgotten/orphaned infrastructure worth decommissioning.

---

### Search 6 — Certificates Expiring Within 30 Days

**Finds:** Approved SSL certificate assets expiring in the next 30 days.

```
kind equals SSL Cert
and
state equals Approved
and
Cert Expiration equals Expires in 30 days
```

> **Analyst note:** Save this as a recurring check. Alert the team owning the cert and confirm renewal is in progress. Consider also running the "Expires in 60 days" variant for earlier warning.

---

### Search 7 — Self-Signed Certificates

**Finds:** Approved SSL certificates that were self-signed rather than issued by a trusted CA.

```
kind equals SSL Cert
and
state equals Approved
and
Self Signed equals true
```

> **Analyst note:** Self-signed certs on public-facing assets bypass browser trust validation and are a red flag for both security posture and shadow IT. Determine whether these were intentionally deployed or represent rogue endpoints.

---

### Search 8 — Weak Certificate Key Size (≤1024 bits)

**Finds:** Approved SSL certificates using a key size of 1024 bits or smaller, which is considered cryptographically weak.

```
kind equals SSL Cert
and
state equals Approved
and
Cert Key Size <= 1024
```

> **Analyst note:** 1024-bit RSA keys no longer meet modern security standards (NIST deprecated them in 2013). Replace any returned certs with 2048-bit or 4096-bit keys. Also check `Cert Key Algorithm` for MD5 or SHA-1 based signature algorithms.

---

## Category 3 — Domain Hygiene & Unauthorized Registration

> Domains are the anchor of your external identity. Expired or improperly registered domains can be hijacked by threat actors for phishing, BEC, or brand abuse.

---

### Search 9 — Expired Domains

**Finds:** Approved domain assets whose registration has already lapsed.

```
kind equals Domain
and
state equals Approved
and
Domain Expiration equals Expired
```

> **Analyst note:** An expired domain in your approved inventory is an active takeover risk. Verify whether the domain is still needed — if so, reclaim and renew immediately. If not, formally decommission and remove from inventory.

---

### Search 10 — Domains Expiring Within 30 Days

**Finds:** Approved domain assets expiring in the next 30 days.

```
kind equals Domain
and
state equals Approved
and
Domain Expiration equals Expires in 30 days
```

> **Analyst note:** Confirm renewal is in progress with the registrar. Check the Registrar and Whois Admin Email fields on each result to identify the responsible team. Also consider the "Expires in 60 days" variant for broader coverage.

---

### Search 11 — Parked / Abandoned Domains

**Finds:** Approved domains that are registered but not connected to an active website or email service.

```
kind equals Domain
and
state equals Approved
and
Parked Domain equals true
```

> **Analyst note:** Parked domains are low-hanging fruit for subdomain takeover or abuse. Determine if the domain still serves a business purpose. If not, consider retiring it or placing it in a holding state with appropriate DNS controls.

---

### Search 12 — Unauthorized Contact / Registrant Review

**Finds:** Approved contact assets associated with your organization's domains and infrastructure.

```
kind equals Contact
and
state equals Approved
```

> **Analyst note:** Review `Whois Registrant Name`, `Whois Registrant Email`, and `Whois Admin Organization` on each result. Look for personal email addresses (Gmail, Yahoo), names not belonging to your organization, or registrars you don't recognize — these may indicate domains registered without authorization or shadow IT acquisitions. Expand to `State = Candidate` to cast a wider net.

---

## Category 4 — Exposed High-Risk Services

> These searches identify management protocols and legacy services exposed directly to the internet — each one represents a significant attack vector if left unprotected.

---

### Search 13 — Exposed RDP (Port 3389)

**Finds:** Approved hosts and IP addresses with port 3389 open to the internet.

```
kind in [Host, IP Address]
and
state equals Approved
and
Port equals 3389
and
Port State equals Open
```

> **Analyst note:** Internet-exposed RDP is one of the leading initial access vectors for ransomware. Every result here should be triaged immediately — place behind VPN/bastion, enable NLA, or close the port if RDP is not required externally.

---

### Search 14 — Exposed SSH (Port 22)

**Finds:** Approved hosts and IP addresses with port 22 open to the internet.

```
kind in [Host, IP Address]
and
state equals Approved
and
Port equals 22
and
Port State equals Open
```

> **Analyst note:** SSH exposure is expected for some infrastructure but should be limited to specific management IPs via allowlisting. Review whether public SSH access is intentional and confirm key-based authentication (not password) is enforced.

---

### Search 15 — Exposed Telnet (Port 23)

**Finds:** Approved hosts and IP addresses with port 23 open to the internet.

```
kind in [Host, IP Address]
and
state equals Approved
and
Port equals 23
and
Port State equals Open
```

> **Analyst note:** Telnet transmits credentials in plaintext and has no place on internet-facing infrastructure. Any result is an immediate remediation item — disable the service and migrate to SSH if remote access is required.

---

### Search 16 — Exposed FTP (Port 21)

**Finds:** Approved hosts and IP addresses with port 21 open to the internet.

```
kind in [Host, IP Address]
and
state equals Approved
and
Port equals 21
and
Port State equals Open
```

> **Analyst note:** FTP transmits credentials and data in plaintext. Migrate to SFTP (port 22) or FTPS, and verify whether legacy FTP services are still actively needed or can be decommissioned.

---

### Search 17 — Non-Standard Web Ports (Dev / Test Exposure)

**Finds:** Approved hosts and IP addresses with development or alternative web ports open to the internet.

```
kind in [Host, IP Address]
and
state equals Approved
and
Port in [8080, 8443, 8000, 8888]
and
Port State equals Open
```

> **Analyst note:** Non-standard ports often expose development, staging, or admin interfaces that were never intended to be internet-accessible. These environments frequently lack hardening and may run outdated software. Validate each result with the owning team.

---

## Category 5 — Web Application Security

> Web pages represent your most visible attack surface. These searches target configuration weaknesses and vulnerable technologies that attackers actively scan for and exploit.

---

### Search 18 — Live Pages Serving over HTTP (Unencrypted)

**Finds:** Live, approved page assets that are being served over plain HTTP rather than HTTPS.

```
kind equals Page
and
state equals Approved
and
Final Scheme equals http
and
Live equals true
```

> **Analyst note:** HTTP pages expose users to credential theft and content injection via MitM attacks. All public-facing pages should redirect to HTTPS. Check the `Final URL` field to identify any redirects that may be stripping TLS.

---

### Search 19 — Insecure Login Forms

**Finds:** Approved page assets where EASM has detected a login form being served insecurely.

```
kind equals Page
and
state equals Approved
and
Security Policy equals insecure-login-form
```

> **Analyst note:** Login forms on HTTP pages or mixed-content pages expose credentials to interception. This is a critical finding on any page that handles authentication. Enforce HTTPS and verify the form action URL is also HTTPS.

---

### Search 20 — Server Error and Auth Failure Responses

**Finds:** Approved page assets returning 500 (Server Error), 401 (Unauthorized), or 403 (Forbidden) response codes.

```
kind equals Page
and
state equals Approved
and
Response Code in [500, 401, 403]
```

> **Analyst note:** 500 errors may indicate misconfigured or crashing applications that leak stack traces or debug info. 401/403 pages may reveal hidden admin panels or restricted resources that are discoverable by attackers. Investigate each for information disclosure.

---

### Search 21 — Vulnerable Web Components (High CVE + Component Present)

**Finds:** Approved pages with at least one identified web component AND a CVSS v3 score of 7.0 or higher.

```
kind equals Page
and
state equals Approved
and
Affected CVSS v3 Score >= 7.0
and
Web Component Name not empty
```

> **Analyst note:** Use `Web Component Name & Version` on each result to identify the specific vulnerable library or framework (e.g., jQuery 3.4.1, Netscaler Gateway 12.1). Cross-reference with the CVE details and prioritize upgrades for any externally-facing component.

---

## Category 6 — Attack Surface Expansion & New Discoveries

> These searches help you understand the full scope of what EASM has discovered beyond your approved inventory — including shadow IT, newly detected assets, and anything flagged for follow-up.

> ⚠️ **For Searches 22 and 23:** Remove the default `State = Approved` filter before building these queries. These searches are specifically designed to look at assets *outside* approved inventory.

---

### Search 22 — Unreviewed Candidate Assets

**Finds:** All assets EASM has associated with your organization that have not yet been reviewed or approved.

```
state equals Candidate
```
*(Remove the default `State = Approved` filter first)*

> **Analyst note:** Candidates are EASM's best guess at assets belonging to you. Review regularly — some will be legitimate assets that need to be approved and brought under formal management, others may be misattributed. High-value finds here often include forgotten subdomains and acquired company infrastructure.

---

### Search 23 — Assets Flagged for Investigation

**Finds:** All assets in your inventory that have been marked as requiring further investigation.

```
state equals Requires Investigation
```
*(Remove the default `State = Approved` filter first)*

> **Analyst note:** These assets were flagged because EASM detected something unusual about them. Work through this list systematically — each asset should either be approved, dismissed, or escalated based on your findings.

---

### Search 24 — New Assets Added in the Last 30 Days

**Finds:** Approved assets that were first added to your inventory within the last 30 days.

```
kind in [Host, Domain, IP Address, Page, SSL Cert]
and
state equals Approved
and
Created At >= [date 30 days ago]
```

> **Analyst note:** A spike in newly discovered assets can indicate infrastructure expansion, acquisitions, or — in some cases — rogue/shadow IT deployments. Run this weekly and review new entries with asset owners. Filter by `kind` to focus on a specific asset type if the volume is high.

---

### Search 25 — Wildcard DNS Records

**Finds:** Approved hosts and domains that have wildcard DNS records configured (e.g., `*.contoso.com`).

```
kind in [Host, Domain]
and
state equals Approved
and
Wildcard equals true
```

> **Analyst note:** Wildcard DNS records mean that any subdomain resolves — including ones that shouldn't exist. This expands your attack surface significantly, as attackers can use valid-looking subdomains for phishing or to reach dangling resources. Confirm each wildcard is intentional and that the target service is hardened.

---

## Quick Reference — All 25 Searches

| # | Name | Asset Kind | Key Filter(s) |
|---|------|-----------|---------------|
| 1 | Critical CVEs on Hosts | Host | CVSS v3 >= 9.0 |
| 2 | Critical CVEs on IP Addresses | IP Address | CVSS v3 >= 9.0 |
| 3 | High CVEs on Web Pages | Page | CVSS v3 >= 7.0 |
| 4 | SQL Injection (CWE-89) | Host, IP, Page | CWE-89 |
| 5 | Expired SSL Certificates | SSL Cert | Cert Expiration = Expired |
| 6 | Certs Expiring in 30 Days | SSL Cert | Cert Expiration = 30 days |
| 7 | Self-Signed Certificates | SSL Cert | Self Signed = true |
| 8 | Weak Cert Key (≤1024 bit) | SSL Cert | Cert Key Size <= 1024 |
| 9 | Expired Domains | Domain | Domain Expiration = Expired |
| 10 | Domains Expiring in 30 Days | Domain | Domain Expiration = 30 days |
| 11 | Parked / Abandoned Domains | Domain | Parked Domain = true |
| 12 | Unauthorized Contact Review | Contact | Review registrant identity |
| 13 | Exposed RDP | Host, IP | Port 3389 Open |
| 14 | Exposed SSH | Host, IP | Port 22 Open |
| 15 | Exposed Telnet | Host, IP | Port 23 Open |
| 16 | Exposed FTP | Host, IP | Port 21 Open |
| 17 | Non-Standard Web Ports | Host, IP | Ports 8080/8443/8000/8888 Open |
| 18 | Live HTTP Pages (No TLS) | Page | Final Scheme = http, Live = true |
| 19 | Insecure Login Forms | Page | Security Policy = insecure-login-form |
| 20 | Error / Auth Failure Responses | Page | Response Code in [500, 401, 403] |
| 21 | Vulnerable Web Components | Page | CVSS v3 >= 7.0 + Component present |
| 22 | Candidate (Unreviewed) Assets | All | State = Candidate |
| 23 | Assets Requiring Investigation | All | State = Requires Investigation |
| 24 | New Assets (Last 30 Days) | All | Created At >= 30 days ago |
| 25 | Wildcard DNS Records | Host, Domain | Wildcard = true |
