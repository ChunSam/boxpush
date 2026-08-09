# Runs the headless test suite. This is the project's verification gate:
# nothing is "done" until this exits 0.
#
#     .\tools\test.ps1
#
# The exit code is forwarded, so it drops straight into CI or a git hook.

. "$PSScriptRoot\find-godot.ps1"

$godot = Find-Godot
$root = Get-ProjectRoot

Write-Host "Godot:   $godot"
Write-Host "Project: $root"

Confirm-GodotImport -Godot $godot -ProjectRoot $root

# stderr is captured to a file so the leak check below can re-read it, then
# printed straight back, so the run looks exactly as it always did.
#
# cmd.exe does the redirect rather than PowerShell. PowerShell 5.1 turns a native
# command's stderr into ErrorRecords and writes *those* to the file — the engine's
# text arrives wrapped in "NativeCommandError" and a CategoryInfo block. Handing
# the redirect to cmd keeps PowerShell out of the stream entirely.
$stderrFile = [System.IO.Path]::GetTempFileName()
$command = '"{0}" --headless --path "{1}" --script res://tests/run_tests.gd 2>"{2}"' `
	-f $godot, $root, $stderrFile
& $env:ComSpec /c $command
$exitCode = $LASTEXITCODE

$stderr = [System.IO.File]::ReadAllText($stderrFile)
Remove-Item $stderrFile -Force -ErrorAction SilentlyContinue
if ($stderr.Trim()) { Write-Host $stderr }

if ($exitCode -ne 0) { exit $exitCode }

# A test that builds a Node and never frees it leaves the suite green and the
# engine leaking. Godot only reports that at exit, long after run_tests.gd has
# printed "0 failed" and decided the run passed, so the gate either notices it
# here or nowhere. Watched to fail: removing the runner's teardown() call leaks
# 24 instances and, without this, still exits 0.
$leaks = [regex]::Matches(
	$stderr,
	'(?m)^.*(ObjectDB instances were leaked|resources still in use at exit).*$'
)
if ($leaks.Count -gt 0) {
	Write-Host ""
	Write-Host "FAIL: every test passed, but the run leaked. A test did not release what it built:"
	foreach ($leak in $leaks) { Write-Host "  $($leak.Value.Trim())" }
	exit 1
}

exit $exitCode
