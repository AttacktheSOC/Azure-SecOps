# Set your variables
param (
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    [Parameter(Mandatory=$true)]
    [string]$WorkspaceName
)

# Requires: Az.Accounts module
# Connect first: Connect-AzAccount

# Get an access token
try {
    $token = (Get-AzAccessToken -ResourceUrl "https://management.azure.com/").Token
    if ($token -is [System.Security.SecureString]) {
        $token = [System.Net.NetworkCredential]::new("", $token).Password
    }
} catch {
    Write-Warning "Failed to get Azure access token. Please run 'Connect-AzAccount' first. Error: $_"
    return
}

# Build the REST API URI
$uri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/tables?api-version=2025-02-01"

# Make the API call
$response = Invoke-RestMethod -Method GET -Uri $uri -Headers @{ Authorization = "Bearer $token" }

# Parse the response
$tablesRaw = $response.value.properties | ConvertTo-Json
$tables = $tablesRaw | ConvertFrom-Json

# Prepare output
$results = @()

foreach ($table in $tables) {
    $results += [pscustomobject]@{
        TableName       = $table.schema.name
	TableType	= $table.schema.tableType
        TablePlan       = $table.plan
        RetentionInDays = $table.retentionInDays
	TotalRetention 	= $table.totalRetentionInDays
	ArchiveRetention	= $table.archiveRetentionInDays
	TotalRetentioDefault	= $table.totalRetentionInDaysAsDefault 
    }
}

# Output to CSV
$outputPath = ".\SentinelTables.csv"
$results | Export-Csv -Path $outputPath -NoTypeInformation

Write-Host "Table info exported to: $outputPath"
