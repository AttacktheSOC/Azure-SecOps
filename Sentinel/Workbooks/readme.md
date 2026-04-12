# Sentinel Workbooks

Microsoft Sentinel workbook templates for visualizing and operating on workspace data. Workbooks are Azure Monitor Workbook resources scoped to a Log Analytics workspace and controlled via Azure RBAC.

---

## Workbooks

### 1. Modified WAF Events

**File:** `Modified WAF Events playbook.json` (ARM template)

**Description:** Visualizes Azure Web Application Firewall (WAF) events from both **Application Gateway WAF** and **Azure Front Door WAF** in a single pane. Displays blocked and detected rule hits with client IP, request URI, matched rule, and rule set details. Includes an optional section to trigger a Logic App playbook directly on a selected WAF event.

**Data sources required:**
- `AzureDiagnostics` – WAF diagnostic logs from Application Gateway (`ApplicationGatewayFirewall` category) and/or Front Door (`FrontDoorWebApplicationFirewallLog` category) must be streamed to your Log Analytics workspace.
- `FakeData` - This workbook contains an auto-generated table of fake logs to ensure you can follow the blog post: [Operational Workbooks - AttacktheSOC.com](https://attackthesoc.com/posts/operational-workbooks-ep1)

**Permissions required:**

| Role | Scope | Purpose |
|---|---|---|
| **Workbook Contributor** (or Owner/Contributor) | Resource group | Deploy and save the workbook |
| **Log Analytics Reader** | Log Analytics workspace | Query WAF diagnostic data |
| **Logic App Contributor** *(optional)* | Logic App resource group | Use the Run Playbook feature |

**Deploy to Azure (ARM template):**

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAttacktheSOC%2FAzure-SecOps%2Fmain%2FSentinel%2FWorkbooks%2FModified%2520WAF%2520Events%2520playbook.json)

The template accepts four parameters:

| Parameter | Default | Notes |
|---|---|---|
| `workbookDisplayName` | `Modified WAF Workbook` | Friendly name shown in the workbook gallery |
| `workbookType` | `sentinel` | Gallery type; keep as `sentinel` for Sentinel workbooks |
| `workbookSourceId` | placeholder workspace resource ID | **Replace** with your Log Analytics workspace resource ID (format: `/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.OperationalInsights/workspaces/{workspaceName}`) |
| `workbookId` | `[newGuid()]` | Leave as default to auto-generate |

**Post-deployment steps:**
1. Ensure WAF diagnostic logs are routed to your Log Analytics workspace (Application Gateway / Front Door → Diagnostic settings → send `ApplicationGatewayFirewall` or `FrontDoorWebApplicationFirewallLog` to your workspace).
2. Open the workbook and select your subscription and workspace in the parameter dropdowns.
3. *(Optional)* To use **Run Playbook**: toggle on the "Run Playbook on selection?" parameter, then specify the resource group, Logic App name, and trigger name. Only Logic Apps with an **incident trigger** are supported.

---

### 2. Sentinel Table Retention – Decouple Total Retention

**File:** `TableManager.workbook` (raw workbook JSON – import via Advanced Editor)

**Description:** Operational workbook for managing Log Analytics table retention settings. Lists all tables in a selected workspace with their current analytics retention, total retention, archive retention, and whether total retention is coupled to the workspace default (`totalRetentionInDaysAsDefault`). Clicking a table name fires an ARM `PUT` to set `totalRetentionInDaysAsDefault = false` for that table, decoupling it from the workspace default while preserving the existing `totalRetentionInDays` value.

**Data sources required:**
- Azure Resource Graph (subscription/workspace discovery)
- ARM API – `Microsoft.OperationalInsights/workspaces/{name}/tables` (read and write)

**Permissions required:**

| Role | Scope | Purpose |
|---|---|---|
| **Workbook Contributor** (or Owner/Contributor) | Resource group | Save the workbook |
| **Log Analytics Contributor** | Log Analytics workspace | Read table metadata and issue ARM `PUT` to update table retention |

> A custom role with `Microsoft.OperationalInsights/workspaces/tables/read` and `Microsoft.OperationalInsights/workspaces/tables/write` is sufficient if you prefer least-privilege.

**Deployment – Advanced Editor import:**

This file is a raw workbook JSON (not an ARM template) and must be imported manually.

1. Open the [raw file](https://raw.githubusercontent.com/AttacktheSOC/Azure-SecOps/main/Sentinel/Workbooks/TableManager.workbook) and copy the entire contents (`Ctrl+A`, `Ctrl+C`).
2. Azure portal → **Microsoft Sentinel** → your workspace → **Workbooks** → **+ Add workbook**.
3. Select **Edit** (pencil icon) → **`</> Advanced Editor`**.
4. Replace the default JSON with the copied content → **Apply** → **Save**.
5. Set a name, subscription, resource group, and location, then save as **Shared**.

**Post-deployment steps:**
1. In the workbook, select your **Subscription** and **Workspace**.
2. Wait for the table list to populate (ARM query may take a few seconds).
3. Click any **TableName** link to open the decoupling confirmation blade and confirm.
4. The `TotalRetentionInDaysAsDefault` column updates after ~60–120 seconds; refresh the workbook to verify.

> **Note:** The ARM API version field defaults to `2025-07-01`. If that version is unsupported in your environment, update it to the latest stable `Microsoft.OperationalInsights` API version.

---

## General Prerequisites

- A Microsoft Sentinel-enabled Log Analytics workspace.
- Azure portal access (workbook editing is not available in the Defender portal).
- At minimum **Workbook Reader** to view an existing shared workbook; **Workbook Contributor** to create or edit.

## Troubleshooting

| Symptom | Fix |
|---|---|
| "No data" on WAF tiles | Confirm WAF diagnostic logs are connected and the `AzureDiagnostics` table exists in your workspace |
| ARM action fails in TableManager | Confirm your account has `microsoft.operationalinsights/workspaces/tables/write` on the workspace |
| Tables not loading in TableManager | Verify the selected Subscription/Workspace parameters are correct and you have read access to the workspace |
| KQL errors after import | Check that required data connectors and solutions are enabled; adjust table names or time ranges as needed |

## References

- [Visualize and monitor data with workbooks in Microsoft Sentinel](https://learn.microsoft.com/en-us/azure/sentinel/monitor-your-data)
- [Programmatically manage Azure Monitor workbooks](https://learn.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-automate)
- [Log Analytics tables API reference](https://learn.microsoft.com/en-us/rest/api/loganalytics/tables)
