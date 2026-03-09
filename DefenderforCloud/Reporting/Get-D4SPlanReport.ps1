<#
.SYNOPSIS
  Report Defender for Servers pricing (P1/P2/Free) per Azure VM and Arc-enabled server and export to CSV.

.DESCRIPTION
  - Inventories compute resources (Azure VMs + Arc machines) across one or more subscriptions (or tenant scope) using Azure Resource Graph for inventory.
  - Queries Defender for Cloud "Pricings" REST API for each resource:
      GET {resourceId}/providers/Microsoft.Security/pricings/VirtualMachines?api-version=2024-01-01
    Falls back to subscription scope if resource scope is unavailable.
  - Exports a readable CSV for Excel.

.NOTES
  Requires: Az.Accounts, Az.ResourceGraph
  Permissions: Reader on target subscriptions/resources is usually sufficient to read pricing config.

#>

param(
    [Parameter(Mandatory = $false)]
    [string[]]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Tenant", "Subscriptions")]
    [string]$ScopeMode = "Subscriptions",

    [Parameter(Mandatory = $false)]
    [string]$OutCsv = ".\DefenderForServersPricing_Report.csv",

    [Parameter(Mandatory = $false)]
    [int]$PageSize = 1000,

    [Parameter(Mandatory = $false)]
    [int]$MaxRetry = 6,

    [Parameter(Mandatory = $false)]
    [string]$OutHtml = ".\DefenderForServersPricing_Report.html"
)

function Get-ArmToken {
    # management.azure.com token
    try {
    $token = (Get-AzAccessToken -ResourceUrl "https://management.azure.com/").Token
    if ($token -is [System.Security.SecureString]) {
        $token = [System.Net.NetworkCredential]::new("", $token).Password
    }
} catch {
    Write-Warning "Failed to get Azure access token. Please run 'Connect-AzAccount' first. Error: $_"
    return
}
return $token
}

function Invoke-ArmGetWithRetry {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Token,
        [Parameter(Mandatory = $false)][int]$MaxRetry = 6
    )

    $headers = @{ Authorization = "Bearer $Token" }
    $attempt = 0

    while ($true) {
        try {
            return Invoke-RestMethod -Method GET -Uri $Uri -Headers $headers -ContentType "application/json" -TimeoutSec 120
        }
        catch {
            $attempt++

            # Try to capture status code (works for many web exceptions)
            $statusCode = $null
            try { $statusCode = $_.Exception.Response.StatusCode.value__ } catch { }

            # Retry on throttling/transient failures
            if ($attempt -le $MaxRetry -and ($statusCode -in 429, 500, 502, 503, 504)) {
                $delay = [Math]::Min(60, [Math]::Pow(2, $attempt))
                Start-Sleep -Seconds $delay
                continue
            }

            throw
        }
    }
}

function Get-ComputeInventory {
    param(
        [string[]]$SubscriptionId,
        [string]$ScopeMode,
        [int]$PageSize
    )

    $query = @"
resources
| where type in~ ('Microsoft.Compute/virtualMachines', 'Microsoft.HybridCompute/machines')
| project id, name, type, subscriptionId, resourceGroup, location
"@

    $all = @()
    $skip = 0

    do {
        if ($ScopeMode -eq "Tenant") {
            
            if ($skip -eq 0){
                $result = Search-AzGraph -Query $query -UseTenantScope -First $PageSize
            }
            else{
                $result = Search-AzGraph -Query $query -UseTenantScope -First $PageSize -Skip $skip
            }
        }
        else {
            if (-not $SubscriptionId -or $SubscriptionId.Count -eq 0) {
                # Use current context subscription if none provided
                $currentSub = (Get-AzContext).Subscription.Id
                $SubscriptionId = @($currentSub)
            }
            if ($skip -eq 0){
                $result = Search-AzGraph -Query $query -Subscription $SubscriptionId -First $PageSize
            }
            else{
            $result = Search-AzGraph -Query $query -Subscription $SubscriptionId -First $PageSize -Skip $skip
            }
        }
        if ($result -and $result.Data) {
            $all += $result.Data
        }

        $skip += $PageSize
    } while ($result.Data.Count -eq $PageSize)

    return $all
}

function Export-DefenderServersPricingHtml {
    param(
        [Parameter(Mandatory)]
        [object[]]$Report,

        [Parameter(Mandatory)]
        [string]$OutHtml,

        [string]$Title = "Defender for Servers Pricing Report (VM + Arc)"
    )

    function HtmlEncode([string]$s) {
        if ($null -eq $s) { return "" }
        return [System.Net.WebUtility]::HtmlEncode($s)
    }

    function SafeId([string]$subId) {
        if ([string]::IsNullOrWhiteSpace($subId)) { return "sub_unknown" }
        return ("sub_" + ($subId -replace '[^a-zA-Z0-9]', ''))
    }

    function PortalResourceUrl([string]$resourceId) {
        if ([string]::IsNullOrWhiteSpace($resourceId)) { return $null }
        return "https://portal.azure.com/#resource$resourceId"
    }

    function PortalSubscriptionUrl([string]$subscriptionId) {
        if ([string]::IsNullOrWhiteSpace($subscriptionId)) { return $null }
        return "https://portal.azure.com/#view/Microsoft_Azure_Billing/SubscriptionDetails.ReactView/subscriptionId/$subscriptionId"
    }

    $generatedLocal = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $total = $Report.Count
    $totalErrors = ($Report | Where-Object { $_.Error }).Count
    $planCounts = $Report | Group-Object EffectivePlan | Sort-Object Name
    $subs = $Report | Group-Object SubscriptionId | Sort-Object Name

    # ----------------------------
    # Trusted CDNs (explicit sources)
    # ----------------------------
    # Bootstrap 5: official docs recommend jsDelivr usage. [3](https://learn.microsoft.com/en-us/rest/api/batchservice/batch-service-rest-api-versioning)[4](https://learn.microsoft.com/fr-fr/rest/api/defenderforcloud/pricings/list?view=rest-defenderforcloud-2024-01-01)
    $bootstrapCss = "https://cdn.jsdelivr.net/npm/bootstrap@5.3.8/dist/css/bootstrap.min.css"
    $bootstrapJs  = "https://cdn.jsdelivr.net/npm/bootstrap@5.3.8/dist/js/bootstrap.bundle.min.js"

    # DataTables: official CDN is cdn.datatables.net; DataTables requires jQuery. [2](https://learn.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-data-sources)[5](https://learn.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-resources)
    $jqueryJs     = "https://code.jquery.com/jquery-3.7.1.min.js"
    $dtCss        = "https://cdn.datatables.net/1.13.11/css/dataTables.bootstrap5.min.css"
    $dtJs         = "https://cdn.datatables.net/1.13.11/js/jquery.dataTables.min.js"
    $dtBsJs       = "https://cdn.datatables.net/1.13.11/js/dataTables.bootstrap5.min.js"

    # Buttons extension + JSZip for Excel export (JSZip needed for HTML5 Excel export). [2](https://learn.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-data-sources)
    $btnCss       = "https://cdn.datatables.net/buttons/2.4.2/css/buttons.bootstrap5.min.css"
    $btnJs        = "https://cdn.datatables.net/buttons/2.4.2/js/dataTables.buttons.min.js"
    $btnBsJs      = "https://cdn.datatables.net/buttons/2.4.2/js/buttons.bootstrap5.min.js"
    $btnHtml5Js   = "https://cdn.datatables.net/buttons/2.4.2/js/buttons.html5.min.js"
    $btnPrintJs   = "https://cdn.datatables.net/buttons/2.4.2/js/buttons.print.min.js"
    $btnColVisJs  = "https://cdn.datatables.net/buttons/2.4.2/js/buttons.colVis.min.js"
    $jszipJs      = "https://cdnjs.cloudflare.com/ajax/libs/jszip/3.10.1/jszip.min.js"

    # Theme-aware CSS
    $customCss = @"
:root{
  --page-bg:#f6f8fb; --panel-bg:#ffffff; --border:rgba(15,23,42,.12);
  --muted:#64748b; --shadow:0 8px 24px rgba(15,23,42,.08);
}
html[data-bs-theme="dark"]{
  --page-bg:#0b1220; --panel-bg:#111a2e; --border:rgba(255,255,255,.12);
  --muted:#9aa4b2; --shadow:0 10px 30px rgba(0,0,0,.25);
}
body{ background:var(--page-bg); }
.small-muted{ color:var(--muted); font-size:.9rem; }
.card{ background:var(--panel-bg); border:1px solid var(--border); box-shadow:var(--shadow); border-radius:12px; }
.nav-tabs .nav-link{ color:var(--muted); }
.nav-tabs .nav-link.active{ color: var(--bs-body-color); background:var(--panel-bg); border-color:var(--border); font-weight:600; }
.tab-content{ background:var(--panel-bg); border:1px solid var(--border); border-top:0; padding:16px; border-radius:0 0 12px 12px; box-shadow:var(--shadow); }
.table thead th{ white-space:nowrap; position:sticky; top:0; z-index:2; }
html[data-bs-theme="light"] .table thead th{ background:#f1f5f9; }
html[data-bs-theme="dark"]  .table thead th{ background:#0f172a; }
.badge-plan{ font-size:.85rem; }
.mono{ font-family: ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono","Courier New",monospace; }
.row-error{ background-color: rgba(239,68,68,.10)!important; }
div.dataTables_wrapper .dataTables_filter input,
div.dataTables_wrapper .dataTables_length select{
  border-radius:10px; border:1px solid var(--border); padding:.35rem .55rem;
  background:var(--panel-bg); color:var(--bs-body-color);
}
.dt-buttons .btn{ border-radius:10px; }
.tab-external{ font-size:.85rem; color:var(--muted); margin-left:.5rem; }
.tab-external:hover{ color: var(--bs-link-color); }
"@

    # IMPORTANT: single-quoted here-string prevents PowerShell expanding $() in JS
    $initJs = @'
(function () {
  // Theme toggle
  const key = "d4sTheme";
  const toggleBtn = document.getElementById("themeToggle");

  function applyTheme(theme) {
    document.documentElement.setAttribute("data-bs-theme", theme);
    localStorage.setItem(key, theme);
    if (window.jQuery && $.fn.dataTable) {
      $.fn.dataTable.tables({ visible: true, api: true }).columns.adjust();
    }
  }

  const saved = localStorage.getItem(key);
  const prefersDark = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
  applyTheme(saved || (prefersDark ? "dark" : "light"));

  if (toggleBtn) {
    toggleBtn.addEventListener("click", () => {
      const current = document.documentElement.getAttribute("data-bs-theme") || "light";
      applyTheme(current === "light" ? "dark" : "light");
    });
  }

  function initTable(table) {
    if ($.fn.dataTable.isDataTable(table)) return;

    $(table).DataTable({
      pageLength: 25,
      lengthMenu: [[10, 25, 50, 100, -1], [10, 25, 50, 100, "All"]],
      dom: "Bfrtip",
      buttons: [
        { extend: "copy", className: "btn btn-sm btn-outline-secondary" },
        { extend: "csv",  className: "btn btn-sm btn-outline-secondary" },
        { extend: "excel", className: "btn btn-sm btn-outline-secondary", title: "DefenderForServersPricing" },
        { extend: "print", className: "btn btn-sm btn-outline-secondary" },
        { extend: "colvis", className: "btn btn-sm btn-outline-secondary" }
      ],
      order: [[0, "desc"]],
      autoWidth: false
    });
  }

  document.querySelectorAll("table.dt-table").forEach(initTable);

  // Bootstrap tab shown event -> adjust DataTables columns for hidden tabs
  const subTabs = document.getElementById("subTabs");
  if (subTabs) {
    subTabs.addEventListener("shown.bs.tab", function (event) {
      const pane = document.querySelector(event.target.getAttribute("data-bs-target"));
      if (!pane) return;
      pane.querySelectorAll("table.dt-table").forEach(function (tbl) {
        initTable(tbl);
        $(tbl).DataTable().columns.adjust();
      });
    });
  }

  // Copy buttons
  document.addEventListener("click", async function(e) {
    const btn = e.target.closest(".copy-btn");
    if (!btn) return;
    const text = btn.getAttribute("data-copy");
    try {
      await navigator.clipboard.writeText(text);
      btn.textContent = "Copied!";
      setTimeout(() => btn.textContent = "Copy", 900);
    } catch (err) {
      alert("Copy failed. You can manually copy the value.");
    }
  });

  // Prevent external subscription links from triggering tab switch
  document.addEventListener("click", function(e){
    const ext = e.target.closest("a.tab-external");
    if (ext) { e.stopPropagation(); }
  });
})();
'@

    $sb = New-Object System.Text.StringBuilder

    [void]$sb.AppendLine("<!doctype html>")
    [void]$sb.AppendLine("<html lang='en' data-bs-theme='light'>")
    [void]$sb.AppendLine("<head>")
    [void]$sb.AppendLine("  <meta charset='utf-8'/>")
    [void]$sb.AppendLine("  <meta name='viewport' content='width=device-width, initial-scale=1'/>")
    [void]$sb.AppendLine("  <title>$(HtmlEncode $Title)</title>")

    [void]$sb.AppendLine("  <!-- Source: Bootstrap 5 (official). CDN via jsDelivr. -->")
    [void]$sb.AppendLine("  <link rel='stylesheet' href='$bootstrapCss' crossorigin='anonymous'>")

    [void]$sb.AppendLine("  <!-- Source: DataTables (official CDN). -->")
    [void]$sb.AppendLine("  <link rel='stylesheet' href='$dtCss' crossorigin='anonymous'>")
    [void]$sb.AppendLine("  <link rel='stylesheet' href='$btnCss' crossorigin='anonymous'>")

    [void]$sb.AppendLine("  <style>$customCss</style>")
    [void]$sb.AppendLine("</head>")
    [void]$sb.AppendLine("<body>")
    [void]$sb.AppendLine("<div class='container-fluid p-4'>")

    # Header (use HTML entity for bullet to avoid encoding artifacts)
    [void]$sb.AppendLine("<div class='d-flex align-items-end justify-content-between flex-wrap gap-2'>")
    [void]$sb.AppendLine("  <div>")
    [void]$sb.AppendLine("    <h2 class='mb-1'>$(HtmlEncode $Title)</h2>")
    [void]$sb.AppendLine("    <div class='small-muted'>Generated: $(HtmlEncode $generatedLocal) (local) &bull; Rows: $total &bull; Errors: $totalErrors</div>")
    [void]$sb.AppendLine("  </div>")
    [void]$sb.AppendLine("  <div class='d-flex gap-2'>")
    [void]$sb.AppendLine("    <button id='themeToggle' class='btn btn-outline-secondary btn-sm'>Toggle theme</button>")
    [void]$sb.AppendLine("  </div>")
    [void]$sb.AppendLine("</div>")

    # Summary cards
    [void]$sb.AppendLine("<div class='row g-3 mt-2'>")
    [void]$sb.AppendLine("  <div class='col-12 col-md-3'><div class='card p-3'><div class='small-muted'>Total resources</div><div class='fs-4 fw-bold'>$total</div></div></div>")
    [void]$sb.AppendLine("  <div class='col-12 col-md-3'><div class='card p-3'><div class='small-muted'>Total errors</div><div class='fs-4 fw-bold'>$totalErrors</div></div></div>")
    foreach ($pc in $planCounts) {
        $name = [string]$pc.Name
        $count = $pc.Count
        $badgeClass = switch ($name) { "P2"{"bg-success"} "P1"{"bg-warning text-dark"} "Free"{"bg-secondary"} default{"bg-danger"} }
        [void]$sb.AppendLine("  <div class='col-12 col-md-3'><div class='card p-3'><div class='small-muted'>EffectivePlan</div><div class='fs-4 fw-bold'>$(HtmlEncode $name) <span class='badge $badgeClass badge-plan'>$count</span></div></div></div>")
    }
    [void]$sb.AppendLine("</div>")

    # Tabs: button is ONLY the subscription id text, external link is separate
    [void]$sb.AppendLine("<ul class='nav nav-tabs mt-4' id='subTabs' role='tablist'>")
    for ($i = 0; $i -lt $subs.Count; $i++) {
        $subId = [string]$subs[$i].Name
        $safe = SafeId $subId
        $active = if ($i -eq 0) { "active" } else { "" }
        $selected = if ($i -eq 0) { "true" } else { "false" }
        $subUrl = PortalSubscriptionUrl $subId

        [void]$sb.AppendLine("<li class='nav-item d-flex align-items-center' role='presentation'>")
        [void]$sb.AppendLine("  <button class='nav-link $active' id='tab-$safe' data-bs-toggle='tab' data-bs-target='#pane-$safe' type='button' role='tab' aria-controls='pane-$safe' aria-selected='$selected'>$(HtmlEncode $subId)</button>")
        if ($subUrl) {
            [void]$sb.AppendLine("  <a class='tab-external' href='$subUrl' target='_blank' rel='noopener' title='Open subscription in Azure portal'>&#8599;</a>")
        }
        [void]$sb.AppendLine("</li>")
    }
    [void]$sb.AppendLine("</ul>")

    [void]$sb.AppendLine("<div class='tab-content' id='subTabsContent'>")

    for ($i = 0; $i -lt $subs.Count; $i++) {
        $subId = [string]$subs[$i].Name
        $safe = SafeId $subId
        $activePane = if ($i -eq 0) { "show active" } else { "" }

        $rows = $subs[$i].Group | Sort-Object ResourceType, ResourceName
        $tableId = "tbl_$safe"

        [void]$sb.AppendLine("<div class='tab-pane fade $activePane' id='pane-$safe' role='tabpanel' aria-labelledby='tab-$safe'>")
        [void]$sb.AppendLine("  <div class='table-responsive'>")
        [void]$sb.AppendLine("    <table id='$tableId' class='table table-striped table-hover align-middle dt-table' style='width:100%'>")
        [void]$sb.AppendLine("      <thead><tr>")
        [void]$sb.AppendLine("        <th>EffectivePlan</th><th>ResourceName</th><th>Type</th><th>RG</th><th>Location</th><th>PricingTier</th><th>SubPlan</th><th>Inherited</th><th>ResourceId</th><th>SourceScope</th><th>Error</th>")
        [void]$sb.AppendLine("      </tr></thead><tbody>")

        foreach ($r in $rows) {
            $plan = [string]$r.EffectivePlan
            $badgeClass = switch ($plan) { "P2"{"bg-success"} "P1"{"bg-warning text-dark"} "Free"{"bg-secondary"} default{"bg-danger"} }

            $resourceId = [string]$r.ResourceId
            $resourceUrl = PortalResourceUrl $resourceId
            $resourceCell = if ($resourceUrl) {
                "<a href='$resourceUrl' target='_blank' rel='noopener' class='mono'>$(HtmlEncode $resourceId)</a> " +
                "<button class='btn btn-sm btn-outline-secondary ms-2 copy-btn' data-copy='$(HtmlEncode $resourceId)'>Copy</button>"
            } else {
                "<span class='mono'>$(HtmlEncode $resourceId)</span>"
            }

            $err = [string]$r.Error
            $rowClass = if ($err) { "row-error" } else { "" }

            [void]$sb.AppendLine("      <tr class='$rowClass'>")
            [void]$sb.AppendLine("        <td><span class='badge $badgeClass badge-plan'>$(HtmlEncode $plan)</span></td>")
            [void]$sb.AppendLine("        <td>$(HtmlEncode ([string]$r.ResourceName))</td>")
            [void]$sb.AppendLine("        <td>$(HtmlEncode ([string]$r.ResourceType))</td>")
            [void]$sb.AppendLine("        <td>$(HtmlEncode ([string]$r.ResourceGroup))</td>")
            [void]$sb.AppendLine("        <td>$(HtmlEncode ([string]$r.Location))</td>")
            [void]$sb.AppendLine("        <td>$(HtmlEncode ([string]$r.PricingTier))</td>")
            [void]$sb.AppendLine("        <td>$(HtmlEncode ([string]$r.SubPlan))</td>")
            [void]$sb.AppendLine("        <td>$(HtmlEncode ([string]$r.Inherited))</td>")
            [void]$sb.AppendLine("        <td>$resourceCell</td>")
            [void]$sb.AppendLine("        <td>$(HtmlEncode ([string]$r.SourceScope))</td>")
            [void]$sb.AppendLine("        <td>$(HtmlEncode $err)</td>")
            [void]$sb.AppendLine("      </tr>")
        }

        [void]$sb.AppendLine("      </tbody></table>")
        [void]$sb.AppendLine("  </div>")
        [void]$sb.AppendLine("</div>")
    }

    [void]$sb.AppendLine("</div>") # tab-content
    [void]$sb.AppendLine("</div>") # container

    # Proper script tags + correct load order
    [void]$sb.AppendLine("<!-- Source: jQuery (required by DataTables). -->")
    [void]$sb.AppendLine("<script src='$jqueryJs' crossorigin='anonymous'></script>")

    [void]$sb.AppendLine("<!-- Source: Bootstrap 5 (official) via jsDelivr. -->")
    [void]$sb.AppendLine("<script src='$bootstrapJs' crossorigin='anonymous'></script>")

    [void]$sb.AppendLine("<!-- Source: DataTables (official CDN). -->")
    [void]$sb.AppendLine("<script src='$dtJs' crossorigin='anonymous'></script>")
    [void]$sb.AppendLine("<script src='$dtBsJs' crossorigin='anonymous'></script>")

    [void]$sb.AppendLine("<!-- Source: JSZip (required for DataTables Excel export). -->")
    [void]$sb.AppendLine("<script src='$jszipJs' crossorigin='anonymous'></script>")

    [void]$sb.AppendLine("<!-- Source: DataTables Buttons extension (official CDN). -->")
    [void]$sb.AppendLine("<script src='$btnJs' crossorigin='anonymous'></script>")
    [void]$sb.AppendLine("<script src='$btnBsJs' crossorigin='anonymous'></script>")
    [void]$sb.AppendLine("<script src='$btnHtml5Js' crossorigin='anonymous'></script>")
    [void]$sb.AppendLine("<script src='$btnPrintJs' crossorigin='anonymous'></script>")
    [void]$sb.AppendLine("<script src='$btnColVisJs' crossorigin='anonymous'></script>")

    [void]$sb.AppendLine("<script>$initJs</script>")
    [void]$sb.AppendLine("</body></html>")

    $sb.ToString() | Out-File -FilePath $OutHtml -Encoding UTF8
}

# ---------------- MAIN ----------------

Write-Host "Authenticating..."
$null = Connect-AzAccount -ErrorAction Stop

$token = Get-ArmToken

Write-Host "Inventorying compute resources (VMs + Arc machines)..."
$compute = Get-ComputeInventory -SubscriptionId $SubscriptionId -ScopeMode $ScopeMode -PageSize $PageSize

Write-Host ("Found {0} compute resources." -f $compute.Count)

$report = New-Object System.Collections.Generic.List[object]

for ($i = 0; $i -lt $compute.Count; $i++) {
    $r = $compute[$i]
    #$percent = [int](($i / [Mathrite-Progress -Activity "Querying Defender pricing per resource" -Status "$($i+1)/$($compute.Count) $($r.name)" -PercentComplete $percent

    $resourceId = [string]$r.id
    $subId = [string]$r.subscriptionId
    $name = [string]$r.name

    # Resource-scope GET for VirtualMachines plan
    $resourcePricingUri = "https://management.azure.com{0}/providers/Microsoft.Security/pricings/VirtualMachines?api-version=2024-01-01" -f $resourceId

    # Subscription-scope fallback
    $subPricingUri = "https://management.azure.com/subscriptions/{0}/providers/Microsoft.Security/pricings/VirtualMachines?api-version=2024-01-01" -f $subId

    $pricing = $null
    $sourceScope = "Resource"

    try {
        $pricing = Invoke-ArmGetWithRetry -Uri $resourcePricingUri -Token $token -MaxRetry $MaxRetry
    }
    catch {
        # Fallback to subscription pricing if resource pricing not available
        $sourceScope = "SubscriptionFallback"
        try {
            $pricing = Invoke-ArmGetWithRetry -Uri $subPricingUri -Token $token -MaxRetry $MaxRetry
        }
        catch {
            # If both calls fail, capture error and keep going
            $report.Add([pscustomobject]@{
                TimestampUtc     = (Get-Date).ToUniversalTime().ToString("s") + "Z"
                SubscriptionId   = $subId
                ResourceGroup    = [string]$r.resourceGroup
                ResourceName     = [string]$r.name
                ResourceType     = [string]$r.type
                Location         = [string]$r.location
                ResourceId       = $resourceId
                PricingTier      = $null
                SubPlan          = $null
                EffectivePlan    = "Unknown"
                Inherited        = $null
                InheritedFrom    = $null
                SourceScope      = $sourceScope
                Error            = ($_.Exception.Message)
            })
            continue
        }
    }

    $tier = $null
    $subPlan = $null
    $inherited = $null
    $inheritedFrom = $null

    if ($pricing -and $pricing.properties) {
        $tier = [string]$pricing.properties.pricingTier
        $subPlan = [string]$pricing.properties.subPlan
        $inherited = [string]$pricing.properties.inherited
        $inheritedFrom = [string]$pricing.properties.inheritedFrom
    }

    # Normalize EffectivePlan for easy Excel filtering
    $effectivePlan =
        if ($tier -ne "Standard") { "Free" }
        elseif ($subPlan -eq "P2") { "P2" }
        elseif ($subPlan -eq "P1" -or [string]::IsNullOrWhiteSpace($subPlan)) { "P1" }
        else { $subPlan }

    $report.Add([pscustomobject]@{
        TimestampUtc     = (Get-Date).ToUniversalTime().ToString("s") + "Z"
        SubscriptionId   = $subId
        ResourceGroup    = [string]$r.resourceGroup
        ResourceName     = [string]$r.name
        ResourceType     = [string]$r.type
        Location         = [string]$r.location
        ResourceId       = $resourceId
        PricingTier      = $tier
        SubPlan          = $subPlan
        EffectivePlan    = $effectivePlan
        Inherited        = $inherited
        InheritedFrom    = $inheritedFrom
        SourceScope      = $sourceScope
        Error            = $null
    })
}

Write-Progress -Activity "Querying Defender pricing per resource" -Completed

Write-Host "Exporting CSV to: $OutCsv"
$report | Sort-Object SubscriptionId, ResourceType, ResourceName |
    Export-Csv -Path $OutCsv -NoTypeInformation -Encoding UTF8

Write-Host "Exporting HTML to: $OutHtml"
Export-DefenderServersPricingHtml -Report $report -OutHtml $OutHtml
Write-Host "Done. HTML exported: $OutHtml"

Write-Host "Done. Rows exported: $($report.Count)"


