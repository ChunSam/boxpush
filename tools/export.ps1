# Exports a Windows release build into build/.
#
#     .\tools\export.ps1
#
# The preset lives in export_presets.cfg, which is committed on purpose so that
# its `*.xsb` non-resource filter travels with the repository — without it the
# build launches, runs, and has no levels. tools\test.ps1 asserts the filter.
#
# Needs the Godot export templates for this engine version, which are a separate
# download from the engine itself. If they are missing this prints where they
# should be rather than leaving you with the engine's raw error.

param(
	[string]$Preset = "Windows Desktop"
)

. "$PSScriptRoot\find-godot.ps1"

$godot = Find-Godot
$root = Get-ProjectRoot
$outDir = Join-Path $root 'build'
$outFile = Join-Path $outDir 'Boxpush.exe'

Write-Host "Godot:   $godot"
Write-Host "Project: $root"
Write-Host "Output:  $outFile"

Confirm-GodotImport -Godot $godot -ProjectRoot $root

New-Item -ItemType Directory -Force $outDir | Out-Null

& $godot --headless --path $root --export-release $Preset $outFile
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
	$templates = Join-Path $env:APPDATA 'Godot\export_templates'
	Write-Host ''
	Write-Host "Export failed. The usual cause is missing export templates." -ForegroundColor Yellow
	Write-Host "They are a separate download from the engine, and belong in:"
	Write-Host "  $templates\<version>.stable\"
	Write-Host "Install them from the editor: Editor > Manage Export Templates."
	exit $exitCode
}

Write-Host ''
Write-Host "Built. Copy the whole build/ folder — the .exe needs its .pck beside it."
exit 0
