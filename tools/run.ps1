# Runs the game itself.
#
#     .\tools\run.ps1              # windowed
#     .\tools\run.ps1 -Headless    # no window; useful for checking boot output
#
# Any extra arguments are forwarded to Godot.

param(
    [switch]$Headless,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Extra
)

. "$PSScriptRoot\find-godot.ps1"

$godot = Find-Godot
$root = Get-ProjectRoot

Confirm-GodotImport -Godot $godot -ProjectRoot $root

$godotArgs = @('--path', $root)
if ($Headless) { $godotArgs += '--headless' }
if ($Extra) { $godotArgs += $Extra }

& $godot @godotArgs
exit $LASTEXITCODE
