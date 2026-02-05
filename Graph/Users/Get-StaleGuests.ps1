<#
.SYNOPSIS
  Reports inactive Entra guest accounts (90–179 days and >=180 days) and emails CSVs for review.

.REQUIREMENTS
  Modules in Automation Account:
    - Microsoft.Graph.Authentication
    - Microsoft.Graph.Users
    - Microsoft.Graph.Users.Actions

  Graph permissions (Application):
    - User.Read.All (or Directory.Read.All)
    - AuditLog.Read.All (needed for signInActivity)
    - Mail.Send (to email attachments) (https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.users.actions/send-mgusermail?view=graph-powershell-1.0)

.NOTES
  Uses signInActivity.lastSignInDateTime for "true activity" (https://learn.microsoft.com/en-us/graph/api/resources/signinactivity?view=graph-rest-1.0)
  If lastSignInDateTime is null (never signed in / not backfilled), uses CreatedDateTime as baseline.
#>

    $InactiveDays90  = 90
    $InactiveDays180 = 180

    # Sender mailbox (UPN) used to send the email (shared mailbox/service account recommended)
    $FromUserId = "name@domain.com"

    # Where to send the reports
    $recipientAddr = "name@domain.com"

    # Subject prefix for easy mail rules
    $SubjectPrefix = "[Entra] Inactive Guest Accounts"

    # Set to $false if you do NOT want a sent item
    $SaveToSentItems = $true

function Convert-FileToGraphAttachment {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [string] $ContentType = "text/csv"
    )

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    @{
        "@odata.type" = "#microsoft.graph.fileAttachment"
        name          = [System.IO.Path]::GetFileName($Path)
        contentType   = $ContentType
        contentBytes  = [System.Convert]::ToBase64String($bytes)
    }
}

try {
    # 1) Connect to Graph using Managed Identity
    Connect-MgGraph -Identity | Out-Null

    # 2) Thresholds (UTC for consistency with Graph timestamps)
    $nowUtc   = (Get-Date).ToUniversalTime()
    $cut90Utc = $nowUtc.AddDays(-1 * $InactiveDays90)
    $cut180Utc= $nowUtc.AddDays(-1 * $InactiveDays180)

    # 3) Query minimal fields for guest users 
    # signInActivity holds lastSignInDateTime [1](https://learn.microsoft.com/en-us/graph/api/resources/signinactivity?view=graph-rest-1.0)
    $selectProps = @(
        "id",
        "displayName",
        "userPrincipalName",
        "mail",
        "accountEnabled",
        "createdDateTime",
        "externalUserState",
        "signInActivity"
    )

    $guests = Get-MgUser `
        -Filter "userType eq 'Guest'" `
        -All `
        -Property $selectProps `
        -ConsistencyLevel eventual

    # 4) Transform into a compact reporting object
    $report = foreach ($u in $guests) {

        $createdUtc = if ($u.CreatedDateTime) { ([datetime]$u.CreatedDateTime).ToUniversalTime() } else { $null }

        # Prefer lastSignInDateTime for true access [1](https://learn.microsoft.com/en-us/graph/api/resources/signinactivity?view=graph-rest-1.0)
        $lastSuccessUtc = $null
        if ($u.SignInActivity -and $u.SignInActivity.lastSignInDateTime) {
            $lastSuccessUtc = ([datetime]$u.SignInActivity.lastSignInDateTime).ToUniversalTime()
        }

        $basis = if ($lastSuccessUtc) { "LastSuccessfulSignIn" } else { "CreatedDateTime (no successful sign-in)" }
        $baselineUtc = if ($lastSuccessUtc) { $lastSuccessUtc } else { $createdUtc }

        # If both are null, baseline is unknown -> treat as very old (force review) with a large number
        $inactiveDays = if ($baselineUtc) {
            [math]::Floor(($nowUtc - $baselineUtc).TotalDays)
        } else {
            99999
        }

        [pscustomobject]@{
            DisplayName                 = $u.DisplayName
            UserPrincipalName           = $u.UserPrincipalName
            Mail                        = $u.Mail
            AccountEnabled              = $u.AccountEnabled
            ExternalUserState           = $u.ExternalUserState
            CreatedDateTimeUtc          = if ($createdUtc) { $createdUtc.ToString("yyyy-MM-ddTHH:mm:ssZ") } else { "" }
            LastSuccessfulSignInUtc     = if ($lastSuccessUtc) { $lastSuccessUtc.ToString("yyyy-MM-ddTHH:mm:ssZ") } else { "" }
            InactivityBasis             = $basis
            InactiveDays                = $inactiveDays
        }
    }

    # 5) Bucket into two reports:
    #    - 90–179 days (review)
    #    - >= 180 days (more severe)
    $inactive180 = $report | Where-Object { $_.InactiveDays -ge $InactiveDays180 } | Sort-Object InactiveDays -Descending
   
    $inactive90  = $report | Where-Object { $_.InactiveDays -ge $InactiveDays90 -and $_.InactiveDays -lt $InactiveDays180 } | Sort-Object InactiveDays -Descending

    # 6) Export CSVs (local temp works in runbook sandbox)
    $dateTag = $nowUtc.ToString("yyyyMMdd-HHmmss")
    $outDir  = $env:TEMP
    if (-not (Test-Path $outDir)) { $outDir = "." }

    $csv90Path  = Join-Path $outDir "InactiveGuests_90to179days_$dateTag.csv"
    $csv180Path = Join-Path $outDir "InactiveGuests_180plusdays_$dateTag.csv"

    $inactive90  | Export-Csv -Path $csv90Path  -NoTypeInformation -Encoding UTF8
    $inactive180 | Export-Csv -Path $csv180Path -NoTypeInformation -Encoding UTF8

    # 7) Email the CSVs as attachments using Send-MgUserMail [2](https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.users.actions/send-mgusermail?view=graph-powershell-1.0)
    $attachments = @()
    if (Test-Path $csv90Path)  { $attachments += Convert-FileToGraphAttachment -Path $csv90Path  }
    if (Test-Path $csv180Path) { $attachments += Convert-FileToGraphAttachment -Path $csv180Path }

    $subject = "$SubjectPrefix - 90/180 Day Inactivity - $($nowUtc.ToString('yyyy-MM-dd'))"

    $bodyHtml = @"
<p><b>Inactive Guest Accounts Report</b></p>
<ul>
  <li>Generated (UTC): <b>$($nowUtc.ToString("yyyy-MM-dd HH:mm:ss"))</b></li>
  <li>Guests inactive 90–179 days: <b>$($inactive90.Count)</b></li>
  <li>Guests inactive ≥180 days: <b>$($inactive180.Count)</b></li>
</ul>
<p><i>Inactivity is based on <b>LastSuccessfulSignIn</b> when available; otherwise <b>CreatedDateTime</b> is used (no successful sign-in recorded).</i></p>
"@

    $mailParams = @{
        message = @{
            subject = $subject
            body    = @{
                contentType = "HTML"
                content     = $bodyHtml
            }
            toRecipients = @(
			@{
				emailAddress = @{
					address = $recipientAddr
				}
			}
		)
            attachments  = $attachments
        }
        saveToSentItems = $SaveToSentItems
    }

    Send-MgUserMail -UserId $FromUserId -BodyParameter $mailParams | Out-Null  # [2](https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.users.actions/send-mgusermail?view=graph-powershell-1.0)

    Write-Output "Success. 90–179 days: $($inactive90.Count); >=180 days: $($inactive180.Count). CSVs emailed to: $($ToRecipients -join ', ')"
}
catch {
    Write-Error "Runbook failed: $($_.Exception.Message)"
    throw
}
finally {
    Disconnect-MgGraph | Out-Null
}
