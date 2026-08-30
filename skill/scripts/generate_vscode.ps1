<#
.SYNOPSIS
    STM32 工程 .vscode 配置生成器（核心，纯生成逻辑）
.DESCRIPTION
    输入工程目录，解析 .ioc 芯片型号，生成 .vscode 全套配置：
      - launch.json   —— 官方 ST-Link（stlinkgdbtarget）+ DAPLink（cortex-debug/OpenOCD）双链路
      - tasks.json    —— CMake Build（供 DAPLink 的 preLaunchTask 自动编译）
      - settings.json —— clangd --query-driver 指向 ARM 交叉编译器（修复缺头文件）

    本脚本既可由 init_stm32_project.ps1 手动调用，也可由 CMake configure 阶段
    （qoder_stm32_auto.cmake 的 execute_process）自动调用，实现「打开工程即自动生成」。

    幂等：生成内容与磁盘一致时不重写，避免 VSCode 反复弹 reload。
.PARAMETER ProjectDir
    工程根目录（含 .ioc 与 CMakeLists.txt）。
.PARAMETER ProjectName
    CMake 工程名（= elf 文件名，顶层 CMakeLists 的 CMAKE_PROJECT_NAME）。
    由 CMake configure 调用时传入，最精确；手动调用时可省略，自动解析或回退目录名。
.EXAMPLE
    powershell -File generate_vscode.ps1 -ProjectDir "D:\my_project"
    powershell -File generate_vscode.ps1 -ProjectDir "D:\my_project" -ProjectName "my_project"
#>
param(
    [Parameter(Mandatory=$true)][string]$ProjectDir,
    [string]$ProjectName = "",
    [string]$BuildDir    = "build/Debug",
    [string]$BundleDir   = "",   # 可选：显式指定 ST 官方 bundle 工具链目录（clangd --query-driver 用）
    [string]$CubeCLTDir  = "",   # 可选：显式指定 STM32CubeCLT 安装目录（DAPLink 的 gdb/SVD/cmake 用）
    [string]$OpenOCDDir  = ""    # 可选：显式指定 OpenOCD 根目录（DAPLink 用，须含 bin\openocd.exe）
)

$ErrorActionPreference = "Stop"

function ConvertTo-HashtableCompat($InputObject) {
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in $InputObject.Keys) { $result[$key] = ConvertTo-HashtableCompat $InputObject[$key] }
        return $result
    }
    if ($InputObject -is [pscustomobject]) {
        $result = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $result[$property.Name] = ConvertTo-HashtableCompat $property.Value
        }
        return $result
    }
    if (($InputObject -is [System.Collections.IEnumerable]) -and -not ($InputObject -is [string])) {
        return @($InputObject | ForEach-Object { ConvertTo-HashtableCompat $_ })
    }
    return $InputObject
}

function Get-VersionSortKey([string]$Name) {
    $match = [regex]::Match($Name, '(?<!\d)\d+(?:\.\d+){1,3}(?!\d)')
    if ($match.Success) {
        try { return [version]$match.Value } catch { }
    }
    return [version]'0.0'
}

$BuildDir = ($BuildDir -replace "\\", "/").Trim("/ ")
if (-not $BuildDir) { $BuildDir = "build/Debug" }
# CMake hooks pass the actual CMAKE_BINARY_DIR, which may be absolute for
# custom presets. Manual invocations can continue using workspace-relative paths.
if ([System.IO.Path]::IsPathRooted($BuildDir)) {
    $buildPath = $BuildDir
} else {
    $buildPath = '${workspaceFolder}/' + $BuildDir
}

# ============ 定位工程根 ============
$ProjectDir = [System.IO.Path]::GetFullPath($ProjectDir)
if (-not (Test-Path $ProjectDir)) { Write-Host "[错误] 目录不存在: $ProjectDir" -ForegroundColor Red; exit 1 }

$toolsManifest = Join-Path $ProjectDir "cmake\stm32-cmake-vscode-tools.json"
$manifest = $null
if (Test-Path $toolsManifest) {
    try { $manifest = Get-Content $toolsManifest -Raw | ConvertFrom-Json } catch {
        Write-Host "  [警告] 工具路径清单无法解析，忽略项目清单并继续探测" -ForegroundColor Yellow
    }
}

$iocFile = Get-ChildItem -Path $ProjectDir -Filter "*.ioc" -File | Select-Object -First 1
if (-not $iocFile) { Write-Host "[错误] 目录里没有 .ioc（不是 STM32 工程根）" -ForegroundColor Red; exit 1 }

# ============ 解析芯片型号（.ioc） ============
$iocText = Get-Content $iocFile.FullName -Raw
$cpn = ""      # 完整商业料号，如 STM32F103C8T6
$family = ""   # 系列，如 STM32F1
if ($iocText -match '(?m)^Mcu\.CPN=(.+)$')     { $cpn = $Matches[1].Trim() }
if ($iocText -match '(?m)^Mcu\.Family=(.+)$')  { $family = $Matches[1].Trim() }

# 工程名：优先用传入参数，其次解析 CMakeLists 的 CMAKE_PROJECT_NAME，最后回退目录名
if (-not $ProjectName) {
    $cmakeFile = Join-Path $ProjectDir "CMakeLists.txt"
    if (Test-Path $cmakeFile) {
        $cmakeText = Get-Content $cmakeFile -Raw
        if ($cmakeText -match 'set\s*\(\s*CMAKE_PROJECT_NAME\s+(\S+)\s*\)') { $ProjectName = $Matches[1] }
    }
}
if (-not $ProjectName) { $ProjectName = Split-Path $ProjectDir -Leaf }

Write-Host "== 工程: $ProjectDir"
Write-Host "== 芯片: CPN=$cpn  Family=$family  工程名=$ProjectName"

# ============ 探测工具链路径 ============
# 优先级：命令行参数 > 环境变量（STM32_BUNDLE_DIR / STM32CLT_DIR / OPENOCD_DIR）
# > 项目工具路径清单（cmake/stm32-cmake-vscode-tools.json）> 常见安装位点
# 自动取最新版本，无需写死版本号。
#
# 链路依赖说明：
#   - 官方 ST-Link 链路：零手动依赖 —— 编译/调试工具由 stm32-vscode-extension 自动安装到
#     %LOCALAPPDATA%\stm32cube\bundles\（仅此一处是官方指定位点，无法靠环境变量重定向）。
#   - DAPLink 链路：需要 CubeCLT（arm-none-eabi-gdb + SVD + cmake）与 OpenOCD。
#     缺任一工具不会报错，会在 launch.json 中省略对应字段并打印提示。

# 1) bundle gcc —— 供 clangd --query-driver（官方链路的编译工具链）
$bundleGcc = ""
$bundleRoot = ""
if ($BundleDir) { $bundleRoot = $BundleDir }
elseif ($env:STM32_BUNDLE_DIR) { $bundleRoot = $env:STM32_BUNDLE_DIR }
elseif ($manifest -and $manifest.BundleDir) { $bundleRoot = [string]$manifest.BundleDir }
elseif ($env:LOCALAPPDATA) { $bundleRoot = Join-Path $env:LOCALAPPDATA "stm32cube\bundles\gnu-tools-for-stm32" }
if ($bundleRoot -and (Test-Path $bundleRoot)) {
    $directGcc = Get-ChildItem (Join-Path $bundleRoot "bin\arm-none-eabi-gcc*") -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $rootGcc = Get-ChildItem (Join-Path $bundleRoot "arm-none-eabi-gcc*") -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($directGcc) {
        $bundleGcc = $bundleRoot
    } elseif ($rootGcc) {
        $bundleGcc = Split-Path $bundleRoot -Parent
    } else {
        $bundleCandidates = Get-ChildItem $bundleRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { Get-ChildItem (Join-Path $_.FullName "bin\arm-none-eabi-gcc*") -File -ErrorAction SilentlyContinue } |
            Sort-Object @{Expression={ Get-VersionSortKey $_.Name }; Descending=$true}, Name -Descending
        $selectedBundle = $bundleCandidates | Select-Object -First 1
        if ($selectedBundle) { $bundleGcc = $selectedBundle.FullName }
    }
}
if (-not $bundleGcc -and $bundleRoot -and (Test-Path $bundleRoot)) { $bundleGcc = $bundleRoot }

# 2) CubeCLT —— 供 DAPLink 链路（arm-none-eabi-gdb、SVD、cmake.exe）
$cltVer = ""
if ($CubeCLTDir) {
    $cltVer = $CubeCLTDir
} elseif ($env:STM32CLT_DIR) {
    $cltVer = $env:STM32CLT_DIR
} elseif ($manifest -and $manifest.CubeCLTDir) {
    $cltVer = [string]$manifest.CubeCLTDir
} else {
    $cltCandidates = @(
        "C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeCLT_*",
        "C:\ST\STM32CubeCLT_*",
        "C:\Program Files (x86)\STMicroelectronics\STM32Cube\STM32CubeCLT_*"
    )
    foreach ($cand in $cltCandidates) {
        $hit = Get-ChildItem $cand -Directory -ErrorAction SilentlyContinue |
            Sort-Object @{Expression={ Get-VersionSortKey $_.Name }; Descending=$true}, Name -Descending | Select-Object -First 1
        if ($hit) { $cltVer = $hit.FullName; break }
    }
}
if (-not $cltVer) { Write-Host "  [提示] 未找到 STM32CubeCLT —— 可用 -CubeCLTDir 参数或 STM32CLT_DIR 环境变量指定" -ForegroundColor DarkYellow }

$armToolchainPath = ""
$svdDir = ""
$cmakeExe = ""
if ($cltVer -and (Test-Path $cltVer)) {
    $armToolchainPath = (Join-Path $cltVer "GNU-tools-for-STM32\bin") -replace "\\", "/"
    $svdDir = Join-Path $cltVer "STMicroelectronics_CMSIS_SVD"
    $cmakeExe = (Join-Path $cltVer "CMake\bin\cmake.exe") -replace "\\", "/"
}
if (-not $cmakeExe) { $cmakeExe = "cmake" }   # 回退到 PATH 中的 cmake
$cubeCmakeCommand = Get-Command cube-cmake -ErrorAction SilentlyContinue
$cubeCommand = Get-Command cube -ErrorAction SilentlyContinue
$hasCubeCmake = $null -ne $cubeCmakeCommand
$hasCubeClangd = $null -ne $cubeCommand
$cmakeSetting = if ($hasCubeCmake) { "cube-cmake" } elseif ($cmakeExe -ne "cmake") { $cmakeExe } else { "cmake" }

# 3) OpenOCD —— DAPLink 用（根目录须含 bin\openocd.exe；scripts 目录多候选自动定位）
$openocdPath = ""
$openocdScripts = ""
$openocdRoot = ""
if ($OpenOCDDir) { $openocdRoot = $OpenOCDDir }
elseif ($env:OPENOCD_DIR) { $openocdRoot = $env:OPENOCD_DIR }
elseif ($manifest -and $manifest.OpenOCDDir) { $openocdRoot = [string]$manifest.OpenOCDDir }
else {
    $ocExe = (Get-Command openocd -ErrorAction SilentlyContinue).Source
    if ($ocExe) { $openocdRoot = Split-Path (Split-Path $ocExe -Parent) -Parent }   # openocd.exe -> bin -> 根
}
if ($openocdRoot -and (Test-Path $openocdRoot)) {
    $exeCand = @(
        (Join-Path $openocdRoot "bin\openocd.exe"),
        (Join-Path $openocdRoot "openocd\bin\openocd.exe")
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($exeCand) {
        $openocdPath = $exeCand -replace "\\", "/"
        $scriptCand = @(
            (Join-Path $openocdRoot "openocd\scripts"),          # 官方 Windows zip 结构：{bin, openocd/scripts}
            (Join-Path $openocdRoot "openocd\openocd\scripts"),  # 旧版/嵌套结构
            (Join-Path $openocdRoot "share\openocd\scripts"),    # gnu-mcu-eclipse / zephyr 风格
            (Join-Path $openocdRoot "scripts")                   # 源码直接解压结构
        ) | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($scriptCand) { $openocdScripts = $scriptCand }
    }
}
if (-not $openocdPath) { Write-Host "  [提示] 未找到 OpenOCD —— DAPLink 链路将不完整（可用 -OpenOCDDir 参数或 OPENOCD_DIR 环境变量指定）" -ForegroundColor DarkYellow }

# ============ 推导 DAPLink 芯片相关字段 ============
# device: CPN 去末尾 2 字符（封装+温度），如 STM32F103C8T6 -> STM32F103C8
$device = ""
if ($cpn -and $cpn.Length -gt 2) { $device = $cpn.Substring(0, $cpn.Length - 2) }

# svdFile: 在 SVD 目录贪心匹配 CPN 前缀（从长到短）
$svdFile = ""
if ($cpn -and $svdDir -and (Test-Path $svdDir)) {
    $prefix = $cpn
    while ($prefix.Length -ge 3 -and -not $svdFile) {
        $cand = Join-Path $svdDir "$prefix.svd"
        if (Test-Path $cand) { $svdFile = $cand -replace "\\", "/" }
        else { $prefix = $prefix.Substring(0, $prefix.Length - 1) }
    }
}

# OpenOCD target cfg: 家族级命名规则 STM32F1 -> stm32f1x.cfg（家族小写 + "x.cfg"）
$targetCfg = ""
if ($family -and $openocdScripts -and (Test-Path $openocdScripts)) {
    $targetDir = Join-Path $openocdScripts "target"
    $famLow = $family.ToLower()
    $exactName = "${famLow}x.cfg"
    if (Test-Path (Join-Path $targetDir $exactName)) {
        $targetCfg = "target/$exactName"
    } else {
        # 回退：前缀 glob（少数家族无统一 x.cfg 时）
        $match = Get-ChildItem $targetDir -Filter "$famLow*.cfg" -File -ErrorAction SilentlyContinue |
            Sort-Object Name | Select-Object -First 1
        if ($match) { $targetCfg = "target/$($match.Name)" }
    }
}

# DAPLink configFiles：cmsis-dap 接口 + 目标芯片 cfg（target 为空则不添加）
$cfgFiles = @('interface/cmsis-dap.cfg')
if ($targetCfg) { $cfgFiles += $targetCfg }

Write-Host "== DAPLink: device=$device  svd=$svdFile  target=$targetCfg"
if (-not $targetCfg) { Write-Host "  [警告] 未能匹配 OpenOCD target cfg（Family=$family）" -ForegroundColor Yellow }
if (-not $svdFile)    { Write-Host "  [提示] 未匹配到 SVD（寄存器视图将缺失，调试不受影响）" -ForegroundColor DarkYellow }

# ============ 生成 .vscode ============
$vsDir = Join-Path $ProjectDir ".vscode"
New-Item -ItemType Directory -Path $vsDir -Force | Out-Null

# --- launch.json：官方 ST-Link + DAPLink 双链路 ---
$configs = @()

$official = [ordered]@{
    type     = 'stlinkgdbtarget'
    request  = 'launch'
    name     = 'STM32Cube: Launch ST-Link GDB Server'
    cwd      = '${workspaceFolder}'
    preBuild = '${command:st-stm32-ide-debug-launch.build}'
    runEntry = 'main'
    imagesAndSymbols = @(
        [ordered]@{ imageFileName = '${command:st-stm32-ide-debug-launch.get-projects-binary-from-context1}' }
    )
}
$configs += $official

$dap = [ordered]@{
    name        = 'STM32 Debug (DAPLink)'
    type        = 'cortex-debug'
    request     = 'launch'
    servertype  = 'openocd'
    cwd         = '${workspaceFolder}'
    executable  = $buildPath + '/' + $ProjectName + '.elf'
    runToEntryPoint = 'main'
    preLaunchTask   = 'CMake Build'
    configFiles = $cfgFiles
}
if ($device)           { $dap['device'] = $device }
if ($svdFile)          { $dap['svdFile'] = $svdFile }
if ($armToolchainPath) { $dap['armToolchainPath'] = $armToolchainPath }
if ($openocdPath)      { $dap['serverpath'] = $openocdPath }
$configs += $dap
$dapIncomplete = (-not $openocdPath) -or (-not $svdFile) -or (-not $device)

# Merge only configurations owned by this generator. Unknown entries (including
# AmphiLink CFG Tool entries) are preserved across every CMake configure.
$launchPath = Join-Path $vsDir "launch.json"
$launchObj = $null
$launchCanWrite = $true
if (Test-Path $launchPath) {
    try { $launchObj = Get-Content $launchPath -Raw | ConvertFrom-Json } catch {
        $launchCanWrite = $false
        Write-Host "  [警告] launch.json 不是可解析的纯 JSON，保留原文件，不覆盖用户配置" -ForegroundColor Yellow
    }
}
if ($launchCanWrite) {
    if (-not $launchObj) { $launchObj = [pscustomobject]@{ version = '0.2.0'; configurations = @() } }
    $existingConfigs = @($launchObj.configurations)
    $managedNames = @('STM32Cube: Launch ST-Link GDB Server', 'STM32 Debug (DAPLink)')
    $keptConfigs = @($existingConfigs | Where-Object { $_.name -notin $managedNames })
    if ($dapIncomplete) {
        $oldDap = $existingConfigs | Where-Object { $_.name -eq 'STM32 Debug (DAPLink)' } | Select-Object -First 1
        if ($oldDap -and ($oldDap.serverpath -or $oldDap.openocdPath) -and $oldDap.executable) { $configs = @($official, $oldDap) }
    }
    $launchObj.version = '0.2.0'
    $launchObj.configurations = @($configs) + $keptConfigs
    $launchJson = $launchObj | ConvertTo-Json -Depth 20
} else { $launchJson = $null }

# --- tasks.json：CMake Build（DAPLink preLaunchTask 依赖） ---
$tasksObj = [ordered]@{
    version = '2.0.0'
    tasks = @(
        [ordered]@{
            label   = 'CMake Build'
            # Process tasks pass the executable and arguments separately, so
            # CubeCLT installs under paths such as "C:\Program Files\..."
            # remain valid without shell quoting rules.
            type    = 'process'
            command = $cmakeExe
            args    = @('--build', $buildPath)
            group   = [ordered]@{ kind = 'build'; isDefault = $true }
            problemMatcher = '$gcc'
        }
    )
}
$tasksPath = Join-Path $vsDir "tasks.json"
$tasksJson = $null
if (Test-Path $tasksPath) {
    try {
        $oldTasksObj = Get-Content $tasksPath -Raw | ConvertFrom-Json
        $oldTaskList = @($oldTasksObj.tasks | Where-Object { $_.label -ne 'CMake Build' })
        $oldTasksObj.version = '2.0.0'
        $oldTasksObj.tasks = @($tasksObj.tasks) + $oldTaskList
        $tasksJson = $oldTasksObj | ConvertTo-Json -Depth 20
    } catch {
        Write-Host "  [警告] tasks.json 不是可解析的纯 JSON，保留原文件，不覆盖用户任务" -ForegroundColor Yellow
        $tasksJson = $null
    }
}
if (-not (Test-Path $tasksPath)) { $tasksJson = $tasksObj | ConvertTo-Json -Depth 20 }

# --- settings.json：clangd query-driver（合并已有内容，不覆盖） ---
$settingsPath = Join-Path $vsDir "settings.json"
$settingsObj = @{}
$settingsCanWrite = $true
if (Test-Path $settingsPath) {
    try { $settingsObj = ConvertTo-HashtableCompat (Get-Content $settingsPath -Raw | ConvertFrom-Json) } catch {
        $settingsCanWrite = $false
        Write-Host "  [警告] settings.json 不是可解析的纯 JSON，保留原文件，不覆盖用户设置" -ForegroundColor Yellow
    }
}
if (-not $settingsObj.ContainsKey("cmake.cmakePath") -or (($settingsObj["cmake.cmakePath"] -eq "cube-cmake") -and -not $hasCubeCmake)) {
    $settingsObj["cmake.cmakePath"] = $cmakeSetting
}
if (-not $settingsObj.ContainsKey("cmake.configureArgs")) {
    $settingsObj["cmake.configureArgs"] = if ($hasCubeCmake) { @("-DCMAKE_COMMAND=cube-cmake") } else { @() }
} elseif (-not $hasCubeCmake) {
    $settingsObj["cmake.configureArgs"] = @($settingsObj["cmake.configureArgs"] | Where-Object { $_ -ne "-DCMAKE_COMMAND=cube-cmake" })
}
if (-not $settingsObj.ContainsKey("cmake.preferredGenerators")) { $settingsObj["cmake.preferredGenerators"] = @("Ninja") }
$settingsObj["cmake.configureOnOpen"] = $true
$settingsObj["cmake.configureOnEdit"] = $true
$settingsObj["cmake.modifyLists.addNewSourceFiles"] = "no"
$settingsObj["cmake.modifyLists.removeDeletedSourceFiles"] = "no"
if ($hasCubeClangd) {
    $settingsObj["stm32cube-ide-clangd.path"] = "cube"
    if ($bundleGcc) {
        $bundleGcc = $bundleGcc -replace "\\", "/"
        $gccDriver = "$bundleGcc/bin/arm-none-eabi-gcc*"
        $gxxDriver = "$bundleGcc/bin/arm-none-eabi-g++*"
        $settingsObj["stm32cube-ide-clangd.arguments"] = @("starm-clangd", "--query-driver=$gccDriver", "--query-driver=$gxxDriver")
    } else {
        $settingsObj["stm32cube-ide-clangd.arguments"] = @("starm-clangd")
    }
} elseif (-not $settingsObj.ContainsKey("stm32cube-ide-clangd.path")) {
    Write-Host "  [提示] 未找到 STM32 专用 clangd 命令，保留普通 clangd/编辑器默认配置" -ForegroundColor DarkYellow
}
$settingsJson = if ($settingsCanWrite) { $settingsObj | ConvertTo-Json -Depth 10 } else { $null }

# ============ 幂等写入（内容不变不重写，避免 VSCode reload 抖动） ============
function Write-IfChanged([string]$path, [string]$content) {
    $content = $content.TrimEnd() + "`r`n"
    if (Test-Path $path) {
        $existing = Get-Content $path -Raw
        if ($existing.TrimEnd() -eq $content.TrimEnd()) {
            Write-Host "  [SKIP] $(Split-Path $path -Leaf)（内容未变）" -ForegroundColor DarkGray
            return
        }
    }
    [System.IO.File]::WriteAllText($path, $content, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "  [OK] $(Split-Path $path -Leaf)" -ForegroundColor Green
}

if ($launchJson) { Write-IfChanged $launchPath $launchJson }

# --- tasks.json 同样防退化：CubeCLT 缺失时 cmake 回退为 PATH 查找，保留已有绝对路径 ---
$tasksPath = Join-Path $vsDir "tasks.json"
if (($cmakeExe -eq "cmake") -and (Test-Path $tasksPath)) {
    $oldTasks = Get-Content $tasksPath -Raw
    $oldTask = $null
    try { $oldTask = ($oldTasks | ConvertFrom-Json).tasks | Where-Object { $_.label -eq 'CMake Build' } } catch { $oldTask = $null }
    if ($oldTask -and $oldTask.command -and ($oldTask.command -ne "cmake")) {
        Write-Host "  [SKIP] tasks.json（本次缺 CubeCLT 探测，保留已有绝对路径 cmake）" -ForegroundColor DarkYellow
        $tasksJson = $null
    }
}
if ($tasksJson) { Write-IfChanged $tasksPath $tasksJson }

if ($settingsJson) { Write-IfChanged (Join-Path $vsDir "settings.json") $settingsJson }

Write-Host "== 完成：launch.json(官方ST-Link + DAPLink) / tasks.json / settings.json(clangd)"
