# *Potential Shadow Credentials Added to AD Computer Object* 

## Query Information

#### MITRE ATT&CK Technique(s)

| Technique ID | Title    | Link    |
| ---  | --- | --- |
| TA0003 | Persistence | https://attack.mitre.org/tactics/TA0003/ |
| T1098 | Account Manipulation | https://attack.mitre.org/techniques/T1098/ |
| T1078 | Valid Accounts | https://attack.mitre.org/techniques/T1078/ |

#### Description
Detects suspicious additions to the KCL attribute (msDS-KeyCredentialLink) of Computer objects in AD when the write event originates from an IP not previously associated with the target device.

This detection assumes you're pulling the DeviceNetworkInfo table from Defender into you log analytics workspace via the (Defender XDR Connector)[https://learn.microsoft.com/en-us/azure/sentinel/connect-microsoft-365-defender?tabs=MDE] within Sentinel.

#### Risk
Shadow credentials provides attackers to authenticate to the domain as the object it was writtent for and acts as a method of persistence that survives password changes.

#### References
- https://attackthesoc.com/posts/detecting-entity-behavior 
- https://posts.specterops.io/shadow-credentials-abusing-key-trust-account-mapping-for-takeover-8ee1a53566ab 
- https://cyberstoph.org/posts/2022/03/detecting-shadow-credentials/ 

## Sentinel
```KQL
let domainName = ".domain.com"
let kcl_added = materialize ( SecurityEvent
| where EventID == 5136 and OperationType == @"%%14674" // all DS object modified events where a value add operation took place
// now to parse out the EventData XML values to only pull writes to the KCL 
| project EventData
| extend EventDataXml = parse_xml(EventData)
| extend DataElements = EventDataXml["EventData"]["Data"]
| mv-expand DataElement = DataElements
| extend Name = tostring(DataElement["@Name"]), Value = tostring(DataElement["#text"])
| summarize bag = make_bag(bag_pack(Name, Value)) by EventData
| evaluate bag_unpack(bag)
| extend AttributeLDAPDisplayName = column_ifexists('AttributeLDAPDisplayName','x'), OperationType = column_ifexists('OperationType','x'), SubjectLogonId = column_ifexists('SubjectLogonId','x')
| project AttributeLDAPDisplayName, OperationType, SubjectLogonId
| where AttributeLDAPDisplayName == "msDS-KeyCredentialLink"
| project SubjectLogonId);
let correlateLogon = materialize ( SecurityEvent
| where EventID == 4624
| where TargetLogonId in (kcl_added) // looking for the correlated logon events via the SubjectLogoId
| project IpAddress, WorkstationName = tolower(strcat(WorkstationName, domainName)));
DeviceNetworkInfo
| join kind=inner correlateLogon on $left.DeviceName == $right.WorkstationName
// check for any logons where the IP does not match any known IPs associated with the host
| where IPAddresses !has IpAddress
| summarize count() by TargetComputer = WorkstationName, AttackerIP = IpAddress
| project-away count_
```
