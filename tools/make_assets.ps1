# Regenerates the placeholder art and audio cues in assets/.
#
#     .\tools\make_assets.ps1
#
# The game loads the generated .png and .wav, not the generator, so the results
# are committed. Run this only after changing the palette or the cues in
# tools/make_assets.gd, then commit what it writes.
#
# It re-imports afterwards, because a new asset is invisible to the engine until
# the .godot cache knows about it.

. "$PSScriptRoot\find-godot.ps1"

$godot = Find-Godot
$root = Get-ProjectRoot

Write-Host "Godot:   $godot"
Write-Host "Project: $root"

Confirm-GodotImport -Godot $godot -ProjectRoot $root

& $godot --headless --path $root --script res://tools/make_assets.gd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Retried once: importing assets that did not exist when the process started has
# been seen to crash on exit *after* writing everything correctly, and a second
# pass over an already-imported tree is both clean and nearly free.
& $godot --headless --path $root --import
if ($LASTEXITCODE -ne 0) {
	Write-Host "First import did not exit cleanly; retrying over the imported tree."
	& $godot --headless --path $root --import
}
exit $LASTEXITCODE
