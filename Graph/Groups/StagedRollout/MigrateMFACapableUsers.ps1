# Migrate users from one specified group to the group assigned to the preferred Staged Rollout method only if they are MFA Capabale

$EntraStagedRollout = '<stagedrollout-assigned-groupid>'
$migrationUsers = '<groupid-users-to-be-migrated>'

$GroupMemberslist = Get-MgGroupMember -GroupId $migrationUsers -All

$registeredUsers = $GroupMemberslist | ForEach-Object -Parallel {
    $userId = $_.Id

    # Find users who've recently registered an acceptable MFA method
    $regDetails = Get-MgReportAuthenticationMethodUserRegistrationDetail -UserRegistrationDetailsId "$userId"
    $newlyRegistered = $regDetails | Where-Object {$_.IsMfaCapable -eq $true}
    $newlyRegistered
}

$registeredUsers | ForEach-Object -Parallel {
    # Access the User ID, DN, and UPN from previous step as a string
    $userId = $_.Id
    $displayName = $_.UserDisplayName
    $upn = $_.UserPrincipalName

    # Add the user to the Entra Staged Rollout, turn off confirmation prompt requirement 
    New-MgGroupMember -Confirm:$false -GroupId $Using:EntraStagedRollout -DirectoryObjectId $userId

    # Output user info in easy copy-paste to email format
    Write-Output "$displayName<$upn>;"
}
