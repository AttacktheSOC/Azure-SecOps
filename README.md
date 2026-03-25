# Azure-SecOps

A security operations toolkit for Microsoft Azure, Entra ID, and Microsoft 365 environments. This repository contains **KQL queries, reusable KQL functions, PowerShell automation scripts, ARM templates, and reference guides** to support threat hunting, security monitoring, identity governance, and compliance automation.

---

## What's in This Repository

| Folder | What you'll find |
|---|---|
| [`API/`](./API/) | PowerShell scripts that call the **Microsoft Defender REST API** directly (Secure Score reports, MDE Live Response) |
| [`ARM/`](./ARM/) | **Azure Resource Manager templates** and scripts to deploy Sentinel Logic Apps, Playbooks, and automation |
| [`Azure Resource Graph/`](./Azure%20Resource%20Graph/) | **Azure Resource Graph (ARG) queries** for asset inventory (e.g. VMs missing Defender for Endpoint) |
| [`DefenderforCloud/`](./DefenderforCloud/) | Scripts and reports for **Microsoft Defender for Cloud** (Defender for Servers plan audit) |
| [`EASM/`](./EASM/) | **Defender EASM** filter search guide and scripts for external attack surface discovery |
| [`Graph/`](./Graph/) | **Microsoft Graph PowerShell** scripts for Entra ID automation (users, groups, service principals) |
| [`KQL/`](./KQL/) | **KQL detection queries** organised by category: Endpoint, Identity, Okta, Email, UEBA, and more |
| [`KQL-Functions/`](./KQL-Functions/) | Reusable **KQL functions** (save once to your workspace and call from any query) |
| [`Policy/`](./Policy/) | Scripts to automate **Azure Policy** remediation tasks at scale |
| [`Sentinel/`](./Sentinel/) | **Microsoft Sentinel** data connectors, workbooks, and log source reference guides |

---

## Prerequisites

Different parts of this repository have different requirements. Find the section that matches what you want to use.

### KQL Queries and Functions

No local software installation is required. You need:

- Access to a **Microsoft Sentinel** workspace or a **Log Analytics** workspace in the Azure portal.

New to KQL? → [Kusto Query Language overview](https://learn.microsoft.com/azure/data-explorer/kusto/query/)

---

### Graph PowerShell Scripts (`Graph/`)

These scripts use the [Microsoft Graph PowerShell SDK](https://learn.microsoft.com/powershell/microsoftgraph/overview).

**Requirements:**

- [PowerShell 7+](https://learn.microsoft.com/powershell/scripting/install/installing-powershell)
- Microsoft Graph PowerShell module:

  ```powershell
  Install-Module Microsoft.Graph -Scope CurrentUser
  ```

- Sign in before running a script:

  ```powershell
  Connect-MgGraph -Scopes "User.Read.All","Group.Read.All"
  ```

  > The required scopes vary per script. Check the comments at the top of each script file for the specific scopes needed.

Full setup guide → [Get started with Microsoft Graph PowerShell](https://learn.microsoft.com/powershell/microsoftgraph/get-started)

---

### Az PowerShell Scripts (`ARM/`, `DefenderforCloud/`, `EASM/`, `Policy/`)

These scripts use the [Azure PowerShell (Az) module](https://learn.microsoft.com/powershell/azure/what-is-azure-powershell).

**Requirements:**

- [PowerShell 7+](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) (PowerShell 5.1 may work for some scripts)
- Azure PowerShell module:

  ```powershell
  Install-Module Az -Scope CurrentUser
  ```

- Sign in to Azure before running a script:

  ```powershell
  Connect-AzAccount
  ```

Full setup guide → [Install Azure PowerShell](https://learn.microsoft.com/powershell/azure/install-azure-powershell)  
Authentication guide → [Sign in with Azure PowerShell](https://learn.microsoft.com/powershell/azure/authenticate-azureps)

---

### API Scripts (`API/`)

These scripts call the Microsoft Defender REST API directly using PowerShell. They require:

- An **Entra ID App Registration** (or Managed Identity) with the appropriate Defender API permissions.
- Either the **Az module** (`Connect-AzAccount`) or a pre-configured service principal for token acquisition.

> Check the comments at the top of each script for the specific API permissions required.

---

### ARM Templates (`ARM/`, `Sentinel/`)

ARM templates can be deployed via the Azure portal, Azure CLI, or Azure PowerShell.

- **Portal**: Use the *Deploy a custom template* option in the Azure portal and upload the JSON file.
- **PowerShell**:

  ```powershell
  Connect-AzAccount
  New-AzResourceGroupDeployment -ResourceGroupName "<rg>" -TemplateFile "<template>.json"
  ```

Deployment guide → [Deploy resources with ARM templates](https://learn.microsoft.com/azure/azure-resource-manager/templates/deploy-powershell)

---

## Quick Start by Use Case

**I want to hunt for threats in Sentinel**  
Browse [`KQL/`](./KQL/) — queries are organised by category (Endpoint, Identity, Okta, etc.). Copy a query directly into the Log Analytics query editor.

**I want to save a reusable function in my workspace**  
See [`KQL-Functions/`](./KQL-Functions/). Each file contains the function body and an example call. Follow the [KQL functions guide](https://learn.microsoft.com/azure/data-explorer/kusto/query/functions/user-defined-functions) to save them to your workspace.

**I want to manage Entra ID users, groups, or service principals**  
See [`Graph/`](./Graph/). Install the Graph PowerShell module, sign in with `Connect-MgGraph`, then run the relevant script.

**I want to audit Defender for Servers pricing across my environment**  
See [`DefenderforCloud/Reporting/`](./DefenderforCloud/Reporting/). Full prerequisites and usage are documented in the [folder README](./DefenderforCloud/Reporting/README.md).

**I want to discover my external attack surface**  
See [`EASM/`](./EASM/) for a filter search reference guide with 25 ready-to-use searches for the Defender EASM inventory.

**I want to automate Azure Policy remediation**  
See [`Policy/`](./Policy/). Requires the Az module and a role with `Microsoft.PolicyInsights/remediations/write` permission.

**I want to deploy a Sentinel data connector or workbook**  
See [`Sentinel/`](./Sentinel/). Each sub-folder contains a README and/or ARM template with deployment steps.

---

## Contributions & Feedback

This is an evolving repository — new queries and scripts are added based on emerging threats and operational needs. Contributions, suggestions, and feedback are welcome.

Feel free to open an **issue** or submit a **pull request** if you have queries or scripts to share.

---
