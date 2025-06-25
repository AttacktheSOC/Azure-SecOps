# This script retrieves and downloads the provisioning schema for all enterprise applications
# (service principals) that have provisioning (synchronization jobs) enabled.

param (
    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = "./ProvisioningSchemas"
)

# Load module
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
}

Connect-MgGraph -Scopes "Application.Read.All", "Synchronization.Read.All"

try {
    if (-not (Test-Path $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
    }

    Write-Host "Paging through all service principals..."

    $uri = "/v1.0/servicePrincipals?$select=id,displayname"
    $allSPs = @()

    do {
        $resp = Invoke-MgGraphRequest -Method GET -Uri $uri
        $allSPs += $resp.value
        $uri = $resp.'@odata.nextLink'
    } while ($uri)

    Write-Host "Retrieved $($allSPs.Count) service principals."

    foreach ($sp in $allSPs) {
        $spId = $sp.id
        $spName = $sp.displayName -replace '[\/\\:]', '-'
        Write-Host "Checking $spName ($spId)..."

        try {
            $jobsResp = Invoke-MgGraphRequest -Method GET -Uri "/v1.0/servicePrincipals/$spId/synchronization/jobs"

            if ($jobsResp.value.Count -gt 0) {
                $jobId = $jobsResp.value[0].id
                Write-Host "  Found job $jobId — downloading schema..."

                $schema = Invoke-MgGraphRequest -Method GET -Uri "/v1.0/servicePrincipals/$spId/synchronization/jobs/$jobId/schema"

                if ($schema) {
                    $file = Join-Path $OutputDirectory "$spName-$jobId.json"
                    $schema | ConvertTo-Json -Depth 100 | Out-File $file -Encoding UTF8
                    Write-Host "  ✔ Schema saved to $file"
                } else {
                    Write-Warning "  ⚠ No schema for job $jobId"
                }
            } else {
                Write-Host "  — No provisioning jobs"
            }
        } catch {
            Write-Warning "  ❌ Error fetching jobs/schema for ${spName}: $_"
        }
    }
} catch {
    Write-Error "General failure: $_"
} finally {
    Disconnect-MgGraph | Out-Null
}
