# Cisco Meraki Events via REST API – Codeless Connector for Microsoft Sentinel

## Overview

This solution enables you to ingest Cisco Meraki organization events (Security Events, Configuration Changes, and API Requests) into Microsoft Sentinel using the Cisco Meraki REST API. The connector leverages DCR-based ingestion time transformations for data normalization and parsing, supporting ASIM schemas for Network Session, Web Session, and Audit Event logs.

**Key Features:**
- Ingests Meraki Security Events, Configuration Changes, and API Requests.
- Supports DCR-based ingestion-time filtering and normalization.
- Maps data to ASIM schemas for advanced analytics in Sentinel.
- Enables custom alerting and investigation workflows.

---

## Deploy to Azure

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com/<YOUR_GITHUB_ORG>/<YOUR_REPO>/main/mainTemplate.json)

---

## Parameters and Expected Inputs

| Parameter           | Description                                                                 | Required | Default/Notes                                                                                  |
|---------------------|-----------------------------------------------------------------------------|----------|-----------------------------------------------------------------------------------------------|
| `workspace`         | **Workspace name for Log Analytics** where Microsoft Sentinel is set up.    | Yes      | **User must enter the Log Analytics Workspace name.**                                          |
| `merakiSiteName`    | Short alphanumeric nickname for this Meraki connection (max 8 chars).       | Yes      | **User must enter a short, alphanumeric-only site name.**                                      |
| `workspace-location`| The location of your Sentinel Workspace (e.g., eastus, centralus, etc.).    | No       | Defaults to the resource group location. Usually, the default is fine.                         |
| `resourceGroupName` | Resource group name where Microsoft Sentinel is set up.                     | No       | Defaults to the current resource group.                                                        |
| `subscription`      | Subscription ID where Microsoft Sentinel is set up.                         | No       | Defaults to the current subscription.                                                          |
|**Post-Deployment**|----|---|---|
| `apikey`            | Cisco Meraki REST API Key.                                                  | Yes      | Obtain from Meraki dashboard ([instructions](https://aka.ms/ciscomerakiapikey)).               |
| `organization`      | Cisco Meraki Organization ID.                                               | Yes      | Obtain using the API key ([instructions](https://aka.ms/ciscomerakifindorg)).                  |

> **Note:** Most defaults are sufficient for typical deployments, but you **must** provide values for `workspace` and `merakiSiteName`.

---

## What Happens When You Click "Deploy to Azure"?

1. **ARM Template Deployment:**  
   The ARM template provisions the necessary resources and configurations in your Azure environment to enable the Cisco Meraki data connector for Microsoft Sentinel.

2. **User Input Required:**  
   - **Log Analytics Workspace Name (`workspace`):**  
     Enter the name of your existing Log Analytics Workspace where Microsoft Sentinel is enabled.
   - **Meraki Site Name (`merakiSiteName`):**  
     Provide a short, unique, alphanumeric-only nickname (max 8 characters) for this Meraki connection.

3. **Connector Setup:**  
   The solution configures REST API pollers to fetch:
   - Security Events (IDS Alerts)
   - API Requests
   - Configuration Changes

   These are ingested into your Log Analytics workspace and mapped to the appropriate ASIM tables for use in Sentinel.

4. **Post-Deployment:**  

   - **Cisco Meraki API Key (`apikey`):**  
     Generate and enter your Meraki API key.
   - **Cisco Meraki Organization ID (`organization`):**  
     Enter your Meraki Organization ID.

   - Data from Meraki will begin flowing into Sentinel.
   - You can use built-in queries and dashboards to analyze Meraki events.
   - Custom alerts and automation can be configured based on ingested data.

---

## Prerequisites

- An active Azure subscription with Microsoft Sentinel enabled.
- A Log Analytics Workspace.
- Cisco Meraki account with API access enabled.
- API Key and Organization ID from your Meraki dashboard.

---

## Additional Resources

- [Cisco Meraki API Documentation](https://developer.cisco.com/meraki/api-latest/)
- [Microsoft Sentinel Documentation](https://aka.ms/azuresentinel)
- [Codeless Connector Platform (CCP)](https://docs.microsoft.com/azure/sentinel/create-codeless-connector?tabs=deploy-via-arm-template%2Cconnect-via-the-azure-portal)

---

## Support

For issues or questions, contact [Microsoft Support](https://support.microsoft.com) or email support@microsoft.com.
