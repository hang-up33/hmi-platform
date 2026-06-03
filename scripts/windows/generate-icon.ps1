#requires -version 5.1
<#
.SYNOPSIS
    Atlas ブランドアイコン（.ico）を生成する。

.DESCRIPTION
    球体（天球）を "A"（Atlas の頭文字）の脚が下から支えるモチーフを
    GDI+（System.Drawing）で直接描画し、複数解像度を 1 つの .ico に
    PNG 圧縮でパックする。ImageMagick / Inkscape 等の外部ツールは不要。

    出力:
      branding/atlas.ico          … exe 埋め込み用（16〜256px をパック）
      branding/atlas-preview.png  … レビュー / README 掲載用（256px）

    本スクリプトがアイコンの「唯一の真実」。色・形を変えたいときは
    ここを編集して再実行すれば両ファイルが再生成される。
#>

Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'

# scripts/windows/ → リポジトリ root/branding/
$repoRoot    = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$brandingDir = Join-Path $repoRoot 'branding'
if (-not (Test-Path $brandingDir)) {
    New-Item -ItemType Directory -Path $brandingDir | Out-Null
}

# --- ブランドカラー ---
$colBgTop    = [System.Drawing.Color]::FromArgb(255,  15,  23,  42)  # 濃紺 (slate-900)
$colBgBottom = [System.Drawing.Color]::FromArgb(255,  23,  37,  84)  # 藍
$colGlobe1   = [System.Drawing.Color]::FromArgb(255, 165, 243, 252)  # 明シアン
$colGlobe2   = [System.Drawing.Color]::FromArgb(255,  14, 165, 200)  # 濃シアン
$colLine     = [System.Drawing.Color]::FromArgb(150,   8,  47,  73)  # 経緯線（濃紺・半透明）
$colLeg      = [System.Drawing.Color]::FromArgb(255,  34, 211, 238)  # 脚（シアン）
$colHi       = [System.Drawing.Color]::FromArgb(170, 255, 255, 255)  # ハイライト

function New-AtlasBitmap([int]$s) {
    $bmp = New-Object System.Drawing.Bitmap($s, $s, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    # --- 背景：角丸四角 + 縦グラデ ---
    $rad  = [float]($s * 0.18)
    $d    = [float]($rad * 2)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0,         0,         $d, $d, 180, 90)
    $path.AddArc($s - $d,   0,         $d, $d, 270, 90)
    $path.AddArc($s - $d,   $s - $d,   $d, $d,   0, 90)
    $path.AddArc(0,         $s - $d,   $d, $d,  90, 90)
    $path.CloseFigure()
    $rectF   = New-Object System.Drawing.RectangleF(0, 0, [float]$s, [float]$s)
    $bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rectF, $colBgTop, $colBgBottom, 90.0)
    $g.FillPath($bgBrush, $path)

    # --- 球（天球） ---
    $cx = [float]($s * 0.5)
    $cy = [float]($s * 0.40)
    $r  = [float]($s * 0.255)
    $globeRect  = New-Object System.Drawing.RectangleF(($cx - $r), ($cy - $r), ($r * 2), ($r * 2))
    $globeBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($globeRect, $colGlobe1, $colGlobe2, 60.0)
    $g.FillEllipse($globeBrush, $globeRect)

    # 経緯線は球の内側だけに描く（楕円クリップ）
    $clip = New-Object System.Drawing.Drawing2D.GraphicsPath
    $clip.AddEllipse($globeRect)
    $g.SetClip($clip)
    $linePen = New-Object System.Drawing.Pen($colLine, [float]($s * 0.020))
    # 緯線（横）
    $g.DrawLine($linePen, $cx - $r,        $cy,             $cx + $r,        $cy)
    $g.DrawLine($linePen, $cx - $r * 0.92, $cy - $r * 0.55, $cx + $r * 0.92, $cy - $r * 0.55)
    $g.DrawLine($linePen, $cx - $r * 0.92, $cy + $r * 0.55, $cx + $r * 0.92, $cy + $r * 0.55)
    # 経線（縦楕円） + 中央縦線
    $g.DrawEllipse($linePen, $cx - $r * 0.45, $cy - $r, $r * 0.9, $r * 2)
    $g.DrawEllipse($linePen, $cx - $r * 0.82, $cy - $r, $r * 1.64, $r * 2)
    $g.DrawLine($linePen, $cx, $cy - $r, $cx, $cy + $r)
    $g.ResetClip()

    # 球のリム（明るい輪郭）とハイライト
    $rimPen = New-Object System.Drawing.Pen($colGlobe1, [float]($s * 0.012))
    $g.DrawEllipse($rimPen, $globeRect)
    $hiBrush = New-Object System.Drawing.SolidBrush($colHi)
    $hiRect  = New-Object System.Drawing.RectangleF(($cx - $r * 0.55), ($cy - $r * 0.70), ($r * 0.55), ($r * 0.32))
    $g.FillEllipse($hiBrush, $hiRect)

    # --- "A" の脚（Atlas が球を支える） ---
    $legPen = New-Object System.Drawing.Pen($colLeg, [float]($s * 0.075))
    $legPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $legPen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
    $apexX = $cx
    $apexY = [float]($cy + $r * 0.55)         # A の頂点は球の下に少し隠れる
    $baseY = [float]($s * 0.88)
    $llx   = [float]($cx - $r * 0.95)
    $rrx   = [float]($cx + $r * 0.95)
    $g.DrawLine($legPen, $apexX, $apexY, $llx, $baseY)
    $g.DrawLine($legPen, $apexX, $apexY, $rrx, $baseY)
    # A の横バー
    $barPen = New-Object System.Drawing.Pen($colLeg, [float]($s * 0.055))
    $barPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $barPen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
    $by = [float]($cy + $r * 1.18)
    $g.DrawLine($barPen, $cx - $r * 0.46, $by, $cx + $r * 0.46, $by)

    $g.Dispose()
    return $bmp
}

function Write-U16($bw, $v) { $bw.Write([System.BitConverter]::GetBytes([uint16]$v)) }
function Write-U32($bw, $v) { $bw.Write([System.BitConverter]::GetBytes([uint32]$v)) }

function Save-Ico($bitmaps, $path) {
    # 各ビットマップを PNG にエンコード（Vista+ は PNG 圧縮 ICO 対応）
    $pngList = @()
    foreach ($b in $bitmaps) {
        $ms = New-Object System.IO.MemoryStream
        $b.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $pngList += , ($ms.ToArray())
        $ms.Dispose()
    }
    $count = $bitmaps.Count
    $fs = [System.IO.File]::Create($path)
    $bw = New-Object System.IO.BinaryWriter($fs)
    # ICONDIR
    Write-U16 $bw 0          # reserved
    Write-U16 $bw 1          # type = icon
    Write-U16 $bw $count     # 画像数
    # ICONDIRENTRY × count（PNG データはヘッダ群の直後から並べる）
    $offset = 6 + 16 * $count
    for ($i = 0; $i -lt $count; $i++) {
        $b = $bitmaps[$i]
        $w = $b.Width;  if ($w -ge 256) { $w = 0 }   # 256 は 0 で表現
        $h = $b.Height; if ($h -ge 256) { $h = 0 }
        $bw.Write([byte]$w)
        $bw.Write([byte]$h)
        $bw.Write([byte]0)   # パレット色数
        $bw.Write([byte]0)   # reserved
        Write-U16 $bw 1      # color planes
        Write-U16 $bw 32     # bits per pixel
        Write-U32 $bw $pngList[$i].Length
        Write-U32 $bw $offset
        $offset += $pngList[$i].Length
    }
    foreach ($pb in $pngList) { $bw.Write($pb) }
    $bw.Flush(); $bw.Close(); $fs.Close()
}

# --- 生成 ---
$sizes   = 16, 24, 32, 48, 64, 128, 256
$bitmaps = foreach ($sz in $sizes) { New-AtlasBitmap $sz }

$icoPath     = Join-Path $brandingDir 'atlas.ico'
$previewPath = Join-Path $brandingDir 'atlas-preview.png'
Save-Ico $bitmaps $icoPath

$preview = New-AtlasBitmap 256
$preview.Save($previewPath, [System.Drawing.Imaging.ImageFormat]::Png)
$preview.Dispose()
foreach ($b in $bitmaps) { $b.Dispose() }

Write-Host "生成しました:"
Write-Host "  $icoPath"
Write-Host "  $previewPath"
