Add-Type -AssemblyName System.Drawing
$dir=".arena_haochen/t13_shots"
$files=Get-ChildItem $dir -Filter *.png | Sort-Object Name
$cw=540;$ch=360;$cols=3;$rows=[Math]::Ceiling($files.Count/$cols)
$sheet=New-Object System.Drawing.Bitmap ($cw*$cols),($ch*$rows)
$g=[System.Drawing.Graphics]::FromImage($sheet)
$g.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$font=New-Object System.Drawing.Font("Arial",14)
$i=0
foreach($f in $files){ $img=[System.Drawing.Image]::FromFile($f.FullName); $x=($i%$cols)*$cw; $y=[Math]::Floor($i/$cols)*$ch
 $src=New-Object System.Drawing.Rectangle 180,120,720,480
 $g.DrawImage($img,(New-Object System.Drawing.Rectangle $x,$y,$cw,$ch),$src,[System.Drawing.GraphicsUnit]::Pixel)
 $g.DrawString($f.BaseName,$font,[System.Drawing.Brushes]::Yellow,$x+4,$y+4); $img.Dispose(); $i++ }
$enc=[System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | ? { $_.MimeType -eq "image/jpeg" }
$ep=New-Object System.Drawing.Imaging.EncoderParameters 1
$ep.Param[0]=New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality),([long]82)
$sheet.Save((Join-Path (Get-Location) ".arena_haochen/t13_sheet.jpg"),$enc,$ep)
[Convert]::ToBase64String([IO.File]::ReadAllBytes(".arena_haochen/t13_sheet.jpg")) | Set-Content .arena_haochen/t13_sheet.b64 -NoNewline
"SIZE " + (Get-Item .arena_haochen/t13_sheet.b64).Length
