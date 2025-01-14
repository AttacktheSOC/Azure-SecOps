# *Possible AI Bot*

## Query Information

#### MITRE ATT&CK Technique(s)

| Technique ID | Title    | Link    |
| ---  | --- | --- |
| T1119 | Automated Collection | https://attack.mitre.org/techniques/T1119 |
| T1123 | Audio Capture | https://attack.mitre.org/techniques/T1123 |
| T1125 | Video Capture | https://attack.mitre.org/techniques/T1125 |

#### Description
Detect AI Bots that have have been invited/joined a Teams meeting to transcribe the meeting, take notes and/or record the call. 
Many of these solutions bypass Application admin consent by joining via the meeting info URL.

*Disclaimer*: This has a very limited use-case and will not catch all instances. This query assumes the client OS is linux and the agent that joins the call does not user
a legitimate UserId. This query can be easily modified to fit your conditions, maybe the AI bot logs in as a legit user, comment out "| where UserKey == UserId".

## Defender XDR
```KQL
OfficeActivity
| project-keep TimeGenerated, Operation, OfficeWorkload, UserId, UserKey, CommunicationType, ExtraProperties, ClientIP, ItemName, ChatName
| where OfficeWorkload == "MicrosoftTeams"
| where CommunicationType != "GroupChat"
| where UserKey == UserId
| where ExtraProperties has "linux"
```
