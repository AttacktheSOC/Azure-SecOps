# Sync users list from a Security group to a Distribution group
## Requires -Modules Microsoft.Graph.Applications, ExchangeOnlineManagement

Connect-MgGraph -Scopes GroupMember.Read.All #-NoWelcome #Uncomment NoWelcome if desired

Connect-ExchangeOnline

# Define variables
$SecurityGroupId = "<Object ID of Security group>" # Replace with the Object ID of the security group in Entra
$DistributionGroup = "<Object ID of Distribution Group>" # Replace with the SMTP address of the distribution group or Object ID in Entra

# Get Ids for members of the security group
$SecurityGroupMembers = Get-MgGroupMember -GroupId $SecurityGroupId -All | Select-Object -ExpandProperty Id

# Get Ids for members of the distribution group
$DistributionGroupMembers = Get-DistributionGroupMember -Identity $DistributionGroup | Where-Object {$_.RecipientType -eq "UserMailbox"} | Select-Object -ExpandProperty ExternalDirectoryObjectId

# Compare and calculate differences
$UsersToAdd = $SecurityGroupMembers | Where-Object { $_ -notin $DistributionGroupMembers }
$UsersToRemove = $DistributionGroupMembers | Where-Object { $_ -notin $SecurityGroupMembers }

# Add users to the distribution group
foreach ($UserId in $UsersToAdd) {
    $UserEmail = Get-MgUser -UserId $UserId | Select-Object -ExpandProperty Mail
    if ($UserEmail) {
        Write-Host "Added $UserEmail to $DistributionGroup"
    }
}

# Remove users from the distribution group
foreach ($UserId in $UsersToRemove) {
    $UserEmail = Get-MgUser -UserId $UserId | Select-Object -ExpandProperty Mail
    if ($UserEmail) {
        Write-Host "Removed $UserEmail from $DistributionGroup"
    }
}
