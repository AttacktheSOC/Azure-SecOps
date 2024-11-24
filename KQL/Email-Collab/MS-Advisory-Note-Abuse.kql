# *MS Advisory Personal Note Abuse*

## Query Information

#### MITRE ATT&CK Technique(s)

| Technique ID | Title    | Link    |
| ---  | --- | --- |
| T1566.002 | Phishing: Spearphishing Link | https://attack.mitre.org/techniques/T1566/002/ |

#### Description
Detects if a forwarded Microsoft Admin Center Advisory has a URL not pointing to a Microsoft owned endpoint.

#### Risk
An attacker could form a convincing email with malicious hyperlinks that will come from the highly trusted "@microsoft.com" domain.

#### References
- https://www.bleepingcomputer.com/news/security/microsoft-365-admin-portal-abused-to-send-sextortion-emails/

## Defender XDR
```KQL
let firstPartyDomains = dynamic(["office.com", "azure.net", "microsoft.com", "azure.com", "aka.ms", "bing.com", "cloud.microsoft", "windowsazure.com", "microsoft365.com"]);
let emailIDs = EmailEvents
| where SenderFromAddress =~ @"o365mc@microsoft.com"
| project NetworkMessageId, RecipientEmailAddress;
EmailUrlInfo
| where NetworkMessageId in (emailIDs)
| extend host_parts = split(UrlDomain, ".")
| extend Domain = strcat(tostring(host_parts[-2]), ".", tostring(host_parts[-1]))
| where UrlLocation == "Body" and Domain !in (firstPartyDomains)
| join emailIDs on NetworkMessageId
| project Timestamp, NetworkMessageId, Url, RecipientEmailAddress, ReportId
```
