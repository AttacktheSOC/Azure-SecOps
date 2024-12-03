# Import-Module Microsoft.Graph.Applications
Connect-MgGraph -Scopes "Application.ReadWrite.All"

# Set your Notification Email Address(es); to have multiple comma-separate each string(ex.: $var = "string1", "string2")
$emailToNotify = 'email@domain.com' #, "email2@domain.com"

$SpIds = Get-MgServicePrincipal -Filter "ServicePrincipalType eq 'Application'" -All -Property Id, PreferredSingleSignOnMode | Where-Object { $_.PreferredSingleSignOnMode -eq "saml" }

$SpIds | ForEach-Object -Parallel {
    $spId = $_.Id
    Update-MgServicePrincipal -ServicePrincipalId $spId -NotificationEmailAddresses $using:emailToNotify
}
