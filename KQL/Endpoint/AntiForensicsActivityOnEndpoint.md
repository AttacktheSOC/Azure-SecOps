# *Anti-Forensics Activity on Endpoint*

## Query Information

### MITRE ATT&CK Technique(s)

| Technique ID | Title | Link |
|-------------|----------------------------------|------------------------------------------------------|
| T1070.004 | Indicator Removal: File Deletion | [MITRE T1070.004](https://attack.mitre.org/techniques/T1070/004/) |
| T1070.001 | Indicator Removal: Clear Windows Event Logs | [MITRE T1070.001](https://attack.mitre.org/techniques/T1070/001/) |
| T1070.003 | Indicator Removal: Clear Command History | [MITRE T1070.003](https://attack.mitre.org/techniques/T1070/003/) |
| T1070.006 | Indicator Removal: Timestomp | [MITRE T1070.006](https://attack.mitre.org/techniques/T1070/006/) |
| T1564.004 | Hide Artifacts: NTFS File Attributes | [MITRE T1564.004](https://attack.mitre.org/techniques/T1564/004/) |
| T1490 | Inhibit System Recovery (Shadow Copies Deletion) | [MITRE T1490](https://attack.mitre.org/techniques/T1490/) |

### Description  
This query detects potential anti-forensic activities by monitoring suspicious executions of built-in Windows utilities commonly used to erase forensic data. It focuses on detecting file deletion, event log clearing, NTFS timestamp manipulation (timestomping), and shadow copy deletion. These techniques are often used by attackers to evade detection and cover tracks.

### Risk  
This activity is high-risk, as it indicates potential intentional anti-forensic activities. Attackers often use these techniques post-compromise to remove traces of execution, making investigation and incident response significantly harder. If detected, immediate investigation is required to assess potential lateral movement, privilege escalation, or destructive actions.

#### Author
- **Name:** Dylan Tenebruso
- **Github:** https://github.com/AttacktheSOC
- **Twitter:** https://x.com/DylanInfosec
- **LinkedIn:** https://www.linkedin.com/in/dylten6
- **Website:** https://attackthesoc.com

## Defender XDR
```KQL
DeviceProcessEvents
| where FileName in~ ("rundll32.exe", "fsutil.exe", "wevtutil.exe", "auditpol.exe", "bcdedit.exe", "sdelete.exe", "cipher.exe", "wmic.exe", "powershell.exe", "cmd.exe", "del.exe", "vssadmin.exe") 
| where (
    // Clearing Shimcache or AppCompatCache
    (FileName == "rundll32.exe" and ProcessCommandLine has_any ("ShimFlushCache", "BaseFlushAppcompatCache")) 
    // USN Journal tampering
    or (FileName == "fsutil.exe" and ProcessCommandLine has "usn" and ProcessCommandLine !has "queryJournal")
    // Clearing Windows Event Logs
    or (FileName == "wevtutil.exe" and ProcessCommandLine has_any ("cl", "clear-log"))
    or (FileName == "powershell.exe" and ProcessCommandLine has_all ("Clear-EventLog"))
    or (FileName == "auditpol.exe" and ProcessCommandLine has "/clear")
    // Secure delete / Encryption overwrite
    or (FileName == "sdelete.exe")
    or (FileName == "cipher.exe" and ProcessCommandLine has "/w")
    // Disabling logging and security settings
    or (FileName == "bcdedit.exe" and ProcessCommandLine has_any ("/set bootstatuspolicy ignoreallfailures", "/set recoveryenabled no"))
    or (FileName == "wmic.exe" and ProcessCommandLine has_all ("shadowcopy", "delete"))
    // Deleting recent files, Prefetch, and browser history
    or (FileName == "cmd.exe" and ProcessCommandLine has "del" and ProcessCommandLine has_any ("\\Microsoft\\Windows\\Recent", "\\Windows\\Prefetch", "history", "cookies", "cache"))
    // Timestomping Detection
    or (FileName == "powershell.exe" and ProcessCommandLine has_all ("Set-ItemProperty", "LastWriteTime")) 
    // Shadow Copy & System Recovery Deletion
    or (FileName == "vssadmin.exe" and ProcessCommandLine has_any ("delete", "resize"))
    or (FileName == "wmic.exe" and ProcessCommandLine has_all ("shadowcopy", "delete"))
    or (FileName == "bcdedit.exe" and ProcessCommandLine has_any ("/delete", "/set safeboot"))
)
```
