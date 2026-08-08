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
