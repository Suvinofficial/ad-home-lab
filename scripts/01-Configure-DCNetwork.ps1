<#
.SYNOPSIS
    Step 1 (run on the server VM): rename the server and give it a static IP.

.DESCRIPTION
    A domain controller needs a fixed IP address and must use itself for DNS.
    The script finds the adapter connected to the lab network (the one with
    no internet gateway, or the one you name), sets the IP, and renames the
    computer to DC01. The server restarts at the end.

.EXAMPLE
    .\01-Configure-DCNetwork.ps1 -InterfaceAlias 'Ethernet'
#>
[CmdletBinding()]
param(
    [string]$NewName       = 'DC01',
    [string]$InterfaceAlias,
    [string]$IPAddress     = '192.168.50.10',
    [int]   $PrefixLength  = 24
)

if (-not $InterfaceAlias) {
    Write-Host 'Network adapters on this server:' -ForegroundColor Cyan
    Get-NetAdapter | Format-Table Name, InterfaceDescription, Status, MacAddress -AutoSize
    $InterfaceAlias = Read-Host 'Type the Name of the adapter on the INTERNAL lab network (e.g. Ethernet)'
}

$adapter = Get-NetAdapter -Name $InterfaceAlias -ErrorAction Stop

# Remove any DHCP address, then set the static one (no gateway on the internal network)
Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -Dhcp Disabled
Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $IPAddress -PrefixLength $PrefixLength | Out-Null

# The DC points DNS at itself (and loopback as secondary)
Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $IPAddress, '127.0.0.1'

Write-Host "Static IP $IPAddress/$PrefixLength set on '$InterfaceAlias'." -ForegroundColor Green
Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex

if ($env:COMPUTERNAME -ne $NewName) {
    Write-Host "Renaming computer to $NewName and restarting in 10 seconds..." -ForegroundColor Yellow
    Rename-Computer -NewName $NewName -Force
    Start-Sleep -Seconds 10
    Restart-Computer -Force
}
