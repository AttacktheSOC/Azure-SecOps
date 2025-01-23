# *Network Activity around Deception Detection*

## Query Information

#### Description
Aids in investigating Deception based alerts.
Pull in all DeviceNetworkEvents within a 2 hour timespan that are tied to a device involved in a deception detection alert.

Disclaimer: This query pulls in a high volume of data, allowing you to get a full picture of what occurred within 2 hours of a detection tirggering

#### References
- https://github.com/AttacktheSOC/PublicTalks/blob/main/Greek%20Microsoft%20Security%20Community/Artifice.pdf

## Defender XDR
```KQL
// Deception triage: Network Conn
// Identify network activity of a device connected related to a deception detection within a 2 hour timespan
let alertID = ""; //change me
let entities = AlertEvidence
| where AlertId == alertID
| where EntityType in ("Machine")
| summarize DeviceId = any(DeviceId) by TimeGenerated, AlertId;
entities
| join DeviceNetworkEvents on $left.DeviceId == $right.DeviceId
| where TimeGenerated1 between (todatetime(TimeGenerated - todatetime(1h)) .. todatetime(TimeGenerated + todatetime(1h)))
| project-away TimeGenerated, DeviceId1, Timestamp
| project-rename TimeGenerated = TimeGenerated1
| sort by TimeGenerated
```
