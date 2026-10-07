# Prepares the Pi boot drive (the "bootfs" partition of the USB stick or SD card)
# for serial debugging through the Arduino (see read_pi_serial.ps1).
#   -Mode serialtest : boot the bare-metal serial + RAM test (serialtest.img)
#   -Mode linux      : boot Linux with kernel messages on GPIO14 / pin 8 (9600)
# Both test modes send at 9600 baud, read through the Uno running pi_serial_bridge.ino.
#   -Mode undo       : put config.txt and cmdline.txt back as they were
# Every run first copies config.txt and cmdline.txt to
# Downloads\usb_boot_backup_serial_<time>. Add -WhatIf to only show the changes.
# Run: powershell -ExecutionPolicy Bypass -File prep_usb_serial.ps1 -Mode serialtest
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][ValidateSet('serialtest', 'linux', 'undo')][string]$Mode,
    [string]$Root,          # boot drive, e.g. E:\ (found automatically if left out)
    [string]$BackupDir      # where backups go (default: your Downloads folder)
)
$ErrorActionPreference = 'Stop'
$begin = '# >>> retro-tv debug'
$end = '# <<< retro-tv debug'
$mark = '#retro-tv '         # prefix for lines this script comments out
$utf8 = New-Object System.Text.UTF8Encoding $false

# --- find the boot drive -------------------------------------------------
if (-not $Root) {
    $found = @(Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root } | Where-Object {
            (Test-Path (Join-Path $_ 'config.txt')) -and (Test-Path (Join-Path $_ 'start4.elf')) })
    if ($found.Count -eq 0) { throw 'No Pi boot drive found (a drive with config.txt and start4.elf). Plug in the USB stick.' }
    if ($found.Count -gt 1) { throw "More than one Pi boot drive found: $($found -join ', '). Unplug the others or add -Root E:\" }
    $Root = $found[0]
}
$config = Join-Path $Root 'config.txt'
$cmdline = Join-Path $Root 'cmdline.txt'
$cmdOrig = Join-Path $Root 'cmdline.txt.retro-tv-orig'
$testImg = Join-Path $Root 'serialtest.img'
foreach ($f in $config, $cmdline) { if (-not (Test-Path $f)) { throw "$f not found - is $Root the Pi boot drive?" } }
Write-Host "Pi boot drive: $Root  (mode: $Mode)"

function Read-Lf($path) { ([IO.File]::ReadAllText($path)) -replace "`r`n", "`n" }
function Save($path, $text) {
    if ($PSCmdlet.ShouldProcess($path, 'write')) { [IO.File]::WriteAllText($path, $text, $utf8) }
}

# Removes this script's block and un-comments lines it commented out earlier.
function Get-CleanConfig($text) {
    $text = [regex]::Replace($text, "(?ms)^$([regex]::Escape($begin))\n.*?^$([regex]::Escape($end))\n?", '')
    $text = [regex]::Replace($text, "(?m)^$([regex]::Escape($mark))", '')
    if ($text.Length -and -not $text.EndsWith("`n")) { $text += "`n" }
    $text
}

function Set-ConfigBlock([string[]]$lines) {
    $text = Get-CleanConfig (Read-Lf $config)
    # a manual kernel= test line outside the block would override the block
    $text = [regex]::Replace($text, '(?m)^(\s*kernel=(blink|serialtest)\.img)', "$mark`$1")
    $text += "$begin`n" + ($lines -join "`n") + "`n$end`n"
    Save $config $text
    Write-Host "config.txt block:"; $lines | ForEach-Object { Write-Host "    $_" }
}

# --- backup --------------------------------------------------------------
if (-not $BackupDir) {
    $home_ = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    $BackupDir = Join-Path $home_ 'Downloads'
}
$bk = Join-Path $BackupDir ('usb_boot_backup_serial_' + (Get-Date -Format 'yyyy-MM-dd_HHmmss'))
if ($PSCmdlet.ShouldProcess($bk, 'back up config.txt and cmdline.txt')) {
    New-Item -ItemType Directory -Path $bk -Force | Out-Null
    Copy-Item $config, $cmdline -Destination $bk
    Write-Host "Backup: $bk"
}

# --- modes ---------------------------------------------------------------
switch ($Mode) {
    'serialtest' {
        $src = @((Join-Path (Join-Path $PSScriptRoot 'arm_serial_ram_test') 'serialtest.img'),
            (Join-Path $PSScriptRoot 'serialtest.img')) | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $src) { throw 'serialtest.img not found next to this script or in arm_serial_ram_test\' }
        if ($PSCmdlet.ShouldProcess($testImg, "copy $src")) { Copy-Item $src $testImg -Force }
        Write-Host "Copied serialtest.img"
        Set-ConfigBlock @('[all]', 'kernel=serialtest.img', 'arm_64bit=1')
    }
    'linux' {
        Set-ConfigBlock @('[all]', 'enable_uart=1', 'uart_2ndstage=1', 'dtoverlay=disable-bt', 'init_uart_baud=9600')
        $old = (Read-Lf $cmdline).Trim()
        if (-not (Test-Path $cmdOrig) -and $PSCmdlet.ShouldProcess($cmdOrig, 'save original cmdline.txt')) {
            Copy-Item $cmdline $cmdOrig
        }
        $drop = '^(quiet|splash|plymouth\.ignore-serial-consoles|ignore_loglevel|keep_bootcon|console=tty1|earlycon(=.*)?|console=(serial0|ttyAMA0|ttyS0).*|loglevel=.*)$'
        $tokens = @($old -split '\s+' | Where-Object { $_ -and $_ -notmatch $drop })
        $tokens = @('earlycon=pl011,mmio32,0xfe201000', 'console=ttyAMA0,9600', 'console=tty1') + $tokens + @('ignore_loglevel', 'keep_bootcon')
        $new = $tokens -join ' '
        Save $cmdline "$new`n"
        Write-Host "cmdline.txt before: $old"
        Write-Host "cmdline.txt after:  $new"
    }
    'undo' {
        Save $config (Get-CleanConfig (Read-Lf $config))
        Write-Host 'config.txt: removed the debug block'
        if (Test-Path $cmdOrig) {
            if ($PSCmdlet.ShouldProcess($cmdline, 'restore original')) { Copy-Item $cmdOrig $cmdline -Force; Remove-Item $cmdOrig }
            Write-Host 'cmdline.txt: restored the original'
        }
        if ((Test-Path $testImg) -and $PSCmdlet.ShouldProcess($testImg, 'delete')) { Remove-Item $testImg; Write-Host 'Removed serialtest.img' }
    }
}
Write-Host 'Done. Eject the drive safely before unplugging it.'
