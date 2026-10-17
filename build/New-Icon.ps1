# Generates assets\PCleaner.png and a multi-size assets\PCleaner.ico: a silver monitor and broom on a black tile.
[CmdletBinding()]
param([string]$OutDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) 'assets'))
Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

function New-RoundedPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90); $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure(); $p
}
function Pt([double]$x, [double]$y) { New-Object System.Drawing.PointF ([float]$x), ([float]$y) }

function New-IconBitmap([int]$Size) {
    $s = $Size / 256.0   # everything below is designed on a 256 grid
    $bmp = New-Object System.Drawing.Bitmap $Size, $Size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.ScaleTransform($s, $s)

    # Tile: near-black with a soft top-light gradient and a hairline silver edge
    $tile = New-RoundedPath 2 2 252 252 56
    $tileBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush (Pt 0 0), (Pt 0 256), ([System.Drawing.Color]::FromArgb(52, 56, 63)), ([System.Drawing.Color]::FromArgb(14, 15, 18))
    $g.FillPath($tileBrush, $tile)
    $edgePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(70, 200, 205, 212)), 2
    $g.DrawPath($edgePen, (New-RoundedPath 3 3 250 250 55))

    $silverLight = [System.Drawing.Color]::FromArgb(236, 238, 241)
    $silverMid = [System.Drawing.Color]::FromArgb(178, 184, 192)
    $silverDark = [System.Drawing.Color]::FromArgb(118, 124, 133)
    $black = [System.Drawing.Color]::FromArgb(8, 9, 11)

    # Monitor body (silver bezel) with black screen
    $bezelBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush (Pt 40 50), (Pt 200 170), $silverLight, $silverDark
    $g.FillPath($bezelBrush, (New-RoundedPath 30 56 150 106 14))
    $g.FillPath((New-Object System.Drawing.SolidBrush $black), (New-RoundedPath 40 66 130 82 8))
    # faint screen sheen
    $sheen = New-Object System.Drawing.Drawing2D.LinearGradientBrush (Pt 40 66), (Pt 110 150), ([System.Drawing.Color]::FromArgb(46, 255, 255, 255)), ([System.Drawing.Color]::FromArgb(0, 255, 255, 255))
    $g.FillPath($sheen, (New-RoundedPath 40 66 130 82 8))
    # stand
    $standBrush = New-Object System.Drawing.SolidBrush $silverMid
    $g.FillRectangle($standBrush, 94, 162, 22, 18)
    $g.FillPath($standBrush, (New-RoundedPath 66 180 78 12 6))

    # Broom: drawn upright around pivot then rotated so it leans against the right side, staying inside the tile
    $state = $g.Save()
    $g.TranslateTransform(186, 158)
    $g.RotateTransform(22)
    # handle
    $handleBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush (Pt -7 0), (Pt 7 0), $silverLight, $silverDark
    $g.FillPath($handleBrush, (New-RoundedPath -6 -110 12 114 6))
    # ferrule (band)
    $g.FillPath((New-Object System.Drawing.SolidBrush $silverDark), (New-RoundedPath -14 -2 28 14 4))
    # bristle head: trapezoid fanning out, silver with darker lines
    $head = New-Object System.Drawing.Drawing2D.GraphicsPath
    $head.AddPolygon([System.Drawing.PointF[]]@((Pt -16 10), (Pt 16 10), (Pt 30 58), (Pt -30 58)))
    $headBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush (Pt -30 10), (Pt 30 58), $silverMid, $silverDark
    $g.FillPath($headBrush, $head)
    $linePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(150, 30, 32, 36)), 2.2
    foreach ($bx in -16, -8, 0, 8, 16) { $g.DrawLine($linePen, [float]($bx * 0.75), [float]14, [float]($bx * 1.7), [float]56) }
    $g.DrawLine((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(120, 30, 32, 36)), 2), [float]-28, [float]52, [float]28, [float]52)
    $g.Restore($state)

    # Three sweep sparkles on the screen edge
    $sparkBrush = New-Object System.Drawing.SolidBrush $silverLight
    foreach ($sp in @(@(60, 82, 7), @(78, 114, 4.5), @(54, 132, 4))) {
        $cx = $sp[0]; $cy = $sp[1]; $a = $sp[2]; $b = $a * 0.28
        $pts = [System.Drawing.PointF[]]@((Pt $cx ($cy - $a)), (Pt ($cx + $b) ($cy - $b)), (Pt ($cx + $a) $cy), (Pt ($cx + $b) ($cy + $b)), (Pt $cx ($cy + $a)), (Pt ($cx - $b) ($cy + $b)), (Pt ($cx - $a) $cy), (Pt ($cx - $b) ($cy - $b)))
        $g.FillPolygon($sparkBrush, $pts)
    }
    $g.Dispose()
    $bmp
}

$png = Join-Path $OutDir 'PCleaner.png'
$big = New-IconBitmap 256
$big.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)

$sizes = 256, 64, 48, 32, 24, 16
$images = @()
foreach ($sz in $sizes) {
    $bmp = New-IconBitmap $sz
    $ms = New-Object IO.MemoryStream; $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $images += , @{ Size = $sz; Bytes = $ms.ToArray() }; $ms.Dispose(); $bmp.Dispose()
}
$ico = Join-Path $OutDir 'PCleaner.ico'
$fs = [IO.File]::Create($ico); $bw = New-Object IO.BinaryWriter $fs
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$images.Count)
$offset = 6 + 16 * $images.Count
foreach ($img in $images) {
    $dim = if ($img.Size -ge 256) { 0 } else { $img.Size }
    $bw.Write([byte]$dim); $bw.Write([byte]$dim); $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$img.Bytes.Length); $bw.Write([uint32]$offset); $offset += $img.Bytes.Length
}
foreach ($img in $images) { $bw.Write($img.Bytes) }
$bw.Dispose(); $fs.Dispose(); $big.Dispose()
Write-Host "Icon written: $ico ($((Get-Item $ico).Length) bytes), preview: $png"
