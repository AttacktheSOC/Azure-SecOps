param (
    [Parameter(Mandatory=$true)]
    [string]$subscriptionId,
    [Parameter(Mandatory=$true)]
    [string]$resourceGroupName,
    [Parameter(Mandatory=$true)]
    [string]$workspaceName
)

# Requires: Az.Accounts module
# Connect first: Connect-AzAccount

$apiVersion = "2023-04-01-preview"

# -------------------------------
# Authenticate and get Bearer token
# -------------------------------
Write-Host "Getting Azure access token..."
try {
    $token = (Get-AzAccessToken -ResourceUrl "https://management.azure.com/").Token
    if ($token -is [System.Security.SecureString]) {
        $token = [System.Net.NetworkCredential]::new("", $token).Password
    }
} catch {
    Write-Warning "Failed to get Azure access token. Please run 'Connect-AzAccount' first. Error: $_"
    return
}

$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
    "Accept" = "application/json"
    "Origin" = "https://security.microsoft.com"
    "Referer" = "https://security.microsoft.com/"
}

# ----------------------------
# GET EXISTING ALERT RULES
# ----------------------------
Write-Host "Fetching existing alert rules..."
$alertRulesUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/alertRules`?api-version=$apiVersion"
try {
    $existingRulesResp = Invoke-RestMethod -Uri $alertRulesUrl -Headers $headers -Method GET
    $existingRules = @{}
    foreach ($rule in $existingRulesResp.value) {
        $existingRules[$rule.name] = $rule.properties.displayName
    }
    Write-Host "Found $($existingRules.Count) existing alert rules."
} catch {
    Write-Warning "Failed to retrieve existing alert rules: $_"
    return
}

# ----------------------------
# GET CONTENT TEMPLATES
# ----------------------------
Write-Host "Fetching analytic rule templates..."
$templatesUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/contenttemplates`?api-version=$apiVersion&`$filter=(properties/contentKind eq 'AnalyticsRule')"
try {
    $templatesJson = Invoke-RestMethod -Uri $templatesUrl -Headers $headers -Method GET
    Write-Host "Found $($templatesJson.value.Count) analytic rule templates."
} catch {
    Write-Warning "Failed to retrieve content templates: $_"
    return
}

$createdCount = 0
$skippedCount = 0
$failedCount = 0

foreach ($tpl in $templatesJson.value) {
    Write-Host "`nProcessing template: $($tpl.properties.displayName)"

    $mainTemplate = $tpl.properties.mainTemplate
    
    # Check to ensure the template has a valid 'mainTemplate.resources' property
    if ($null -eq $mainTemplate -or $null -eq $mainTemplate.resources) {
        Write-Warning "Template '$($tpl.properties.displayName)' does not have a valid 'mainTemplate.resources' property. Skipping."
        $skippedCount++
        continue
    }

    # Find the AlertRuleTemplates resource nested in the mainTemplate
    $alertRuleResource = $mainTemplate.resources | Where-Object { $_.type -eq "Microsoft.SecurityInsights/AlertRuleTemplates" }

    if ($null -eq $alertRuleResource) {
        Write-Warning "Template '$($tpl.properties.displayName)' does not contain a valid 'AlertRuleTemplates' resource, skipping."
        $skippedCount++
        continue
    }

    $ruleId = $alertRuleResource.name

    if ($existingRules.ContainsKey($ruleId)) {
        Write-Host "Rule '$($tpl.properties.displayName)' already exists in workspace. Skipping."
        $skippedCount++
        continue
    }

    Write-Host "Creating new rule: '$($alertRuleResource.properties.displayName)'"
    
    # Construct the JSON body. Use a hashtable to create a new object.
    $bodyProperties = @{}
    # Copy all properties from the original template
    $alertRuleResource.properties.psobject.Properties | ForEach-Object {
        $bodyProperties[$_.Name] = $_.Value
    }

    $body = @{
        name = $ruleId
        type = "Microsoft.SecurityInsights/alertRules"
        kind = $alertRuleResource.kind
        properties = $bodyProperties
    }
    
    # Set 'enabled' to $true in the final body
    $body.properties.enabled = $true
    
    # Add the 'alertRuleTemplateName' property 
    $body.properties.alertRuleTemplateName = $tpl.properties.contentId
    
    # Convert the PowerShell hashtable to JSON
    $bodyJson = $body | ConvertTo-Json -Depth 10

    <# For debugging purposes
    Write-Host "--- Debugging PUT Request Body ---"
    Write-Host $bodyJson
    Write-Host "------------------------------------"
    #>

    $apiVersion = "2023-04-01-preview"

    $putUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/alertrules/$ruleId`?api-version=$apiVersion"

    try {
        Invoke-RestMethod -Uri $putUrl -Method PUT -Headers $headers -Body $bodyJson
        Write-Host "Success: Created alert rule '$($alertRuleResource.properties.displayName)'."
        $createdCount++
    } catch {
        Write-Warning "Failed to create rule '$($tpl.properties.displayName)': $_"
        $failedCount++
    }
}

# ----------------------------
# SUMMARY
# ----------------------------
Write-Host "`nSummary:"
Write-Host " - Created new rules: $createdCount"
Write-Host " - Skipped (already enabled): $skippedCount"
Write-Host " - Failed: $failedCount"
