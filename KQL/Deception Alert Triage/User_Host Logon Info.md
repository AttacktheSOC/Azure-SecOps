# *User -> Host Logon Info*

## Query Information
#### Description
Aids in investigating Deception based alerts.

Identify all DeviceLogonEvents within a 2 hour timespan associated with devices implicated in a deception-based alert

#### References
- https://github.com/AttacktheSOC/PublicTalks/blob/main/Greek%20Microsoft%20Security%20Community/Artifice.pdf

## Defender XDR
```KQL
// Deception triage: Host/Acct
// This query assumes the decoy was used on an MDE managed device
// Identify the account that hit the decoy and how it accessed the system
let alertID = ""; // change me
let entities = AlertEvidence
| where AlertId == alertID
| where EntityType in ("Machine", "User")
| summarize DeviceId = any(DeviceId), AccountName = any(AccountName) by TimeGenerated, AlertId;
entities
| join DeviceLogonEvents on $left.DeviceId == $right.DeviceId and $left.AccountName == $right.AccountName
| where TimeGenerated1 between ((TimeGenerated - totimespan(1h)) .. (TimeGenerated + totimespan(1h)))
| project-away TimeGenerated, DeviceId1, Timestamp
| project-rename TimeGenerated = TimeGenerated1
| sort by TimeGenerated
// Keep an eye out for logins at odd hours or remote logins
//| where parse_json(AdditionalFields).IsLocalLogon == false
//| where isnotempty(RemoteIP)
```
