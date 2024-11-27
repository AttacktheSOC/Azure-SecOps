# *Live Response Session Review*

## Query Information

#### MITRE ATT&CK Technique(s)

| Technique ID | Title    | Link    |
| ---  | --- | --- |
| T1059.001 | Command and Scripting Interpreter: PowerShell | https://attack.mitre.org/techniques/T1059/001/ |
| T1059.009 | Command and Scripting Interpreter: Cloud API | https://attack.mitre.org/techniques/T1059/009/ |

#### Description
Correlates commands run during a Live Response session on individual endpoints using the row_window_session function.

#### Risk
Live Resposne is a limited RMM tool that can be used to run various commands and deploy files and scripts to endpoints under MDE management.

#### References
- (coming soon)
  
## Defender XDR
```KQL
let PIDs = DeviceProcessEvents
| where InitiatingProcessCommandLine startswith @"""SenseIR.exe"" ""OnlineSenseIR"""
| project DeviceId, ProcessId;
PIDs
| join DeviceProcessEvents on $right.InitiatingProcessId == $left.ProcessId , $right.DeviceId == $left.DeviceId
| where FileName !in ("csc.exe", "conhost.exe") // noisy processes
| where InitiatingProcessFileName == "powershell.exe" and InitiatingProcessFileName == "powershell.exe"
| where ProcessCommandLine !contains "ew0KICAgICJTY2FubmVyQXJncyI" // Disovery scan configs
| where InitiatingProcessCommandLine !contains "eyJEZXRlY3Rpb25LZXlzIjp" // MDE deception lure configs
| sort by DeviceId, TimeGenerated asc
| extend EventSessionId = row_window_session(TimeGenerated, 10m, 3m, DeviceId != prev(DeviceId))
| project DeviceName, TimeGenerated, FileName, ProcessCommandLine, EventSessionId
```
