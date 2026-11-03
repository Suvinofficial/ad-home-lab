<#
.SYNOPSIS
    Step 6 (run on DC01): set the domain password policy and create Group Policies.

.DESCRIPTION
    Configures security and user-environment policies a typical company uses:

      Domain password & lockout policy
        - minimum 10 characters, complexity on, 90-day maximum age,
          24 remembered passwords
        - lock the account for 15 minutes after 5 wrong passwords

      GPO "LAB - Screen Lock" (all staff)
        - password-protected screen saver after 10 minutes

      GPO "LAB - Restrict Control Panel" (Finance, HR, Sales, Admin; not IT)
        - blocks Control Panel and Settings for non-IT staff

      GPO "LAB - Logon Banner" (all workstations)
        - shows an authorised-use notice before sign-in

    Safe to run again: existing GPOs are reused and settings re-applied.

.EXAMPLE
    .\06-Configure-GPOs.ps1
#>
[CmdletBinding()]
param([string]$CompanyOU = 'LAB Company')

Import-Module ActiveDirectory, GroupPolicy
$domain   = Get-ADDomain
$company  = "OU=$CompanyOU,$($domain.DistinguishedName)"
$usersOU  = "OU=Users,$company"
$wksOU    = "OU=Workstations,OU=Computers,$company"

# --- Domain password and lockout policy ------------------------------------
Set-ADDefaultDomainPasswordPolicy -Identity $domain.DNSRoot `
    -MinPasswordLength 10 -ComplexityEnabled $true -PasswordHistoryCount 24 `
    -MaxPasswordAge (New-TimeSpan -Days 90) -MinPasswordAge (New-TimeSpan -Days 1) `
    -LockoutThreshold 5 -LockoutDuration (New-TimeSpan -Minutes 15) `
    -LockoutObservationWindow (New-TimeSpan -Minutes 15)
Write-Host 'Domain password and lockout policy set.' -ForegroundColor Green

function Get-OrCreateGPO {
    param([string]$Name, [string]$Comment)
    $gpo = Get-GPO -Name $Name -ErrorAction SilentlyContinue
    if (-not $gpo) { $gpo = New-GPO -Name $Name -Comment $Comment; Write-Host "Created GPO: $Name" -ForegroundColor Green }
    return $gpo
}

function Add-GPLinkIfMissing {
    param([string]$GpoName, [string]$Target)
    $linked = (Get-GPInheritance -Target $Target).GpoLinks | Where-Object DisplayName -eq $GpoName
    if (-not $linked) { New-GPLink -Name $GpoName -Target $Target | Out-Null; Write-Host "  linked to $Target" }
}

# --- GPO: Screen lock (user settings) --------------------------------------
$name = 'LAB - Screen Lock'
Get-OrCreateGPO -Name $name -Comment 'Password-protected screen saver after 10 minutes' | Out-Null
$key = 'HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop'
Set-GPRegistryValue -Name $name -Key $key -ValueName 'ScreenSaveActive'    -Type String -Value '1' | Out-Null
Set-GPRegistryValue -Name $name -Key $key -ValueName 'ScreenSaverIsSecure' -Type String -Value '1' | Out-Null
Set-GPRegistryValue -Name $name -Key $key -ValueName 'ScreenSaveTimeOut'   -Type String -Value '600' | Out-Null
Set-GPRegistryValue -Name $name -Key $key -ValueName 'SCRNSAVE.EXE'        -Type String -Value 'scrnsave.scr' | Out-Null
Add-GPLinkIfMissing -GpoName $name -Target $usersOU

# --- GPO: Restrict Control Panel for non-IT staff ---------------------------
$name = 'LAB - Restrict Control Panel'
Get-OrCreateGPO -Name $name -Comment 'Blocks Control Panel and Settings for non-IT users' | Out-Null
Set-GPRegistryValue -Name $name -Key 'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' `
    -ValueName 'NoControlPanel' -Type DWord -Value 1 | Out-Null
foreach ($dept in 'Admin', 'Finance', 'HR', 'Sales') {
    Add-GPLinkIfMissing -GpoName $name -Target "OU=$dept,$usersOU"
}

# --- GPO: Logon banner (computer settings) ----------------------------------
$name = 'LAB - Logon Banner'
Get-OrCreateGPO -Name $name -Comment 'Authorised-use notice before sign-in' | Out-Null
$key = 'HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System'
Set-GPRegistryValue -Name $name -Key $key -ValueName 'legalnoticecaption' -Type String -Value 'LAB Company - Authorised Use Only' | Out-Null
Set-GPRegistryValue -Name $name -Key $key -ValueName 'legalnoticetext' -Type String `
    -Value 'This computer is for authorised LAB Company users only. Activity may be monitored. Contact IT Support for help.' | Out-Null
Add-GPLinkIfMissing -GpoName $name -Target $wksOU

Write-Host "`nGroup Policy objects:" -ForegroundColor Cyan
Get-GPO -All | Where-Object DisplayName -like 'LAB - *' | Format-Table DisplayName, GpoStatus, ModificationTime -AutoSize
Write-Host 'On a client, run  gpupdate /force  then  gpresult /r  to confirm the policies apply.'
