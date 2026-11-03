<#
.SYNOPSIS
    Step 8 (run on the CLIENT VM as local admin): join the PC to the domain.

.DESCRIPTION
    Checks the client got a DHCP address and DNS from DC01, confirms the
    domain can be found, renames the PC and joins it to lab.local. The
    computer object lands in OU=Workstations (set by step 4). Restarts.

.EXAMPLE
    .\08-Join-Domain.ps1
#>
[CmdletBinding()]
param(
    [string]$DomainName = 'lab.local',
    [string]$NewName    = 'CL01'
)

Write-Host 'Current IP configuration:' -ForegroundColor Cyan
Get-NetIPConfiguration | Where-Object { $_.IPv4Address } | Format-Table InterfaceAlias, IPv4Address, DNSServer -AutoSize

Write-Host "Checking that $DomainName can be found in DNS..." -ForegroundColor Cyan
try {
    $dc = Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.$DomainName" -Type SRV -ErrorAction Stop | Where-Object Type -eq 'SRV'
    Write-Host "Found domain controller: $($dc.NameTarget)" -ForegroundColor Green
}
catch {
    throw "Cannot find $DomainName. Check the VM is on the lab network, has a 192.168.50.x address, and DNS is 192.168.50.10 (ipconfig /all)."
}

$cred = Get-Credential -Message "Domain admin to join $DomainName (e.g. LAB\Administrator)"
if ($env:COMPUTERNAME -ne $NewName) {
    Add-Computer -DomainName $DomainName -NewName $NewName -Credential $cred -Restart -Force
}
else {
    Add-Computer -DomainName $DomainName -Credential $cred -Restart -Force
}
