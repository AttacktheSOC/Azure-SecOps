# *Conditional Access Policy Gap Detection*

## Query Information

#### MITRE ATT&CK Technique(s)

| Technique ID | Title    | Link    |
| ---  | --- | --- |
| T1078 |	Valid Accounts | https://attack.mitre.org/techniques/T1078/ |

#### Description
This is a collection of detections including a template in relation to my article on Conditional Access Policy Gap detection.
Use these queries to detect violations of your perceived Conditional Access strategy.

#### References
- [Using KQL to Detect Gaps in your Conditional Access Strategy](https://attackthesoc.com/posts/detect-cap-gaps/)

## Require every administrator to perform multifactor authentication
```KQL
let firstPartyIds = dynamic(["c2ada927-a9e2-4564-aae2-70775a2fa0af","04436913-cf0d-4d2a-9cc6-2ffe7f1d3d1c"]);
let excludedResourceIds = dynamic([]);
// initialize list of CAP targeted group members
let CAPTargetGroup = materialize(ExposureGraphEdges
| where EdgeLabel == "member of" and TargetNodeLabel == "group"
| where TargetNodeName == "<GROUP_NAME>"
| distinct SourceNodeName);
let privilegedRoles = dynamic(["Global Administrator", "Application Administrator", "Authentication Administrator", "Billing Administrator", "Cloud Application Administrator", "Conditional Access Administrator", "Exchange Administrator", "Helpdesk Administrator", "Password Administrator", "Privileged Authentication Administrator", "Privileged Role Administrator", "Security Administrator", "SharePoint Administrator", "User Administrator"]);
let CAPTargetAdmins = IdentityInfo
| where AssignedRoles has_any(privilegedRoles)// or isnotempty(PrivilegedEntraPimRoles)
| distinct AccountDisplayName;
SigninLogs
| where Identity in (CAPTargetGroup, CAPTargetAdmins)
| where ResultType == 0
| where AuthenticationRequirement == @"singleFactorAuthentication"
// when looking for single-factor authentication exclude the expected
| where ResourceId !in (firstPartyIds, excludedResourceIds)
| where AppDisplayName != @"Windows Sign In"
| project-away OperationName, OperationVersion, Category, DurationMs, Resource, ResourceGroup, ProcessingTimeInMilliseconds
```

## Require Group Members Access a Specific App from a Trusted Location and via a Company Owned Device
```KQL
let excludedUsers = dynamic([""]);
let CAPTargetGroup = materialize(ExposureGraphEdges
| where EdgeLabel == "member of" and TargetNodeLabel == "group"
| where TargetNodeName == "<GROUP_NAME>"
| distinct SourceNodeName);
SigninLogs
| where ApplicationDisplayName == @"<AppDisplayName>"//ResourceId == @"<resourceId>"
| where ResultType == 0
| where Identity in (CAPTargetGroup) and Identity !in (excludedUsers)
| where NetworkLocationDetails !has "trustedNamedLocation"
| extend DeviceDetail = parse_json(DeviceDetail)
//# Specify expected Device Details
| extend
              IsCompliant = DeviceDetail.isCompliant,
              IsManaged = DeviceDetail.isManaged,
              TrustType = DeviceDetail.trustType
//# modify according to what is expected in your environment
| where IsCompliant == true
| where IsManaged == true              
| where TrustType in ("Workplace", "AzureAD", "ServerAD")
| project-away OperationName, OperationVersion, Category, DurationMs, Resource, ResourceGroup, ProcessingTimeInMilliseconds, DeviceDetail, NetworkLocationDetails
```

## Identify Resource with No Policies Applied to SignIns
```SQL
let firstPartyIds = dynamic(["c2ada927-a9e2-4564-aae2-70775a2fa0af","04436913-cf0d-4d2a-9cc6-2ffe7f1d3d1c"]);
let excludedResourceIds = dynamic([]);
SigninLogs
| where ResultType == 0
| where ResourceTenantId == AADTenantId
| where AuthenticationRequirement == @"singleFactorAuthentication"
| where ConditionalAccessStatus == "notApplied"
// when looking for single factor authentication exclude the expected
| where ResourceId in (firstPartyIds, excludedResourceIds)
| where AppDisplayName != @"Windows Sign In"
| where ResourceTenantId == AADTenantId
```

## Template (incomplete/updates will come; but you should be able to get any missing pieces based on methods used to get other data elements)
```SQL
let firstyPartyIds = dynamic(["c2ada927-a9e2-4564-aae2-70775a2fa0af","04436913-cf0d-4d2a-9cc6-2ffe7f1d3d1c"]);
let privilegedRoles = dynamic(["Global Administrator", "Application Administrator", "Authentication Administrator", "Billing Administrator", "Cloud Application Administrator", "Conditional Access Administrator", "Exchange Administrator", "Helpdesk Administrator", "Password Administrator", "Privileged Authentication Administrator", "Privileged Role Administrator", "Security Administrator", "SharePoint Administrator", "User Administrator"]);
let excludedResourceIds = dynamic([""]);
let CAPTargetGroups = materialize ( ExposureGraphEdges
| where EdgeLabel == "member of" and TargetNodeLabel == "group"
| where TargetNodeName == "<GROUP_NAME>"
| distinct SourceNodeName);
let CAPTargetAdmins = IdentityInfo
| where AssignedRoles has_any(privilegedRoles)
| distinct AccountDisplayName;
SigninLogs
| where Identity in (CAPTargetGroups)
| where ResultType == 0
//# Specify expected included/excluded Client App or comment-out for all
| where ClientAppUsed == @"Mobile Apps and Desktop clients" or ClientAppUsed == @"Browser"
| where AuthenticationRequirement == @"singleFactorAuthentication" or AuthenticationRequirement == @"multiFactorAuthentication"
// when looking for single factor, exclude the expected
| where ResourceId in (firstyPartyIds, excludedResourceIds)
| where AppDisplayName != @"Windows Sign In"
| where ResourceTenantId == AADTenantId
| where ConditionalAccessStatus == "notApplied"
//# Specify expected included/exlcuded ResourceDisplayName (ex. is of CAP excluded apps)
| where ResourceDisplayName != @"" and AppDisplayName != @""
//# Parse out NetworkLocationDetails
| mv-expand NetworkLocationDetails
| extend NetworkLocationDetails = parse_json(NetworkLocationDetails)
| extend NamedLocation = NetworkLocationDetails.networkNames
| extend NetworkType = tostring(NetworkLocationDetails.networkType)
| project-away NetworkLocationDetails
//# Specify expected Device Details
| extend DeviceDetail = parse_json(DeviceDetail)
| extend
              DeviceId = DeviceDetail.deviceId,
              DisplayName = DeviceDetail.displayName,
              OS = DeviceDetail.operatingSystem,
              Browser = DeviceDetail.browser,
              IsCompliant = DeviceDetail.isCompliant,
              IsManaged = DeviceDetail.isManaged,
              TrustType = DeviceDetail.trustType
| project-away DeviceDetail
```
