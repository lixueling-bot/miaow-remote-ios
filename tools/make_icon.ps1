# 画 App 图标（1024×1024，不透明）：深色底 + 暖金色 MIAOW 标志（一根线两只小猫耳，路径同 机箱\标志\miaow_mark.svg）
param([string]$Out = (Join-Path $PSScriptRoot '..\MIAOWRemote\Assets.xcassets\AppIcon.appiconset\icon-1024.png'))
Add-Type -AssemblyName System.Drawing
$n = 1024
$bmp = New-Object System.Drawing.Bitmap $n, $n
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$g.PixelOffsetMode = 'HighQuality'
# 底：上浅下深的炭灰
$rect = New-Object System.Drawing.Rectangle 0, 0, $n, $n
$bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, ([System.Drawing.Color]::FromArgb(255, 38, 38, 40)), ([System.Drawing.Color]::FromArgb(255, 14, 14, 15)), 90
$g.FillRectangle($bg, $rect)
# 标志：原图宽 100、线 y 24–52，放到宽 700
$w = 700.0; $k = $w / 100.0
$ox = ($n - $w) / 2; $oy = $n / 2 - 38 * $k + 10
function P([double]$x, [double]$y) { New-Object System.Drawing.PointF ([single]($ox + $x * $k)), ([single]($oy + $y * $k)) }
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$path.AddLine((P 0 52), (P 14 52))
$path.AddLine((P 14 52), (P 30 24))
$path.AddLine((P 30 24), (P 42 38))
$path.AddBezier((P 42 38), (P 44.4 40.8), (P 55.6 40.8), (P 58 38))
$path.AddLine((P 58 38), (P 70 24))
$path.AddLine((P 70 24), (P 86 52))
$path.AddLine((P 86 52), (P 100 52))
$pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 219, 168, 102)), ([single](5.2 * $k))
$pen.LineJoin = 'Miter'
$pen.MiterLimit = 10
$pen.StartCap = 'Flat'; $pen.EndCap = 'Flat'
$g.DrawPath($pen, $path)
$g.Dispose()
$full = [System.IO.Path]::GetFullPath($Out)
$bmp.Save($full, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
"图标：$full"
