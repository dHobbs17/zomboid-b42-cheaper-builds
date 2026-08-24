<#
.SYNOPSIS
    Generates the SteamCMD workshop VDF, embedding workshop-description.bbcode as the
    item description so the Workshop page updates on every publish.

.DESCRIPTION
    SteamCMD's workshop_build_item has no "descriptionfile" key - the description has to
    be an inline string in the VDF. This script reads workshop-description.bbcode, escapes
    it for VDF, and writes the finished .vdf, so the Workshop description is never edited
    by hand and never drifts from what is in the repo.

    Run this, then publish:
        steamcmd.exe +login <user> +workshop_build_item <OutFile> +quit

.PARAMETER ChangeNote
    Change note shown in the Workshop "Change Notes" tab for this upload.

.PARAMETER OutFile
    Where to write the generated VDF. Defaults to the local steamcmd folder.

.PARAMETER RawNewlines
    Emit real newlines inside the quoted description instead of \n escape sequences.
    Steam's KeyValues parser should accept the escapes, but if the published page shows
    literal "\n" text, re-run with this switch.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ChangeNote,

    [string]$OutFile = "C:\Users\daveh\Desktop\steamcmd\upload_cheap_builds.vdf",

    [switch]$RawNewlines
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path $PSScriptRoot -Parent
$DescriptionFile = Join-Path $RepoRoot "workshop-description.bbcode"
$ContentFolder = Join-Path $RepoRoot "Contents"
$PreviewFile = Join-Path $RepoRoot "preview.png"

# Workshop item identity. publishedfileid must keep pointing at the live item -
# a wrong or empty id silently publishes a brand new item instead of updating.
$AppId = "108600"
$PublishedFileId = "3788978147"
$Title = "Cheaper Building Multiplayer B42"
$Visibility = "0"   # 0 = public, 1 = friends only, 2 = hidden

foreach ($p in @($DescriptionFile, $ContentFolder, $PreviewFile)) {
    if (-not (Test-Path $p)) { throw "Missing required path: $p" }
}

function ConvertTo-VdfString {
    param([string]$Text, [bool]$KeepNewlines)
    # Backslashes first, or the escapes added below would be double-escaped.
    $s = $Text -replace '\\', '\\'
    $s = $s -replace '"', '\"'
    $s = $s -replace "`r`n", "`n"
    if (-not $KeepNewlines) { $s = $s -replace "`n", '\n' }
    return $s
}

# -Encoding UTF8 is required: Windows PowerShell 5.1 otherwise reads a BOM-less UTF-8
# file as Windows-1252, turning em dashes and arrows into mojibake in the description.
$descriptionRaw = Get-Content -LiteralPath $DescriptionFile -Raw -Encoding UTF8
$description = ConvertTo-VdfString -Text $descriptionRaw -KeepNewlines:$RawNewlines
$note = ConvertTo-VdfString -Text $ChangeNote -KeepNewlines:$false

# Paths inside a VDF string need their backslashes escaped like any other content.
$contentEsc = ConvertTo-VdfString -Text $ContentFolder -KeepNewlines:$false
$previewEsc = ConvertTo-VdfString -Text $PreviewFile -KeepNewlines:$false

$vdf = @"
"workshopitem"
{
    "appid"            "$AppId"
    "publishedfileid"  "$PublishedFileId"
    "contentfolder"    "$contentEsc"
    "previewfile"      "$previewEsc"
    "visibility"       "$Visibility"
    "title"            "$Title"
    "description"      "$description"
    "changenote"       "$note"
}
"@

$outDir = Split-Path $OutFile -Parent
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

# UTF-8 *without* BOM - Set-Content -Encoding utf8 on PS 5.1 emits a BOM, and the leading
# bytes can trip the VDF parser before it reaches "workshopitem".
$OutFile = [System.IO.Path]::GetFullPath((Join-Path (Resolve-Path $outDir) (Split-Path $OutFile -Leaf)))
[System.IO.File]::WriteAllText($OutFile, $vdf, (New-Object System.Text.UTF8Encoding($false)))

$descLines = ($descriptionRaw -split "`n").Count
Write-Host "Wrote $OutFile"
Write-Host "  description: $descLines lines from workshop-description.bbcode"
Write-Host "  changenote : $ChangeNote"
Write-Host ""
Write-Host "Publish with:"
Write-Host "  steamcmd.exe +login <user> +workshop_build_item `"$OutFile`" +quit"
