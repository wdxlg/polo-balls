# 用法: powershell -File tests\run_tests.ps1 [-Filter test_*] [-Out tests\last_run.txt]
param([string]$Filter='test_*.gd',[string]$Out='tests\last_run.txt',[int]$TimeoutSec=90)
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$g = 'E:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
if (-not (Test-Path $g)) { $g = (Get-Command godot -EA SilentlyContinue).Source }
$results=@()
"# started $(Get-Date -Format s)" | Set-Content $Out -Encoding UTF8
foreach ($t in (Get-ChildItem tests -Filter $Filter | Sort-Object Name)) {
  $o="$env:TEMP\t_out.txt"; $e="$env:TEMP\t_err.txt"
  $sw=[Diagnostics.Stopwatch]::StartNew()
  $p = Start-Process -FilePath $g -ArgumentList @('--headless','--path','.','--script',"res://tests/$($t.Name)",'--quit-after','3000') -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
  $done = $p.WaitForExit($TimeoutSec*1000)
  if (-not $done) { Stop-Process -Id $p.Id -Force; Start-Sleep -m 300; $code='TIMEOUT' } else { $code=$p.ExitCode }
  $sw.Stop()
  $errLines = Get-Content $e -EA SilentlyContinue | Select-String 'SCRIPT ERROR|ERROR:|Parse Error|Parser Error'
  $line = "{0,-45} exit={1,-8} errs={2,-3} {3,5:N1}s" -f $t.Name,$code,$errLines.Count,$sw.Elapsed.TotalSeconds
  $line | Add-Content $Out -Encoding UTF8
  if ($errLines.Count -gt 0) { ($errLines | Select-Object -First 3 | % { "      " + $_.Line.Trim() }) | Add-Content $Out -Encoding UTF8 }
  $results += $line
}
"# finished $(Get-Date -Format s)" | Add-Content $Out -Encoding UTF8
$results
