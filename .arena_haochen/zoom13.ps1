Add-Type -AssemblyName System.Drawing
$items=@(@("02_yank_taut",590,440),@("05_milk",560,450),@("06_potion",450,500),@("01_herd",300,230),@("04_spit",500,420))
$w=220;$h=170;$s=3
$sheet=New-Object System.Drawing.Bitmap ($w*$s*3),($h*$s*2)
$g=[System.Drawing.Graphics]::FromImage($sheet)
$g.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$i=0
foreach($it in $items){ $img=[System.Drawing.Image]::FromFile((Join-Path (Get-Location) (".arena_haochen/t13_shots/"+$it[0]+".png")))
 $x=($i%3)*$w*$s; $y=[Math]::Floor($i/3)*$h*$s
 $g.DrawImage($img,(New-Object System.Drawing.Rectangle $x,$y,($w*$s),($h*$s)),(New-Object System.Drawing.Rectangle $it[1],$it[2],$w,$h),[System.Drawing.GraphicsUnit]::Pixel)
 $g.DrawString($it[0],(New-Object System.Drawing.Font("Arial",16)),[System.Drawing.Brushes]::Yellow,$x+4,$y+4); $img.Dispose(); $i++ }
$enc=[System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | ? { $_.MimeType -eq "image/jpeg" }
$ep=New-Object System.Drawing.Imaging.EncoderParameters 1
$ep.Param[0]=New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality),([long]80)
$sheet.Save((Join-Path (Get-Location) ".arena_haochen/t13_zoom.jpg"),$enc,$ep)
[Convert]::ToBase64String([IO.File]::ReadAllBytes(".arena_haochen/t13_zoom.jpg")) | Set-Content .arena_haochen/t13_zoom.b64 -NoNewline
"SIZE " + (Get-Item .arena_haochen/t13_zoom.b64).Length
