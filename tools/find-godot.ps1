# Locates the Godot 4 executable to use for command-line work.
#
# Dot-source this from the other scripts in tools/:
#     . "$PSScriptRoot\find-godot.ps1"
#     $godot = Find-Godot
#
# Resolution order: $env:GODOT_BIN, then PATH, then the winget package folder.
# The *_console.exe build is preferred: on Windows the plain Godot binary is a
# GUI application that detaches from the console, so its stdout never reaches
# the caller and a test run would look silent and pass regardless.

function Find-Godot {
    if ($env:GODOT_BIN) {
        if (Test-Path $env:GODOT_BIN) {
            return (Resolve-Path $env:GODOT_BIN).Path
        }
        Write-Warning "GODOT_BIN is set to '$env:GODOT_BIN' but that path does not exist; ignoring it."
    }

    foreach ($name in @('godot_console.exe', 'godot_console', 'godot.exe', 'godot')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source) { return $cmd.Source }
    }

    $packages = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path $packages) {
        $hit = Get-ChildItem -Path $packages -Recurse -Depth 3 -Filter 'Godot_v4*_console.exe' -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }

    throw "Godot 4 not found. Install it with 'winget install GodotEngine.GodotEngine', or set GODOT_BIN to the executable."
}

function Get-ProjectRoot {
    return (Split-Path -Parent $PSScriptRoot)
}

# Runs a headless Godot script, echoes its output, and fails a *passing* run that
# leaked. Shared by test.ps1 and smoke.ps1 so that both hold the same line.
#
# Godot reports leaked objects at exit, long after the script has printed its own
# verdict and decided the run passed, so nothing inside the engine can notice.
# Watched to fail: deleting the test runner's teardown() call leaks 24 instances
# and, before this existed, still exited 0.
#
# cmd.exe owns the stderr redirect rather than PowerShell. PowerShell 5.1 turns a
# native command's stderr into ErrorRecords and writes *those* to the file, so
# the engine's text arrives wrapped in a NativeCommandError block.
function Invoke-GodotScript {
    param([string]$Godot, [string]$ProjectRoot, [string]$ScriptPath)

    $stderrFile = [System.IO.Path]::GetTempFileName()
    $command = '"{0}" --headless --path "{1}" --script {2} 2>"{3}"' `
        -f $Godot, $ProjectRoot, $ScriptPath, $stderrFile

    # Captured, not streamed. A PowerShell function returns *everything* it does
    # not capture, so letting the engine's stdout through would make this return
    # an array of output lines with the exit code buried at the end — and
    # `exit (Invoke-GodotScript ...)` would quietly become 0. Assigning also
    # keeps $LASTEXITCODE intact, which a pipeline would not.
    $stdout = & $env:ComSpec /c $command
    $exitCode = $LASTEXITCODE
    foreach ($line in $stdout) { Write-Host $line }

    $stderr = [System.IO.File]::ReadAllText($stderrFile)
    Remove-Item $stderrFile -Force -ErrorAction SilentlyContinue
    if ($stderr.Trim()) { Write-Host $stderr }

    if ($exitCode -ne 0) { return $exitCode }

    $leaks = [regex]::Matches(
        $stderr,
        '(?m)^.*(ObjectDB instances were leaked|resources still in use at exit).*$'
    )
    if ($leaks.Count -gt 0) {
        Write-Host ''
        Write-Host 'FAIL: the run passed, but leaked. Something did not release what it built:'
        foreach ($leak in $leaks) { Write-Host "  $($leak.Value.Trim())" }
        return 1
    }

    return $exitCode
}

# Imports assets if the engine cache is missing. Without this, a freshly cloned
# checkout has no global class-name cache, so `class_name` types such as
# LevelData are unresolved and every script fails to compile.
function Confirm-GodotImport {
    param([string]$Godot, [string]$ProjectRoot)

    if (Test-Path (Join-Path $ProjectRoot '.godot')) { return }

    Write-Host 'No .godot cache found; running a one-time import...' -ForegroundColor Yellow
    & $Godot --headless --path $ProjectRoot --import
    if ($LASTEXITCODE -ne 0) {
        throw "Godot import failed with exit code $LASTEXITCODE."
    }
}
