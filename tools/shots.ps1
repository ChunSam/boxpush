# Renders every screen to a PNG in shots/, for the review no assertion can do.
#
#     .\tools\shots.ps1
#     .\tools\shots.ps1 -OutDir C:\somewhere\else
#
# Unlike test.ps1 and smoke.ps1 this opens a real window, because there is
# nothing to look at without one. It writes to a scratch save, not the player's.
#
# shots/ is git-ignored: the images are for looking at now, not for keeping.

param(
	[string]$OutDir = ""
)

. "$PSScriptRoot\find-godot.ps1"

$godot = Find-Godot
$root = Get-ProjectRoot

if (-not $OutDir) { $OutDir = Join-Path $root "shots" }
$env:BOXPUSH_SHOT_DIR = $OutDir.Replace('\', '/')

Write-Host "Godot:   $godot"
Write-Host "Project: $root"
Write-Host "Shots:   $OutDir"

Confirm-GodotImport -Godot $godot -ProjectRoot $root

& $godot --path $root --script res://tools/shots.gd
exit $LASTEXITCODE
