<#
Project HOME - membongkar semua perubahan setup-backup-target.ps1 di laptop.
DIJALANKAN OLEH KLIEN, sebagai Administrator.

Yang dilakukan:
  - sshd dihentikan; sshd_config dikembalikan ke salinan aslinya.
  - Rule firewall HOME-backup-SSH-In dihapus; rule bawaan OpenSSH-Server-In-TCP dikembalikan
    ke kondisi awal.
  - Akun homebackup dan profilnya dihapus.
  - OpenSSH Server (fitur Windows) di-uninstall kalau SEBELUMNYA memang belum terpasang.
    Kalau terpasang lewat MSI, sshd hanya dinonaktifkan dan diberi petunjuk uninstall lewat Apps.
  - Folder backup C:\HOME-backup TIDAK dihapus, kecuali diberi -RemoveBackupData (akan ditanya dulu).

Cara menjalankan (PowerShell "Run as Administrator"):
  powershell -ExecutionPolicy Bypass -File .\remove-backup-target.ps1
  powershell -ExecutionPolicy Bypass -File .\remove-backup-target.ps1 -RemoveBackupData
#>
[CmdletBinding()]
param(
    [switch]$RemoveBackupData
)

$ErrorActionPreference = 'Stop'

$UserName   = 'homebackup'
$BackupRoot = 'C:\HOME-backup'
$StateDir   = 'C:\ProgramData\HOME-backup-setup'
$StateFile  = Join-Path $StateDir 'state.json'
$SshdConfig = 'C:\ProgramData\ssh\sshd_config'
$FwRuleName = 'HOME-backup-SSH-In'
$FwDefault  = 'OpenSSH-Server-In-TCP'
$InstallFile    = Join-Path $StateDir 'openssh-install.json'
$FwDisabledFile = Join-Path $StateDir 'disabled-firewall-rules.json'

function Get-SshdExe {
    $svc = Get-CimInstance Win32_Service -Filter "Name='sshd'" -ErrorAction SilentlyContinue
    if (-not $svc -or -not $svc.PathName) { return $null }
    if ($svc.PathName -match '^\s*"([^"]+)"') { return $Matches[1] }
    if ($svc.PathName -match '^\s*(\S+\.exe)') { return $Matches[1] }
    return $null
}
function Get-OpenSshCapability {
    try { return (Get-WindowsCapability -Online -Name 'OpenSSH.Server*' -ErrorAction Stop | Select-Object -First 1) }
    catch { return $null }
}

function Step($text) { Write-Host ''; Write-Host "=== $text ===" -ForegroundColor Cyan }
function Info($text) { Write-Host "  $text" }

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'BERHENTI: jalankan PowerShell sebagai Administrator.' -ForegroundColor Red; exit 1
}

if (Test-Path $StateFile) {
    $state = Get-Content $StateFile -Raw | ConvertFrom-Json
    Info "Kondisi awal dari $StateFile (dicatat $($state.created))."
} else {
    Write-Host "PERINGATAN: $StateFile tidak ada. Dianggap semua dibuat oleh setup." -ForegroundColor Yellow
    $state = [pscustomobject]@{ openSshServerWasInstalled = $false; defaultRuleExisted = $false;
        defaultRuleWasEnabled = $false; userExisted = $false; sshdConfigExisted = $false }
}

Step 'sshd dan sshd_config'
if (Get-Service sshd -ErrorAction SilentlyContinue) { Stop-Service sshd -ErrorAction SilentlyContinue }
$orig = Join-Path $StateDir 'sshd_config.orig'
if (Test-Path $orig) {
    Copy-Item $orig $SshdConfig -Force
    Info 'sshd_config dikembalikan ke salinan asli.'
}

Step 'Firewall'
if (Get-NetFirewallRule -Name $FwRuleName -ErrorAction SilentlyContinue) {
    Remove-NetFirewallRule -Name $FwRuleName; Info "Rule $FwRuleName dihapus."
}
# Rule OpenSSH yang dimatikan oleh setup (tercatat) dinyalakan kembali.
if (Test-Path $FwDisabledFile) {
    foreach ($name in @(Get-Content $FwDisabledFile -Raw | ConvertFrom-Json)) {
        if ($name -and (Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue)) {
            Enable-NetFirewallRule -Name $name; Info "Rule $name dinyalakan kembali (dimatikan oleh setup)."
        }
    }
} elseif (Get-NetFirewallRule -Name $FwDefault -ErrorAction SilentlyContinue) {
    if ($state.defaultRuleWasEnabled) { Enable-NetFirewallRule -Name $FwDefault; Info "$FwDefault diaktifkan lagi (seperti semula)." }
    else { Info "$FwDefault dibiarkan nonaktif (semula tidak ada/nonaktif)." }
}

Step "Akun $UserName"
if (-not $state.userExisted) {
    $user = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
    if ($user) {
        $sid = $user.SID.Value
        Get-CimInstance Win32_UserProfile | Where-Object { $_.SID -eq $sid } | Remove-CimInstance
        Remove-LocalUser -Name $UserName
        Info 'Akun dan profil dihapus.'
    }
} else {
    Info 'Akun sudah ada sebelum setup, jadi TIDAK dihapus.'
}

Step 'OpenSSH Server'
$sshdExe = Get-SshdExe
$isMsi = $sshdExe -and -not $sshdExe.StartsWith("$env:SystemRoot\System32", [StringComparison]::OrdinalIgnoreCase)
if ($state.openSshServerWasInstalled) {
    Info 'OpenSSH Server sudah ada sebelum setup; dibiarkan terpasang.'
    Start-Service sshd -ErrorAction SilentlyContinue
} elseif ($isMsi) {
    # MSI (github.com/PowerShell/Win32-OpenSSH) tidak di-uninstall otomatis.
    Set-Service -Name sshd -StartupType Disabled -ErrorAction SilentlyContinue
    Write-Host "  OpenSSH terpasang lewat MSI ($sshdExe). Service sshd sudah dihentikan dan dinonaktifkan." -ForegroundColor Yellow
    Write-Host '  Untuk meng-uninstall: Settings > Apps > Installed apps > cari "OpenSSH" > Uninstall.' -ForegroundColor Yellow
} else {
    $cap = Get-OpenSshCapability
    if ($cap -and $cap.State -eq 'Installed') {
        try {
            Remove-WindowsCapability -Online -Name $cap.Name -ErrorAction Stop | Out-Null
            Info 'OpenSSH Server (fitur Windows) di-uninstall (semula belum terpasang).'
        } catch {
            Set-Service -Name sshd -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Host '  Uninstall otomatis gagal. sshd sudah dinonaktifkan. Uninstall manual:' -ForegroundColor Yellow
            Write-Host '  Settings > System > Optional features > "OpenSSH Server" > Remove.' -ForegroundColor Yellow
        }
    } elseif (Get-Service sshd -ErrorAction SilentlyContinue) {
        Set-Service -Name sshd -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Host '  Status fitur OpenSSH tidak terbaca. sshd sudah dinonaktifkan. Uninstall manual:' -ForegroundColor Yellow
        Write-Host '  Settings > System > Optional features > "OpenSSH Server" > Remove.' -ForegroundColor Yellow
    }
    if (Get-NetFirewallRule -Name $FwDefault -ErrorAction SilentlyContinue) {
        Remove-NetFirewallRule -Name $FwDefault; Info "Rule $FwDefault dihapus."
    }
}

Step "Folder $BackupRoot"
if ($RemoveBackupData -and (Test-Path $BackupRoot)) {
    $answer = Read-Host "Ketik HAPUS untuk menghapus SEMUA isi $BackupRoot (backup tidak bisa dikembalikan)"
    if ($answer -ceq 'HAPUS') { Remove-Item $BackupRoot -Recurse -Force; Info 'Folder backup dihapus.' }
    else { Info 'Dibatalkan; folder backup dibiarkan.' }
} else {
    Info 'Folder backup dibiarkan (pakai -RemoveBackupData untuk menghapusnya).'
}

Remove-Item $StateDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''; Write-Host 'SELESAI.' -ForegroundColor Green
