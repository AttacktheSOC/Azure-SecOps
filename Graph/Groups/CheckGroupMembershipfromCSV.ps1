# Identify group membership of a list of users

# Define the path to your CSV file; must contain a column 'Email' and a column 'Group'
$csvPath = "C:\Users\<UserName>\users.csv"

# Define the group IDs you want to check
$groupId1 = "<group1-id>"
$groupId2 = "<group2-id>"

# Import the CSV
$users = Import-Csv -Path $csvPath

# Iterate through each user in the CSV
foreach ($user in $users) {
    # Initialize an array to hold group membership status
    $groupMembership = @()

    # Get user by email
    $graphUser = Get-MgUser -Filter "mail eq '$($user.Email)'" -ErrorAction SilentlyContinue

    # Check if user exists
    if ($graphUser) {
        # Debug output to verify we have a valid user
        Write-Host "Checking user: $($user.Email) - User ID: $($graphUser.Id)"

        # Get the user's group memberships
        $memberships = Get-MgUserMemberOf -UserId $graphUser.Id

        # Check if user is a member of the first group
        if ($memberships | Where-Object { $_.Id -eq $groupId1 }) {
            $groupMembership += "Group1"
        }
        # Check if user is a member of the second group
        if ($memberships | Where-Object { $_.Id -eq $groupId2 }) {
            $groupMembership += "Group2"
        }

        # Debug output to show found memberships
        Write-Host "Group memberships found for $($user.Email): $($groupMembership -join ', ')"
    } else {
        Write-Host "User not found: $($user.Email)"
    }

    # Determine what to write to the Group column
    if ($groupMembership.Count -eq 0) {
        $user.Group = "none"  # Write "none" if the user is not a member of either group
    } else {
        $user.Group = -join $groupMembership  # Join the group membership statuses
    }
}

# Export the updated CSV
$users | Export-Csv -Path $csvPath -NoTypeInformation
