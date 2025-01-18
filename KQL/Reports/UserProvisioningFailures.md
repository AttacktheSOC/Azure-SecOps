# *User Provisioning Failures*

## Query Information

#### Description
Identify (API/SCIM) user provisioning failures related to enterprise applications provisioning and pull the error information.

## Defender XDR
```KQL
// Retrieve a report on the latest application user provisioning (api/scim) failures
AuditLogs
| where OperationName == @"Process escrow" and Result == @"failure"
| extend ApplicationName = tostring(parse_json(TargetResources)[0]["displayName"])
| extend TargetUserDisplayName = tostring(parse_json(TargetResources)[1]["displayName"])
| extend ErrorDetails = substring(ResultDescription, indexof(ResultDescription, "Error:"))
| summarize arg_max(TimeGenerated, ErrorDetails) by ApplicationName, TargetUserDisplayName
```
