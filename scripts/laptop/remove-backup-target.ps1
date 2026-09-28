<#
Project HOME - membongkar semua perubahan setup-backup-target.ps1 di laptop.
DIJALANKAN OLEH KLIEN, sebagai Administrator.

Yang dilakukan:
  - sshd dihentikan; sshd_config dikembalikan ke salinan aslinya.
  - Rule firewall HOME-backup-SSH-In dihapus; rule bawaan OpenSSH-Server-In-TCP dikembalikan
    ke kondisi awal.
  - Akun homebackup dan profilnya dihapus.
  - OpenSSH Server di-uninstall kalau SEBELUMNYA memang belum terpasang.
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
if (Get-NetFirewallRule -Name $FwDefault -ErrorAction SilentlyContinue) {
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
if (-not $state.openSshServerWasInstalled) {
    $cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' | Select-Object -First 1
    if ($cap -and $cap.State -eq 'Installed') {
        Remove-WindowsCapability -Online -Name $cap.Name | Out-Null
        Info 'OpenSSH Server di-uninstall (semula belum terpasang).'
    }
    if (Get-NetFirewallRule -Name $FwDefault -ErrorAction SilentlyContinue) {
        Remove-NetFirewallRule -Name $FwDefault; Info "Rule $FwDefault dihapus."
    }
} else {
    Info 'OpenSSH Server sudah ada sebelum setup; dibiarkan terpasang.'
    Start-Service sshd -ErrorAction SilentlyContinue
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
