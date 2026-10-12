# Waits for the Arduino's COM port, then records everything the Pi sends
# (115200 baud) into a log file until stopped or MaxMinutes passes.
param([int]$MaxMinutes = 10)
$log = "C:\Users\haals\Downloads\pi_boot_serial_log.txt"
"=== waiting for Arduino COM port $(Get-Date) ===" | Out-File $log -Encoding utf8

$port = $null
$deadline = (Get-Date).AddMinutes($MaxMinutes)
while (-not $port -and (Get-Date) -lt $deadline) {
    $dev = Get-CimInstance Win32_PnPEntity | Where-Object { $_.Name -match '\((COM\d+)\)' } | Select-Object -First 1
    if ($dev) { $port = [regex]::Match($dev.Name, 'COM\d+').Value; "found $($dev.Name)" | Out-File $log -Append -Encoding utf8 }
    else { Start-Sleep -Seconds 2 }
}
if (-not $port) { "no COM port appeared" | Out-File $log -Append -Encoding utf8; exit 1 }

$sp = New-Object System.IO.Ports.SerialPort $port, 115200, 'None', 8, 'One'
$sp.ReadTimeout = 500
$sp.DtrEnable = $false
$sp.Open()
"=== reading $port at 115200 $(Get-Date) ===" | Out-File $log -Append -Encoding utf8
while ((Get-Date) -lt $deadline) {
    try {
        $s = $sp.ReadExisting()
        if ($s) { [IO.File]::AppendAllText($log, $s) }
    } catch {}
    Start-Sleep -Milliseconds 200
}
$sp.Close()
"`n=== stopped $(Get-Date) ===" | Out-File $log -Append -Encoding utf8
