[Console]::OutputEncoding=[Text.Encoding]::UTF8
$g="E:/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
foreach ($t in @(@("test_jjk_fx_gallery","1280x960"),@("test_jjk_domain_gallery","1280x960"),@("test_jjk_gpu","800x600"))) {
  $log=".backups/jjk_20260928/$($t[0]).log"
  $p = Start-Process -FilePath $g -ArgumentList @("--path",".","--audio-driver","Dummy","--resolution",$t[1],"--script","res://tests/$($t[0]).gd") -NoNewWindow -Wait -PassThru -RedirectStandardOutput $log -RedirectStandardError "$log.err"
  "== $($t[0]) exit=$($p.ExitCode)"
  Get-Content $log,"$log.err" | Select-String -Pattern "SCRIPT ERROR|ERROR:|JJK_FAIL|JJK_RESULT|at: res|JJK_SHOT" | Select-Object -First 16 | ForEach-Object { $_.Line }
}

