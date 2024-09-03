# This script is to help get started with enabling SSPR via selected groups
# Use an existing group with users you want to allow SSPR for and exclude groups of other users
# Example: you have all domain users in a single group but need to exclude privileged accounts, service, devs, etc..
##
##

# Group ID for the existing group that contains both users who are allowed and not allowed to use SSPR
$existingGroup = '<group-id-existingGroup>'

# Group ID assigned to your SSPR policy
$ssprAllowed = '<group-id-ssprEnabled>'

# list of group ids containing users you want excluded from SSPR
$excludedUserGroups = "<group-id1>", "<group-id2>", "<group-id3>", "<group-id4>"

# Get the members of each exclusion group and combine the results
$ssprNotAllowed = @()
foreach ($groupId in $excludedUserGroups) {
        $members = Get-MgGroupMember -GroupId $groupId
        $ssprNotAllowed += $members | Select-Object Id
}

# Grab the Id column
$ssprNotAllowedIds = $ssprNotAllowed.Id

# Grab all users from the existing group
$allUsers = Get-MgGroupMember -GroupId $existingGroup -All

# loop through all users and assign them to the SSPR allowed group unless they are in an exclusion group
$allUsers | ForEach-Object -Parallel {
    # Access the User ID variable from previous step as a string (previously an object)
    $userId = $_.Id

    # Add filtered users to SSPR
    if ($using:ssprNotAllowedIds -notcontains $userId ) { New-MgGroupMember -Confirm:$false -GroupId $using:ssprAllowed -DirectoryObjectId $userId }
}
