# SentinelCostReport Logic App

Deploys a Logic App that queries **Azure Cost Management** for Sentinel resource group spend, queries **Log Analytics** for top table ingestion trends (with sparklines), generates an HTML report, and emails it on a weekly schedule via **Office 365 Outlook**.

## Deploy

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAttacktheSOC%2FAzure-SecOps%2Fmain%2FARM%2FLogicApps%2FSentinelCostReport%2FSentinelCostReport.json)

## Parameters

| Parameter | Required | Default | Description |
|---|---|---|---|
| `logicAppName` | No | `SentinelCostReport` | Name of the Logic App resource |
| `location` | No | Resource group location | Azure region for all resources |
| `sentinelResourceGroupName` | **Yes** | — | Resource group containing Sentinel resources. Cost queries are scoped here |
| `sentinelSubscriptionId` | No | Current subscription | Subscription ID containing the Sentinel resource group |
| `logAnalyticsWorkspaceId` | **Yes** | — | Workspace ID (GUID) — found in Log Analytics workspace → Properties |
| `lookbackDays` | No | `30` | Days of cost and ingestion data to include (1–90) |
| `topNTables` | No | `10` | Number of top ingestion tables shown in the report (1–50) |
| `scheduleDay` | No | `Monday` | Day of the week to send the report |
| `scheduleHour` | No | `8` | Hour (UTC) to send the report (0–23) |
| `emailRecipients` | **Yes** | — | Semicolon-separated list of report recipients |
| `emailSubject` | No | `Weekly Sentinel Cost & Ingestion Report` | Email subject prefix |
| `o365ConnectionName` | No | `office365-sentinel-report` | Name of the Office 365 API connection resource |

## Post-Deployment Steps

1. **Authorize the Office 365 connection** — in the Azure Portal, open the deployed API connection (`office365-sentinel-report`) → **Edit API connection** → sign in with the account that will send emails → **Save**.
2. **Verify RBAC** — the ARM template assigns the Logic App's system-assigned managed identity two roles on the Sentinel resource group:
   - `Cost Management Reader` — for cost data
   - `Log Analytics Reader` — for ingestion data

   If your deployment account lacks `Microsoft.Authorization/roleAssignments/write` on the resource group, assign these roles manually.
3. **Enable the Logic App** — confirm it is in the **Enabled** state and trigger a manual run to validate the end-to-end flow before the scheduled run fires.

## Requirements

- An existing Log Analytics workspace with Microsoft Sentinel enabled
- An Office 365 / Exchange Online mailbox to send from
- Deploying account must have Contributor + User Access Administrator (or Owner) on the target resource group to create role assignments
