# *Endpoint with Missing Agents*

## Query Information

#### Description
Report on missing agents from your Defender onboarded machines. This assumes the machines are onboarded into Defender and that you're using an MDM (Intune) to push software to your fleet.
Intune reporting is not always 100%. Sometimes devices fail to comminucate the software install status and remains an unknown issue lurking outside of the "Install status" dashboards purview.

In the query, we find active devices via the DeviceLogonEvents where a user of your org has logged in, in the past x days. The reason being, you may have devices pre-provisioned but not assigned to a user in Intune just yet creating noise in this report.
If your support team has a separate privileged account they use for troubleshooting, testing, etc, consider excluding the logon events.

You'll likely want to look at a known good device to identify the string(s) you'll need for your searches:

#### Risk
If required security software is getting stuck in your MDM at "Waiting to install", between failing and success, you have a hidden issue of unprotected endpoints. Identify these active endpoints with the following queries.

## Identify a specific missing agent
```KQL
let targetAgent = "<SOFTWARENAMESTRING>";
let activeDevices = DeviceLogonEvents
| where TimeGenerated > ago(7d)
| where LogonType == "Interactive"// or LogonType == "RemoteInteractive"
| where AccountDomain =~ "<DOMAIN>" //set your domain
| distinct DeviceName;
DeviceTvmSoftwareInventory
// according to the docs software inventory syncs every 24 hours but I reccomend 
| where DeviceName in~ (activeDevices)
| summarize Software = tostring(make_set(SoftwareName)) by DeviceName
| where Software !has targetAgent
```

## Identify multiple missing agents
```KQL
let targetAgents = dynamic(["", ""]);
let activeDevices = DeviceLogonEvents
| where TimeGenerated > ago(7d)
| where LogonType == "Interactive"// or LogonType == "RemoteInteractive"
| where AccountDomain == "<DOMAIN>" //set your domain
| distinct DeviceName;
DeviceTvmSoftwareInventory
| where DeviceName in~ (activeDevices)
| summarize Software = make_set(SoftwareName) by DeviceName
| extend MissingAgents = set_difference(targetAgents, Software)
| project-away Software
```
