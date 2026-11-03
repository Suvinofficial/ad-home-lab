<#
.SYNOPSIS
    Step 7 (run on DC01): create department file shares with NTFS permissions
    and a logon script that maps drives.

.DESCRIPTION
    For each department a folder C:\Shares\<Dept> is shared as \\DC01\<Dept>$
    (hidden share). Permissions follow the usual best practice:
      - Share permission: Authenticated Users = Change
      - NTFS: inheritance removed; Administrators and SYSTEM = Full Control;
        GG_<Dept> = Modify. Other departments cannot open the folder.
    A shared "Public" folder is readable by all domain users.

    A logon script (MapDrives.bat) is copied to NETLOGON and assigned to every
    user, mapping P: to Public and S: to their department share.

    In production you would put shares on a file server, not a domain
    controller. Using DC01 keeps the lab to two VMs.

.EXAMPLE
    .\07-Create-FileShares.ps1
#>
[CmdletBinding()]
param(
    [string]$ShareRoot   = 'C:\Shares',
    [string]$CompanyOU   = 'LAB Company',
    [string[]]$Departments = @('Admin', 'IT', 'Finance', 'HR', 'Sales')
)

Import-Module ActiveDirectory
$domain  = Get-ADDomain
$netbios = $domain.NetBIOSName
$usersOU = "OU=Users,OU=$CompanyOU,$($domain.DistinguishedName)"

function New-SecuredShare {
    param([string]$Name, [string]$GroupName, [string]$Rights)
    $path = Join-Path $ShareRoot $Name
    if (-not (Test-Path $path)) { New-Item -Path $path -ItemType Directory -Force | Out-Null }

    # NTFS: remove inherited permissions, then grant explicitly
    icacls $path /inheritance:r /grant:r 'Administrators:(OI)(CI)F' 'SYSTEM:(OI)(CI)F' "${netbios}\${GroupName}:(OI)(CI)$Rights" | Out-Null

    $shareName = if ($Name -eq 'Public') { 'Public' } else { "$Name$" }
    if (-not (Get-SmbShare -Name $shareName -ErrorAction SilentlyContinue)) {
        New-SmbShare -Name $shareName -Path $path -ChangeAccess 'Authenticated Users' -FullAccess 'Administrators' `
            -Description "$Name share" | Out-Null
    }
    Write-Host ("Share \\{0}\{1} -> {2}  ({3}: {4})" -f $env:COMPUTERNAME, $shareName, $path, $GroupName, $Rights) -ForegroundColor Green
}

New-Item -Path $ShareRoot -ItemType Directory -Force | Out-Null
foreach ($dept in $Departments) { New-SecuredShare -Name $dept -GroupName "GG_$dept" -Rights 'M' }
New-SecuredShare -Name 'Public' -GroupName 'Domain Users' -Rights 'RX'

# --- Logon script ------------------------------------------------------------
$netlogon = "C:\Windows\SYSVOL\sysvol\$($domain.DNSRoot)\scripts"
$bat = @"
@echo off
rem LAB Company drive mapping - assigned by 07-Create-FileShares.ps1
net use P: /delete /y >nul 2>&1
net use S: /delete /y >nul 2>&1
net use P: \\$env:COMPUTERNAME\Public /persistent:no
"@
foreach ($dept in $Departments) {
    $bat += "`r`nwhoami /groups | find /i ""\GG_$dept "" >nul && net use S: \\$env:COMPUTERNAME\$dept$ /persistent:no"
}
Set-Content -Path (Join-Path $netlogon 'MapDrives.bat') -Value $bat -Encoding ASCII
Write-Host "Logon script written to $netlogon\MapDrives.bat" -ForegroundColor Green

Get-ADUser -Filter * -SearchBase $usersOU | Set-ADUser -ScriptPath 'MapDrives.bat'
Write-Host 'Logon script assigned to all users in the Users OU.' -ForegroundColor Green
Get-SmbShare | Where-Object Path -like "$ShareRoot*" | Format-Table Name, Path, Description -AutoSize
