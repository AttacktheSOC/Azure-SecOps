# Azure Automation Runbook: Defender Secure Score Executive Report
# Runtime: PowerShell 7.x

param(
    [string]$DistributionList = "<send-to>",
    [string]$SenderUser = "<send-as>",
    [ValidateSet("ManagedIdentity", "Interactive")]
    [string]$AuthMode = "Interactive",
    [string]$TenantId
)

# ============================================================================
# 1. AUTHENTICATION - Microsoft Graph PowerShell SDK
# ============================================================================
function Connect-GraphContext {
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
    try {
        if ($AuthMode -eq "ManagedIdentity") {
            if ($TenantId) {
                Connect-MgGraph -Identity -TenantId $TenantId -NoWelcome | Out-Null
            }
            else {
                Connect-MgGraph -Identity -NoWelcome | Out-Null
            }
        }
        else {
            $scopes = @("SecurityEvents.Read.All", "Mail.Send")
            if ($TenantId) {
                Connect-MgGraph -TenantId $TenantId -Scopes $scopes -NoWelcome | Out-Null
            }
            else {
                Connect-MgGraph -Scopes $scopes -NoWelcome | Out-Null
            }
        }

        $context = Get-MgContext
        if (-not $context) {
            throw "Microsoft Graph connection context was not created."
        }
    } catch {
        throw "Failed to connect to Microsoft Graph using mode '$AuthMode'. Error: $($_.Exception.Message)"
    }
}

function Invoke-GraphRequestSafe {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Uri,
        $Body
    )

    try {
        if ($PSBoundParameters.ContainsKey('Body')) {
            return Invoke-MgGraphRequest -Method $Method -Uri $Uri -Body $Body -OutputType PSObject
        }

        return Invoke-MgGraphRequest -Method $Method -Uri $Uri -OutputType PSObject
    }
    catch {
        throw "Graph request failed ($Method $Uri): $($_.Exception.Message)"
    }
}

# ============================================================================
# 2. DATA RETRIEVAL - Microsoft Graph API Queries
# ============================================================================
function Get-SecureScoreData {
    
    # Fetch current secure score (latest record is sufficient)
    $scoreUri = "https://graph.microsoft.com/v1.0/security/secureScores?`$top=2"
    $scoreData = Invoke-GraphRequestSafe -Method GET -Uri $scoreUri
    
    # Fetch ALL control profiles with pagination
    $allProfiles = @()
    $controlUri = "https://graph.microsoft.com/v1.0/security/secureScoreControlProfiles"
    do {
        $controlData = Invoke-GraphRequestSafe -Method GET -Uri $controlUri
        $allProfiles += @($controlData.value)
        $controlUri = $controlData.'@odata.nextLink'
    } while ($controlUri)
    
    return @{
        Score    = $scoreData
        Controls = @{ value = $allProfiles }
    }
}

# ============================================================================
# 3. DATA TRANSFORMATION - Process for Report
# ============================================================================
function ConvertTo-ReportData {
    param($RawData)

    $currentScore = $RawData.Score.value | Sort-Object -Property createdDateTime -Descending | Select-Object -First 1
    if (-not $currentScore) {
        throw "No Secure Score records were returned by Microsoft Graph."
    }

    $categoryBreakdown = @{}

    # Build a lookup map: profile.id -> profile (profile.id matches controlScore.controlName)
    $profileMap = @{}
    foreach ($p in $RawData.Controls.value) {
        if ($p.id) { $profileMap[[string]$p.id] = $p }
    }
    Write-Output "Profile map built with $($profileMap.Count) control profiles."

    # Category breakdown using two-source maxScore:
    #   - If scoreInPercentage > 0: derive maxScore = score * 100 / scoreInPercentage
    #   - If scoreInPercentage == 0: look up profile.maxScore (control is fully unimplemented)
    foreach ($cs in $currentScore.controlScores) {
        $category = if ($cs.controlCategory) { $cs.controlCategory } else { 'Other' }

        if (-not $categoryBreakdown[$category]) {
            $categoryBreakdown[$category] = @{ score = 0; maxScore = 0 }
        }

        $csScore    = if ($null -ne $cs.score) { [double]$cs.score } else { 0 }
        $scoreInPct = if ($null -ne $cs.scoreInPercentage) { [double]$cs.scoreInPercentage } else { 0 }

        if ($scoreInPct -gt 0) {
            $csMaxScore = [math]::Round(($csScore * 100) / $scoreInPct, 4)
        } else {
            # Zero percent — use profile maxScore as the attainable points for this control
            $profile    = $profileMap[$cs.controlName]
            $csMaxScore = if ($profile -and $null -ne $profile.maxScore) { [double]$profile.maxScore } else { 0 }
        }

        $categoryBreakdown[$category].score    += $csScore
        $categoryBreakdown[$category].maxScore += $csMaxScore
    }

    # Top 5 improvement actions — join controlScores with profiles for metadata
    $topActions = @()
    foreach ($cs in $currentScore.controlScores) {
        $profile = $profileMap[$cs.controlName]

        $csScore    = if ($null -ne $cs.score) { [double]$cs.score } else { 0 }
        $scoreInPct = if ($null -ne $cs.scoreInPercentage) { [double]$cs.scoreInPercentage } else { 0 }

        if ($scoreInPct -gt 0) {
            $csMaxScore = [math]::Round(($csScore * 100) / $scoreInPct, 4)
        } elseif ($profile -and $null -ne $profile.maxScore) {
            $csMaxScore = [double]$profile.maxScore
        } else {
            $csMaxScore = 0
        }

        $gain = [math]::Round(($csMaxScore - $csScore), 2)
        if ($gain -le 0) { continue }

        # Determine display title
        $title = if ($profile -and $profile.title) { $profile.title } else { [string]$cs.controlName }
        # Build Defender portal deep link: actionId = controlName (same as profile.id)
        $actionLink = "https://security.microsoft.com/securescore?viewid=actions&actionId=$([string]$cs.controlName)"
        # Implementation effort from profile
        $effort = if ($profile -and $profile.implementationCost) { $profile.implementationCost } else { '' }
        $impact = if ($profile -and $profile.userImpact) { $profile.userImpact } else { '' }

        $topActions += [PSCustomObject]@{
            id                    = if ($profile) { [string]$profile.id } else { [string]$cs.controlName }
            title                 = $title
            potentialScoreIncrease = $gain
            actionUrl             = $actionLink
            implementationCost    = $effort
            userImpact            = $impact
        }
    }
    $topActions = $topActions | Sort-Object -Property potentialScoreIncrease -Descending | Select-Object -First 5

    $scorePercent = if ($currentScore.maxScore -gt 0) {
        [math]::Round((($currentScore.currentScore / $currentScore.maxScore) * 100), 2)
    } else { 0 }

    # Score trend — compare with previous day if available
    $allScores = @($RawData.Score.value | Sort-Object -Property createdDateTime -Descending)
    $scoreTrend = 'flat'
    $trendDelta = 0
    if ($allScores.Count -ge 2) {
        $prevScore = $allScores[1]
        if ($prevScore.maxScore -gt 0) {
            $prevPct   = [math]::Round((($prevScore.currentScore / $prevScore.maxScore) * 100), 2)
            $trendDelta = [math]::Round(($scorePercent - $prevPct), 2)
            $scoreTrend = if ($trendDelta -gt 0) { 'up' } elseif ($trendDelta -lt 0) { 'down' } else { 'flat' }
        }
    }

    # Industry benchmark from averageComparativeScores
    $benchmark = $currentScore.averageComparativeScores | Where-Object { $_.basis -eq 'AllTenants' } | Select-Object -First 1
    $benchmarkPct = if ($benchmark -and $benchmark.averageScore -gt 0 -and $currentScore.maxScore -gt 0) {
        [math]::Round(($benchmark.averageScore / $currentScore.maxScore) * 100, 2)
    } else { 0 }

    return @{
        CurrentScore      = $scorePercent
        CategoryBreakdown = $categoryBreakdown
        TopActions        = $topActions
        DateGenerated     = (Get-Date -Format "MMMM dd, yyyy HH:mm UTC")
        TenantId          = if ($TenantId) { $TenantId } else { (Get-MgContext).TenantId }
        ScoreTrend        = $scoreTrend
        TrendDelta        = $trendDelta
        BenchmarkPct      = $benchmarkPct
    }
}

# ============================================================================
# 4. HTML REPORT GENERATION - Inline CSS/JS Dashboard
# ============================================================================
function New-SecureScoreHtmlReport {
    param($ReportData)

    $dashboardUrl = "https://security.microsoft.com/exposure-secure-scores"
    $tenantId = [string]$ReportData.TenantId
    
    # Build action items HTML server-side
    $actionItemsHtml = ""
    foreach ($action in $ReportData.TopActions) {
        $actionTitle = [System.Web.HttpUtility]::HtmlEncode($action.title)
        $actionGain  = [System.Web.HttpUtility]::HtmlEncode([string]$action.potentialScoreIncrease)
        $actionLink  = if ($action.actionUrl -and $action.actionUrl -ne '') { $action.actionUrl } else { $dashboardUrl }
        # Effort and impact badges
        $effortBadge = if ($action.implementationCost) {
            $effortColor = switch ($action.implementationCost) { 'Low' { '#059669' } 'Moderate' { '#d97706' } 'High' { '#dc2626' } default { '#6b7280' } }
            "<span style=`"display:inline-block;font-size:11px;padding:2px 8px;border-radius:10px;background:$effortColor;color:white;margin-right:6px;`">Effort: $($action.implementationCost)</span>"
        } else { '' }
        $impactBadge = if ($action.userImpact) {
            "<span style=`"display:inline-block;font-size:11px;padding:2px 8px;border-radius:10px;background:#6366f1;color:white;`">User Impact: $($action.userImpact)</span>"
        } else { '' }
        $badges = if ($effortBadge -or $impactBadge) { "<div style=`"margin-top:6px;`">$effortBadge$impactBadge</div>" } else { '' }

        $actionItemsHtml += @"
            <div class="action-item">
                <div class="action-title"><a href="$actionLink" target="_blank" rel="noopener noreferrer">$actionTitle</a></div>
                <div class="action-impact">Potential score gain: +$actionGain pts</div>
                $badges
            </div>
"@
    }

    # Build priority actions mini list (unused in current template but kept for flexibility)
    $priorityActionsHtml = ""
    foreach ($action in $ReportData.TopActions) {
        $actionTitle = [System.Web.HttpUtility]::HtmlEncode($action.title)
        $actionGain  = [System.Web.HttpUtility]::HtmlEncode([string]$action.potentialScoreIncrease)
        $actionLink  = if ($action.actionUrl -and $action.actionUrl -ne '') { $action.actionUrl } else { $dashboardUrl }

        $priorityActionsHtml += @"
            <li><a href="$actionLink" target="_blank" rel="noopener noreferrer" style="flex:1;color:#0a66c2;text-decoration:none;">$actionTitle</a><span class="mini-score">+$actionGain</span></li>
"@
    }
    
    # Build category bars HTML server-side with color coding
    $categoryBarsHtml = ""
    foreach ($catName in $ReportData.CategoryBreakdown.Keys | Sort-Object) {
        $cat = $ReportData.CategoryBreakdown[$catName]
        $catPercent = if ($cat.maxScore -gt 0) { [math]::Round(($cat.score / $cat.maxScore) * 100) } else { 0 }
        $catNameEscaped = [System.Web.HttpUtility]::HtmlEncode($catName)
        # Color-code: green >70%, yellow 40-70%, red <40%
        $barColor = if ($catPercent -ge 70) { '#059669' } elseif ($catPercent -ge 40) { '#d97706' } else { '#dc2626' }
        
        $categoryBarsHtml += @"
            <div class="category-row">
                <div class="category-head">
                    <a href="$dashboardUrl" target="_blank" rel="noopener noreferrer">$catNameEscaped</a>
                    <span class="category-pct">$catPercent%</span>
                </div>
                <div class="bar-track"><div class="bar-fill" style="width:${catPercent}%;background:${barColor};"></div></div>
            </div>
"@
    }
    
    # Trend indicator
    $trendArrow = switch ($ReportData.ScoreTrend) { 'up' { '&#9650;' } 'down' { '&#9660;' } default { '&#9644;' } }
    $trendColor = switch ($ReportData.ScoreTrend) { 'up' { '#059669' } 'down' { '#dc2626' } default { '#6b7280' } }
    $trendSign  = if ($ReportData.TrendDelta -gt 0) { '+' } else { '' }
    $trendText  = "${trendSign}$($ReportData.TrendDelta)%"
    $benchmarkPct = $ReportData.BenchmarkPct * 100

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Microsoft Defender Secure Score Report</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f5f5f5; padding: 20px; color: #1f2937; }
        .container { max-width: 980px; margin: 0 auto; background: white; border-radius: 10px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); overflow: hidden; }
        .header { background: linear-gradient(135deg, #0078d4 0%, #00a4ef 100%); color: white; padding: 36px; text-align: center; }
        .header h1 { font-size: 30px; margin-bottom: 8px; }
        .header p { font-size: 14px; opacity: 0.95; }
        .header a { color: #e8f3ff; text-decoration: underline; }
        .score-display { text-align: center; padding: 34px; background: #f9fafb; }
        .score-value { font-size: 50px; font-weight: 700; color: #0078d4; }
        .score-label { font-size: 14px; color: #6b7280; margin-top: 5px; }
        .score-meta { font-size: 13px; color: #6b7280; margin-top: 8px; }
        .metrics { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 16px; padding: 24px; background: white; }
        .metric { background: #f8fafc; padding: 18px; border-radius: 8px; border: 1px solid #e5e7eb; text-align: center; }
        .metric-value { font-size: 22px; font-weight: 700; color: #0078d4; margin-bottom: 4px; }
        .metric-label { font-size: 12px; color: #6b7280; text-transform: uppercase; letter-spacing: .04em; }
        .section { padding: 6px 24px 24px; }
        .section h3 { color: #0078d4; margin-bottom: 12px; font-size: 18px; }
        .action-item { padding: 12px; background: #f9fafb; border-left: 4px solid #0078d4; margin-bottom: 10px; border-radius: 4px; border: 1px solid #edf2f7; }
        .action-title a { font-weight: 600; color: #0a66c2; text-decoration: none; }
        .action-title a:hover { text-decoration: underline; }
        .action-impact { font-size: 12px; color: #6b7280; margin-top: 4px; }
        .category-row { margin-bottom: 12px; }
        .category-head { display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 5px; }
        .category-head a { color: #0a66c2; text-decoration: none; font-weight: 600; }
        .category-head a:hover { text-decoration: underline; }
        .category-pct { font-size: 12px; color: #6b7280; font-weight: 600; }
        .bar-track { width: 100%; height: 10px; background: #e5e7eb; border-radius: 999px; overflow: hidden; }
        .bar-fill { height: 100%; border-radius: 999px; }
        .footer { background: #f5f5f5; padding: 18px; text-align: center; font-size: 12px; color: #6b7280; border-top: 1px solid #e5e7eb; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Microsoft Defender Secure Score</h1>
            <p>Executive Security Dashboard | $($ReportData.DateGenerated)</p>
            <p><a href="$dashboardUrl" target="_blank" rel="noopener noreferrer">Open Secure Score Dashboard</a></p>
        </div>
        
        <div class="score-display">
            <div class="score-value">$($ReportData.CurrentScore)%</div>
            <div class="score-label">Overall Security Posture</div>
            <div class="score-meta">
                <span style="color:${trendColor};font-weight:600;">$trendArrow $trendText</span> vs previous day
            </div>
        </div>
        
        <div class="metrics">
            <div class="metric">
                <div class="metric-value" style="color:${trendColor};">$trendArrow $trendText</div>
                <div class="metric-label">Score Trend</div>
            </div>
            <div class="metric">
                <div class="metric-value">${benchmarkPct}%</div>
                <div class="metric-label">Industry Average</div>
            </div>
            <div class="metric">
                <div class="metric-value">$($ReportData.CategoryBreakdown.Keys.Count)</div>
                <div class="metric-label">Categories Monitored</div>
            </div>
            <div class="metric">
                <div class="metric-value"><a href="$dashboardUrl" target="_blank" rel="noopener noreferrer" style="color:#0078d4;text-decoration:none;">Open Portal</a></div>
                <div class="metric-label">Quick Access</div>
            </div>
        </div>
        
        <div class="section">
            <h3>Monitored Categories</h3>
            $categoryBarsHtml
        </div>

        <div class="section">
            <h3>Top 5 Recommended Improvements</h3>
            $actionItemsHtml
        </div>
        
        <div class="footer">
            Report generated by Azure Automation. For questions, contact your security team.
        </div>
    </div>
</body>
</html>
"@
    return $html
}

# ============================================================================
# 5. EMAIL DELIVERY - Send via Graph API
# ============================================================================
function Send-SecureScoreReport {
    param([string]$HtmlContent, [string]$Recipients)

    if (-not $SenderUser) {
        throw "SenderUser is required for app-only sendMail."
    }

    $recipientAddresses = @($Recipients -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($recipientAddresses.Count -eq 0) {
    throw "At least one recipient is required."
}

$toRecipients = @()
foreach ($address in $recipientAddresses) {
    $toRecipients += @{
        emailAddress = @{
            address = [string]$address
        }
    }
}

$emailBody = @{
    message = @{
        subject = "Microsoft Defender Secure Score Report - Executive Summary"
        body = @{
            contentType = "HTML"
            content = $HtmlContent
        }
        toRecipients = $toRecipients
    }
    saveToSentItems = $true
}

$uri = "https://graph.microsoft.com/v1.0/users/$SenderUser/sendMail"
$jsonBody = $emailBody | ConvertTo-Json -Depth 10 -Compress
Invoke-MgGraphRequest -Method 'POST' -Uri $uri -Body $jsonBody -ContentType "application/json" | Out-Null
}

# ============================================================================
# 6. MAIN ORCHESTRATION
# ============================================================================
try {
    Write-Output "Starting Secure Score Report Generation..."

    Connect-GraphContext
    Write-Output "Connected to Microsoft Graph."

    $rawData = Get-SecureScoreData
    Write-Output "Secure Score data retrieved."

    $processedData = ConvertTo-ReportData -RawData $rawData
    $htmlReport = New-SecureScoreHtmlReport -ReportData $processedData

    Send-SecureScoreReport -HtmlContent $htmlReport -Recipients $DistributionList
    
    Write-Output "Report generated and sent successfully."
}
catch {
    Write-Error "Runbook failed: $_"
    exit 1
}
finally {
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
}
