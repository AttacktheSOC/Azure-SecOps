# Run ex. '.\Get-UserObjectIds.ps1 .\sso_users.csv'
# target CSV must have header of 'email'
##
#
param(
    [string]$csvFilePath
)

# Check if the file exists
if (-Not (Test-Path $csvFilePath)) {
    Write-Host "Error: File not found at $csvFilePath"
    exit 1
}

# Output file appends _processed.csv
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
        try {
            $graphUser = Get-MgUser -Filter "mail eq '$email'"
            if ($graphUser) {
                $objectId = $graphUser.Id
                Write-Host "Found User: $email -> Object ID: $objectId"
            }
        } catch {
            Write-Host "Error finding user: $email"
        }
    }
    
    $processedUsers += [PSCustomObject]@{
        Email = $email
        ObjectID = $objectId
    }
}

$processedUsers | Export-Csv -Path $outputFilePath -NoTypeInformation

Write-Host "Processed CSV saved to $outputFilePath"
