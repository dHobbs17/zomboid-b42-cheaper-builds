<#
.SYNOPSIS
    Regenerates the mod's construction-recipe overrides from the vanilla PZ B42 entity scripts.

.DESCRIPTION
    Reads walls/, stairs/, and fences_low/ entity definitions from a local Project Zomboid
    install and writes modified copies into the mod's 42/media/scripts/entities/ folder.

    Within each entity's component CraftRecipe block:
      - "time = N,"  -> reduced by $TimeMultiplier (floor of 1)
      - "item N ..."  -> set to $DefaultAmount (1), or to a per-entity value from
                         $MaterialOverrides below, UNLESS the line is a tool
                         requirement (mode:keep, or Base.BlowTorch fuel draw)

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

.PARAMETER DefaultAmount
    Amount every consumed material drops to unless $MaterialOverrides says otherwise.
#>
param(
    [string]$PZRoot = "C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid",
    [string]$ModRoot = (Join-Path $PSScriptRoot "..\Contents\mods\CheaperBuildingMultiplayerB42"),
    [double]$TimeMultiplier = 0.25,
    [int]$DefaultAmount = 1
)

$ErrorActionPreference = "Stop"

# Build 42 mods must keep their content inside a version folder (42\), not flat at
# the mod root - the game resolves media/ through that folder. A flat layout makes
# the loader report the mod as "not found" (or load it with zero content).
$SourceEntitiesRoot = Join-Path $PZRoot "media\scripts\generated\entities"
$DestScriptsRoot = Join-Path $ModRoot "42\media\scripts\entities"

if (-not (Test-Path $SourceEntitiesRoot)) {
    throw "Could not find vanilla entities folder at: $SourceEntitiesRoot"
}

# Source subfolders that hold buildable walls/doors/windows/frames/stairs/floors/fences/gates.
$sourceDirs = @("walls", "stairs", "fences_low")

# Decorative wall coverings - not structural building objects, out of scope.
$excludeFiles = @("paint_sign.txt", "paint_wall.txt", "paper_wall.txt", "plaster_wall.txt")

# These four use "face SINGLE" in their SpriteConfig, which the engine rejects when a
# mod redefines the entity ("Unknown block 'face' in entity iso script"), risking a
# broken sprite config for objects that would otherwise still be buildable. They all
# already cost 1 of every material in vanilla, so the only thing the mod would change
# is craft time - not worth a load error. Every other entity uses directional faces
# (face W/N/S/...) and redefines cleanly.
$excludeFiles += @("entity_floor_dirt.txt", "entity_floor_gravel.txt",
                   "entity_floor_sand.txt", "entity_woodenpole.txt")

# Per-entity material amounts for recipes that would be too cheap at a flat 1 - large
# multi-tile builds (double doors/gates, stairs) and the masonry set. Keyed by entity
# name, then by a substring of the vanilla "item N ..." line. Anything not listed
# falls back to $DefaultAmount. Amounts equal to the default are kept here anyway so
# this table reads as the full intended recipe rather than just the exceptions.
$MaterialOverrides = @{
    # Carpentry
    "DoubleDoor"              = @{ "Base.Plank" = 4; "Base.Nails" = 4; "Base.Hinge" = 2; "Base.Doorknob" = 2 }
    "Wood_Stairs"             = @{ "Base.Plank" = 4; "Base.Nails" = 4 }
    "WoodFenceGate"           = @{ "Base.Plank" = 1; "Base.Nails" = 1; "Base.Hinge" = 2 }

    # Masonry - concrete drops to 1, the block/brick body keeps some weight
    "StoneWall"               = @{ "base:concrete" = 1; "Base.StoneBlock" = 2 }
    "StoneDoorFrame"          = @{ "base:concrete" = 1; "Base.StoneBlock" = 2 }
    "StoneWindowFrame"        = @{ "base:concrete" = 1; "Base.StoneBlock" = 2 }
    "BrickWallLvl1"           = @{ "base:concrete" = 1; "Base.ClayBrick" = 2 }
    "BrickWallLvl2"           = @{ "base:concrete" = 1; "Base.ClayBrick" = 2 }
    "BrickDoorFrameLvl1"      = @{ "base:concrete" = 1; "Base.ClayBrick" = 2 }
    "BrickDoorFrameLvl2"      = @{ "base:concrete" = 1; "Base.ClayBrick" = 2 }
    "BrickWindowFrameLvl1"    = @{ "base:concrete" = 1; "Base.ClayBrick" = 2 }
    "BrickWindowFrameLvl2"    = @{ "base:concrete" = 1; "Base.ClayBrick" = 2 }

    # Welding - the two double-width gates
    "DoubleFenceGate"         = @{ "Base.MetalPipe" = 4; "Base.WeldingRods" = 4; "Base.Hinge" = 2; "Base.ScrapMetal" = 1 }
    "DoubleWireGate"          = @{ "Base.MetalPipe" = 4; "Base.WeldingRods" = 4; "Base.Hinge" = 2; "Base.Wire" = 1; "Base.ScrapMetal" = 1 }
}

$processed = 0
$overridesApplied = @{}

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

            $entity = $null
            foreach ($l in $lines) {
                if ($l -match '^\s*entity\s+([A-Za-z_0-9]+)') { $entity = $Matches[1]; break }
            }
            $entityOverrides = $null
            if ($entity -and $MaterialOverrides.ContainsKey($entity)) {
                $entityOverrides = $MaterialOverrides[$entity]
            }

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
                    $head = $Matches[1]
                    $tail = $Matches[3]
                    $amount = $DefaultAmount
                    if ($entityOverrides) {
                        foreach ($key in $entityOverrides.Keys) {
                            if ($tail -like "*$key*") {
                                $amount = $entityOverrides[$key]
                                $overridesApplied["$entity/$key"] = $true
                                break
                            }
                        }
                    }
                    "$head$amount$tail"
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

# Surface typos: an override that never matched a real entity/material silently does
# nothing, which is easy to miss when the vanilla scripts get renamed by an update.
foreach ($ent in $MaterialOverrides.Keys) {
    foreach ($key in $MaterialOverrides[$ent].Keys) {
        if (-not $overridesApplied.ContainsKey("$ent/$key")) {
            Write-Warning "Override never applied: $ent -> $key (entity or material not found)"
        }
    }
}

Write-Host "Generated $processed recipe override(s) into $DestScriptsRoot"
