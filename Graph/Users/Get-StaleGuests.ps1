# 1. Connect to Microsoft Graph with necessary permissions
Connect-MgGraph -Scopes "User.Read.All", "AuditLog.Read.All"

# 2. Define the inactivity threshold (90 days)
$ThresholdDate = (Get-Date).AddDays(-90)

# 3. Fetch all Guest users and their sign-in activity
$AllGuests = Get-MgUser -Filter "UserType eq 'Guest'" -Property "DisplayName", "Mail", "Id", "SignInActivity", "UserPrincipalName" -All

$InactiveGuests = $AllGuests | Where-Object {
    # If they have NEVER signed in, they won't have a LastSignInDateTime
    $LastSignIn = $_.SignInActivity.LastSignInDateTime
    ($null -eq $LastSignIn) -or ($LastSignIn -lt $ThresholdDate)
}

# 4. Export the results for your IT team to review
$InactiveGuests | Select-Object DisplayName, UserPrincipalName, Mail, @{N='LastSignIn'; E={$_.SignInActivity.LastSignInDateTime}} | 
    Export-Csv -Path "InactiveGuests_Report.csv" -NoTypeInformation

Write-Host "Report generated: InactiveGuests_Report.csv. Total inactive guests found: $($InactiveGuests.Count)" -ForegroundColor Cyan
