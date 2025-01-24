# *Possible Exfilration Staging Activity*

## Query Information
#### Description
Aids in investigating Deception based alerts. Identify possible exfiltration staging activity via hunting for archiving processes.

Disclaimer: This query currently only detects 7Zip and built-in Tar usage, will add more soon

#### References
- https://github.com/AttacktheSOC/PublicTalks/blob/main/Greek%20Microsoft%20Security%20Community/Artifice.pdf

## Defender XDR
```KQL// Deception triage: Exfil
// Identify archiving activity within a 2 hour timespan of a Deception detection
// more to come, this currently only detects 7Zip and built-in Tar usage.
let alertID = "da66cc5c32-74ff-4e44-a666-2c78ea98a892_1";
let entities = AlertEvidence
| where AlertId == alertID
| where EntityType in ("Process")
| summarize by TimeGenerated, DeviceId;
entities
| join DeviceFileEvents on $left.DeviceId == $right.DeviceId
| where TimeGenerated1 between ((TimeGenerated - 1h) .. (TimeGenerated + 1h))
| where InitiatingProcessVersionInfoCompanyName == @"Igor Pavlov" or InitiatingProcessVersionInfoFileDescription == @"bsdtar archive tool"
```
