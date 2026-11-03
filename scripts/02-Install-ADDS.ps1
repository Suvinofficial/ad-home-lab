<#
.SYNOPSIS
    Step 2 (run on DC01): install Active Directory Domain Services and DNS,
    and create a new forest.

.DESCRIPTION
    Installs the AD DS role with management tools, then promotes the server
    to the first domain controller of a new forest with integrated DNS.
    You are asked for the Directory Services Restore Mode (DSRM) password.
    The server restarts automatically when promotion finishes.

.EXAMPLE
    .\02-Install-ADDS.ps1
#>
[CmdletBinding()]
param(
    [string]$DomainName    = 'lab.local',
    [string]$NetBIOSName   = 'LAB'
)

Write-Host 'Installing the AD DS role (a few minutes)...' -ForegroundColor Cyan
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Format-Table Success, RestartNeeded, FeatureResult -AutoSize

$dsrm = Read-Host -AsSecureString 'Enter a DSRM (Directory Services Restore Mode) password. Write it down.'

Import-Module ADDSDeployment

Write-Host "Creating forest '$DomainName'. The server will restart when done." -ForegroundColor Yellow
Install-ADDSForest `
    -DomainName $DomainName `
    -DomainNetbiosName $NetBIOSName `
    -DomainMode 'WinThreshold' `
    -ForestMode 'WinThreshold' `
    -InstallDns `
    -SafeModeAdministratorPassword $dsrm `
    -DatabasePath 'C:\Windows\NTDS' `
    -LogPath 'C:\Windows\NTDS' `
    -SysvolPath 'C:\Windows\SYSVOL' `
    -NoRebootOnCompletion:$false `
    -Force
