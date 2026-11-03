<#
.SYNOPSIS
    Step 4 (run on DC01): build the OU structure and department security groups.

.DESCRIPTION
    Creates a company OU tree like a real small business:

      LAB Company
      ├── Users        (Admin, IT, Finance, HR, Sales)
      ├── Computers    (Workstations, Servers)
      ├── Groups
      ├── Service Accounts
      └── Disabled Users

    and one global security group per department (GG_Finance, ...).
    Objects are protected from accidental deletion. Safe to run again.

.EXAMPLE
    .\04-Create-OUStructure.ps1
#>
[CmdletBinding()]
param(
    [string]$CompanyOU   = 'LAB Company',
    [string[]]$Departments = @('Admin', 'IT', 'Finance', 'HR', 'Sales')
)

Import-Module ActiveDirectory
$domainDN = (Get-ADDomain).DistinguishedName

function New-OUIfMissing {
    param([string]$Name, [string]$Path)
    $dn = "OU=$Name,$Path"
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'" -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $true
        Write-Host "Created OU: $dn" -ForegroundColor Green
    }
    else { Write-Host "Exists:     $dn" -ForegroundColor DarkGray }
    return $dn
}

$company   = New-OUIfMissing -Name $CompanyOU -Path $domainDN
$usersOU   = New-OUIfMissing -Name 'Users' -Path $company
$compOU    = New-OUIfMissing -Name 'Computers' -Path $company
$groupsOU  = New-OUIfMissing -Name 'Groups' -Path $company
New-OUIfMissing -Name 'Service Accounts' -Path $company | Out-Null
New-OUIfMissing -Name 'Disabled Users' -Path $company | Out-Null
New-OUIfMissing -Name 'Workstations' -Path $compOU | Out-Null
New-OUIfMissing -Name 'Servers' -Path $compOU | Out-Null

foreach ($dept in $Departments) {
    New-OUIfMissing -Name $dept -Path $usersOU | Out-Null
    $groupName = "GG_$dept"
    if (-not (Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $groupName -GroupScope Global -GroupCategory Security -Path $groupsOU `
            -Description "All $dept department staff"
        Write-Host "Created group: $groupName" -ForegroundColor Green
    }
}

# New computers joined to the domain land in Workstations instead of the default container
redircmp "OU=Workstations,$compOU" | Out-Null
Write-Host "`nDefault location for new computers set to OU=Workstations." -ForegroundColor Cyan

Get-ADOrganizationalUnit -Filter * -SearchBase $company | Sort-Object DistinguishedName |
    Format-Table Name, DistinguishedName -AutoSize
