param([string]$extra="")
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$g='E:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
$o="$env:TEMP\b.out"; $e="$env:TEMP\b.err"
$args=@('--headless','--path','.','--script','res://tests/bench_knife100.gd','--quit-after','4000')
if ($extra.Trim() -ne "") { $args += "--"; $args += $extra.Trim().Split(" ") }
$p=Start-Process -FilePath $g -ArgumentList $args -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e; $p.WaitForExit(280000)|Out-Null
Get-Content $o | Select-String 'SPAWN|FRAME_MS|PHYS|MON nodes|ALIVE'
"errs=" + (Get-Content $e | Select-String '^(ERROR|SCRIPT ERROR)' | Measure-Object).Count
