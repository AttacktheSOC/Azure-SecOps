# Sentinel Playbooks

Azure Logic Apps deployed as Microsoft Sentinel automation playbooks. Each playbook is packaged as a self-contained ARM template and can be deployed directly from the buttons below.

---

## Playbooks

| Playbook | Trigger | Description |
|---|---|---|
| [Formatted Incident Notification](#formatted-incident-notification---incident-trigger) | Incident creation | Sends a formatted HTML email notification on new Sentinel incidents |

---

## Formatted Incident Notification - Incident trigger

### Overview

A Logic App triggered by the **Microsoft Sentinel incident-creation webhook**. On each new incident it:

1. Maps severity (`High` / `Medium` / `Low` / `Informational`) to a hex color used throughout the email.
2. Selects up to **10 related entities** and renders them in a table (friendly name + entity type).
3. Collects any **incident labels**.
4. Composes a single **HTML email** that includes:
   - Incident number, title, and workspace name in a color-coded header banner
   - Severity badge, status, alert count, created timestamp (UTC), owner, and source alert products
   - Description (falls back to the first alert description if the incident description is empty)
   - MITRE ATT&CK tactics and techniques
   - Entities table (up to 10)
   - Labels section (omitted when empty)
   - *View in Microsoft Defender* button linking to the Defender portal
5. Sends the email via the **Office 365 Outlook** connector (`Send_email_V2`). High-severity incidents set email `Importance: High`.

**Connections required**

| Connection | Type | Auth |
|---|---|---|
| `azuresentinel` | Azure Sentinel managed API | System-assigned Managed Identity |
| `office365` | Office 365 Outlook managed API | OAuth (delegated user) |

The Logic App is deployed in a **Disabled** state and must be enabled after post-deployment steps are complete.

### Deploy to Azure

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAttacktheSOC%2FAzure-SecOps%2Fmain%2FSentinel%2FPlaybooks%2FFormatted-IncidentNotification.json)

### Parameters

| Parameter | Required | Default | Description |
|---|---|---|---|
| `logicAppName` | No | `Sentinel-IncidentNotification` | Resource name for the Logic App |
| `location` | No | Resource group location | Azure region for all deployed resources |
| `recipientAddress` | **Yes** | — | Semicolon-separated recipient email addresses |
| `logoUrl` | No | *(empty)* | URL to a logo image displayed at the top of the email; omit to hide |
| `azuresentinel_Connection_Name` | No | `azuresentinel` | Name for the Azure Sentinel API connection resource |
| `office365_Connection_Name` | No | `office365` | Name for the Office 365 Outlook API connection resource |

### Post-Deployment Steps

1. **Authorize the Office 365 connection**  
   In the Azure portal, navigate to the deployed `office365` API connection → **Edit API connection** → **Authorize**, and sign in with a licensed Microsoft 365 account that has a mailbox. Save the connection.

2. **Enable the Logic App**  
   The playbook deploys in a disabled state. Once the Office 365 connection is authorized, navigate to the Logic App → **Overview** → **Enable**.

3. **Attach to a Sentinel Automation Rule**  
   In Microsoft Sentinel, go to **Configuration → Automation** → **Create → Automation rule**. Set the trigger to *When incident is created*, add an action of *Run playbook*, and select this Logic App. Scope the rule to the analytic rules or severity levels you want covered.

---
