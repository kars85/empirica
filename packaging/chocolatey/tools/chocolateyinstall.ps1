# Chocolatey Install Script for Empirica
# Documentation: https://docs.chocolatey.org/en-us/create/create-packages

$ErrorActionPreference = 'Stop'

$packageName = 'empirica'
$packageVersion = '1.8.20'

Write-Host "Installing Empirica $packageVersion..." -ForegroundColor Cyan

function Get-EmpiricaPython {
    if ($env:EMPIRICA_CHOCO_TEST_PYTHON_EXE) {
        $candidates = @(
            @{ Exe = $env:EMPIRICA_CHOCO_TEST_PYTHON_EXE; VersionArgs = @('--version'); PipPrefixArgs = @() }
        )
    } else {
        $candidates = @(
            @{ Exe = 'py'; VersionArgs = @('-3.12', '--version'); PipPrefixArgs = @('-3.12') },
            @{ Exe = 'C:\Python312\python.exe'; VersionArgs = @('--version'); PipPrefixArgs = @() },
            @{ Exe = 'python'; VersionArgs = @('--version'); PipPrefixArgs = @() }
        )
    }

    foreach ($candidate in $candidates) {
        $cmd = Get-Command $candidate.Exe -ErrorAction SilentlyContinue
        if (-not $cmd) {
            continue
        }

        try {
            $version = & $cmd.Source @($candidate.VersionArgs) 2>&1
        } catch {
            continue
        }

        if ($version -match 'Python 3\.12\.') {
            $scriptsPath = Split-Path -Parent $cmd.Source
            if ($candidate.PipPrefixArgs.Count -gt 0) {
                $scriptsPath = 'C:\Python312\Scripts'
            } elseif ($cmd.Source -match '\\python(?:\.exe)?$') {
                $scriptsPath = Join-Path (Split-Path -Parent $cmd.Source) 'Scripts'
            }

            return @{
                Exe = $cmd.Source
                PipPrefixArgs = $candidate.PipPrefixArgs
                Version = $version
                ScriptsPath = $scriptsPath
            }
        }
    }

    throw @"
Python 3.12 is required for the Chocolatey Empirica package.
Expected Chocolatey dependency: python312 3.12.10.
No usable Python 3.12 interpreter was found via 'py -3.12', 'C:\Python312\python.exe', or 'python'.
"@
}

$pythonInfo = Get-EmpiricaPython
Write-Host "Found: $($pythonInfo.Version) at $($pythonInfo.Exe)" -ForegroundColor Green

if ($env:EMPIRICA_CHOCO_VALIDATE_ONLY -eq '1') {
    Write-Host "Python prerequisite validation completed." -ForegroundColor Green
    return
}

# Install via pip
Write-Host "Installing Empirica via pip..." -ForegroundColor Cyan
$pipArgs = @($pythonInfo.PipPrefixArgs) + @(
    '-m', 'pip',
    'install',
    '--upgrade',
    '--disable-pip-version-check',
    "empirica==$packageVersion"
)

$exitCode = Start-ChocolateyProcessAsAdmin `
    -Statements ($pipArgs -join ' ') `
    -ExeToRun $pythonInfo.Exe `
    -ValidExitCodes @(0) `
    -WorkingDirectory $env:TEMP

if ($exitCode -eq 0) {
    $empiricaExe = Join-Path $pythonInfo.ScriptsPath 'empirica.exe'
    if (Test-Path $empiricaExe) {
        Install-BinFile -Name 'empirica' -Path $empiricaExe
    } else {
        Write-Warning "Empirica CLI was installed, but '$empiricaExe' was not found for Chocolatey shim creation."
    }

    Write-Host "Empirica installed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Quick Start:" -ForegroundColor Cyan
    Write-Host "  empirica bootstrap --ai-id myagent --level extended"
    Write-Host "  empirica --help"
    Write-Host ""
    Write-Host "Documentation: https://github.com/nubaeon/empirica" -ForegroundColor Cyan
} else {
    throw "Installation failed with exit code: $exitCode"
}
