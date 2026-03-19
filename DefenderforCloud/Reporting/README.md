# Get-D4SPlanReport — Defender for Servers Plan (P1/P2/Free) Report (VM + Arc)

Generates a per-machine report of Microsoft Defender for Servers pricing (P1 / P2 / Free) for Azure VMs and Azure Arc-enabled servers, exporting results to CSV (Excel-friendly) and an optional interactive HTML report.

![HTML D4S report](/DefenderforCloud/Reporting/dashboard.png)

---

## What it does

- Inventories compute resources (Azure VMs + Arc machines) using Azure Resource Graph for inventory.
- Queries the Defender for Cloud “Pricings” REST API for each resource (with subscription fallback when resource scope is unavailable).
- Outputs:
  - DefenderForServersPricing_Report.csv (default)
  - DefenderForServersPricing_Report.html (default; interactive if enabled)

API used (example):
- List pricing configurations at scope:
  - GET https://management.azure.com/{scopeId}/providers/Microsoft.Security/pricings?api-version=2024-01-01

---

## Prerequisites

### Local environment

- PowerShell: Windows PowerShell 5.1 works, but PowerShell 7+ is recommended.
- Required Az modules:
  - Az.Accounts
  - Az.ResourceGraph

Install modules:

    Install-Module Az.Accounts -Scope CurrentUser
    Install-Module Az.ResourceGraph -Scope CurrentUser

### Permissions

- Reader (or higher) on the target subscriptions/resources is typically sufficient to read pricing configuration.

---

## Usage

### 1) Authenticate

    Connect-AzAccount

### 2) Run the script

Single subscription:

    .\Get-D4SPlanReport.ps1 -SubscriptionId "00000000-1111-2222-3333-444444444444"

Multiple subscriptions:

    .\Get-D4SPlanReport.ps1 -SubscriptionId @(
      "00000000-1111-2222-3333-444444444444",
      "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    )

Tenant scope (all accessible subscriptions):

    .\Get-D4SPlanReport.ps1 -ScopeMode Tenant

---

## Parameters

Common parameters supported by the script:

- -SubscriptionId (string[]): Target subscription IDs.
- -ScopeMode (Tenant | Subscriptions): Query across tenant or provided subscriptions.
- -OutCsv (string): CSV output path.
- -OutHtml (string): HTML output path.
- -PageSize (int): ARG paging size (default 1000).
- -MaxRetry (int): Retry attempts for transient ARM errors.

---

## Output

### CSV

Includes fields such as:

- SubscriptionId, ResourceGroup, ResourceName, ResourceType, Location
- PricingTier, SubPlan, EffectivePlan
- Inherited, InheritedFrom, SourceScope, Error

### HTML report (optional)

The HTML report is intended to be an easy-to-share, interactive view (tabs per subscription, searchable/sortable tables, and export buttons) when CDNs are reachable from the viewing browser.

If your network blocks CDNs, the HTML may still render but interactive features (search/export buttons) may not work.

---

## Troubleshooting (quick)

- No export buttons / no table interactivity in HTML:
  - Open browser DevTools → Console and check for missing script load errors.
  - Confirm CDN access to jQuery / DataTables / Buttons.
- Throttling / 429 errors:
  - Increase -MaxRetry or reduce scope (fewer subscriptions).
- EffectivePlan shows “Unknown”:
  - Check the Error column for that row to see which API call failed.

---

## Notes

- This report focuses on the VirtualMachines pricing configuration (Defender for Servers) and normalizes output into EffectivePlan for easy filtering.
- The Pricings API supports subscription scope and resource scope for supported resources, and can return properties such as pricingTier, subPlan, inherited, and inheritedFrom.
