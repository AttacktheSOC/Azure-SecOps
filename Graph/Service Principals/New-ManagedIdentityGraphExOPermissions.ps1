<# 
This script allows you to grant a Managed Identity access to Graph and Exchange Online Powershell.
1. Grants MS Graph permission
2. Grants ExchangeManageAsApp permission
3. Creates a linked ExO service principal
4. creates a new Management role with option to have least privilege
5. Assigns the new ExO management role to the linked SPN
You could also create a new ExO Management scope to further lock down the SPN to a particular object(s)
#>
## Requires -Modules Microsoft.Graph.Applications, ExchangeOnlineManagement
$DestinationTenantId = "<TenantID>" # Azure Tenant ID, can be found at https://portal.azure.com/#view/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/~/Overview
$ManagedIdentityName = "<Name of MId>" # Name of system-assigned or user-assigned managed service identity. (System-assigned use same name as resource).
$ManagementRoleName = "<ExO Management Role name>" # Name for the new ExO Manage Role with restricted permissions
$ParentExOManagementRole = "<Ex. Distribution Groups>" # Name for the parent ExO manaement role. To view List of possible roles run: Get-ManagementRole * | Select-Object Name, RoleEntries

# Graph permissions to assign to the Managed Identity 
$AssignMgPermissions = @(
  "User.Read.All"
  "GroupMember.Read.All"
  # "Add.More.Permissions"
)

# Scopes required to perform Graph permission assignment
$MgRequiredScopes = @(
    "Application.Read.All"
    "AppRoleAssignment.ReadWrite.All"
    "Directory.Read.All"
)

# ExO permissions to assign to the newly created ExO Management Role
$ExORolePermissions = @(
    "Get-DistributionGroupMember", 
    "Add-DistributionGroupMember", 
    "Remove-DistributionGroupMember"
)

$GraphAppId = "00000003-0000-0000-c000-000000000000" # Don't change this. This is the immutable application ID of the Microsoft Graph service principal.

##
# Connect to Graph and ExchangeOnline Powershell
Connect-MgGraph -TenantId $DestinationTenantId -Scopes $MgRequiredScopes #-NoWelcome #Uncomment NoWelcome if desired

Connect-ExchangeOnline

#########################################################################################
#
# Perform actions to grant Managed Identity access to Microsoft Graph

# Get the SP objects
$MIdSPN = Get-MgServicePrincipal -Filter "displayName eq '$ManagedIdentityName'"
$GraphSPN = Get-MgServicePrincipal -Filter "appId eq '$GraphAppId'"

# Retrieve MS Graph App role Ids for your specified permissions
$AppPermIds = $GraphSPN.AppRoles | Where-Object {($_.Value -in $AssignMgPermissions) -and ($_.AllowedMemberTypes -contains "Application")}

# Iteravely assign the permissions to the Managed Identity
foreach($AppPermission in $AppPermIds)
{
  $AppPermissionAssingment = @{
    "PrincipalId" = $MIdSPN.Id
    "ResourceId" = $GraphSPN.Id
    "AppRoleId" = $AppPermission.Id
  }
  
  New-MgServicePrincipalAppRoleAssignment `
    -ServicePrincipalId $AppPermissionAssingment.PrincipalId `
    -BodyParameter $AppPermissionAssingment `
    -Verbose
}

#########################################################################################
#
# The code below performs actions to grant your Managed Identity access to ExO Powershell

# Get the SPId for Exchange Online
$ExOResourceID = (Get-MgServicePrincipal -Filter "AppId eq '00000002-0000-0ff1-ce00-000000000000'").Id

# ExchangeManageAsApp role Id
$AppRoleID = "dc50a0fb-09a3-484d-be87-e023b12c6440" 

# Assign the ExchangeManageAsApp role to the Managed Identity
New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $MIdSPN.Id -PrincipalId $MIdSPN.Id -AppRoleId $AppRoleID -ResourceId $ExOResourceID

# Create a linked Service Principal in Exchange for the Managed Identity
New-ServicePrincipal -AppId $MIdSPN.AppId -ServiceId $MIdSPN.Id -DisplayName $ManagedIdentityName

# Create a new management role and restrict permissions of Service Principal to only those required to perform task
New-ManagementRole -Name "$ManagementRoleName" -Parent $ParentExOManagementRole

# Get a list possible permissions by running: Get-ManagementRoleEntry "${ManagementRoleName}\*" | fl*
Get-ManagementRoleEntry "${ManagementRoleName}\*" | Where-Object { $_.Name -notin $ExORolePermissions } | ForEach-Object { Remove-ManagementRoleEntry -Identity "${ManagementRoleName}\$($_.Name)" -Verbose -Confirm:$false }

# Assign the SPN to the new Management Role
New-ManagementRoleAssignment -Role "${ManagementRoleName}" -App $MIdSPN.Id
