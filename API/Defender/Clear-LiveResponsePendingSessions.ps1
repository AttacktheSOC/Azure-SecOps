# MS Defender LiveResponse Session Manager
# Example: .\Clear-LiveResponsePendingSessions.ps1 -ClientId "your-client-id" -ClientSecret "your-client-secret" -TenantId "your-tenant-id"
# This script retrieves active LiveResponse sessions and allows cancelling them one by one: https://learn.microsoft.com/en-us/defender-endpoint/api/cancel-machine-action

param(
    [Parameter(Mandatory=$true)]
    [string]$ClientId,
    
    [Parameter(Mandatory=$true)]
    [string]$ClientSecret,
    
    [Parameter(Mandatory=$true)]
    [string]$TenantId
)

# API Base URL for Microsoft Defender API
$ApiBaseUrl = "https://api.security.microsoft.com/api"

# Rate limit constants
$MaxCallsPerMinute = 100
$MaxCallsPerHour = 1500

# Variables to track API calls
$CallsInCurrentMinute = 0
$CallsInCurrentHour = 0
$MinuteStartTime = Get-Date
$HourStartTime = Get-Date

# Function to manage rate limits
function Wait-ForRateLimit {
    $currentTime = Get-Date
    
    # Reset minute counter if more than a minute has passed
    if (($currentTime - $MinuteStartTime).TotalSeconds -ge 60) {
        $script:CallsInCurrentMinute = 0
        $script:MinuteStartTime = $currentTime
    }
    
    # Reset hour counter if more than an hour has passed
    if (($currentTime - $HourStartTime).TotalMinutes -ge 60) {
        $script:CallsInCurrentHour = 0
        $script:HourStartTime = $currentTime
    }
    
    # Check minute limit
    if ($CallsInCurrentMinute -ge $MaxCallsPerMinute) {
        $waitTimeSeconds = 60 - ($currentTime - $MinuteStartTime).TotalSeconds
        if ($waitTimeSeconds -gt 0) {
            Write-Host "Rate limit reached ($MaxCallsPerMinute calls per minute). Waiting for $([Math]::Ceiling($waitTimeSeconds)) seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds ([Math]::Ceiling($waitTimeSeconds))
            # Reset counter after waiting
            $script:CallsInCurrentMinute = 0
            $script:MinuteStartTime = Get-Date
        }
    }
    
    # Check hour limit
    if ($CallsInCurrentHour -ge $MaxCallsPerHour) {
        $waitTimeMinutes = 60 - ($currentTime - $HourStartTime).TotalMinutes
        if ($waitTimeMinutes -gt 0) {
            Write-Host "Hourly rate limit reached ($MaxCallsPerHour calls per hour). Waiting for $([Math]::Ceiling($waitTimeMinutes)) minutes..." -ForegroundColor Yellow
            Start-Sleep -Seconds ([Math]::Ceiling($waitTimeMinutes * 60))
            # Reset counter after waiting
            $script:CallsInCurrentHour = 0
            $script:HourStartTime = Get-Date
        }
    }
    
    # Increment counters for this call
    $script:CallsInCurrentMinute++
    $script:CallsInCurrentHour++
}

# Function to get access token
function Get-AccessToken {
    param(
        [Parameter(Mandatory=$true)][string]$ClientId,
        [Parameter(Mandatory=$true)][string]$ClientSecret,
        [Parameter(Mandatory=$true)][string]$TenantId
    )
    
    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $scope = "https://api.securitycenter.microsoft.com/.default"
    
    $tokenBody = @{
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = $scope
        grant_type    = "client_credentials"
    }
    
    try {
        $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
        return $tokenResponse.access_token
    }
    catch {
        Write-Error "Failed to acquire access token: $_"
        exit 1
    }
}

# Function to get LiveResponse sessions
function Get-LiveResponseSessions {
    param(
        [Parameter(Mandatory=$true)][string]$AccessToken
    )
    
    $uri = "$ApiBaseUrl/machineactions"
    $headers = @{
        'Authorization' = "Bearer $AccessToken"
        'Content-Type'  = 'application/json'
    }
    
    # This call counts against our rate limit
    Wait-ForRateLimit
    
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers
        # Filter for LiveResponse sessions only
        $liveResponseSessions = $response.value | Where-Object { 
            $_.type -eq "LiveResponse" -and
            ($_.status -eq "InProgress" -or $_.status -eq "Pending")
        }
        return $liveResponseSessions
    }
    catch {
        Write-Error "Failed to retrieve LiveResponse sessions: $_"
        return $null
    }
}

# Function to cancel a LiveResponse session
function Cancel-LiveResponseSession {
    param(
        [Parameter(Mandatory=$true)][string]$AccessToken,
        [Parameter(Mandatory=$true)][string]$ActionId,
        [Parameter(Mandatory=$true)][string]$Comment
    )
    
    $uri = "$ApiBaseUrl/machineactions/$ActionId/cancel"
    $headers = @{
        'Authorization' = "Bearer $AccessToken"
        'Content-Type'  = 'application/json'
    }
    
    # Creating body with required Comment parameter as per documentation
    $bodyObj = @{
        Comment = $Comment
    }
    $body = $bodyObj | ConvertTo-Json
    
    # This call counts against our rate limit
    Wait-ForRateLimit
    
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body
        return $true
    }
    catch {
        # If we get a 429 (Too Many Requests), we can wait and retry
        if ($_.Exception.Response.StatusCode -eq 429) {
            Write-Host "Rate limit exceeded. Waiting 60 seconds before retrying..." -ForegroundColor Yellow
            Start-Sleep -Seconds 60
            # Reset counters
            $script:CallsInCurrentMinute = 0
            $script:MinuteStartTime = Get-Date
            
            # Try again
            Wait-ForRateLimit
            try {
                $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body
                return $true
            }
            catch {
                Write-Error "Failed to cancel LiveResponse session $ActionId after retry: $_"
                return $false
            }
        }
        else {
            Write-Error "Failed to cancel LiveResponse session $ActionId : $_"
            return $false
        }
    }
}

# Main execution
Write-Host "Authenticating to Microsoft Defender API..." -ForegroundColor Cyan
$accessToken = Get-AccessToken -ClientId $ClientId -ClientSecret $ClientSecret -TenantId $TenantId

Write-Host "Retrieving active LiveResponse sessions..." -ForegroundColor Cyan
$liveResponseSessions = Get-LiveResponseSessions -AccessToken $accessToken

if ($null -eq $liveResponseSessions -or $liveResponseSessions.Count -eq 0) {
    Write-Host "No active LiveResponse sessions found." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($liveResponseSessions.Count) active LiveResponse sessions:" -ForegroundColor Green
Write-Host ("-" * 100)

# Flag to track if "all" option was chosen
$cancelAll = $false
# Comment to use for all cancellations if "all" is chosen
$globalComment = ""

# Display sessions and prompt for cancellation
foreach ($session in $liveResponseSessions) {
    # Format creation time
    $createdAtFormatted = [DateTime]::Parse($session.creationDateTimeUtc).ToString("yyyy-MM-dd HH:mm:ss")
    
    # Display session information
    Write-Host "Session ID: " -NoNewline -ForegroundColor Cyan
    Write-Host "$($session.id)"
    Write-Host "Machine: " -NoNewline -ForegroundColor Cyan
    Write-Host "$($session.computerDnsName) ($($session.machineId))"
    Write-Host "Status: " -NoNewline -ForegroundColor Cyan
    Write-Host "$($session.status)"
    Write-Host "Created: " -NoNewline -ForegroundColor Cyan
    Write-Host "$createdAtFormatted UTC"
    Write-Host "Command: " -NoNewline -ForegroundColor Cyan
    Write-Host "$($session.commands -join ', ')"
    
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
        
        Write-Host "Cancelling session $($session.id)..." -ForegroundColor Yellow
        $result = Cancel-LiveResponseSession -AccessToken $accessToken -ActionId $session.id -Comment $comment
        
        if ($result) {
            Write-Host "Session cancelled successfully." -ForegroundColor Green
        }
        else {
            Write-Host "Failed to cancel session." -ForegroundColor Red
        }
    }
    else {
        Write-Host "Skipping cancellation for this session." -ForegroundColor Gray
    }
    
    Write-Host ("-" * 100)
}

Write-Host "LiveResponse session management completed." -ForegroundColor Green
