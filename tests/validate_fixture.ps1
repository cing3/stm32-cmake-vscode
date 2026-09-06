$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$fixtureRoot = Join-Path $PSScriptRoot 'fixtures\minimal'
$testRoot = Join-Path $repoRoot '.test-artifacts\tests'
$projectDir = Join-Path $testRoot 'fixture'
$buildDir = Join-Path $testRoot 'build'
$brokenBuildDir = Join-Path $testRoot 'broken-config'

function Invoke-Checked([string]$FilePath, [string[]]$Arguments) {
    $output = & $FilePath @Arguments 2>&1 | Out-String
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        throw "Command failed ($code): $FilePath $($Arguments -join ' ')`n$output"
    }
    return $output
}

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

try {
    Write-Host '[fixture] prepare project'
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    Copy-Item -LiteralPath $fixtureRoot -Destination $projectDir -Recurse -Force

    $initializer = Join-Path $repoRoot 'skill\scripts\init_stm32_project.ps1'
    $generator = Join-Path $projectDir 'cmake\generate_vscode.ps1'
    $cmake = (Get-Command cmake -ErrorAction Stop).Source

    # The project lives below a directory named "tests" on purpose. The old
    # absolute-path regex incorrectly excluded every source in this layout.
    Write-Host '[fixture] initialize project'
    Invoke-Checked 'powershell.exe' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $initializer, '-ProjectDir', $projectDir) | Out-Null

    $amphiLaunch = @'
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "AmphiLink CFG: fixture",
      "type": "cortex-debug",
      "request": "launch",
      "servertype": "openocd",
      "configFiles": ["${workspaceFolder}/.vscode/amphilink-cfg-openocd.cfg"],
      "executable": "${workspaceFolder}/build/Debug/qoder_fixture.elf"
    }
  ]
}
'@
    [System.IO.File]::WriteAllText((Join-Path $projectDir '.vscode\launch.json'), $amphiLaunch, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host '[fixture] harden launch.json'
    Invoke-Checked 'powershell.exe' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $generator, '-ProjectDir', $projectDir, '-ProjectName', 'qoder_fixture', '-BuildDir', $buildDir) | Out-Null

    $launch = Get-Content -LiteralPath (Join-Path $projectDir '.vscode\launch.json') -Raw | ConvertFrom-Json
    $amphi = @($launch.configurations | Where-Object { $_.name -like 'AmphiLink*' }) | Select-Object -First 1
    Assert-True ($null -ne $amphi) 'AmphiLink configuration was not preserved.'
    Assert-True ($amphi.preLaunchTask -eq 'CMake Build') 'AmphiLink configuration is missing preLaunchTask.'
    Assert-True (@($amphi.preLaunchCommands) -contains 'set remotetimeout 10') 'AmphiLink configuration is missing the wireless GDB timeout.'
    $dap = @($launch.configurations | Where-Object { $_.name -eq 'STM32 Debug (DAPLink)' }) | Select-Object -First 1
    Assert-True (@($dap.preLaunchCommands) -contains 'set remotetimeout 10') 'Generic DAPLink configuration is missing the GDB timeout.'

    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $vsInstance = ''
    if (Test-Path -LiteralPath $vswhere) {
        $vsInstance = ((& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null | Select-Object -First 1) -as [string]).Trim()
    }
    $compiler = @(
        (Get-Command gcc.exe -ErrorAction SilentlyContinue),
        (Get-Command clang.exe -ErrorAction SilentlyContinue),
        (Get-Command clang-cl.exe -ErrorAction SilentlyContinue)
    ) | Where-Object { $_ } | Select-Object -First 1
    $vsUsable = $vsInstance -and (Test-Path -LiteralPath (Join-Path $vsInstance 'Common7\IDE\devenv.exe'))
    if ((Get-Command ninja -ErrorAction SilentlyContinue) -and $compiler) {
        $compilerPath = $compiler.Source -replace '\\', '/'
        $configureArgs = @('-S', $projectDir, '-B', $buildDir, '-G', 'Ninja', "-DCMAKE_C_COMPILER=$compilerPath")
    } elseif ($vsUsable) {
        $configureArgs = @('-S', $projectDir, '-B', $buildDir, '-G', 'Visual Studio 17 2022', '-A', 'x64')
    } else {
        throw 'No supported CMake generator/compiler found (Visual Studio with C++ tools, or Ninja with GCC/Clang).'
    }
    Write-Host '[fixture] configure and build'
    Invoke-Checked $cmake $configureArgs | Out-Null
    Invoke-Checked $cmake @('--build', $buildDir, '--config', 'Debug') | Out-Null

    # A generator failure must stop Configure instead of leaving stale debug files.
    Write-Host '[fixture] verify configure blocks generator failure'
    [System.IO.File]::WriteAllText($generator, 'exit 7', (New-Object System.Text.UTF8Encoding($false)))
    $brokenArgs = @('-S', $projectDir, '-B', $brokenBuildDir) + ($configureArgs | Select-Object -Skip 4)
    $brokenOutput = & $cmake @($brokenArgs) 2>&1 | Out-String
    $brokenCode = $LASTEXITCODE
    Assert-True ($brokenCode -ne 0) 'CMake Configure unexpectedly succeeded after the .vscode generator failed.'
    Assert-True ($brokenOutput -match 'qoder \.vscode auto-generate failed') 'CMake output did not expose the qoder generator failure.'
} catch {
    $message = ($_.Exception.Message -replace '[\r\n]+', ' ')
    Write-Output "::error file=tests/validate_fixture.ps1,line=1::$message"
    throw
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'STM32 skill fixture validation passed.'
