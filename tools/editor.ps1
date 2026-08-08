# Opens this project in the Godot editor.
#
#     .\tools\editor.ps1

. "$PSScriptRoot\find-godot.ps1"

$godot = Find-Godot
$root = Get-ProjectRoot

& $godot --editor --path $root
exit $LASTEXITCODE
