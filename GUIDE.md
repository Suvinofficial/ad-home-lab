# Active Directory Home Lab: Step-by-Step Guide

Build a small company network on your own laptop: a Windows Server domain controller and a Windows client, with users, groups, Group Policy, DHCP and file shares. Everything here is free.

**Time:** about 4–6 hours, spread over 2–3 sessions.
**Cost:** free (evaluation versions of Windows).

---

## 0. What you need

| Item | Notes |
|---|---|
| Laptop/PC | 16 GB RAM is comfortable. 8 GB works if you give the VMs less memory and close other apps. About 100 GB free disk space. Virtualisation (VT-x/AMD-V) on in BIOS. |
| [Oracle VirtualBox](https://www.virtualbox.org/wiki/Downloads) | Free. Works on Windows Home. (Hyper-V is fine too if you have Windows Pro.) |
| Windows Server evaluation ISO | Free 180-day trial from the [Microsoft Evaluation Center](https://www.microsoft.com/en-us/evalcenter). Choose Windows Server 2022 or 2025, ISO, English 64-bit. |
| Windows 11 (or 10) Enterprise evaluation ISO | Free 90-day trial from the same site. |

> Take screenshots as you go (Win + Shift + S). The list of screenshots for GitHub is at the end.

---

## 1. Create the lab network design

```
            VirtualBox Internal Network "labnet"  (192.168.50.0/24)
   ┌────────────────────────────┐          ┌──────────────────────────┐
   │ DC01  Windows Server        │          │ CL01  Windows 11 client   │
   │ 192.168.50.10 (static)      │◄────────►│ 192.168.50.100+ (DHCP)    │
   │ AD DS · DNS · DHCP · Shares │          │ joined to lab.local       │
   └────────────────────────────┘          └──────────────────────────┘
```

The lab uses an **internal network only**, so it is isolated from your home network and the internet. That is safe, and it avoids DNS problems.

## 2. Create the server VM (DC01)

1. VirtualBox → **New**. Name `DC01`, select the Windows Server ISO, Type *Microsoft Windows*, Version *Windows 2022 (64-bit)*.
2. Tick **Skip Unattended Installation**.
3. Memory **4096 MB** (or 2048 MB on an 8 GB laptop), 2 CPUs, disk **50 GB**.
4. Before starting: **Settings → Network → Adapter 1 → Attached to: Internal Network**, Name: `labnet`.
5. Start the VM and install Windows Server. Choose **Standard Evaluation (Desktop Experience)**, then **Custom install**. Set a strong local Administrator password.
6. After login: **Devices → Insert Guest Additions CD image**, install it and reboot. This gives you better screen resolution and copy/paste.

## 3. Copy the scripts into the VM

Put the `scripts` folder from this repository into the VM at `C:\Lab\scripts`. Either:
- turn on **Devices → Shared Clipboard → Bidirectional** and **Drag and Drop** and drag the folder in, or
- set up **Devices → Shared Folders**, or build a small ISO of the folder.

Open **PowerShell as Administrator** in the VM and run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
cd C:\Lab\scripts
Get-ChildItem *.ps1 | Unblock-File
```

## 4. Build the domain controller (run on DC01)

| Step | Command | What happens |
|---|---|---|
| 1 | `.\01-Configure-DCNetwork.ps1` | Choose the adapter. Sets static IP 192.168.50.10, DNS to itself, renames the server to DC01. **Restarts.** |
| 2 | `.\02-Install-ADDS.ps1` | Installs AD DS + DNS and creates the forest **lab.local**. Asks for a DSRM password. **Restarts.** |
| — | Log in as **LAB\Administrator** (same password as before) | |
| 3 | `.\03-Configure-DHCP.ps1` | Installs DHCP, authorises it in AD, creates scope .100–.200 with DNS options. |
| 4 | `.\04-Create-OUStructure.ps1` | Builds the OU tree and department groups (GG_Finance, GG_HR …). |
| 5 | `.\05-New-BulkUsers.ps1` | Creates 15 users from `users.csv` with a temporary password. They must change it at first logon. |
| 6 | `.\06-Configure-GPOs.ps1` | Sets the password/lockout policy and creates 3 GPOs. |
| 7 | `.\07-Create-FileShares.ps1` | Creates department shares with NTFS permissions and the drive-mapping logon script. |

Check your work in the GUI too, because interviewers ask about the consoles:
- **Active Directory Users and Computers** (dsa.msc): OUs, users, groups
- **Group Policy Management** (gpmc.msc): GPOs and where they are linked
- **DHCP** (dhcpmgmt.msc): scope, leases
- **DNS** (dnsmgmt.msc): the lab.local zone and the `_msdcs` records

## 5. Create the client VM (CL01)

1. VirtualBox → **New** → `CL01`, Windows 11 ISO, 4096 MB (or 2048 MB), 2 CPUs, 50 GB.
   For Windows 11, VirtualBox 7 adds the TPM/Secure Boot settings automatically.
2. **Network → Internal Network → labnet** (same as DC01).
3. Install Windows. With no internet, choose **"I don't have internet" / Domain join instead** to create a local account.
4. Open PowerShell as Administrator and check `ipconfig /all`. You should have a 192.168.50.1xx address and DNS server 192.168.50.10. That's DHCP working.
5. Copy `08-Join-Domain.ps1` across and run it. Enter **LAB\Administrator** credentials. The PC joins the domain as CL01 and restarts.

## 6. Test everything (this is what proves it works)

Log in on CL01 as a Finance user, e.g. **LAB\meera.krishnan** with the temporary password. You'll be asked to change it.

| Test | How | Expected |
|---|---|---|
| Logon banner | Before sign-in | "LAB Company – Authorised Use Only" notice |
| Group Policy applied | `gpupdate /force` then `gpresult /r` | Screen Lock and Restrict Control Panel listed |
| Control Panel blocked | Open Control Panel | Restriction message |
| Drive mapping | File Explorer | **P:** Public and **S:** Finance |
| Share security | Try `\\DC01\HR$` | Access denied (Meera isn't in HR) |
| IT user not restricted | Log in as **LAB\rahul.pillai** | Control Panel opens; S: is the IT share |

## 7. Practise real helpdesk tickets

Do these on DC01. They're the questions you'll be asked in interviews.

1. **"I forgot my password."** Reset it:
   `Set-ADAccountPassword meera.krishnan -Reset -NewPassword (Read-Host -AsSecureString); Set-ADUser meera.krishnan -ChangePasswordAtLogon $true`
2. **"My account is locked."** Type a wrong password 5 times on CL01, then:
   `Search-ADAccount -LockedOut` → `Unlock-ADAccount meera.krishnan`
3. **New joiner in Sales.** Add a row to `users.csv` and re-run step 5. Existing users are skipped.
4. **Employee moved from Sales to Finance.** Move the user to the Finance OU, swap their group, log off/on, and check that S: changes.
5. **Leaver / stale accounts.** Run `Get-InactiveADUsers.ps1 -Days 0 -WhatIf` from the [PowerShell toolkit](https://github.com/Suvinofficial/sysadmin-powershell-toolkit) and read what it would disable.
6. **"PC can't find the domain."** On CL01 set DNS to 8.8.8.8, try to log in as a new user, see it fail, then fix it (DNS must point to the DC). This is the most common AD fault.

## 8. Screenshots to put on GitHub

Save these in a `screenshots` folder using these names, so they appear in the README:

1. `aduc-ou-structure.png`: Active Directory Users and Computers showing the OU tree and users
2. `gpmc-gpos.png`: Group Policy Management with the 3 GPOs linked
3. `dhcp-leases.png`: DHCP console showing CL01's lease
4. `bulk-users-script.png`: PowerShell output of step 5
5. `client-gpresult.png`: `gpresult /r` on CL01
6. `client-drives.png`: File Explorer on CL01 with P: and S:
7. `access-denied.png`: denied access to another department's share
8. `account-unlock.png`: Search-ADAccount / Unlock-ADAccount

Hide any personal information before uploading.

## Troubleshooting

| Problem | Fix |
|---|---|
| VM won't start, "VT-x is disabled" | Turn on virtualisation in BIOS/UEFI. On Windows, turn off "Memory integrity" if VirtualBox still complains. |
| Client has a 169.254.x.x address | DHCP not reached. Both VMs must be on Internal Network **labnet**, and the DHCP scope must be Active. |
| "An Active Directory domain controller could not be contacted" | Client DNS isn't 192.168.50.10. Run `ipconfig /all` and `ipconfig /renew`. |
| GPO not applying | Check it's linked to the OU where the user/computer actually is. Run `gpupdate /force`, then log off and on. |
| Drive not mapped | Log off/on (logon scripts run at sign-in). Check that the user's **Profile → Logon script** says MapDrives.bat. |
