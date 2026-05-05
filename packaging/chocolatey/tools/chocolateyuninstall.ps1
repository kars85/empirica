# Chocolatey Uninstall Script for Empirica

$ErrorActionPreference = 'Stop'

$packageName = 'empirica'

Write-Host "Uninstalling Empirica..." -ForegroundColor Cyan

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
            return @{
                Exe = $cmd.Source
                PipPrefixArgs = $candidate.PipPrefixArgs
                Version = $version
            }
        }
    }

    Write-Warning "Python 3.12 was not found. Empirica may already be removed or Python 3.12 may have been uninstalled."
    return $null
}

$pythonInfo = Get-EmpiricaPython
if (-not $pythonInfo) {
    return
}

Write-Host "Found: $($pythonInfo.Version) at $($pythonInfo.Exe)" -ForegroundColor Green

# Uninstall via pip
$pipArgs = @($pythonInfo.PipPrefixArgs) + @(
    '-m', 'pip',
    'uninstall',
    '-y',
    'empirica'
)

$exitCode = Start-ChocolateyProcessAsAdmin `
    -Statements ($pipArgs -join ' ') `
    -ExeToRun $pythonInfo.Exe `
    -ValidExitCodes @(0) `
    -WorkingDirectory $env:TEMP

if ($exitCode -eq 0) {
    Write-Host "Empirica uninstalled successfully!" -ForegroundColor Green
} else {
    Write-Warning "Uninstallation may have failed with exit code: $exitCode"
}
