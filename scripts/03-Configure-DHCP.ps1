<#
.SYNOPSIS
    Step 3 (run on DC01 as LAB\Administrator): install and authorise DHCP.

.DESCRIPTION
    Installs the DHCP Server role, authorises it in Active Directory, creates
    the lab scope (192.168.50.100-200), and sets the DNS server and domain
    name options so clients find the domain automatically.

.EXAMPLE
    .\03-Configure-DHCP.ps1
#>
[CmdletBinding()]
param(
    [string]$DCIPAddress = '192.168.50.10',
    [string]$ScopeId     = '192.168.50.0',
    [string]$StartRange  = '192.168.50.100',
    [string]$EndRange    = '192.168.50.200',
    [string]$SubnetMask  = '255.255.255.0'
)

$domain = (Get-ADDomain).DNSRoot
$fqdn   = "$env:COMPUTERNAME.$domain"

Write-Host 'Installing the DHCP Server role...' -ForegroundColor Cyan
Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null

# Create the local DHCP security groups and authorise the server in AD
netsh dhcp add securitygroups | Out-Null
Restart-Service -Name DHCPServer
if (-not (Get-DhcpServerInDC | Where-Object DnsName -eq $fqdn)) {
    Add-DhcpServerInDC -DnsName $fqdn -IPAddress $DCIPAddress
}

# Tell Server Manager the post-install configuration is complete
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12' -Name ConfigurationState -Value 2

if (-not (Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Where-Object { $_.ScopeId.ToString() -eq $ScopeId })) {
    Add-DhcpServerv4Scope -Name 'LAB Clients' -StartRange $StartRange -EndRange $EndRange `
        -SubnetMask $SubnetMask -LeaseDuration (New-TimeSpan -Days 8) -State Active
}

# Option 6 (DNS servers) and 15 (DNS domain name)
Set-DhcpServerv4OptionValue -ScopeId $ScopeId -DnsServer $DCIPAddress -DnsDomain $domain

Write-Host 'DHCP is ready:' -ForegroundColor Green
Get-DhcpServerv4Scope | Format-Table ScopeId, Name, StartRange, EndRange, State -AutoSize
Get-DhcpServerv4OptionValue -ScopeId $ScopeId | Format-Table OptionId, Name, Value -AutoSize
