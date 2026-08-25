<#
.SYNOPSIS
    One-step deploy: builds the SteamCMD VDF from workshop-description.bbcode, uploads
    the mod to the Steam Workshop, and reports what Steam actually logged.

.DESCRIPTION
    SteamCMD's workshop_build_item has no "descriptionfile" key, so the Workshop
    description has to be inlined into the VDF. This script escapes
    workshop-description.bbcode into the VDF, publishes, then reads Steam's own
    workshop log to confirm the upload rather than trusting the console output.

    Paths are hardcoded for this machine. Run it bare and it prompts for what it needs:
        .\Deploy-Workshop.ps1

.PARAMETER ChangeNote
    Change note shown in the Workshop "Change Notes" tab. Prompted for when omitted,
    and cannot be left blank - publishing without one leaves users guessing.

.PARAMETER SteamUser
    Steam account that owns the Workshop item. Prompted for when omitted.

.PARAMETER Yes
    Skip the confirmation prompt before publishing.

.PARAMETER SkipUpload
    Build the VDF and stop. Useful for inspecting the generated file first.

.PARAMETER RawNewlines
    Emit real newlines in the description instead of \n escapes. Use only if a
    published page shows literal "\n" text.

.NOTES
    Steam allows one authenticated session per account, so uploading will disconnect
    the desktop Steam client. That is expected - relaunch it afterwards.
#>
param(
    [string]$ChangeNote,
    [string]$SteamUser,
    [switch]$SkipUpload,
    [switch]$RawNewlines,
    [switch]$Yes
)

$ErrorActionPreference = "Stop"

$DefaultSteamUser = "your-steam-username"

# Both values are prompted for when not passed, so a bare run is fully interactive
# while still being scriptable with -ChangeNote/-SteamUser.
if (-not $ChangeNote) {
    Write-Host ""
    Write-Host "Change note for this update (shown in the Workshop 'Change Notes' tab):" -ForegroundColor Cyan
    $ChangeNote = Read-Host "  Change note"
    while ([string]::IsNullOrWhiteSpace($ChangeNote)) {
        Write-Warning "A change note is required - users see this to know what moved."
        $ChangeNote = Read-Host "  Change note"
    }
}

if (-not $SteamUser) {
    $entered = Read-Host "  Steam username [$DefaultSteamUser]"
    if ([string]::IsNullOrWhiteSpace($entered)) { $SteamUser = $DefaultSteamUser }
    else { $SteamUser = $entered.Trim() }
}

# --- Hardcoded for this machine ---------------------------------------------------
$RepoRoot   = "E:\Projects\zomboid\zomboid-cheap-builds"
$SteamCmdDir = "C:\Users\daveh\Desktop\steamcmd"
$SteamCmdExe = Join-Path $SteamCmdDir "steamcmd.exe"
$VdfPath     = Join-Path $SteamCmdDir "upload_cheap_builds.vdf"
$WorkshopLog = Join-Path $SteamCmdDir "logs\workshop_log.txt"

$DescriptionFile = Join-Path $RepoRoot "workshop-description.bbcode"
$ContentFolder   = Join-Path $RepoRoot "Contents"
$PreviewFile     = Join-Path $RepoRoot "preview.png"
$ModInfo         = Join-Path $RepoRoot "Contents\mods\CheaperBuildingMultiplayerB42\42\mod.info"

# Workshop item identity. publishedfileid must keep pointing at the live item -
# a wrong or empty id silently publishes a brand new item instead of updating.
$AppId           = "108600"
$PublishedFileId = "3788978147"
$Title           = "Cheaper Building Multiplayer B42"
$Visibility      = "0"   # 0 = public, 1 = friends only, 2 = hidden
# ----------------------------------------------------------------------------------

foreach ($p in @($DescriptionFile, $ContentFolder, $PreviewFile, $ModInfo)) {
    if (-not (Test-Path $p)) { throw "Missing required path: $p" }
}
if (-not $SkipUpload -and -not (Test-Path $SteamCmdExe)) {
    throw "steamcmd.exe not found at: $SteamCmdExe"
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

$vdf = @"
"workshopitem"
{
    "appid"            "$AppId"
    "publishedfileid"  "$PublishedFileId"
    "contentfolder"    "$(ConvertTo-VdfString -Text $ContentFolder -KeepNewlines:$false)"
    "previewfile"      "$(ConvertTo-VdfString -Text $PreviewFile -KeepNewlines:$false)"
    "visibility"       "$Visibility"
    "title"            "$Title"
    "description"      "$(ConvertTo-VdfString -Text $descriptionRaw -KeepNewlines:$RawNewlines)"
    "changenote"       "$(ConvertTo-VdfString -Text $ChangeNote -KeepNewlines:$false)"
}
"@

# UTF-8 *without* BOM - Set-Content -Encoding utf8 on PS 5.1 emits a BOM, and the
# leading bytes can trip the VDF parser before it reaches "workshopitem".
[System.IO.File]::WriteAllText($VdfPath, $vdf, (New-Object System.Text.UTF8Encoding($false)))

$modVersion = (Select-String -LiteralPath $ModInfo -Pattern '^modversion=(.+)$').Matches.Groups[1].Value
$fileCount = (Get-ChildItem -LiteralPath $ContentFolder -Recurse -File).Count

Write-Host ""
Write-Host "Built $VdfPath" -ForegroundColor Green
Write-Host "  mod version : $modVersion"
Write-Host "  content     : $fileCount files"
Write-Host "  description : $(($descriptionRaw -split "`n").Count) lines"
Write-Host "  changenote  : $ChangeNote"

if ($SkipUpload) {
    Write-Host ""
    Write-Host "-SkipUpload set, not publishing." -ForegroundColor Yellow
    return
}

# Publishing is public and immediate, so confirm before pushing unless told not to.
if (-not $Yes) {
    Write-Host ""
    $answer = Read-Host "Publish version $modVersion to the Steam Workshop as '$SteamUser'? [y/N]"
    if ($answer.Trim() -notmatch '^(y|yes)$') {
        Write-Host "Cancelled - the VDF is built but nothing was published." -ForegroundColor Yellow
        return
    }
}

# Note where Steam's log ends now, so we only report lines from THIS upload.
$logMark = 0
if (Test-Path $WorkshopLog) { $logMark = (Get-Content -LiteralPath $WorkshopLog).Count }

Write-Host ""
Write-Host "Publishing as '$SteamUser' (your desktop Steam client will be disconnected)..." -ForegroundColor Cyan
Write-Host ""

& $SteamCmdExe +login $SteamUser +workshop_build_item $VdfPath +quit
$steamExit = $LASTEXITCODE

Write-Host ""
if (-not (Test-Path $WorkshopLog)) {
    Write-Warning "steamcmd exited $steamExit but no workshop log found at $WorkshopLog - verify manually."
    return
}

# steamcmd's console output and exit code are both unreliable indicators, so confirm
# against what Steam wrote to its own log for this item.
$new = Get-Content -LiteralPath $WorkshopLog | Select-Object -Skip $logMark |
       Where-Object { $_ -match $PublishedFileId -or $_ -match 'ERROR|Failed' }

if ($new) {
    Write-Host "Steam workshop log for this run:" -ForegroundColor Cyan
    $new | ForEach-Object { Write-Host "  $_" }
}

$ok = $new | Where-Object { $_ -match 'Upload finished.*OK' }
$bad = $new | Where-Object { $_ -match 'ERROR|Failed' }

Write-Host ""
if ($ok -and -not $bad) {
    Write-Host "Published OK - version $modVersion is live." -ForegroundColor Green
    Write-Host "https://steamcommunity.com/sharedfiles/filedetails/?id=$PublishedFileId"
    Write-Host "Restart the server to pull the update."
} elseif ($bad) {
    Write-Warning "Steam reported a problem - the upload may not have gone through."
} else {
    Write-Warning "Could not confirm success from the log (steamcmd exit $steamExit). Check the Workshop page."
}
