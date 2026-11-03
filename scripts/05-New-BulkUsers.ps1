<#
.SYNOPSIS
    Step 5 (run on DC01): create domain users in bulk from a CSV.

.DESCRIPTION
    Reads users.csv (FirstName, LastName, Department, Title) and for each row:
      - builds a username (first.last, trimmed to 20 characters)
      - creates the account in the department OU with name, title,
        department, UPN and a temporary password
      - forces a password change at first logon
      - adds the user to the department group (GG_<Department>)
    Existing users are skipped, so the script is safe to run again.
    Results are written to a CSV log.

.EXAMPLE
    .\05-New-BulkUsers.ps1 -CsvPath .\users.csv
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$CsvPath   = (Join-Path $PSScriptRoot 'users.csv'),
    [string]$CompanyOU = 'LAB Company'
)

Import-Module ActiveDirectory
$domain   = Get-ADDomain
$usersOU  = "OU=Users,OU=$CompanyOU,$($domain.DistinguishedName)"
$tempPass = Read-Host -AsSecureString 'Temporary password for all new users (must meet complexity rules)'

$log = foreach ($row in (Import-Csv -Path $CsvPath)) {
    $first = $row.FirstName.Trim(); $last = $row.LastName.Trim(); $dept = $row.Department.Trim()
    $sam   = ("{0}.{1}" -f $first, $last).ToLower() -replace '[^a-z0-9.]', ''
    if ($sam.Length -gt 20) { $sam = $sam.Substring(0, 20) }
    $upn   = "$sam@$($domain.DNSRoot)"
    $path  = "OU=$dept,$usersOU"

    if (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
        Write-Host "Skipped (exists): $sam" -ForegroundColor DarkGray
        [pscustomobject]@{ User = $sam; Department = $dept; Result = 'Already existed' }
        continue
    }

    if ($PSCmdlet.ShouldProcess($sam, "Create user in $path")) {
        try {
            New-ADUser -Name "$first $last" -GivenName $first -Surname $last -DisplayName "$first $last" `
                -SamAccountName $sam -UserPrincipalName $upn -Path $path `
                -Title $row.Title -Department $dept -Company 'LAB Company' `
                -AccountPassword $tempPass -ChangePasswordAtLogon $true -Enabled $true -ErrorAction Stop

            Add-ADGroupMember -Identity "GG_$dept" -Members $sam -ErrorAction Stop
            Write-Host "Created: $sam ($dept)" -ForegroundColor Green
            [pscustomobject]@{ User = $sam; Department = $dept; Result = 'Created' }
        }
        catch {
            Write-Warning "Failed: $sam - $($_.Exception.Message)"
            [pscustomobject]@{ User = $sam; Department = $dept; Result = "Failed: $($_.Exception.Message)" }
        }
    }
}

$logFile = Join-Path $PSScriptRoot ("UserCreation_{0}.csv" -f (Get-Date -Format 'yyyy-MM-dd_HHmm'))
$log | Export-Csv -Path $logFile -NoTypeInformation -Encoding UTF8
Write-Host "`n$(@($log | Where-Object Result -eq 'Created').Count) users created. Log: $logFile" -ForegroundColor Cyan
