# *Live Response via API Session Review* (v.01)

## Query Information

#### MITRE ATT&CK Technique(s)

| Technique ID | Title    | Link    |
| ---  | --- | --- |
| T1059.001 | Command and Scripting Interpreter: PowerShell | https://attack.mitre.org/techniques/T1059/001/ |
| T1059.009 | Command and Scripting Interpreter: Cloud API | https://attack.mitre.org/techniques/T1059/009/ |

#### Description
*this query still needs work and testing* - *Dylan 11-27-2024*

Correlates commands run during a Live Response session initiated via API on individual endpoints using the row_window_session function.
Thanks to @fabian.bader.cloud for pointing out RunLiveResponseApi is now included in the UAL

The results include the Device name, binaries run, and the corresponding Live Response API command string

#### Risk
Live Resposne is a limited RMM tool that can be used to run various commands and deploy files and scripts to endpoints under MDE management.

#### References
- (coming soon)
  
## Defender XDR
```KQL
let lrSessionStarted = CloudAppEvents
| where ActionType == "RunLiveResponseApi"
| extend DeviceId = tostring(parse_json(RawEventData)["DeviceId"])
| extend CommandsString = tostring(parse_json(RawEventData)["CommandsString"])
| project TimeGenerated, DeviceId, CommandsString;
let PIDs = lrSessionStarted 
| join kind=inner DeviceProcessEvents on $right.DeviceId == $left.DeviceId
| extend timeDiff = abs(datetime_diff('second', TimeGenerated1, TimeGenerated))// <= 120
| where timeDiff <= 300 
// Consider commenting out the line above ^^^ played with the idea of joining only where the event 
// occurred within minutes of eachother but there could easily be too much latency though and log ingest lag time
| where InitiatingProcessCommandLine startswith @"""SenseIR.exe"" ""OnlineSenseIR"""
| project DeviceId, ProcessId, CommandsString;
PIDs
| join DeviceProcessEvents on $right.InitiatingProcessId == $left.ProcessId , $right.DeviceId == $left.DeviceId
| where FileName !in ("csc.exe", "conhost.exe") // noisy processes
| where InitiatingProcessFileName == "powershell.exe" and InitiatingProcessFileName == "powershell.exe"
| where ProcessCommandLine !contains "ew0KICAgICJTY2FubmVyQXJncyI" // Disovery scan configs
| where InitiatingProcessCommandLine !contains "eyJEZXRlY3Rpb25LZXlzIjp" // MDE deception lure configs
| sort by DeviceId, TimeGenerated asc
| extend EventSessionId = row_window_session(TimeGenerated, 10m, 3m, DeviceId != prev(DeviceId))
| project DeviceName, TimeGenerated, FileName, ProcessCommandLine, EventSessionId, CommandsString
```
