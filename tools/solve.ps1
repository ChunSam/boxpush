# Searches for a shortest solution to every indexed level and prints a
# ready-to-paste SOLUTIONS block for tests/test_levels.gd.
#
#     .\tools\solve.ps1
#
# Run it after editing a level: the test suite replays recorded solutions rather
# than searching, so a board change that invalidates one is only fixed here.
#
# Exits non-zero if any level fails to parse or has no solution at all.

. "$PSScriptRoot\find-godot.ps1"

$godot = Find-Godot
$root = Get-ProjectRoot

Write-Host "Godot:   $godot"
Write-Host "Project: $root"

Confirm-GodotImport -Godot $godot -ProjectRoot $root

& $godot --headless --path $root --script res://tools/solve_levels.gd
exit $LASTEXITCODE
