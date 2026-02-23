# Using the Microsoft Sentinel Workbooks in This Repo

This folder contains **Microsoft Sentinel workbook templates** (JSON) that you can import into your own Sentinel workspace to visualize and investigate data. [1](https://github.com/AttacktheSOC/Azure-SecOps) [2](https://learn.microsoft.com/en-us/azure/sentinel/monitor-your-data)

> **Good to know:** Sentinel workbooks are built on **Azure Monitor Workbooks** and are saved as **Azure resources**, so you can control access using **Azure RBAC**. [2](https://learn.microsoft.com/en-us/azure/sentinel/monitor-your-data)

---

## Prerequisites

- **A Microsoft Sentinel workspace** (Log Analytics workspace with Sentinel enabled). [2](https://learn.microsoft.com/en-us/azure/sentinel/monitor-your-data)  
- **Data connected** that matches what the workbook queries (for example Entra ID sign-ins, Defender, etc.); otherwise tiles will show “no data” or errors. [2](https://learn.microsoft.com/en-us/azure/sentinel/monitor-your-data)  
- **Permissions**: at minimum **Workbook Reader** to view and **Workbook Contributor** to create/edit (at the workspace resource group scope). [2](https://learn.microsoft.com/en-us/azure/sentinel/monitor-your-data)  

---

## Where to Use Workbooks (Portal Notes)

- You can **view Sentinel workbooks in the Microsoft Defender portal**, but **editing/creating** capabilities may still require the **Azure portal experience** depending on your tenant and feature state. [3](https://techcommunity.microsoft.com/blog/microsoftsentinelblog/whats-new-view-microsoft-sentinel-workbooks-directly-from-unified-soc-operations/4356094) [2](https://learn.microsoft.com/en-us/azure/sentinel/monitor-your-data)  
- Microsoft has announced a transition where Sentinel’s Azure portal experience is being retired in favor of the Defender portal (plan accordingly if your org is standardizing). [2](https://learn.microsoft.com/en-us/azure/sentinel/monitor-your-data)  

---

## Option A (Recommended): Import via Microsoft Sentinel → Workbooks → Advanced Editor

Use this method when you want to quickly import a workbook JSON from GitHub.

### Step-by-step

1. **Open the workbook JSON in GitHub**
   - Browse to this repo’s workbook JSON file, then select **RAW** to view the full JSON content. [1](https://github.com/AttacktheSOC/Azure-SecOps) [4](https://charbelnemnom.com/import-export-share-workbooks-in-azure-sentinel/)  

2. **Copy the JSON**
   - In the RAW view, select all (`Ctrl + A`) and copy (`Ctrl + C`). [4](https://charbelnemnom.com/import-export-share-workbooks-in-azure-sentinel/)  

3. **Open Sentinel Workbooks**
   - Azure portal → **Microsoft Sentinel** → select your workspace → **Workbooks** (under Threat Management). [2](https://learn.microsoft.com/en-us/azure/sentinel/monitor-your-data) [4](https://charbelnemnom.com/import-export-share-workbooks-in-azure-sentinel/)  

4. **Create a new workbook**
   - Select **+ Add workbook**. [4](https://charbelnemnom.com/import-export-share-workbooks-in-azure-sentinel/)  

5. **Open Advanced Editor**
   - Select **Edit** (pencil icon), then select the **</> Advanced Editor** button. [4](https://charbelnemnom.com/import-export-share-workbooks-in-azure-sentinel/)  

6. **Paste JSON and Apply**
   - Delete the default template JSON, paste the copied workbook JSON, then select **Apply**. [4](https://charbelnemnom.com/import-export-share-workbooks-in-azure-sentinel/)  

7. **Save the workbook**
   - Give it a name and save it to the appropriate **subscription/resource group/location**.
   - Choose **Shared** vs **My reports** based on whether you want others to access it. [4](https://charbelnemnom.com/import-export-share-workbooks-in-azure-sentinel/) [2](https://learn.microsoft.com/en-us/azure/sentinel/monitor-your-data)  

---

## Common Troubleshooting

- **“No data” tiles**
  - Confirm the workbook’s data sources are connected and the tables referenced in KQL exist in your workspace (or adjust queries/parameters). [2](https://learn.microsoft.com/en-us/azure/sentinel/monitor-your-data)  

- **Permission errors**
  - Ensure you have **Workbook Contributor** (or equivalent) on the workspace resource group to save/edit. [2](https://learn.microsoft.com/en-us/azure/sentinel/monitor-your-data)  

- **KQL failures after import**
  - Some workbooks expect specific solutions/connectors/content hub items; update table names, workspace parameters, or time ranges as needed. [2](https://learn.microsoft.com/en-us/azure/sentinel/monitor-your-data)  

---

## Updating Workbooks from This Repo

- Re-import the updated JSON using the same **Advanced Editor** flow, or use ARM-based deployments for consistent versioning. [4](https://charbelnemnom.com/import-export-share-workbooks-in-azure-sentinel/) [5](https://learn.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-automate)  
- Consider keeping a small changelog in your environment to track which workbook version is deployed where. [5](https://learn.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-automate)  

---

## References

- Repo: https://github.com/AttacktheSOC/Azure-SecOps [1](https://github.com/AttacktheSOC/Azure-SecOps)  
- Microsoft Learn: Visualize and monitor your data by using workbooks in Microsoft Sentinel [2](https://learn.microsoft.com/en-us/azure/sentinel/monitor-your-data)  
- Guide: Import/Export/Share Workbooks in Microsoft Sentinel (Advanced Editor steps) [4](https://charbelnemnom.com/import-export-share-workbooks-in-azure-sentinel/)  
- Microsoft Learn: Programmatically manage workbooks (ARM templates) [5](https://learn.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-automate)  
- Microsoft Sentinel blog: View workbooks in Defender portal [3](https://techcommunity.microsoft.com/blog/microsoftsentinelblog/whats-new-view-microsoft-sentinel-workbooks-directly-from-unified-soc-operations/4356094)  
