<#
.SYNOPSIS
    指定プロセスのトップレベルウィンドウを PNG でキャプチャする（Windows 版動作証跡）。

.DESCRIPTION
    macOS の scripts/capture-app-window.sh に相当する Windows 実装。
    PrintWindow(PW_RENDERFULLCONTENT=2) を使うため、ウィンドウが前面でなくても
    （他ウィンドウに隠れていても）当該ウィンドウだけを切り出せる。
    CLAUDE.md「動作証跡スクリーンショット運用」が想定する scripts/windows/ 配下の
    キャプチャ手段（Phase 4 / Task 25 で追加）。

.PARAMETER ProcessName
    対象プロセス名（拡張子なし。例: hmi_editor / hmi_simulator）。

.PARAMETER Out
    出力 PNG パス。

.EXAMPLE
    .\scripts\windows\capture-app-window.ps1 -ProcessName hmi_editor -Out Docs\screenshots\task-25-selection.png
#>
param(
    [Parameter(Mandatory = $true)][string]$ProcessName,
    [Parameter(Mandatory = $true)][string]$Out
)

$ErrorActionPreference = 'Stop'

Add-Type -ReferencedAssemblies System.Drawing @"
using System;
using System.Runtime.InteropServices;
using System.Drawing;
using System.Drawing.Imaging;

public static class WinCap
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();

    // PW_RENDERFULLCONTENT = 2 : 隠れていても全内容を描画させる
    public static Bitmap Capture(IntPtr hWnd)
    {
        RECT r;
        if (!GetWindowRect(hWnd, out r)) throw new Exception("GetWindowRect failed");
        int w = r.Right - r.Left;
        int h = r.Bottom - r.Top;
        if (w <= 0 || h <= 0) throw new Exception("window has no size");
        Bitmap bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(bmp))
        {
            IntPtr hdc = g.GetHdc();
            try { PrintWindow(hWnd, hdc, 2); }
            finally { g.ReleaseHdc(hdc); }
        }
        return bmp;
    }
}
"@

# 表示スケール 100% 超（例 150%）の画面では、DPI 非対応の PowerShell に対して
# GetWindowRect が縮小した仮想座標を返し、PrintWindow の結果がウィンドウの左上部分だけに
# 切り取られる（インスペクタが写らない。Task RF-G で発覚）。物理ピクセルで扱うため
# 先に DPI 対応を宣言する。
[WinCap]::SetProcessDPIAware() | Out-Null

$proc = Get-Process -Name $ProcessName -ErrorAction Stop |
    Where-Object { $_.MainWindowHandle -ne 0 } |
    Select-Object -First 1
if (-not $proc) { throw "プロセス '$ProcessName' のトップレベルウィンドウが見つかりません" }

$hWnd = $proc.MainWindowHandle
[WinCap]::SetForegroundWindow($hWnd) | Out-Null
Start-Sleep -Milliseconds 300

$bmp = [WinCap]::Capture($hWnd)
$outDir = Split-Path -Parent $Out
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "Saved: $Out ($($proc.ProcessName) PID=$($proc.Id))"
