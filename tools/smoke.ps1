# Drives the whole screen flow once, headlessly: menu, level select, all five
# levels cleared in sequence, the clear overlay, and a relaunch.
#
#     .\tools\smoke.ps1
#
# This is the v0.3 acceptance path made re-runnable. It is not part of the gate —
# `tools\test.ps1` deliberately never builds a scene tree, and this needs a live
# one — so run it after touching a screen, a signal between screens, or the save.
#
# It writes to a scratch save, never to the player's own.
#
# Exits non-zero if any check fails.

. "$PSScriptRoot\find-godot.ps1"

$godot = Find-Godot
$root = Get-ProjectRoot

Write-Host "Godot:   $godot"
Write-Host "Project: $root"

Confirm-GodotImport -Godot $godot -ProjectRoot $root

& $godot --headless --path $root --script res://tools/smoke_flow.gd
exit $LASTEXITCODE
