<#
Project HOME - menyiapkan laptop Windows sebagai target backup (SFTP) untuk STB.
Rancangan: docs/rancangan-backup.md, Bagian A. DIJALANKAN OLEH KLIEN, sebagai Administrator.

Yang dilakukan (bisa dijalankan ulang; langkah yang sudah beres dilewati):
  1. OpenSSH Server: kalau service sshd sudah ada (fitur Windows, Settings > Optional features,
     atau MSI resmi Win32-OpenSSH), dipakai apa adanya. Kalau belum, dipasang sebagai fitur
     Windows (butuh internet). Kalau gagal, script berhenti dan menjelaskan jalur lain.
     Service sshd = Manual selama diatur, baru Automatic + dinyalakan di akhir script.
  2. Buat akun lokal standar "homebackup" (anggota Users, BUKAN admin). Password acak panjang
     dibuat di memori, TIDAK ditampilkan dan TIDAK disimpan (akun ini hanya login dengan key).
  3. Buat C:\HOME-backup\restic. Izin: hanya homebackup, SYSTEM, Administrators.
  4. sshd_config: "PasswordAuthentication no" untuk semua akun, dan blok "Match User homebackup"
     (hanya SFTP, terkunci di C:\HOME-backup). File asli dibackup dulu. Divalidasi dengan sshd -t.
  5. Firewall: rule bawaan OpenSSH-Server-In-TCP dimatikan; rule baru hanya mengizinkan
     TCP 22 dari 192.168.137.0/24 (jaringan kabel STB). Di WiFi lain port 22 tertutup.
  6. Public key backup dari STB dipasang di authorized_keys milik homebackup.
Kondisi awal dicatat di C:\ProgramData\HOME-backup-setup\ untuk remove-backup-target.ps1.

Cara menjalankan (PowerShell "Run as Administrator", laptop tersambung internet):
  powershell -ExecutionPolicy Bypass -File .\setup-backup-target.ps1 -StbPublicKey "ssh-ed25519 AAAA... root@stb-backup"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$StbPublicKey
)

$ErrorActionPreference = 'Stop'

$UserName    = 'homebackup'
$BackupRoot  = 'C:\HOME-backup'
$RepoDir     = 'C:\HOME-backup\restic'
$StateDir    = 'C:\ProgramData\HOME-backup-setup'
$StateFile   = Join-Path $StateDir 'state.json'
$InstallFile = Join-Path $StateDir 'openssh-install.json'
$FwDisabledFile = Join-Path $StateDir 'disabled-firewall-rules.json'
$SshdConfig  = 'C:\ProgramData\ssh\sshd_config'
$StbSubnet   = '192.168.137.0/24'
$FwRuleName  = 'HOME-backup-SSH-In'
$FwDefault   = 'OpenSSH-Server-In-TCP'
$MarkerTop   = '# --- Project HOME: global (setup-backup-target.ps1) ---'
$MarkerMatch = '# --- Project HOME: target backup (setup-backup-target.ps1) ---'
$SidSystem   = '*S-1-5-18'
$SidAdmins   = '*S-1-5-32-544'
$SidUsers    = 'S-1-5-32-545'
$Utf8NoBom   = New-Object System.Text.UTF8Encoding($false)

function Step($text) { Write-Host ''; Write-Host "=== $text ===" -ForegroundColor Cyan }
function Info($text) { Write-Host "  $text" }
function Stop-Setup($text) { Write-Host ''; Write-Host "BERHENTI: $text" -ForegroundColor Red; exit 1 }
function Invoke-Icacls {
    & icacls @args | Out-Null
    if ($LASTEXITCODE -ne 0) { Stop-Setup "icacls gagal: icacls $($args -join ' ')" }
}
# Password acak panjang, hanya di memori (SecureString). Tidak pernah ditampilkan/disimpan.
function New-RandomSecurePassword {
    $bytes = New-Object byte[] 48
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $s = ConvertTo-SecureString ([Convert]::ToBase64String($bytes) + 'aA1!') -AsPlainText -Force
    [Array]::Clear($bytes, 0, $bytes.Length)
    return $s
}
# Lokasi sshd.exe diambil dari service (fitur Windows: System32\OpenSSH; MSI: Program Files\OpenSSH).
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
# Keanggotaan grup lewat `net localgroup` (nama grup diterjemahkan dari SID supaya tidak bergantung
# bahasa Windows). Get-LocalGroupMember bisa error kalau grup berisi SID yatim.
function Get-GroupName($sid) {
    $acct = (New-Object System.Security.Principal.SecurityIdentifier($sid)).Translate([System.Security.Principal.NTAccount]).Value
    return $acct.Split('\')[-1]
}
function Test-GroupMember($groupSid, $name) {
    $out = & net localgroup (Get-GroupName $groupSid) 2>$null
    if ($LASTEXITCODE -ne 0) { Stop-Setup "net localgroup gagal membaca grup $groupSid." }
    return [bool]($out | Where-Object { $_.Trim() -ieq $name -or $_.Trim() -like "*\$name" })
}
function Get-UserProfileDir($name) {
    $sid = (Get-LocalUser -Name $name).SID.Value
    $p = Get-CimInstance Win32_UserProfile | Where-Object { $_.SID -eq $sid }
    if ($p) { return $p.LocalPath } else { return $null }
}

# --- Pemeriksaan awal ---------------------------------------------------------
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Stop-Setup 'jalankan PowerShell sebagai Administrator (klik kanan > Run as administrator).'
}
$StbPublicKey = $StbPublicKey.Trim()
if ($StbPublicKey -notmatch '^ssh-ed25519 [A-Za-z0-9+/]+={0,2}( [^\r\n]*)?$') {
    Stop-Setup 'StbPublicKey bukan public key ssh-ed25519 yang valid (satu baris, diawali "ssh-ed25519 ").'
}

New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
if (Test-Path $StateFile) {
    $state = Get-Content $StateFile -Raw | ConvertFrom-Json
    Info "Catatan kondisi awal sudah ada ($StateFile), tidak ditimpa."
} else {
    $cap = Get-OpenSshCapability
    $fw  = Get-NetFirewallRule -Name $FwDefault -ErrorAction SilentlyContinue
    $state = [pscustomobject]@{
        created                   = (Get-Date).ToString('s')
        openSshServerWasInstalled = (($cap -and $cap.State -eq 'Installed') -or [bool](Get-Service sshd -ErrorAction SilentlyContinue))
        defaultRuleExisted        = [bool]$fw
        defaultRuleWasEnabled     = [bool]($fw -and $fw.Enabled -eq 'True')
        userExisted               = [bool](Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue)
        sshdConfigExisted         = (Test-Path $SshdConfig)
    }
    $state | ConvertTo-Json | Set-Content -Path $StateFile -Encoding ASCII
    Info "Kondisi awal dicatat di $StateFile"
}

# --- 1. OpenSSH Server --------------------------------------------------------
Step '1. OpenSSH Server'
$InstallHelp = @'
OpenSSH Server tidak bisa dipasang otomatis lewat fitur Windows. Pilih SALAH SATU jalur, lalu
jalankan ulang script ini (catatan kondisi awal tidak akan ditimpa):
  (a) Restart laptop, jalankan Windows Update sampai tuntas, lalu ulangi script ini.
  (b) Pasang manual: Settings > System > Optional features > View features / Add a feature >
      "OpenSSH Server" > Install. Setelah terpasang, ulangi script ini.
  (c) Pasang MSI resmi Microsoft dari https://github.com/PowerShell/Win32-OpenSSH/releases
      (file OpenSSH-Win64-v*.msi), lalu ulangi script ini.
'@
if (Get-Service sshd -ErrorAction SilentlyContinue) {
    Info 'Service sshd sudah ada (fitur Windows, Settings, atau MSI); pemasangan dilewati.'
    $method = 'sudah-ada'
} else {
    $cap = Get-OpenSshCapability
    if (-not $cap) { Stop-Setup ("fitur OpenSSH.Server tidak bisa dibaca dari Windows.`n" + $InstallHelp) }
    Info "Memasang $($cap.Name) (butuh internet, bisa beberapa menit)..."
    try {
        Add-WindowsCapability -Online -Name $cap.Name -ErrorAction Stop | Out-Null
    } catch {
        $code = if ($_.Exception.HResult) { '0x{0:X8}' -f $_.Exception.HResult } else { 'tidak diketahui' }
        Stop-Setup ("pemasangan fitur OpenSSH Server gagal (kode $code).`n" + $InstallHelp)
    }
    if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) {
        Stop-Setup ("fitur terpasang tapi service sshd belum muncul (mungkin perlu restart).`n" + $InstallHelp)
    }
    $method = 'fitur-windows-oleh-setup'
}
$SshdExe = Get-SshdExe
if (-not $SshdExe -or -not (Test-Path $SshdExe)) { Stop-Setup 'lokasi sshd.exe tidak bisa dibaca dari service sshd.' }
$SshDir = Split-Path $SshdExe -Parent
$isMsi = -not $SshDir.StartsWith("$env:SystemRoot\System32", [StringComparison]::OrdinalIgnoreCase)
if ($isMsi) { $method = "$method (msi: $SshDir)" }
Info "sshd.exe: $SshdExe"
if (-not (Test-Path $InstallFile)) {
    [pscustomobject]@{ recorded = (Get-Date).ToString('s'); method = $method; sshdExe = $SshdExe; msi = $isMsi } |
        ConvertTo-Json | Set-Content -Path $InstallFile -Encoding ASCII
}
# Selama diatur: Manual + berhenti. Baru diset Automatic di akhir, setelah sshd_config dan
# firewall beres, supaya run yang terhenti di tengah tidak meninggalkan sshd yang otomatis
# menyala dengan konfigurasi bawaan (login password aktif).
Set-Service -Name sshd -StartupType Manual
if (-not (Test-Path $SshdConfig)) {
    # Start pertama membuat sshd_config dan host key.
    Start-Service sshd
    Start-Sleep -Seconds 2
}
Stop-Service sshd -ErrorAction SilentlyContinue
if (-not (Test-Path $SshdConfig)) { Stop-Setup "$SshdConfig tidak terbentuk." }
Info 'sshd: Manual dan dihentikan selama diatur (Automatic di akhir script).'

# --- 2. Akun homebackup -------------------------------------------------------
Step "2. Akun lokal $UserName"
$user = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
$secure = $null
if (-not $user) {
    $secure = New-RandomSecurePassword
    New-LocalUser -Name $UserName -Password $secure -PasswordNeverExpires -UserMayNotChangePassword `
        -AccountNeverExpires -Description 'Project HOME: backup SFTP dari STB (hanya key)' | Out-Null
    Info 'Akun dibuat. Password acak tidak ditampilkan/disimpan.'
} else {
    Info 'Akun sudah ada.'
}
if (-not (Test-GroupMember $SidUsers $UserName)) {
    Add-LocalGroupMember -SID $SidUsers -Member $UserName
    Info 'Ditambahkan ke grup Users (user standar).'
}
if (-not (Test-GroupMember $SidUsers $UserName)) { Stop-Setup "$UserName gagal ditambahkan ke grup Users." }
if (Test-GroupMember 'S-1-5-32-544' $UserName) {
    Stop-Setup "$UserName ternyata anggota Administrators. Periksa manual."
}

$ProfileDir = Get-UserProfileDir $UserName
if (-not $ProfileDir) {
    # Windows membuat folder profil saat login pertama. Picu sekali dengan password di memori,
    # supaya C:\Users\homebackup dibuat oleh Windows sendiri (bukan folder buatan tangan).
    # Kalau akun sudah ada tapi profil belum (mis. run sebelumnya terhenti), password acak dibuat ulang.
    if (-not $secure) {
        $secure = New-RandomSecurePassword
        Set-LocalUser -Name $UserName -Password $secure
    }
    $cred = New-Object System.Management.Automation.PSCredential($UserName, $secure)
    Start-Process -FilePath 'cmd.exe' -ArgumentList '/c exit' -Credential $cred -LoadUserProfile `
        -WorkingDirectory 'C:\Windows\System32' -WindowStyle Hidden -Wait
    $ProfileDir = Get-UserProfileDir $UserName
}
$cred = $null; $secure = $null
if (-not $ProfileDir) { Stop-Setup "profil $UserName tidak terbentuk." }
Info "Profil: $ProfileDir"

# --- 3. Folder backup ---------------------------------------------------------
Step "3. Folder $RepoDir"
New-Item -ItemType Directory -Force -Path $RepoDir | Out-Null
# C:\HOME-backup: homebackup hanya boleh membuka folder ini (tidak turun ke subfolder).
Invoke-Icacls $BackupRoot /setowner $SidAdmins
Invoke-Icacls $BackupRoot /inheritance:r /grant:r "${SidSystem}:(OI)(CI)F" "${SidAdmins}:(OI)(CI)F" "${UserName}:(RX)"
# C:\HOME-backup\restic: homebackup boleh baca/tulis/hapus (restic butuh itu).
Invoke-Icacls $RepoDir /setowner $SidAdmins
Invoke-Icacls $RepoDir /inheritance:r /grant:r "${SidSystem}:(OI)(CI)F" "${SidAdmins}:(OI)(CI)F" "${UserName}:(OI)(CI)M"
& icacls $BackupRoot
& icacls $RepoDir

# --- 4. sshd_config -----------------------------------------------------------
Step '4. sshd_config'
$orig = Join-Path $StateDir 'sshd_config.orig'
if (-not (Test-Path $orig)) { Copy-Item $SshdConfig $orig; Info "Backup asli: $orig" }
$text = [IO.File]::ReadAllText($SshdConfig)
$changed = $false
if (-not $text.Contains($MarkerTop)) {
    # sshd memakai nilai PERTAMA yang ditemukan, jadi pengaturan global ditaruh paling atas.
    $top = "$MarkerTop`nPasswordAuthentication no`n# --- akhir Project HOME global ---`n`n"
    $text = $top + $text
    $changed = $true
}
if (-not $text.Contains($MarkerMatch)) {
    # Blok Match harus di akhir file (berlaku sampai Match berikutnya / akhir file).
    $match = @(
        '', $MarkerMatch,
        "Match User $UserName",
        '    ForceCommand internal-sftp',
        "    ChrootDirectory $BackupRoot",
        '    PasswordAuthentication no',
        '    AllowTcpForwarding no',
        '    X11Forwarding no',
        '    PermitTTY no', ''
    ) -join "`n"
    $text = $text.TrimEnd() + "`n" + $match
    $changed = $true
}
if ($changed) {
    $prev = "$SshdConfig.sebelum-setup"
    Copy-Item $SshdConfig $prev -Force
    [IO.File]::WriteAllText($SshdConfig, $text, $Utf8NoBom)
    & $SshdExe -t
    if ($LASTEXITCODE -ne 0) {
        Copy-Item $prev $SshdConfig -Force
        Stop-Setup 'sshd -t menolak konfigurasi; sshd_config dikembalikan ke versi sebelumnya.'
    }
    Remove-Item $prev -Force
    Info 'sshd_config diperbarui dan lolos sshd -t.'
} else {
    & $SshdExe -t
    if ($LASTEXITCODE -ne 0) { Stop-Setup 'sshd -t menolak konfigurasi yang ada.' }
    Info 'sshd_config sudah berisi pengaturan Project HOME.'
}

# --- 5. Firewall --------------------------------------------------------------
Step '5. Firewall'
# Matikan semua rule inbound OpenSSH/sshd selain milik kita (nama rule bawaan fitur Windows
# dan MSI bisa berbeda). Nama yang dimatikan dicatat supaya remove-backup-target.ps1 bisa
# menyalakannya kembali.
$disabledBefore = @()
if (Test-Path $FwDisabledFile) { $disabledBefore = @(Get-Content $FwDisabledFile -Raw | ConvertFrom-Json) }
$sshRules = Get-NetFirewallRule -Direction Inbound -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -ne $FwRuleName -and $_.Enabled -eq 'True' -and $_.Action -eq 'Allow' -and
    ($_.Name -like '*OpenSSH*' -or $_.DisplayName -like '*OpenSSH*' -or $_.DisplayName -like '*sshd*')
}
foreach ($r in $sshRules) {
    Disable-NetFirewallRule -Name $r.Name
    if ($disabledBefore -notcontains $r.Name) { $disabledBefore += $r.Name }
    Info "Rule $($r.Name) ($($r.DisplayName)) dimatikan (membuka port 22 untuk semua jaringan)."
}
ConvertTo-Json -InputObject @($disabledBefore) | Set-Content -Path $FwDisabledFile -Encoding ASCII
if (-not (Get-NetFirewallRule -Name $FwRuleName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name $FwRuleName -DisplayName 'Project HOME: SSH hanya dari STB (192.168.137.0/24)' `
        -Direction Inbound -Protocol TCP -LocalPort 22 -RemoteAddress $StbSubnet -Action Allow -Profile Any | Out-Null
}
Set-NetFirewallRule -Name $FwRuleName -Enabled True -RemoteAddress $StbSubnet
Get-NetFirewallRule -Name $FwRuleName, $FwDefault -ErrorAction SilentlyContinue |
    Select-Object Name, Enabled, Direction, Action | Format-Table -AutoSize | Out-String | Write-Host
Info ("RemoteAddress rule baru: " + ((Get-NetFirewallRule -Name $FwRuleName | Get-NetFirewallAddressFilter).RemoteAddress -join ', '))

# --- 6. authorized_keys -------------------------------------------------------
Step '6. Public key STB'
$sshDir = Join-Path $ProfileDir '.ssh'
$akFile = Join-Path $sshDir 'authorized_keys'
New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
[IO.File]::WriteAllText($akFile, $StbPublicKey + "`n", $Utf8NoBom)
# OpenSSH Windows menolak authorized_keys yang bisa ditulis selain SYSTEM/Administrators/pemilik.
Invoke-Icacls $sshDir /inheritance:r /grant:r "${SidSystem}:(OI)(CI)F" "${SidAdmins}:(OI)(CI)F" "${UserName}:(OI)(CI)R"
Invoke-Icacls $akFile /inheritance:r /grant:r "${SidSystem}:F" "${SidAdmins}:F" "${UserName}:R"
& icacls $akFile
Info "Terpasang: $akFile"

# --- Selesai ------------------------------------------------------------------
Step 'Menyalakan sshd'
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd
Get-Service sshd | Select-Object Name, Status, StartType | Format-Table -AutoSize | Out-String | Write-Host
Write-Host 'Sidik jari host key laptop (untuk dicocokkan dari STB):'
& (Join-Path $SshDir 'ssh-keygen.exe') -lf 'C:\ProgramData\ssh\ssh_host_ed25519_key.pub'
Write-Host ''
Write-Host 'SELESAI. Beri tahu Claude Code untuk memverifikasi dari STB (Bagian A langkah 7).' -ForegroundColor Green
