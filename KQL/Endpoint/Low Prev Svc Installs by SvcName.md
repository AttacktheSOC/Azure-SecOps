# *Low Prevalence Service Installations by Service Name*

## Query Information
#### Description
Identify services installations with a low prevalence in  your environment. This query determines low prevelance service installs by the name of the service.

Disclaimer: This query uses the **ServiceInstalled** ActionType which is gathered via the Windows event ID 4697, which requires the advanced security audit setting Audit Security System Extension.

## Defender XDR
```KQL
let susServices = DeviceEvents
| where ActionType == "ServiceInstalled"
| extend AdditionalFieldsParsed = parse_json(AdditionalFields)
| evaluate bag_unpack(AdditionalFieldsParsed)
//| where ServiceStartType != 3 // uncomment to exclude services installed with a start type of Manual
| extend ServiceName = extract("^[a-zA-Z]+", 0, ServiceName)
| summarize any(ReportId), count() by ServiceName
| where count_ <= 3
| project any_ReportId;
DeviceEvents
| where ActionType == "ServiceInstalled" and ReportId in (susServices)
| extend AdditionalFieldsParsed = parse_json(AdditionalFields)
| evaluate bag_unpack(AdditionalFieldsParsed)
| where ServiceStartType != 3
| extend ServiceName = extract("^[a-zA-Z]+", 0, ServiceName)
```
