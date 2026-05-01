$ErrorActionPreference = 'Stop'

$packageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$installScript = Join-Path $packageRoot 'tools\chocolateyinstall.ps1'

function Invoke-PrereqValidation {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FakeVersion
    )

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("empirica-choco-prereq-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempRoot | Out-Null

    try {
        $fakePython = Join-Path $tempRoot 'python.cmd'
        @"
@echo off
echo $FakeVersion
"@ | Set-Content -Path $fakePython -Encoding ASCII

        $oldValidateOnly = $env:EMPIRICA_CHOCO_VALIDATE_ONLY
        $oldTestPythonExe = $env:EMPIRICA_CHOCO_TEST_PYTHON_EXE
        $env:EMPIRICA_CHOCO_VALIDATE_ONLY = '1'
        $env:EMPIRICA_CHOCO_TEST_PYTHON_EXE = $fakePython

        try {
            & $installScript 2>&1
        } finally {
            if ($null -eq $oldValidateOnly) {
                Remove-Item Env:\EMPIRICA_CHOCO_VALIDATE_ONLY -ErrorAction SilentlyContinue
            } else {
                $env:EMPIRICA_CHOCO_VALIDATE_ONLY = $oldValidateOnly
            }
            if ($null -eq $oldTestPythonExe) {
                Remove-Item Env:\EMPIRICA_CHOCO_TEST_PYTHON_EXE -ErrorAction SilentlyContinue
            } else {
                $env:EMPIRICA_CHOCO_TEST_PYTHON_EXE = $oldTestPythonExe
            }
        }
    } finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

try {
    Invoke-PrereqValidation -FakeVersion 'Python 3.12.10' | Out-Null
} catch {
    throw "Expected Python 3.12 prereq validation to pass. Error: $($_.Exception.Message)"
}

$failed = $false
try {
    Invoke-PrereqValidation -FakeVersion 'Python 3.14.4' | Out-Null
} catch {
    $failed = $_.Exception.Message -match 'Python 3\.12 is required'
}

if (-not $failed) {
    throw "Expected non-3.12 Python prereq validation to fail with a clear Python 3.12 requirement."
}

Write-Host "Chocolatey Python prerequisite validation tests passed."
