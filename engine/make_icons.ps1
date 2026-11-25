# SmartCounter 8.1: item icons from the game's own shop art (read-only on the game files).
#
#   powershell -ExecutionPolicy Bypass -File make_icons.ps1 [-GamePath D:\...\Paladins]
#
# Source: GameUI_SF.upk, movie "itemimagestack", sprite "ItemCards" (26 frames, 256x196).
# Frame N = DATA_SET_ICONS.ICON_INDEX = items[*].icon_index in champions_data.json.
# Frame -> texture (decoded from the SWF, 8.1.5839.0): frame 1 = itemimagestack_I61, then +2 (hex)
# per frame; frames 14 and 17 are empty (no texture), so frames 15+ are shifted by one slot.
# Output: src\icons\<ItemWithoutSpaces>.png, 48x37 (same name as export_lua.icon_file).
param(
    [string]$GamePath = "D:\SteamLibrary\steamapps\common\Paladins",
    [int]$Width = 48
)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$mod = Split-Path -Parent $here
$upk = "C:\FiF Project\Tools\TempestStudio\1.0.0-alpha.10\upk.exe"
$work = Join-Path $mod "..\..\Work\Extracted\8.1.5839.0\itemimagestack"
$out = Join-Path $mod "src\icons"
New-Item -ItemType Directory -Force $work, $out | Out-Null

if (-not (Test-Path (Join-Path $work "itemimagestack_i61.png"))) {
    $tmp = Join-Path $env:TEMP ("sc_icons_" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force $tmp | Out-Null
    & $upk texture export-all (Join-Path $GamePath "ChaosGame\CookedPCConsole\GameUI_SF.upk") $tmp --png | Out-Null
    Get-ChildItem $tmp -Recurse -Filter "itemimagestack_*.png" | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $work $_.Name.ToLower()) -Force
    }
    Remove-Item -Recurse -Force $tmp
}

function Get-TextureName([int]$frame) {
    if ($frame -eq 14 -or $frame -eq 17 -or $frame -lt 1 -or $frame -gt 26) { return $null }
    $slot = $frame - 1
    if ($frame -gt 14) { $slot -= 1 }
    if ($frame -gt 17) { $slot -= 1 }
    return "itemimagestack_i{0:x}.png" -f (0x61 + 2 * $slot)
}

Add-Type -AssemblyName System.Drawing
$data = Get-Content (Join-Path $here "champions_data.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$missing = @()
foreach ($p in $data.items.PSObject.Properties) {
    $name = $p.Name
    $tex = Get-TextureName ([int]$p.Value.icon_index)
    $src = if ($tex) { Join-Path $work $tex } else { $null }
    if (-not $src -or -not (Test-Path $src)) { $missing += "$name (frame $($p.Value.icon_index))"; continue }
    $img = [System.Drawing.Image]::FromFile($src)
    $h = [int][math]::Round($Width * $img.Height / $img.Width)
    $bmp = New-Object System.Drawing.Bitmap $Width, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($img, 0, 0, $Width, $h)
    $file = Join-Path $out (($name -replace '[^A-Za-z0-9]', '') + ".png")
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose(); $img.Dispose()
}
$n = (Get-ChildItem $out -Filter *.png).Count
Write-Output "$n icones dans $out"
if ($missing) { Write-Output ("sans icone : " + ($missing -join ", ")) }
