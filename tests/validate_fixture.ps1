$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$fixtureRoot = Join-Path $PSScriptRoot 'fixtures\minimal'
$testRoot = Join-Path $repoRoot '.test-artifacts\tests'
$projectDir = Join-Path $testRoot 'fixture'
$buildDir = Join-Path $projectDir 'custom-output'
$brokenBuildDir = Join-Path $testRoot 'broken-config'
$settingsPath = Join-Path $projectDir '.vscode\settings.json'
$originalOpenOCDDir = $env:OPENOCD_DIR
$resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
if (-not $resolvedTestRoot.StartsWith(([IO.Path]::GetFullPath($repoRoot).TrimEnd('\') + '\.test-artifacts\'), [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe cleanup path' }

function Invoke-Checked([string]$FilePath, [string[]]$Arguments) {
    $ErrorActionPreference = 'Continue'
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
    $mockOpenOCD = Join-Path $testRoot 'mock-openocd'
    New-Item -ItemType Directory -Path (Join-Path $mockOpenOCD 'bin'),(Join-Path $mockOpenOCD 'share\openocd\scripts\target') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $mockOpenOCD 'bin\openocd.exe'), '')
    [IO.File]::WriteAllText((Join-Path $mockOpenOCD 'share\openocd\scripts\target\stm32f4x.cfg'), '')
    $env:OPENOCD_DIR = $mockOpenOCD

    $initializer = Join-Path $repoRoot 'skill\scripts\init_stm32_project.ps1'
    $generator = Join-Path $projectDir 'cmake\generate_vscode.ps1'
    $cmake = (Get-Command cmake -ErrorAction Stop).Source
    $badSettings = Join-Path $projectDir '.vscode/settings.json'
    $ErrorActionPreference = 'Continue'
    $missingToolOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $initializer -ProjectDir $projectDir -OpenOCDDir (Join-Path $testRoot 'missing-openocd') 2>&1 | Out-String
    $ErrorActionPreference = 'Stop'
    Assert-True ($LASTEXITCODE -ne 0) 'A missing explicit tool directory must fail initialization.'
    Assert-True (-not (Test-Path $generator)) 'Missing explicit tool directory copied generator.'
    New-Item -ItemType Directory (Split-Path $badSettings) -Force | Out-Null
    [IO.File]::WriteAllText($badSettings, '{ broken')
    $originalCmake = [IO.File]::ReadAllText((Join-Path $projectDir 'CMakeLists.txt'))
    $ErrorActionPreference = 'Continue'
    $invalidOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $initializer -ProjectDir $projectDir 2>&1 | Out-String
    $ErrorActionPreference = 'Stop'
    Assert-True ($LASTEXITCODE -ne 0) 'Invalid JSON must fail initialization.'
    Assert-True ([IO.File]::ReadAllText((Join-Path $projectDir 'CMakeLists.txt')) -eq $originalCmake) 'Failed preflight changed CMakeLists.'
    Assert-True (-not (Test-Path $generator)) 'Failed preflight copied generator.'
    [IO.File]::WriteAllText($badSettings, '{"cmake.preferredGenerators":{"unexpected":true}}')
    $ErrorActionPreference = 'Continue'
    $invalidShapeOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $initializer -ProjectDir $projectDir 2>&1 | Out-String
    $ErrorActionPreference = 'Stop'
    Assert-True ($LASTEXITCODE -ne 0) 'Invalid settings field shape must fail initialization.'
    Assert-True ([IO.File]::ReadAllText((Join-Path $projectDir 'CMakeLists.txt')) -eq $originalCmake) 'Invalid settings shape changed CMakeLists.'
    Assert-True (-not (Test-Path $generator)) 'Invalid settings shape copied generator.'
    [IO.File]::WriteAllText($badSettings, '{"cmake.preferredGenerators":{"Length":5},"cmake.configureArgs":{"Length":26}}')
    $rollbackTemplates = Join-Path $testRoot 'rollback-templates'
    New-Item -ItemType Directory $rollbackTemplates -Force | Out-Null
    Copy-Item (Join-Path $repoRoot 'skill/scripts/*') $rollbackTemplates
    [IO.File]::WriteAllText((Join-Path $rollbackTemplates 'generate_vscode.ps1'), 'param([string]$ProjectDir, [switch]$ValidateOnly) if ($ValidateOnly) { exit 0 }; exit 7')
    $ErrorActionPreference = 'Continue'
    $rollbackOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $rollbackTemplates 'init_stm32_project.ps1') -ProjectDir $projectDir 2>&1 | Out-String
    $ErrorActionPreference = 'Stop'
    Assert-True ($LASTEXITCODE -ne 0) 'Injected generator failure must fail initialization.'
    Assert-True ([IO.File]::ReadAllText((Join-Path $projectDir 'CMakeLists.txt')) -eq $originalCmake) 'Rollback did not restore CMakeLists.'
    Assert-True (-not (Test-Path $generator)) 'Rollback left copied generator.'

    [IO.File]::WriteAllText((Join-Path $projectDir 'second.ioc'), "Mcu.CPN=STM32F407VET6`nMcu.Family=STM32F4`n")
    $ErrorActionPreference = 'Continue'
    $multiIocOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $initializer -ProjectDir $projectDir 2>&1 | Out-String
    $ErrorActionPreference = 'Stop'
    Assert-True ($LASTEXITCODE -ne 0) 'Multiple root-level IOC files must fail initialization.'
    Assert-True ([IO.File]::ReadAllText((Join-Path $projectDir 'CMakeLists.txt')) -eq $originalCmake) 'Multiple-IOC preflight changed CMakeLists.'
    Remove-Item -LiteralPath (Join-Path $projectDir 'second.ioc') -Force

    # The project lives below a directory named "tests" on purpose. The old
    # absolute-path regex incorrectly excluded every source in this layout.
    Write-Host '[fixture] initialize project'
    Invoke-Checked 'powershell.exe' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $initializer, '-ProjectDir', $projectDir) | Out-Null
    $repairedSettings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    Assert-True ($repairedSettings.'cmake.preferredGenerators' -is [array]) 'Initializer did not repair legacy preferredGenerators output.'
    Assert-True (@($repairedSettings.'cmake.preferredGenerators') -contains 'Ninja') 'Initializer repair lost the Ninja generator.'
    Assert-True ($repairedSettings.'cmake.configureArgs' -is [array]) 'Initializer did not repair legacy configureArgs output.'

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
      "executable": "${workspaceFolder}/build/Debug/qoder_fixture.elf",
      "preLaunchCommands": ["monitor reset halt", "set remotetimeout 25"]
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
    Assert-True ($amphi.executable -eq '${command:cmake.launchTargetPath}') 'AmphiLink executable does not follow the active CMake launch target.'
    Assert-True (@($amphi.preLaunchCommands) -contains 'set remotetimeout 25') 'AmphiLink custom GDB timeout was not preserved.'
    Assert-True (@($amphi.preLaunchCommands) -notcontains 'set remotetimeout 10') 'AmphiLink default timeout replaced a custom timeout.'
    $dap = @($launch.configurations | Where-Object { $_.name -eq 'STM32 Debug (DAPLink)' }) | Select-Object -First 1
    Assert-True (@($dap.preLaunchCommands) -contains 'set remotetimeout 10') 'Generic DAPLink configuration is missing the GDB timeout.'
    Assert-True (@($dap.searchDir).Count -eq 1) 'Generic DAPLink configuration is missing the OpenOCD script search directory.'
    Assert-True (([string]$dap.searchDir[0]) -match '/share/openocd/scripts$') 'Generic DAPLink OpenOCD search directory is invalid.'

    $launchPath = Join-Path $projectDir '.vscode\launch.json'
    $tasksPath = Join-Path $projectDir '.vscode\tasks.json'
    [IO.File]::WriteAllText($launchPath, $amphiLaunch, (New-Object System.Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($settingsPath, '{}', (New-Object System.Text.UTF8Encoding($false)))
    (Get-Item -LiteralPath $settingsPath).IsReadOnly = $true
    $launchBeforeFailure = [IO.File]::ReadAllBytes($launchPath)
    $tasksBeforeFailure = [IO.File]::ReadAllBytes($tasksPath)
    $ErrorActionPreference = 'Continue'
    $writeFailureOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $generator -ProjectDir $projectDir -ProjectName qoder_fixture -BuildDir $buildDir 2>&1 | Out-String
    $ErrorActionPreference = 'Stop'
    Assert-True ($LASTEXITCODE -ne 0) 'A managed JSON write failure must fail generation.'
    Assert-True ([Convert]::ToBase64String([IO.File]::ReadAllBytes($launchPath)) -eq [Convert]::ToBase64String($launchBeforeFailure)) 'Generator did not restore launch.json after a later write failure.'
    Assert-True ([Convert]::ToBase64String([IO.File]::ReadAllBytes($tasksPath)) -eq [Convert]::ToBase64String($tasksBeforeFailure)) 'Generator did not restore tasks.json after a later write failure.'
    (Get-Item -LiteralPath $settingsPath).IsReadOnly = $false
    Invoke-Checked 'powershell.exe' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $generator, '-ProjectDir', $projectDir, '-ProjectName', 'qoder_fixture', '-BuildDir', $buildDir) | Out-Null
    Invoke-Checked 'powershell.exe' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $generator, '-ProjectDir', $projectDir, '-ProjectName', 'qoder_fixture', '-BuildDir', $buildDir) | Out-Null
    $generatedSettings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    Assert-True ($generatedSettings.'cmake.preferredGenerators' -is [array]) 'cmake.preferredGenerators must remain a JSON array after repeated generation.'
    Assert-True (@($generatedSettings.'cmake.preferredGenerators') -contains 'Ninja') 'cmake.preferredGenerators lost Ninja.'
    Assert-True ($generatedSettings.'cmake.configureArgs' -is [array]) 'cmake.configureArgs must remain a JSON array after repeated generation.'
    $generatedTasks = Get-Content -LiteralPath $tasksPath -Raw | ConvertFrom-Json
    $cmakeTask = @($generatedTasks.tasks | Where-Object { $_.label -eq 'CMake Build' }) | Select-Object -First 1
    Assert-True ($cmakeTask.type -eq 'cmake') 'CMake Build must use the CMake Tools task provider.'
    Assert-True ($cmakeTask.command -eq 'build') 'CMake Build task command is invalid.'
    $generatedLaunch = Get-Content -LiteralPath $launchPath -Raw | ConvertFrom-Json
    $generatedDap = @($generatedLaunch.configurations | Where-Object { $_.name -eq 'STM32 Debug (DAPLink)' }) | Select-Object -First 1
    Assert-True ($generatedDap.executable -eq '${command:cmake.launchTargetPath}') 'DAPLink executable does not follow the active CMake launch target.'

    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $vsInstance = ''
    if (Test-Path -LiteralPath $vswhere) {
        $vsInstance = ([string](& $vswhere -latest -products '*' -version '[17.0,18.0)' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null | Select-Object -First 1)).Trim()
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
    $excludedBuildSource = Join-Path $buildDir 'generated-should-not-trigger.c'
    [IO.File]::WriteAllText($excludedBuildSource, 'this is intentionally not valid C')
    $quietBuildOutput = Invoke-Checked $cmake @('--build', $buildDir, '--config', 'Debug')
    Assert-True ($quietBuildOutput -notmatch 'GLOB mismatch') 'Files created under the excluded build tree triggered Configure.'
    $addedDir = Join-Path $projectDir 'Application/new_headers'
    New-Item -ItemType Directory $addedDir -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $addedDir 'added.h'), '#define ADDED_VALUE 7')
    [IO.File]::WriteAllText((Join-Path $projectDir 'Application/added.c'), "#include <added.h>`nint added_value(void) { return ADDED_VALUE; }")
    [IO.File]::AppendAllText((Join-Path $projectDir 'src/main.c'), "`nint added_value(void);`nint (*added_reference)(void) = added_value;`n")
    Invoke-Checked $cmake @('--build', $buildDir, '--config', 'Debug') | Out-Null
    [IO.File]::WriteAllText($launchPath, '{"version":"0.2.0","configurations":[]}')
    [IO.File]::AppendAllText((Join-Path $projectDir 'qoder_fixture.ioc'), "`n# reconfigure test`n")
    Invoke-Checked $cmake @('--build', $buildDir, '--config', 'Debug') | Out-Null
    Assert-True ((Get-Content $launchPath -Raw | ConvertFrom-Json).configurations.Count -gt 0) 'IOC edit did not rerun generator.'

    # A generator failure must stop Configure instead of leaving stale debug files.
    Write-Host '[fixture] verify configure blocks generator failure'
    [System.IO.File]::WriteAllText($generator, 'exit 7', (New-Object System.Text.UTF8Encoding($false)))
    $brokenArgs = @('-S', $projectDir, '-B', $brokenBuildDir) + ($configureArgs | Select-Object -Skip 4)
    $ErrorActionPreference = 'Continue'
    $brokenOutput = & $cmake @($brokenArgs) 2>&1 | Out-String
    $ErrorActionPreference = 'Stop'
    $brokenCode = $LASTEXITCODE
    Assert-True ($brokenCode -ne 0) 'CMake Configure unexpectedly succeeded after the .vscode generator failed.'
    Assert-True ($brokenOutput -match 'qoder \.vscode auto-generate failed') 'CMake output did not expose the qoder generator failure.'
} catch {
    $message = ($_.Exception.Message -replace '[\r\n]+', ' ')
    Write-Output "::error file=tests/validate_fixture.ps1,line=1::$message"
    throw
} finally {
    $env:OPENOCD_DIR = $originalOpenOCDDir
    if (Test-Path -LiteralPath $settingsPath) { (Get-Item -LiteralPath $settingsPath).IsReadOnly = $false }
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'STM32 skill fixture validation passed.'
exit 0
