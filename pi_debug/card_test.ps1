# READ-ONLY SD card test. Never writes to the card.
$report = "C:\Users\haals\Downloads\card_test_report.txt"
$disk = '\\.\PhysicalDrive1'
$chunk = 1MB
$firstBytes = 3GB
function Log($m) { $m | Tee-Object -FilePath $report -Append }
"" | Out-File $report
Log ("Card test " + (Get-Date))
$size = (Get-Disk -Number 1).Size
Log ("Disk 1 size reported: {0:N2} GB" -f ($size/1GB))

function ReadHash($bytes) {
    $fs = [IO.File]::Open($disk,'Open','Read','ReadWrite')
    $sha = [Security.Cryptography.SHA256]::Create()
    $buf = New-Object byte[] $chunk
    $errors = 0; $done = 0
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($done -lt $bytes) {
        try {
            $n = $fs.Read($buf, 0, $chunk)
            if ($n -le 0) { break }
            [void]$sha.TransformBlock($buf, 0, $n, $null, 0)
            $done += $n
        } catch {
            $errors++
            Log ("READ ERROR at offset {0:N0}: {1}" -f $done, $_.Exception.Message)
            $done += $chunk
            try { [void]$fs.Seek($done, 'Begin') } catch { break }
            if ($errors -gt 50) { break }
        }
    }
    [void]$sha.TransformFinalBlock($buf, 0, 0)
    $fs.Close()
    $mbps = ($done/1MB) / [math]::Max($sw.Elapsed.TotalSeconds, 0.1)
    return @{ hash = ([BitConverter]::ToString($sha.Hash) -replace '-',''); errors = $errors; mbps = $mbps; bytes = $done }
}

Log "Pass 1: reading first 3 GB ..."
$a = ReadHash $firstBytes
Log ("  pass 1: {0:N0} MB read, {1} errors, {2:N1} MB/s" -f ($a.bytes/1MB), $a.errors, $a.mbps)
Log "Pass 2: reading first 3 GB again ..."
$b = ReadHash $firstBytes
Log ("  pass 2: {0:N0} MB read, {1} errors, {2:N1} MB/s" -f ($b.bytes/1MB), $b.errors, $b.mbps)
if ($a.hash -eq $b.hash) { Log "RESULT: both passes identical (consistent reads)" } else { Log "RESULT: PASSES DIFFER - card returns inconsistent data (bad/failing card)" }

Log "Sampling the rest of the card (1 MB every 2 GB) ..."
$fs = [IO.File]::Open($disk,'Open','Read','ReadWrite')
$buf = New-Object byte[] $chunk
$bad = 0; $ok = 0
for ($off = 3GB; $off + $chunk -lt $size; $off += 2GB) {
    try {
        [void]$fs.Seek($off, 'Begin'); [void]$fs.Read($buf, 0, $chunk); $ok++
    } catch { $bad++; Log ("  sample read error at {0:N1} GB: {1}" -f ($off/1GB), $_.Exception.Message) }
}
$fs.Close()
Log ("  samples ok: {0}, failed: {1}" -f $ok, $bad)
Log "DONE"
