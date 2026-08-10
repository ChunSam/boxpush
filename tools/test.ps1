# Runs the headless test suite. This is the project's verification gate:
# nothing is "done" until this exits 0.
#
#     .\tools\test.ps1
#
# The exit code is forwarded, so it drops straight into CI or a git hook. A run
# where every test passes but the engine leaked also fails — see
# Invoke-GodotScript in find-godot.ps1 for why that check lives out here.

. "$PSScriptRoot\find-godot.ps1"

$godot = Find-Godot
$root = Get-ProjectRoot

Write-Host "Godot:   $godot"
Write-Host "Project: $root"

Confirm-GodotImport -Godot $godot -ProjectRoot $root

exit (Invoke-GodotScript -Godot $godot -ProjectRoot $root -ScriptPath 'res://tests/run_tests.gd')
