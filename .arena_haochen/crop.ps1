Add-Type -AssemblyName System.Drawing
$d="C:/Users/q2283/AppData/Roaming/Godot/app_userdata/polo_balls"
$cx=[double]$args[0]; $cy=[double]$args[1]; $half=[double]$args[2]; $out=[int]$args[3]
foreach($n in $args[4..($args.Length-1)]){
  $src=[System.Drawing.Image]::FromFile("$d/$n.png")
  $W=$src.Width; $H=$src.Height
  $x=[int]($cx*$W-$half*$W); $y=[int]($cy*$H-$half*$W); $s=[int](2*$half*$W)
  $bmp=New-Object System.Drawing.Bitmap $out,$out
  $g=[System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.DrawImage($src,(New-Object System.Drawing.Rectangle 0,0,$out,$out),(New-Object System.Drawing.Rectangle $x,$y,$s,$s),[System.Drawing.GraphicsUnit]::Pixel)
  $g.Dispose(); $src.Dispose()
  $ms=New-Object IO.MemoryStream; $bmp.Save($ms,[System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
  [IO.File]::WriteAllText("$PWD/.arena_haochen/$n.b64",[Convert]::ToBase64String($ms.ToArray(),[Base64FormattingOptions]::InsertLineBreaks))
  "$n src=${W}x${H} bytes=$($ms.Length)"
}
