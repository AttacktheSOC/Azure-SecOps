<#
.SYNOPSIS
  Create remediation tasks for all remediatable (deployIfNotExists/modify) policies
  within a policy set (initiative) assignment.

.REQUIREMENTS
  Az.Accounts, Az.Resources, Az.PolicyInsights
  Logged in (Connect-AzAccount) with permission to create remediations.

.PARAMETER PolicyAssignmentId
  Full resource ID of the policy assignment.

.PARAMETER ResourceDiscoveryMode
  Optional. For subscription/RG scope you can choose ReEvaluateCompliance or ExistingNonCompliant.
  For MG scope it will be forced to ExistingNonCompliant (ReEvaluateCompliance not supported). 

.EXAMPLE
  .\Start-InitiativeRemediations.ps1 -PolicyAssignmentId "/providers/Microsoft.Management/managementGroups/mg1/providers/Microsoft.Authorization/policyAssignments/pa1"

.EXAMPLE
  .\Start-InitiativeRemediations.ps1 -PolicyAssignmentId "/subscriptions/<subId>/providers/Microsoft.Authorization/policyAssignments/<assignName>"
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [string]$PolicyAssignmentId,

  [ValidateSet("ExistingNonCompliant","ReEvaluateCompliance")]
  [string]$ResourceDiscoveryMode = "ReEvaluateCompliance",

  # Optional: add a prefix so names are easy to find
  [string]$RemediationNamePrefix = "rem"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Determine if assignment is at Management Group scope (and extract MG name) ---
$mgMatch = [regex]::Match(
  $PolicyAssignmentId,
  "^/providers/Microsoft\.Management/managementGroups/(?<mg>[^/]+)/providers/Microsoft\.Authorization/policyAssignments/(?<pa>[^/]+)$",
  [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
)

$IsManagementGroupScope = $mgMatch.Success
$ManagementGroupName = if ($IsManagementGroupScope) { $mgMatch.Groups["mg"].Value } else { $null }

# ReEvaluateCompliance is not supported for MG remediations; force ExistingNonCompliant
# (per Start-AzPolicyRemediation docs). 
if ($IsManagementGroupScope -and $ResourceDiscoveryMode -eq "ReEvaluateCompliance") {
  Write-Verbose "MG scope detected. Forcing ResourceDiscoveryMode to ExistingNonCompliant."
  $ResourceDiscoveryMode = "ExistingNonCompliant"
}

Write-Host "Assignment: $PolicyAssignmentId"
if ($IsManagementGroupScope) { Write-Host "Scope type: Management Group ($ManagementGroupName)" }
else { Write-Host "Scope type: non-Management Group" }
Write-Host "Discovery mode: $ResourceDiscoveryMode"
Write-Host ""

# --- Pull noncompliant, remediatable policy states for THIS assignment ---
# Remediation is supported only for deployIfNotExists and modify effects.
# (Filtering out auditIfNotExists etc. is critical.)
$states = Get-AzPolicyState | Where-Object {
  $_.PolicyAssignmentId -eq $PolicyAssignmentId -and
  $_.ComplianceState -eq "NonCompliant" -and
  ($_.PolicyDefinitionAction -eq "deployIfNotExists" -or $_.PolicyDefinitionAction -eq "modify")
}

if (-not $states) {
  Write-Warning "No noncompliant, remediatable (deployIfNotExists/modify) policy states found for this assignment."
  Write-Warning "If you're seeing only auditIfNotExists/audit results, those cannot be remediated via remediation tasks."
  return
}

# --- Unique list of initiative children (PolicyDefinitionReferenceId) ---
# For initiative assignments, PolicyDefinitionReferenceId identifies which policy within the initiative to remediate.
$targets = $states |
  Where-Object { -not [string]::IsNullOrWhiteSpace($_.PolicyDefinitionReferenceId) } |
  Select-Object PolicyDefinitionReferenceId -Unique

if (-not $targets) {
  Write-Warning "No PolicyDefinitionReferenceId values found. If this is NOT an initiative assignment, remove the reference-id logic and remediate the assignment directly."
  return
}

Write-Host ("Found {0} remediatable policy references to remediate." -f $targets.Count)
Write-Host ""

foreach ($t in $targets) {
  $refId = $t.PolicyDefinitionReferenceId

  # Remediation resource names must be ARM-safe; keep it simple + deterministic.
  $safeRef = ($refId -replace "[^a-zA-Z0-9\-\.]", "-").ToLowerInvariant()
  $remName = "$RemediationNamePrefix-$safeRef"

  # Skip if remediation already exists (any state)
  $existing = Get-AzPolicyRemediation -Name $remName -ErrorAction SilentlyContinue
  if ($existing) {
    Write-Host "SKIP: Remediation '$remName' already exists (state: $($existing.ProvisioningState))."
    continue
  }

  Write-Host "START: $remName  (ReferenceId: $refId)"

  if ($IsManagementGroupScope) {
    Start-AzPolicyRemediation `
      -Name $remName `
      -ManagementGroupName $ManagementGroupName `
      -PolicyAssignmentId $PolicyAssignmentId `
      -PolicyDefinitionReferenceId $refId `
      -ResourceDiscoveryMode $ResourceDiscoveryMode | Out-Null
  }
  else {
    Start-AzPolicyRemediation `
      -Name $remName `
      -PolicyAssignmentId $PolicyAssignmentId `
      -PolicyDefinitionReferenceId $refId `
      -ResourceDiscoveryMode $ResourceDiscoveryMode | Out-Null
  }
}

Write-Host ""
Write-Host "Done. Use: Get-AzPolicyRemediation | Sort-Object -Property Name"
