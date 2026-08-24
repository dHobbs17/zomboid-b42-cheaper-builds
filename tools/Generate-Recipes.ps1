<#
.SYNOPSIS
    Regenerates the mod's construction-recipe overrides from the vanilla PZ B42 entity scripts.

.DESCRIPTION
    Reads walls/, stairs/, and fences_low/ entity definitions from a local Project Zomboid
    install and writes modified copies into the mod's media/scripts/entities/ folder.

    Within each entity's component CraftRecipe block:
      - "time = N,"  -> reduced by $TimeMultiplier (floor of 1)
      - "item N ..."  -> set to 1, UNLESS the line is a tool requirement
                         (mode:keep, or Base.BlowTorch fuel draw)

    Everything else in the file (UiConfig, SpriteConfig, OnCreate/OnIsValid hooks,
    SkillRequired, xpAward, tool lines) is copied through unchanged, since a mod
    redefining "module Base { entity X {...} }" fully replaces the vanilla entity -
    dropping a component would break rendering/placement.

    Re-run this after a PZ update to pick up any vanilla balance changes.

.PARAMETER PZRoot
    Path to the Project Zomboid install (folder containing media/).

.PARAMETER ModRoot
    Path to the mod folder to write into. Defaults to
    Contents/mods/CheaperBuildingMultiplayerB42 next to this script.

.PARAMETER TimeMultiplier
    Fraction of vanilla craft time to keep. 0.25 = 75% reduction.
#>
param(
    [string]$PZRoot = "C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid",
    [string]$ModRoot = (Join-Path $PSScriptRoot "..\Contents\mods\CheaperBuildingMultiplayerB42"),
    [double]$TimeMultiplier = 0.25
)

$ErrorActionPreference = "Stop"

$SourceEntitiesRoot = Join-Path $PZRoot "media\scripts\generated\entities"
$DestScriptsRoot = Join-Path $ModRoot "media\scripts\entities"

if (-not (Test-Path $SourceEntitiesRoot)) {
    throw "Could not find vanilla entities folder at: $SourceEntitiesRoot"
}

# Source subfolders that hold buildable walls/doors/windows/frames/stairs/floors/fences/gates.
$sourceDirs = @("walls", "stairs", "fences_low")

# Decorative wall coverings - not structural building objects, out of scope.
$excludeFiles = @("paint_sign.txt", "paint_wall.txt", "paper_wall.txt", "plaster_wall.txt")

$processed = 0
$skipped = 0

foreach ($dir in $sourceDirs) {
    $srcDir = Join-Path $SourceEntitiesRoot $dir
    if (-not (Test-Path $srcDir)) {
        Write-Warning "Source dir not found, skipping: $srcDir"
        continue
    }

    Get-ChildItem -LiteralPath $srcDir -Filter *.txt |
        Where-Object { $excludeFiles -notcontains $_.Name } |
        ForEach-Object {
            $lines = Get-Content -LiteralPath $_.FullName

            $out = foreach ($line in $lines) {
                if ($line -match '^(\s*time\s*=\s*)(\d+)(\s*,?\s*)$') {
                    $prefix = $Matches[1]
                    $orig = [int]$Matches[2]
                    $suffix = $Matches[3]
                    $new = [Math]::Max(1, [int][Math]::Round($orig * $TimeMultiplier))
                    "$prefix$new$suffix"
                }
                elseif ($line -match '^(\s*item\s+)(\d+)(\s+.*)$' -and
                        $line -notmatch 'mode:keep' -and
                        $line -notmatch 'Base\.BlowTorch') {
                    "$($Matches[1])1$($Matches[3])"
                }
                else {
                    $line
                }
            }

            $destPath = Join-Path $DestScriptsRoot "$dir\$($_.Name)"
            $destDir = Split-Path $destPath -Parent
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
            Set-Content -LiteralPath $destPath -Value $out -Encoding ascii
            $processed++
        }
}

Write-Host "Generated $processed recipe override(s) into $DestScriptsRoot"
