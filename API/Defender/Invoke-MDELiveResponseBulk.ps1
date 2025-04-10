<#
List all active LiveResponse sessions
.\Invoke-MDELiveResponseBulk.ps1 -TenantId "<id>" -ClientId "<id>" -ClientSecret "<secret>" -ListSessions

Cancel sessions interactively
.\Invoke-MDELiveResponseBulk.ps1 -TenantId "<id>" -ClientId "<id>" -ClientSecret "<secret>" -CancelSessions

Run a script on multiple devices from a CSV
.\Invoke-MDELiveResponseBulk.ps1 -TenantId "<id>" -ClientId "<id>" -ClientSecret "<secret>" -RunScript -ScriptName "CollectForensicData.ps1" -CsvFilePath "devices.csv"
#>

# =================== CONFIG ===================
param(
    [Parameter(Mandatory=$false)]
    [string]$CsvFilePath = "",  # Path to CSV file with device IDs
    
    [Parameter(Mandatory=$false)]
    [switch]$ListSessions,      # Switch to list active sessions
    
    [Parameter(Mandatory=$false)]
    [switch]$CancelSessions,    # Switch to cancel sessions
    
    [Parameter(Mandatory=$false)]
    [switch]$RunScript,         # Switch to run scripts via LiveResponse
    
    [Parameter(Mandatory=$false)]
    [string]$ScriptName = "",   # Name of script to run
    
    [Parameter(Mandatory=$true)]
    [string]$TenantId,
    
    [Parameter(Mandatory=$true)]
    [string]$ClientId,
    
    [Parameter(Mandatory=$true)]
    [string]$ClientSecret
)

# API and rate limiting configuration
$ApiBaseUrl = "https://api.security.microsoft.com/api"
$MaxApiCallsPerMinute = 10
$MaxConcurrentSessions = 25
$SessionCheckInterval = 15      # Seconds to wait before checking session status
$CancelWaitTime = 30            # Seconds to wait before attempting to cancel a pending action
$TokenExpiryBuffer = 300        # Seconds before token expiry to refresh (5 minutes)
$MaxSessionTime = 600           # Maximum time (in seconds) to keep a session before canceling (10 minutes)
$LogFilePath = ".\LiveResponseLog_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
# =============================================

# Function to get access token with expiry tracking
function Get-AccessToken {
    $TokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $Body = @{
        client_id     = $ClientId
        scope         = "https://api.securitycenter.microsoft.com/.default"
        client_secret = $ClientSecret
        grant_type    = "client_credentials"
    }
    try {
        $Response = Invoke-RestMethod -Method Post -Uri $TokenUrl -ContentType "application/x-www-form-urlencoded" -Body $Body
        # Calculate expiry time (usually 1 hour from now)
        $expiryTime = (Get-Date).AddSeconds($Response.expires_in - $TokenExpiryBuffer)
        return @{
            Token = $Response.access_token
            ExpiryTime = $expiryTime
        }
    }
    catch {
        Write-Error "Failed to acquire access token: $_"
        exit 1
    }
}

# Function to invoke API with retries, rate limiting, and token refresh
function Invoke-ApiCallWithRetry {
    param (
        [string]$Uri,
        [string]$Method,
        [hashtable]$Headers,
        [string]$Body = $null,
        [int]$MaxRetries = 5,
        [ref]$TokenInfo
    )
    
    # Check if token needs refresh
    if ((Get-Date) -ge $TokenInfo.Value.ExpiryTime) {
        Write-Host "Access token is expiring soon. Refreshing..."
        $newTokenInfo = Get-AccessToken
        $TokenInfo.Value = $newTokenInfo
        $Headers["Authorization"] = "Bearer $($newTokenInfo.Token)"
    }
    
    $retry = 0
    do {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        try {
            $webRequest = Invoke-WebRequest -Uri $Uri -Method $Method -Headers $Headers -Body $Body -ContentType "application/json" -UseBasicParsing
            # Add random delay between requests to avoid thundering herd problem
            Start-Sleep -Seconds (Get-Random -Minimum 2 -Maximum 5)
            #Write-Host "API Response: $($webRequest.StatusCode)"
            return $webRequest.Content | ConvertFrom-Json
        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            $errorMsg = $_.Exception.Message
            
            # Handle rate limiting (429)
            if ($statusCode -eq 429) {
                if ($errorMsg -match 'You can send requests again in (\d+) seconds') {
                    $waitSeconds = [int]$matches[1]
                } else {
                    $waitSeconds = 60
                }
                Write-Warning "API rate limit hit. Waiting for $waitSeconds seconds..."
                Start-Sleep -Seconds $waitSeconds
                $retry++
            }
            # Handle device offline or unreachable (404 or 400)
            elseif ($statusCode -eq 404 -or ($statusCode -eq 400 -and $errorMsg -match "device.*offline|cannot establish session")) {
                throw "Device appears to be offline or unreachable: $errorMsg"
            }
            # Handle authentication issues (401)
            elseif ($statusCode -eq 401) {
                Write-Host "Authentication token expired. Refreshing..."
                $newTokenInfo = Get-AccessToken
                $TokenInfo.Value = $newTokenInfo
                $Headers["Authorization"] = "Bearer $($newTokenInfo.Token)"
                $retry++
            }
            else {
                throw "API call failed ($statusCode): $errorMsg"
            }
        }
    } while ($retry -lt $MaxRetries)

    throw "Max retries reached for $Uri"
}

# Function to check session status
function Check-SessionStatus {
    param (
        [string]$ActionID,
        [hashtable]$Headers,
        [ref]$TokenInfo
    )
    
    $checkUrl = "$ApiBaseUrl/machineactions/$ActionID"
    try {
        $response = Invoke-ApiCallWithRetry -Uri $checkUrl -Method Get -Headers $Headers -TokenInfo $TokenInfo
        return $response
    }
    catch {
        Write-Warning "Failed to check session status for action $ActionID : $_"
        return $null
    }
}

# Function to update status of all active sessions
function Update-SessionStatuses {
    param (
        [ref]$SessionList,
        [hashtable]$Headers,
        [ref]$TokenInfo,
        [ref]$Results
    )
    
    $now = Get-Date
    $NewList = @()
    
    foreach ($entry in $SessionList.Value) {
        $deviceId = $entry.DeviceID
        $actionId = $entry.ActionID
        $sessionAge = ($now - $entry.StartTime).TotalSeconds
        
        # Check if session has been running too long
        if ($sessionAge -gt $MaxSessionTime) {
            Write-Warning "Session on device $deviceId has been running for $([math]::Round($sessionAge/60, 1)) minutes. Attempting to cancel."
            Cancel-PendingAction -ActionID $actionId -Headers $Headers -TokenInfo $TokenInfo
            $Results.Value += [PSCustomObject]@{
                DeviceID = $deviceId
                ActionID = $actionId
                Status = "Timeout"
                StartTime = $entry.StartTime
                EndTime = $now
                Duration = "$([math]::Round($sessionAge/60, 1)) minutes"
                ErrorMessage = "Session exceeded max time of $($MaxSessionTime/60) minutes"
            }
            continue
        }
        
        $response = Check-SessionStatus -ActionID $actionId -Headers $Headers -TokenInfo $TokenInfo
        
        if ($null -eq $response) {
            # Keep session in the list if we couldn't determine its status
            $NewList += $entry
            continue
        }
        
        if ($response.status -eq "Completed" -or $response.status -eq "Failed" -or $response.status -eq "Cancelled") {
            Write-Host "Session on device $deviceId has ended with status: $($response.status)."
            $Results.Value += [PSCustomObject]@{
                DeviceID = $deviceId
                ActionID = $actionId
                Status = $response.status
                StartTime = $entry.StartTime
                EndTime = $now
                Duration = "$([math]::Round($sessionAge/60, 1)) minutes"
                ErrorMessage = $response.error
            }
        } else {
            $NewList += $entry
        }
        
        Start-Sleep -Milliseconds 300
    }
    
    $SessionList.Value = $NewList
}

# Function to get existing LiveResponse sessions
function Get-ExistingLiveResponseSessions {
    param (
        [hashtable]$Headers,
        [ref]$TokenInfo,
        [array]$DeviceIDs = @()
    )

    $existingSessions = @()
    $uri = "$ApiBaseUrl/machineactions"

    $headers = @{
        'Authorization' = "Bearer $AccessToken"
        'Content-Type'  = 'application/json'
    }
    
    try {
        $response = Invoke-ApiCallWithRetry -Uri $uri -Method Get -Headers $Headers -TokenInfo $TokenInfo

        # Filter for LiveResponse sessions only
        $liveResponseSessions = $response.value | Where-Object { 
            $_.type -eq "LiveResponse" -and
            ($_.status -eq "InProgress" -or $_.status -eq "Pending")
        }

        foreach ($action in $liveResponseSessions) {
            if ($DeviceIDs.Count -eq 0 -or $DeviceIDs -contains $action.machineId) {
                $existingSessions += [PSCustomObject]@{
                    DeviceID = $action.machineId
                    ActionID = $action.id
                    Status = $action.status
                    StartTime = [datetime]$action.creationDateTimeUtc
                    ComputerName = $action.computerDnsName
                    Command = ($action.commands | ForEach-Object { $_.type }) -join ", "
                }
            }
        }
    }
    catch {
        Write-Warning "Failed to fetch existing sessions: $_"
    }

    return $existingSessions
}

# Improved Cancel-PendingAction function that is more robust
function Cancel-PendingAction {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ActionID,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$Headers,
        
        [Parameter(Mandatory=$false)]
        [ref]$TokenInfo,
        
        [Parameter(Mandatory=$false)]
        [string]$Comment = "Cancelled by automated script"
    )
    
    # If no token info was provided, create a new one
    $useProvidedToken = $null -ne $TokenInfo
    if (-not $useProvidedToken) {
        $tempTokenInfo = Get-AccessToken
        $localTokenRef = [ref]$tempTokenInfo
        $TokenInfo = $localTokenRef
    }
    
    # If no headers were provided, create them
    $useProvidedHeaders = $null -ne $Headers
    if (-not $useProvidedHeaders) {
        $Headers = @{
            Authorization = "Bearer $($TokenInfo.Value.Token)"
            "Content-Type" = "application/json"
        }
    }
    
    # URL for cancellation
    $cancelUrl = "$ApiBaseUrl/machineactions/$ActionID/cancel"
    
    # Required body with comment
    $bodyObj = @{ Comment = $Comment }
    $body = $bodyObj | ConvertTo-Json
    
    # Wait before attempting cancellation
    Write-Host "Waiting $CancelWaitTime seconds before cancelling action $ActionID..."
    Start-Sleep -Seconds $CancelWaitTime
    
    Write-Host "Attempting to cancel action $ActionID..."
    
    $maxRetries = 3
    $retryCount = 0
    $success = $false
    
    while (-not $success -and $retryCount -lt $maxRetries) {
        try {
            # Make sure token is fresh
            if ((Get-Date) -ge $TokenInfo.Value.ExpiryTime) {
                Write-Host "Access token is expiring soon. Refreshing..."
                $newTokenInfo = Get-AccessToken
                $TokenInfo.Value = $newTokenInfo
                $Headers["Authorization"] = "Bearer $($newTokenInfo.Token)"
            }
            
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
            $response = Invoke-WebRequest -Uri $cancelUrl -Method Post -Headers $Headers -Body $body -ContentType "application/json" -UseBasicParsing
            
            if ($response.StatusCode -eq 200 -or $response.StatusCode -eq 202) {
                Write-Host "Successfully cancelled action $ActionID."
                $success = $true
                return $true
            }
        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            $errorMsg = $_.Exception.Message
            $retryCount++
            
            # Handle specific error cases
            switch ($statusCode) {
                429 {
                    # Handle rate limiting
                    if ($errorMsg -match 'You can send requests again in (\d+) seconds') {
                        $waitSeconds = [int]$matches[1] + 5  # Add buffer
                    } else {
                        $waitSeconds = 60  # Default wait
                    }
                    Write-Warning "API rate limit hit. Waiting for $waitSeconds seconds before retry ($retryCount/$maxRetries)..."
                    Start-Sleep -Seconds $waitSeconds
                }
                401 {
                    # Handle authentication issues
                    Write-Warning "Authentication token expired. Refreshing token..."
                    try {
                        $newTokenInfo = Get-AccessToken
                        $TokenInfo.Value = $newTokenInfo
                        $Headers["Authorization"] = "Bearer $($newTokenInfo.Token)"
                        # No increment of retry count for auth refresh
                        $retryCount--
                        Start-Sleep -Seconds 2
                    }
                    catch {
                        Write-Error "Failed to refresh token: $_"
                        return $false
                    }
                }
                404 {
                    # Handle non-existent action ID
                    Write-Warning "Action $ActionID not found. It may have already completed or been cancelled."
                    return $false
                }
                default {
                    # Handle other errors
                    Write-Warning "Failed to cancel action $ActionID (Attempt $retryCount/$maxRetries): Status $statusCode - $errorMsg"
                    Start-Sleep -Seconds (5 * $retryCount)  # Increasing backoff
                }
            }
        }
    }
    
    if (-not $success) {
        Write-Error "Failed to cancel action $ActionID after $maxRetries attempts."
        return $false
    }
    
    return $true
}

# Function to present sessions and allow interactive cancellation
function Show-LiveResponseSessions {
    param (
        [array]$Sessions,
        [hashtable]$Headers,
        [ref]$TokenInfo
    )
    
    if ($Sessions.Count -eq 0) {
        Write-Host "No active LiveResponse sessions found." -ForegroundColor Yellow
        return
    }
    
    Write-Host "Found $($Sessions.Count) LiveResponse sessions:" -ForegroundColor Green
    Write-Host ("-" * 100)
    
    # Flag to track if "all" option was chosen
    $cancelAll = $false
    # Comment to use for all cancellations if "all" is chosen
    $globalComment = ""
    $results = @()
    
    foreach ($session in $Sessions) {
        # Display session information
        Write-Host "Session ID: " -NoNewline -ForegroundColor Cyan
        Write-Host "$($session.ActionID)"
        Write-Host "Machine: " -NoNewline -ForegroundColor Cyan
        Write-Host "$($session.ComputerName) ($($session.DeviceID))"
        Write-Host "Status: " -NoNewline -ForegroundColor Cyan
        Write-Host "$($session.Status)"
        Write-Host "Created: " -NoNewline -ForegroundColor Cyan
        Write-Host "$($session.StartTime) UTC"
        if ($session.Command) {
            Write-Host "Command: " -NoNewline -ForegroundColor Cyan
            Write-Host "$($session.Command)"
        }
        
        # Check if session is in a cancellable state
        if ($session.Status -eq "Completed" -or $session.Status -eq "Failed" -or $session.Status -eq "Cancelled") {
            Write-Host "Session is already in final state: $($session.Status). Skipping." -ForegroundColor Yellow
            continue
        }
        
        # Skip prompt if cancelAll is already true
        if (-not $cancelAll) {
            # Prompt to cancel session
            Write-Host "Do you want to cancel this LiveResponse session? (yes/no/all)" -ForegroundColor Yellow
            $cancel = Read-Host "Enter 'all' to cancel all remaining sessions"
            
            if ($cancel.ToLower() -eq "all") {
                $cancelAll = $true
                # Get comment once for all sessions
                $globalComment = Read-Host "Please provide a reason for cancellation (required for all sessions)"
                
                # Ensure comment is not empty
                while ([string]::IsNullOrWhiteSpace($globalComment)) {
                    Write-Host "Comment is required. Please provide a reason." -ForegroundColor Yellow
                    $globalComment = Read-Host "Please provide a reason for cancellation"
                }
                
                # Set cancel to yes for the current session
                $cancel = "yes"
            }
        }
        else {
            # If cancelAll is true, we automatically set cancel to yes
            $cancel = "yes"
            Write-Host "Auto-cancelling as part of 'cancel all' operation..." -ForegroundColor Yellow
        }
        
        if ($cancel.ToLower() -eq "yes") {
            # If we're not in cancelAll mode, get a comment for this specific session
            $comment = $globalComment
            if (-not $cancelAll) {
                $comment = Read-Host "Please provide a reason for cancellation (required)"
                
                # Ensure comment is not empty
                while ([string]::IsNullOrWhiteSpace($comment)) {
                    Write-Host "Comment is required. Please provide a reason." -ForegroundColor Yellow
                    $comment = Read-Host "Please provide a reason for cancellation"
                }
            }
            
            Write-Host "Cancelling session $($session.ActionID)..." -ForegroundColor Yellow
            $result = Cancel-PendingAction -ActionID $session.ActionID -Headers $Headers -TokenInfo $TokenInfo -Comment $comment
            
            if ($result) {
                Write-Host "Session cancelled successfully." -ForegroundColor Green
                $results += [PSCustomObject]@{
                    DeviceID = $session.DeviceID
                    ActionID = $session.ActionID
                    Status = "Cancelled"
                    StartTime = $session.StartTime
                    EndTime = Get-Date
                    Duration = "$([math]::Round(((Get-Date) - $session.StartTime).TotalMinutes, 1)) minutes"
                    ErrorMessage = ""
                }
            }
            else {
                Write-Host "Failed to cancel session." -ForegroundColor Red
                $results += [PSCustomObject]@{
                    DeviceID = $session.DeviceID
                    ActionID = $session.ActionID
                    Status = "CancellationFailed"
                    StartTime = $session.StartTime
                    EndTime = Get-Date
                    Duration = "$([math]::Round(((Get-Date) - $session.StartTime).TotalMinutes, 1)) minutes"
                    ErrorMessage = "Failed to cancel session"
                }
            }
        }
        else {
            Write-Host "Skipping cancellation for this session." -ForegroundColor Gray
        }
        
        Write-Host ("-" * 100)
    }
    
    # Return results
    return $results
}

# Function to run LiveResponse sessions from a CSV file
function Run-LiveResponseFromCsv {
    param (
        [string]$CsvPath,
        [string]$ScriptToRun,
        [hashtable]$Headers,
        [ref]$TokenInfo
    )
    
    # Validate CSV file
    if (-not (Test-Path -Path $CsvPath)) {
        Write-Error "CSV file not found at path: $CsvPath"
        return $null
    }

    try {
        $DeviceIDs = Import-Csv -Path $CsvPath | Select-Object -ExpandProperty DeviceId
    }
    catch {
        Write-Error "Failed to read CSV file or 'DeviceID' column not found: $_"
        return $null
    }

    Write-Host "Found $($DeviceIDs.Count) devices in CSV file"

    $ActiveSessions = @()
    $ApiCallCount = 0
    $ApiCallResetTime = (Get-Date).AddMinutes(1)
    $Results = @()

    # Process each device ID
    foreach ($DeviceID in $DeviceIDs) {
        # Clean up completed or timed-out sessions
        Update-SessionStatuses -SessionList ([ref]$ActiveSessions) -Headers $Headers -TokenInfo $TokenInfo -Results ([ref]$Results)
        
        # Wait if we've reached the max concurrent sessions
        while ($ActiveSessions.Count -ge $MaxConcurrentSessions) {
            Write-Host "Max concurrent sessions reached ($MaxConcurrentSessions). Waiting $SessionCheckInterval seconds..."
            Start-Sleep -Seconds $SessionCheckInterval
            Update-SessionStatuses -SessionList ([ref]$ActiveSessions) -Headers $Headers -TokenInfo $TokenInfo -Results ([ref]$Results)
        }
        
        # Reset API call counter if minute has passed
        if ((Get-Date) -gt $ApiCallResetTime) {
            $ApiCallCount = 0
            $ApiCallResetTime = (Get-Date).AddMinutes(1)
        }
        
        # Wait if we've hit the API call limit
        if ($ApiCallCount -ge $MaxApiCallsPerMinute) {
            $waitSeconds = [math]::Ceiling(($ApiCallResetTime - (Get-Date)).TotalSeconds)
            Write-Host "API call limit hit. Waiting $waitSeconds seconds until next minute..."
            Start-Sleep -Seconds $waitSeconds
            $ApiCallCount = 0
            $ApiCallResetTime = (Get-Date).AddMinutes(1)
        }
        
        $Body = @{
            Commands = @(
                @{
                    type   = "RunScript"
                    params = @(
                        @{ key = "ScriptName"; value = $ScriptToRun }
                    )
                }
            )
            Comment = "Running script $ScriptToRun via automated process"
        } | ConvertTo-Json -Depth 5
        
        $Uri = "$ApiBaseUrl/machines/$DeviceID/runliveresponse"
        
        try {
            Write-Host "Attempting to start live response session on device $DeviceID..."
            $response = Invoke-ApiCallWithRetry -Uri $Uri -Method "Post" -Headers $Headers -Body $Body -TokenInfo $TokenInfo
            $ActionID = $response.id
            Write-Host "Started live response on $DeviceID with Action ID $ActionID"
            $ActiveSessions += [PSCustomObject]@{
                DeviceID = $DeviceID
                ActionID = $ActionID
                StartTime = Get-Date
            }
            $ApiCallCount++
        }
        catch {
            Write-Warning "Failed to start session on $DeviceID : $_"
            $Results += [PSCustomObject]@{
                DeviceID = $DeviceID
                ActionID = "N/A"
                Status = "Failed"
                StartTime = Get-Date
                EndTime = Get-Date
                Duration = "0 minutes"
                ErrorMessage = $_.Exception.Message
            }
        }
        
        Start-Sleep -Seconds 2  # Pause between requests
    }

    # Wait for any remaining sessions to complete
    Write-Host "All devices processed. Waiting for remaining sessions to complete..."
    while ($ActiveSessions.Count -gt 0) {
        Write-Host "Waiting for $($ActiveSessions.Count) active sessions to complete..."
        Start-Sleep -Seconds $SessionCheckInterval
        Update-SessionStatuses -SessionList ([ref]$ActiveSessions) -Headers $Headers -TokenInfo $TokenInfo -Results ([ref]$Results)
    }

    return $Results
}

# === MAIN EXECUTION ===
Write-Host "Starting Microsoft Defender LiveResponse Management at $(Get-Date)"
$TokenInfo = Get-AccessToken
$Headers = @{
    Authorization = "Bearer $($TokenInfo.Token)"
    "Content-Type" = "application/json"
}
$TokenRef = [ref]$TokenInfo

# Define results collection
$Results = @()

# Process based on selected mode
if ($ListSessions) {
    Write-Host "Listing active LiveResponse sessions..."
    $sessions = Get-ExistingLiveResponseSessions -Headers $Headers -TokenInfo $TokenRef
    
    if ($sessions.Count -eq 0) {
        Write-Host "No active LiveResponse sessions found."
    } else {
        Write-Host "Found $($sessions.Count) LiveResponse sessions:"
        $sessions | Format-Table -Property DeviceID, ActionID, Status, StartTime, ComputerName, Command -AutoSize
    }
}
elseif ($CancelSessions) {
    Write-Host "Retrieving LiveResponse sessions for cancellation..."
    $sessions = Get-ExistingLiveResponseSessions -Headers $Headers -TokenInfo $TokenRef
    $Results = Show-LiveResponseSessions -Sessions $sessions -Headers $Headers -TokenInfo $TokenRef
}
elseif ($RunScript) {
    if (-not $ScriptName) {
        Write-Error "ScriptName parameter is required when using -RunScript"
        exit 1
    }
    
    if (-not $CsvFilePath -or -not (Test-Path $CsvFilePath)) {
        Write-Error "Valid CsvFilePath is required when using -RunScript"
        exit 1
    }
    
    Write-Host "Running script '$ScriptName' on devices in '$CsvFilePath'..."
    $Results = Run-LiveResponseFromCsv -CsvPath $CsvFilePath -ScriptToRun $ScriptName -Headers $Headers -TokenInfo $TokenRef
}
else {
    Write-Host "No operation specified. Use -ListSessions, -CancelSessions, or -RunScript"
    Write-Host "Example usage:"
    Write-Host "  .\script.ps1 -TenantId <id> -ClientId <id> -ClientSecret <secret> -ListSessions"
    Write-Host "  .\script.ps1 -TenantId <id> -ClientId <id> -ClientSecret <secret> -CancelSessions"
    Write-Host "  .\script.ps1 -TenantId <id> -ClientId <id> -ClientSecret <secret> -RunScript -ScriptName <script> -CsvFilePath <path>"
    exit 0
}

# Export results to CSV if we have any
if ($Results.Count -gt 0) {
    $Results | Export-Csv -Path $LogFilePath -NoTypeInformation
    Write-Host "Results exported to $LogFilePath"
    
    # Summary
    $successful = ($Results | Where-Object { $_.Status -eq "Completed" -or $_.Status -eq "Cancelled" }).Count
    $failed = ($Results | Where-Object { $_.Status -ne "Completed" -and $_.Status -ne "Cancelled" }).Count
    Write-Host "Summary: $successful successful, $failed failed. See $LogFilePath for details."
}

Write-Host "Microsoft Defender LiveResponse Management completed at $(Get-Date)"
