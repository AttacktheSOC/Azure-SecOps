# *Interesting Network Activity (Aggregated)*

## Query Information
#### Description
Aids in investigationg Deception based alerts.

Identifies interesting network activity by utilizing the aggregated reporting logs. Specifically searching for RemoteIPs with a high volume of connections to hosts implicated in deception-based alerts.

#### References
- https://github.com/AttacktheSOC/PublicTalks/blob/main/Greek%20Microsoft%20Security%20Community/Artifice.pdf

## Defender XDR
```KQL
// Deception triage: Network Conn
// Identify interesting network connections to a device related to a deception detection
let alertID = ""; // change me
let activityThreshold = 10; // Adjust as necessary
let entities = AlertEvidence
| where AlertId == alertID
| where EntityType in ("Machine")
| summarize DeviceId = any(DeviceId) by TimeGenerated, AlertId;
entities
| join DeviceNetworkEvents on $left.DeviceId == $right.DeviceId
| where TimeGenerated1 between ((TimeGenerated - 1h) .. (TimeGenerated + 1h))
| where ActionType endswith "AggregatedReport"
| extend uniqueEventsAggregated = toint(extractjson("$.uniqueEventsAggregated", ["AdditionalFields"]))
| summarize Total = sum(uniqueEventsAggregated) by RemoteIP, ActionType
| where Total > activityThreshold
```
