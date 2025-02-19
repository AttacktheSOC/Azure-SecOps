# Run ex. '.\Get-UserObjectIds.ps1 .\sso_users.csv'
# target CSV must have header of 'email'
##
#
param(
    [string]$csvFilePath
)

if (-Not (Test-Path $csvFilePath)) {
    Write-Host "Error: File not found at $csvFilePath"
    exit 1
}

$outputFilePath = [System.IO.Path]::Combine(
    [System.IO.Path]::GetDirectoryName($csvFilePath),
    "$( [System.IO.Path]::GetFileNameWithoutExtension($csvFilePath))_processed.csv"
)

$users = Import-Csv -Path $csvFilePath

$processedUsers = @()

foreach ($user in $users) {
    $email = $user.'email'
    $objectId = "Not Found"
    
    if ($email -and $email -ne "") {
        $graphUser = Get-MgUser -Filter "mail eq '$email'" -ErrorAction SilentlyContinue
        
        if ($graphUser) {
            $objectId = $graphUser.Id
            Write-Host "Found User: $email -> Object ID: $objectId"
        } else {
            Write-Host "User not found by email: $email"
            
            # if item is not found via email, check if email is a UPN
            $graphUser = Get-MgUser -Filter "userPrincipalName eq '$email'" -ErrorAction SilentlyContinue
            
            if ($graphUser) {
                $objectId = $graphUser.Id
                Write-Host "Found UPN: $email -> Object ID: $objectId"
            } else {
                Write-Host "User not found by UPN: $email"
            }
        }
    }
    
    $processedUsers += [PSCustomObject]@{
        Email = $email
        ObjectID = $objectId
    }
}

$processedUsers | Export-Csv -Path $outputFilePath -NoTypeInformation

Write-Host "Finished writing results to $outputFilePath ..."
