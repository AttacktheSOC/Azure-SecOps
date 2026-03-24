[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$WorkspaceName,

    [Parameter(Mandatory = $true)]
    [string]$Region,

    [Parameter(Mandatory = $false)]
    [string]$AccessToken,

    [Parameter(Mandatory = $false)]
    [string]$ClientId,

    [Parameter(Mandatory = $false)]
    [string]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [int]$TopN = 10,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 64)]
    [int]$MaxConcurrency = 10,

    [Parameter(Mandatory = $false)]
    [ValidateRange(10, 100)]
    [int]$PageSize = 100,

    [Parameter(Mandatory = $false)]
    [ValidateSet('CSV', 'JSON', 'Both')]
    [string]$ExportFormat = 'Both',

    [Parameter(Mandatory = $false)]
    [string]$ExportPath = ".\\easm-report-$((Get-Date).ToString('yyyyMMdd-HHmmss'))",

    [Parameter(Mandatory = $false)]
    [switch]$NoInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Section {
    param([string]$Text)
    Write-Host "`n=== $Text ===" -ForegroundColor Cyan
}

function Write-Info {
    param([string]$Text)
    Write-Host "[INFO] $Text" -ForegroundColor Gray
}

function Write-Warn {
    param([string]$Text)
    Write-Host "[WARN] $Text" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Text)
    Write-Host "[ERROR] $Text" -ForegroundColor Red
}

function Test-Prerequisites {
    Write-Section 'Validating prerequisites'

    if ($PSVersionTable.PSVersion.Major -lt 7) {
        throw 'PowerShell 7+ is required for ForEach-Object -Parallel concurrency.'
    }

    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw "Azure CLI ('az') was not found in PATH. Install Azure CLI and sign in."
    }

    Write-Info "PowerShell version: $($PSVersionTable.PSVersion)"
    Write-Info "Azure CLI located."
}

function Get-EasmAccessToken {
    param(
        [string]$Tenant,
        [string]$Subscription,
        [string]$ProvidedToken,
        [string]$SpClientId,
        [string]$SpClientSecret
    )

    # If a token was passed directly, use it as-is
    if (-not [string]::IsNullOrWhiteSpace($ProvidedToken)) {
        Write-Info 'Using caller-provided access token.'
        return [pscustomobject]@{
            AccessToken = $ProvidedToken
            ExpiresOn   = (Get-Date).AddMinutes(50)
        }
    }

    # Try to get a token from an existing Azure CLI session first
    Write-Info 'Checking for existing Azure CLI session...'
    $tokenJson = $null
    try {
        $tokenJson = & az account get-access-token --scope 'https://easm.defender.microsoft.com/.default' --output json 2>$null
    }
    catch { }

    if (-not $tokenJson) {
        # No existing session — need to log in
        if (-not [string]::IsNullOrWhiteSpace($SpClientId) -and -not [string]::IsNullOrWhiteSpace($SpClientSecret)) {
            if ([string]::IsNullOrWhiteSpace($Tenant)) {
                throw '-TenantId is required when using service principal authentication.'
            }
            Write-Info 'Authenticating with service principal...'
            & az login --service-principal -u $SpClientId -p $SpClientSecret --tenant $Tenant --allow-no-subscriptions | Out-Null
        }
        else {
            if ([string]::IsNullOrWhiteSpace($Tenant)) {
                throw '-TenantId is required when no existing Azure CLI session is available.'
            }
            Write-Info 'Authenticating with Azure CLI (interactive browser login)...'
            & az login --tenant $Tenant | Out-Null
        }

        if ($Subscription) {
            Write-Info "Setting active subscription: $Subscription"
            & az account set --subscription $Subscription | Out-Null
        }

        $tokenJson = & az account get-access-token --scope 'https://easm.defender.microsoft.com/.default' --output json
    }

    if (-not $tokenJson) {
        throw 'Failed to obtain access token from Azure CLI.'
    }

    $tokenObj = $tokenJson | ConvertFrom-Json
    if (-not $tokenObj.accessToken) {
        throw 'Access token payload did not include accessToken.'
    }

    [pscustomobject]@{
        AccessToken = $tokenObj.accessToken
        ExpiresOn   = if ($tokenObj.expiresOn) { [datetime]$tokenObj.expiresOn } else { (Get-Date).AddMinutes(50) }
    }
}

function Get-ApiBaseUri {
    param(
        [string]$Workspace,
        [string]$WorkspaceRegion,
        [string]$Subscription,
        [string]$ResourceGroup
    )

    "https://$WorkspaceRegion.easm.defender.microsoft.com/subscriptions/$Subscription/resourceGroups/$ResourceGroup/workspaces/$Workspace"
}

function ConvertTo-AssetList {
    param([object]$Response)

    if ($null -eq $Response) { return @() }

    if ($Response -is [System.Array]) {
        $items = $Response
    } else {
        $items = $null
        foreach ($candidate in @('value', 'items', 'assets', 'data')) {
            if ($Response.PSObject.Properties[$candidate]) {
                $items = @($Response.$candidate)
                break
            }
        }
        if ($null -eq $items) { return @() }
    }

    # Promote nested .asset sub-properties to top level for direct access
    foreach ($item in $items) {
        if ($item.PSObject.Properties['asset'] -and $null -ne $item.asset) {
            foreach ($prop in $item.asset.PSObject.Properties) {
                if (-not $item.PSObject.Properties[$prop.Name]) {
                    $item.PSObject.Properties.Add(
                        [System.Management.Automation.PSNoteProperty]::new($prop.Name, $prop.Value))
                }
            }
        }
    }

    return @($items)
}

function Get-TotalElements {
    param([object]$Response)

    foreach ($candidate in @('totalElements', 'totalCount', 'count', 'total')) {
        if ($Response.PSObject.Properties[$candidate]) {
            return [int]$Response.$candidate
        }
    }

    return $null
}

function Get-AssetId {
    param([object]$Asset)

    foreach ($candidate in @('id', 'assetId', 'uuid')) {
        if ($Asset.PSObject.Properties[$candidate] -and -not [string]::IsNullOrWhiteSpace([string]$Asset.$candidate)) {
            return [string]$Asset.$candidate
        }
    }

    return $null
}

function Get-AssetName {
    param([object]$Asset)

    foreach ($candidate in @('name', 'host', 'assetName', 'fqdn')) {
        if ($Asset.PSObject.Properties[$candidate] -and -not [string]::IsNullOrWhiteSpace([string]$Asset.$candidate)) {
            return [string]$Asset.$candidate
        }
    }

    return '(unknown-host)'
}

function Invoke-EasmApiWithRetry {
    param(
        [string]$Uri,
        [hashtable]$Headers,
        [int]$TimeoutSec = 120,
        [int]$MaxRetry = 4
    )

    $attempt = 0
    while ($true) {
        try {
            return Invoke-RestMethod -Method GET -Uri $Uri -Headers $Headers -TimeoutSec $TimeoutSec
        }
        catch {
            $attempt++
            $statusCode = $null
            if ($_.Exception.PSObject.Properties['Response'] -and
                $_.Exception.Response -and
                $_.Exception.Response.PSObject.Properties['StatusCode']) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            $isRetriable = $statusCode -in @(429, 500, 502, 503, 504)
            if (-not $isRetriable -or $attempt -gt $MaxRetry) {
                throw
            }

            $delay = [math]::Min(30, [math]::Pow(2, $attempt))
            Write-Warn "API call throttled/failed (HTTP $statusCode). Retry $attempt/$MaxRetry in ${delay}s: $Uri"
            Start-Sleep -Seconds $delay
        }
    }
}

function Get-AllApprovedHosts {
    param(
        [string]$BaseUri,
        [string]$ApiVersion,
        [string]$AccessToken,
        [int]$Top,
        [int]$Concurrency
    )

    Write-Section 'Fetching approved host assets'

    $headers = @{ Authorization = "Bearer $AccessToken" }
    $filter = 'kind = "host" and state = "confirmed"'
    $encodedFilter = [uri]::EscapeDataString($filter)

    $firstUrl = "$BaseUri/assets?api-version=$ApiVersion&maxpagesize=$Top&filter=$encodedFilter"
    Write-Info "Request URL: $firstUrl"
    $firstResponse = Invoke-EasmApiWithRetry -Uri $firstUrl -Headers $headers

    $allItems = [System.Collections.Generic.List[object]]::new()
    foreach ($item in (ConvertTo-AssetList -Response $firstResponse)) {
        $allItems.Add($item)
    }

    $total = Get-TotalElements -Response $firstResponse
    if ($null -ne $total) {
        Write-Info "Total host assets reported by API: $total"
    }

    $nextLink = if ($firstResponse.PSObject.Properties['nextLink']) { $firstResponse.nextLink } else { $null }
    while (-not [string]::IsNullOrWhiteSpace([string]$nextLink)) {
        $nextResponse = Invoke-EasmApiWithRetry -Uri $nextLink -Headers $headers
        foreach ($item in (ConvertTo-AssetList -Response $nextResponse)) {
            $allItems.Add($item)
        }
        $nextLink = if ($nextResponse.PSObject.Properties['nextLink']) { $nextResponse.nextLink } else { $null }
        Write-Info "Loaded $($allItems.Count) hosts so far..."
    }

    $allItems.ToArray()
}

function Get-RecentIpRows {
    param([object]$HostAsset)

    $rows = @()
    if (-not $HostAsset.PSObject.Properties['ipAddresses']) {
        return $rows
    }

    foreach ($ip in @($HostAsset.ipAddresses)) {
        $recent = $false
        if ($ip.PSObject.Properties['recent'] -and $null -ne $ip.recent) {
            $recent = [bool]$ip.recent
        }

        if (-not $recent) {
            continue
        }

        $ipValue = $null
        foreach ($candidate in @('ipAddress', 'address', 'name', 'value')) {
            if ($ip.PSObject.Properties[$candidate] -and -not [string]::IsNullOrWhiteSpace([string]$ip.$candidate)) {
                $ipValue = [string]$ip.$candidate
                break
            }
        }

        if ([string]::IsNullOrWhiteSpace($ipValue)) {
            continue
        }

        $rows += [pscustomobject]@{
            IPAddress = $ipValue
            FirstSeen = if ($ip.PSObject.Properties['firstSeen']) { $ip.firstSeen } else { $null }
            LastSeen  = if ($ip.PSObject.Properties['lastSeen']) { $ip.lastSeen } else { $null }
            Recent    = $recent
        }
    }

    $rows
}

function Convert-PriorityToRank {
    param([string]$Priority)

    switch -Regex ($Priority) {
        'critical' { return 1 }
        '^high$'   { return 2 }
        'medium'   { return 3 }
        'low'      { return 4 }
        default    { return 5 }
    }
}

function Get-ObservationRows {
    param([object]$Detail)

    $obs = @()
    if (-not $Detail.PSObject.Properties['observations'] -or $null -eq $Detail.observations) {
        return $obs
    }

    foreach ($o in @($Detail.observations)) {
        $priority = if ($o.PSObject.Properties['priority'] -and $o.priority) { [string]$o.priority } else { 'Unknown' }
        $cvss3 = if ($o.PSObject.Properties['cvssv3Score'] -and $null -ne $o.cvssv3Score) { [double]$o.cvssv3Score }
                 elseif ($o.PSObject.Properties['cvssV3Score'] -and $null -ne $o.cvssV3Score) { [double]$o.cvssV3Score } else { 0.0 }
        $cvss2 = if ($o.PSObject.Properties['cvssv2Score'] -and $null -ne $o.cvssv2Score) { [double]$o.cvssv2Score }
                 elseif ($o.PSObject.Properties['cvssV2Score'] -and $null -ne $o.cvssV2Score) { [double]$o.cvssV2Score } else { 0.0 }

        $obs += [pscustomobject]@{
            Name      = if ($o.PSObject.Properties['name'] -and $o.name) { [string]$o.name } else { '(unnamed-observation)' }
            Type      = if ($o.PSObject.Properties['type'] -and $o.type) { [string]$o.type } else { '' }
            Priority  = $priority
            CVSSv3    = $cvss3
            CVSSv2    = $cvss2
            Rank      = Convert-PriorityToRank -Priority $priority
            RawObject = $o
        }
    }

    $obs | Sort-Object Rank, @{ Expression = 'CVSSv3'; Descending = $true }, @{ Expression = 'CVSSv2'; Descending = $true }
}

function Get-DiscoveryChainSummary {
    param([object]$Detail)

    if (-not $Detail.PSObject.Properties['auditTrail'] -or $null -eq $Detail.auditTrail) {
        return @('(no discovery chain found)')
    }

    $lines = @()
    $i = 0
    foreach ($node in @($Detail.auditTrail)) {
        $i++
        $parts = @()
        foreach ($candidate in @('source', 'from', 'seed', 'relation', 'type', 'property', 'value', 'target', 'to', 'name')) {
            if ($node.PSObject.Properties[$candidate] -and -not [string]::IsNullOrWhiteSpace([string]$node.$candidate)) {
                $parts += "${candidate}=$($node.$candidate)"
            }
        }

        if ($parts.Count -eq 0) {
            $parts += (ConvertTo-Json $node -Compress -Depth 6)
        }

        $lines += "[$i] " + ($parts -join '; ')
    }

    $lines
}

function Get-HostDetailEnrichment {
    param(
        [object[]]$TopHosts,
        [string]$BaseUri,
        [string]$ApiVersion,
        [string]$AccessToken,
        [int]$Concurrency
    )

    Write-Section "Enriching top $($TopHosts.Count) hosts (discovery chain + observations)"

    $results = $TopHosts | ForEach-Object -Parallel {
        $hostRecord = $_
        $assetId = $hostRecord.AssetId
        if ([string]::IsNullOrWhiteSpace($assetId)) {
            return [pscustomobject]@{
                Host           = $hostRecord
                DiscoveryChain = @('(no asset id available)')
                Observations   = @()
                Error          = 'AssetId missing'
            }
        }

        $encodedId = [uri]::EscapeDataString($assetId)
        $detailUrl = "$using:BaseUri/assets/${encodedId}?api-version=$using:ApiVersion"
        $headers = @{ Authorization = "Bearer $using:AccessToken" }

        try {
            $detail = Invoke-RestMethod -Method GET -Uri $detailUrl -Headers $headers -TimeoutSec 120

            # Promote nested .asset sub-properties to top level
            if ($detail.PSObject.Properties['asset'] -and $null -ne $detail.asset) {
                foreach ($prop in $detail.asset.PSObject.Properties) {
                    if (-not $detail.PSObject.Properties[$prop.Name]) {
                        $detail.PSObject.Properties.Add(
                            [System.Management.Automation.PSNoteProperty]::new($prop.Name, $prop.Value))
                    }
                }
            }

            $auditTrail = @()
            if ($detail.PSObject.Properties['auditTrail'] -and $null -ne $detail.auditTrail) {
                $auditTrail = @($detail.auditTrail)
            }

            $obs = @()
            if ($detail.PSObject.Properties['observations'] -and $null -ne $detail.observations) {
                $obs = @($detail.observations)
            }

            [pscustomobject]@{
                Host           = $hostRecord
                Detail         = $detail
                DiscoveryTrail = $auditTrail
                Observations   = $obs
                Error          = $null
            }
        }
        catch {
            [pscustomobject]@{
                Host           = $hostRecord
                Detail         = $null
                DiscoveryTrail = @()
                Observations   = @()
                Error          = $_.Exception.Message
            }
        }
    } -ThrottleLimit $Concurrency

    $enriched = [System.Collections.Generic.List[object]]::new()

    foreach ($entry in $results) {
        if ($entry.Error) {
            Write-Warn "Failed to enrich host '$($entry.Host.HostName)': $($entry.Error)"
        }

        $detailObj = $entry.Detail
        if ($null -eq $detailObj) {
            $detailObj = [pscustomobject]@{ auditTrail = @(); observations = @() }
        }

        $discoverySummary = Get-DiscoveryChainSummary -Detail $detailObj
        $observationRows = Get-ObservationRows -Detail $detailObj

        $enriched.Add([pscustomobject]@{
            Host             = $entry.Host
            DiscoverySummary = $discoverySummary
            ObservationRows  = $observationRows
            RawDetail        = $detailObj
        })
    }

    $enriched.ToArray()
}

function Show-SummaryTable {
    param([object[]]$Rows)

    Write-Section 'Top hosts by billable Host:IP pairs'
    $table = $Rows | Select-Object Rank, HostName, PairCount, AssetId, FirstSeen, LastSeen
    $table | Format-Table -AutoSize
}

function Show-HostDrillDown {
    param([object]$EnrichedRow)

    $hostRecord = $EnrichedRow.Host
    Write-Section "Host drill-down: $($hostRecord.HostName)"
    Write-Host "AssetId: $($hostRecord.AssetId)" -ForegroundColor DarkGray
    Write-Host "Billable Host:IP pair count: $($hostRecord.PairCount)" -ForegroundColor Green

    Write-Host "`nHost:IP pairs (recent only):" -ForegroundColor Cyan
    if (@($hostRecord.RecentIpRows).Count -eq 0) {
        Write-Host '  (none found)' -ForegroundColor DarkGray
    }
    else {
        $hostRecord.RecentIpRows | Select-Object IPAddress, FirstSeen, LastSeen | Format-Table -AutoSize
    }

    Write-Host "`nDiscovery chain:" -ForegroundColor Cyan
    foreach ($line in $EnrichedRow.DiscoverySummary) {
        Write-Host "  $line"
    }

    Write-Host "`nTop findings / observations:" -ForegroundColor Cyan
    if (@($EnrichedRow.ObservationRows).Count -eq 0) {
        Write-Host '  (none found)' -ForegroundColor DarkGray
    }
    else {
        $EnrichedRow.ObservationRows | Select-Object -First 10 Name, Type, Priority, CVSSv3, CVSSv2 | Format-Table -AutoSize
    }
}

function Export-Results {
    param(
        [object[]]$EnrichedRows,
        [string]$OutputPath,
        [string]$Format
    )

    Write-Section 'Exporting results'

    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null

    $pairRows = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $EnrichedRows) {
        $hostRecord = $row.Host

        $topObs = $null
        if (@($row.ObservationRows).Count -gt 0) {
            $topObs = $row.ObservationRows[0]
        }

        foreach ($ip in $hostRecord.RecentIpRows) {
            $pairRows.Add([pscustomobject]@{
            HostName               = $hostRecord.HostName
            AssetId                = $hostRecord.AssetId
            PairCount              = $hostRecord.PairCount
                IPAddress              = $ip.IPAddress
                IPFirstSeen            = $ip.FirstSeen
                IPLastSeen             = $ip.LastSeen
                DiscoveryChainSummary  = ($row.DiscoverySummary -join ' | ')
                TopObservation         = if ($topObs) { $topObs.Name } else { '' }
                TopObservationPriority = if ($topObs) { $topObs.Priority } else { '' }
                TopObservationCVSSv3   = if ($topObs) { $topObs.CVSSv3 } else { $null }
            })
        }
    }

    $summaryRows = $EnrichedRows | ForEach-Object {
        $hostRecord = $_.Host
        $topObs = $null
        if (@($_.ObservationRows).Count -gt 0) {
            $topObs = $_.ObservationRows[0]
        }

        [pscustomobject]@{
            Rank            = $hostRecord.Rank
            HostName        = $hostRecord.HostName
            AssetId         = $hostRecord.AssetId
            PairCount       = $hostRecord.PairCount
            DiscoverySteps  = @($_.DiscoverySummary).Count
            ObservationCount = @($_.ObservationRows).Count
            TopObservation  = if ($topObs) { $topObs.Name } else { '' }
            TopPriority     = if ($topObs) { $topObs.Priority } else { '' }
            TopCVSSv3       = if ($topObs) { $topObs.CVSSv3 } else { $null }
        }
    }

    if ($Format -in @('CSV', 'Both')) {
        $summaryCsv = Join-Path $OutputPath 'top-host-summary.csv'
        $pairsCsv = Join-Path $OutputPath 'host-ip-pairs.csv'

        $summaryRows | Export-Csv -Path $summaryCsv -NoTypeInformation -Encoding UTF8
        $pairRows | Export-Csv -Path $pairsCsv -NoTypeInformation -Encoding UTF8

        Write-Info "CSV exported: $summaryCsv"
        Write-Info "CSV exported: $pairsCsv"
    }

    if ($Format -in @('JSON', 'Both')) {
        $jsonFile = Join-Path $OutputPath 'host-analysis.json'

        $jsonPayload = $EnrichedRows | ForEach-Object {
            [pscustomobject]@{
                Host             = $_.Host
                DiscoverySummary = $_.DiscoverySummary
                Observations     = $_.ObservationRows
                RawDetail        = $_.RawDetail
            }
        }

        $jsonPayload | ConvertTo-Json -Depth 12 | Set-Content -Path $jsonFile -Encoding UTF8
        Write-Info "JSON exported: $jsonFile"
    }
}

function Start-InteractiveView {
    param([object[]]$EnrichedRows)

    if (@($EnrichedRows).Count -eq 0) {
        Write-Warn 'No rows available for interactive view.'
        return
    }

    Write-Section 'Interactive view'
    Write-Info "Type a host rank number to drill in, 'g' for Out-GridView, or 'q' to quit."

    while ($true) {
        $inputValue = Read-Host 'Selection'
        if ([string]::IsNullOrWhiteSpace($inputValue)) {
            continue
        }

        if ($inputValue -match '^[Qq]$') {
            break
        }

        if ($inputValue -match '^[Gg]$') {
            $ogv = Get-Command Out-GridView -ErrorAction SilentlyContinue
            if ($null -eq $ogv) {
                Write-Warn 'Out-GridView is not available in this session.'
                continue
            }

            $EnrichedRows | ForEach-Object {
                [pscustomobject]@{
                    Rank            = $_.Host.Rank
                    HostName        = $_.Host.HostName
                    AssetId         = $_.Host.AssetId
                    PairCount       = $_.Host.PairCount
                    ObservationCount = @($_.ObservationRows).Count
                    DiscoverySteps  = @($_.DiscoverySummary).Count
                    IPs             = ($_.Host.RecentIpRows.IPAddress -join ', ')
                }
            } | Out-GridView -Title 'Defender EASM Host:IP Pair Analysis'

            continue
        }

        $selected = $null
        if ($inputValue -match '^\d+$') {
            $rank = [int]$inputValue
            $selected = $EnrichedRows | Where-Object { $_.Host.Rank -eq $rank } | Select-Object -First 1
        }

        if ($null -eq $selected) {
            Write-Warn 'Invalid selection. Enter a visible rank number, g, or q.'
            continue
        }

        Show-HostDrillDown -EnrichedRow $selected
    }
}

# -------------------------------
# Main
# -------------------------------

$apiVersion = '2024-03-01-preview'

try {
    Test-Prerequisites

    $tokenContext = Get-EasmAccessToken -Tenant $TenantId -Subscription $SubscriptionId -ProvidedToken $AccessToken -SpClientId $ClientId -SpClientSecret $ClientSecret
    $baseUri = Get-ApiBaseUri -Workspace $WorkspaceName -WorkspaceRegion $Region -Subscription $SubscriptionId -ResourceGroup $ResourceGroupName

    Write-Section 'Calling Defender EASM API'
    Write-Info "Base URI: $baseUri"
    Write-Info "API version: $apiVersion"
    Write-Info "Filter: kind = host, state = confirmed (approved inventory)"

    $hosts = Get-AllApprovedHosts -BaseUri $baseUri -ApiVersion $apiVersion -AccessToken $tokenContext.AccessToken -Top $PageSize -Concurrency $MaxConcurrency
    Write-Info "Total approved host assets retrieved: $($hosts.Count)"

    if ($hosts.Count -eq 0) {
        Write-Warn 'No approved host assets were returned. Exiting.'
        return
    }

    Write-Section 'Computing billable Host:IP pairs'

    $scored = [System.Collections.Generic.List[object]]::new()
    $counter = 0

    foreach ($h in $hosts) {
        $counter++
        if ($counter % 500 -eq 0 -or $counter -eq $hosts.Count) {
            Write-Progress -Activity 'Scoring host assets' -Status "$counter / $($hosts.Count)" -PercentComplete (($counter / $hosts.Count) * 100)
        }

        $hostName = Get-AssetName -Asset $h
        $assetId = Get-AssetId -Asset $h
        $recentIps = Get-RecentIpRows -HostAsset $h

        $scored.Add([pscustomobject]@{
            HostName     = $hostName
            AssetId      = $assetId
            PairCount    = $recentIps.Count
            RecentIpRows = $recentIps
            FirstSeen    = if ($h.PSObject.Properties['firstSeen']) { $h.firstSeen } else { $null }
            LastSeen     = if ($h.PSObject.Properties['lastSeen']) { $h.lastSeen } else { $null }
            Raw          = $h
        })
    }

    Write-Progress -Activity 'Scoring host assets' -Completed

    $ranked = $scored.ToArray() |
        Sort-Object -Property @{ Expression = 'PairCount'; Descending = $true }, @{ Expression = 'HostName'; Descending = $false } |
        ForEach-Object -Begin { $r = 0 } -Process {
            $r++
            $_ | Add-Member -MemberType NoteProperty -Name Rank -Value $r -Force
            $_
        }

    $topHosts = $ranked | Select-Object -First $TopN

    Show-SummaryTable -Rows $topHosts

    $enriched = Get-HostDetailEnrichment -TopHosts $topHosts -BaseUri $baseUri -ApiVersion $apiVersion -AccessToken $tokenContext.AccessToken -Concurrency $MaxConcurrency

    Write-Section 'Most important observations by top host'
    foreach ($row in $enriched | Sort-Object { $_.Host.Rank }) {
        $topObs = @($row.ObservationRows | Select-Object -First 3)
        if ($topObs.Count -eq 0) {
            Write-Host ("[{0}] {1}: no active observations" -f $row.Host.Rank, $row.Host.HostName) -ForegroundColor DarkGray
            continue
        }

        $obsSummary = $topObs | ForEach-Object {
            "{0} ({1}, CVSSv3 {2})" -f $_.Name, $_.Priority, $_.CVSSv3
        }

        Write-Host ("[{0}] {1}: {2}" -f $row.Host.Rank, $row.Host.HostName, ($obsSummary -join ' | ')) -ForegroundColor Magenta
    }

    Export-Results -EnrichedRows $enriched -OutputPath $ExportPath -Format $ExportFormat

    if (-not $NoInteractive) {
        Start-InteractiveView -EnrichedRows $enriched
    }

    Write-Section 'Completed'
    Write-Host 'Analysis complete.' -ForegroundColor Green
}
catch {
    Write-Err $_.Exception.Message
    throw
}
