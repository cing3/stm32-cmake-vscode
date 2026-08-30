<#
.SYNOPSIS
    STM32 新工程一键初始化（官方 ST 扩展链路 + ST-Link/DAPLink，零手动配置）
.DESCRIPTION
    CubeMX 生成 CMake 工程后，运行本脚本一次，自动完成：
      1. 生成 .vscode/launch.json   —— 官方 ST-Link（stlinkgdbtarget，固定模板）
                                          + DAPLink（cortex-debug/OpenOCD，芯片自动解析）
      2. 生成 .vscode/tasks.json    —— CMake Build（DAPLink 的 preLaunchTask 自动编译）
      3. 生成 .vscode/settings.json —— clangd --query-driver 指向 ARM 交叉编译器
      4. 向 CMakeLists.txt 注入两段：
         —— 内联「全层收集源文件」段（核心功能，不依赖外部模板目录，
         模板被移动/删除也照常编译，新增 C/C++/汇编源文件和头文件保存后 Build 自动收录）
         —— include(qoder_stm32_auto.cmake) 钩子（附加功能，每次 configure
         重新生成 .vscode，芯片改了也自动跟上）

    即「一次初始化，之后打开工程即全自动」：CubeMX 改了芯片/引脚重新生成后，
    只要顶层 CMakeLists.txt 不被覆盖（官方保证 generated only once），
    configure 时就会自动刷新 .vscode 的 device/svdFile/target.cfg。

    为什么保留 DAPLink：
      DAPLink 与 ST-Link 是不同硬件，走 cortex-debug + OpenOCD（cmsis-dap.cfg），
      与官方 stlinkserver(127.0.0.1:7184) 不冲突。只有「手动 cortex-debug 的
      ST-Link 链路」才与官方 stlinkserver 抢 USB 冲突，因此那一套被移除。
.USAGE
    powershell -ExecutionPolicy Bypass -File init_stm32_project.ps1 -ProjectDir "D:\xxx\工程目录"
    或直接把工程文件夹拖到本脚本图标上。
    或 -Register 注册右键菜单（以后右键工程文件夹一键初始化）。
#>
param(
    [string]$ProjectDir = "",
    [switch]$Register,
    [switch]$Unregister,
    [string]$BundleDir = "",
    [string]$CubeCLTDir = "",
    [string]$OpenOCDDir = ""
)

$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "STM32 工程初始化"

# 模板目录 = 本脚本自身所在目录（可移植：整个模板目录拷贝到任意位置均可工作）
# 初始化时会把生成器和钩子复制到工程自己的 cmake/ 目录，CMakeLists.txt 只引用
# 这个项目内的相对路径；移动模板目录不会使已初始化工程失效。
$TEMPLATE_DIR = $PSScriptRoot
if (-not $TEMPLATE_DIR) { $TEMPLATE_DIR = (Get-Location).Path }   # 兼容从管道/非文件方式调用
$GENERATOR    = Join-Path $TEMPLATE_DIR "generate_vscode.ps1"
$AUTO_CMAKE   = Join-Path $TEMPLATE_DIR "qoder_stm32_auto.cmake"

# ============ 右键菜单注册（可选，与核心逻辑无关） ============
if ($Register -or $Unregister) {
    $key = "HKCU:\Software\Classes\Directory\shell\InitSTM32Project"
    if ($Unregister) {
        if (Test-Path $key) { Remove-Item $key -Recurse -Force; Write-Host "已移除右键菜单项" }
        exit 0
    }
    $scriptPath = $MyInvocation.MyCommand.Path
    $cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -ProjectDir `"%V`""
    New-Item -Path $key -Force | Out-Null
    Set-Item -Path $key -Value "初始化 STM32 VSCode 工程"
    New-Item -Path "$key\command" -Force | Out-Null
    Set-Item -Path "$key\command" -Value $cmd
    Write-Host "右键菜单已注册：在工程文件夹上点右键 -> 初始化 STM32 VSCode 工程"
    exit 0
}

# ============ 定位工程根 ============
if (-not $ProjectDir) { $ProjectDir = (Get-Location).Path }
$ProjectDir = [System.IO.Path]::GetFullPath($ProjectDir)
if (-not (Test-Path $ProjectDir)) { Write-Host "错误：目录不存在 $ProjectDir" -ForegroundColor Red; exit 1 }

$iocFile = Get-ChildItem -Path $ProjectDir -Filter "*.ioc" -File | Select-Object -First 1
if (-not $iocFile) { Write-Host "错误：目录里没有 .ioc 文件（不是 STM32 工程根）" -ForegroundColor Red; exit 1 }
$cmakeFile = Join-Path $ProjectDir "CMakeLists.txt"
if (-not (Test-Path $cmakeFile)) { Write-Host "错误：目录里没有 CMakeLists.txt" -ForegroundColor Red; exit 1 }
$projectAutoCmake = Join-Path $ProjectDir "cmake\qoder_stm32_auto.cmake"
$projectGenerator = Join-Path $ProjectDir "cmake\generate_vscode.ps1"
$toolsManifest = Join-Path $ProjectDir "cmake\stm32-cmake-vscode-tools.json"
New-Item -ItemType Directory -Path (Split-Path $projectAutoCmake -Parent) -Force | Out-Null
Copy-Item -LiteralPath $AUTO_CMAKE -Destination $projectAutoCmake -Force
Copy-Item -LiteralPath $GENERATOR -Destination $projectGenerator -Force

if ($BundleDir -or $CubeCLTDir -or $OpenOCDDir) {
    $toolConfig = [ordered]@{}
    if (Test-Path $toolsManifest) {
        try {
            $oldToolConfig = Get-Content $toolsManifest -Raw | ConvertFrom-Json
            foreach ($property in $oldToolConfig.PSObject.Properties) { $toolConfig[$property.Name] = $property.Value }
        } catch { Write-Host "  [警告] 旧工具路径清单无法解析，将用新参数覆盖可用字段" -ForegroundColor Yellow }
    }
    if ($BundleDir)  { $toolConfig['BundleDir'] = [System.IO.Path]::GetFullPath($BundleDir) }
    if ($CubeCLTDir)  { $toolConfig['CubeCLTDir'] = [System.IO.Path]::GetFullPath($CubeCLTDir) }
    if ($OpenOCDDir)  { $toolConfig['OpenOCDDir'] = [System.IO.Path]::GetFullPath($OpenOCDDir) }
    [System.IO.File]::WriteAllText($toolsManifest, ($toolConfig | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "  [OK] 已保存项目工具路径清单（仅本机工程使用）" -ForegroundColor Green
}

Write-Host "== 工程: $ProjectDir" -ForegroundColor Cyan

# ============ 1. 注入/升级自动配置块（幂等） ============
# 用单引号 here-string（不插值），CMake 的 ${...} 原样保留；include 路径用占位符后替换。
$autoCmakePosix = '${CMAKE_SOURCE_DIR}/cmake/qoder_stm32_auto.cmake'
$injectBlock = @'
# ==================== QODER_AUTO_CONFIG ====================
# Reconfigure automatically when the CubeMX .ioc changes before the next build.
file(GLOB QODER_IOC_FILES CONFIGURE_DEPENDS "${CMAKE_SOURCE_DIR}/*.ioc")
foreach(_ioc IN LISTS QODER_IOC_FILES)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_ioc}")
endforeach()
# Collect user C/C++ and assembly sources recursively.
file(GLOB_RECURSE QODER_USER_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_SOURCE_DIR}/*.c"
    "${CMAKE_SOURCE_DIR}/*.cc"
    "${CMAKE_SOURCE_DIR}/*.cpp"
    "${CMAKE_SOURCE_DIR}/*.cxx"
    "${CMAKE_SOURCE_DIR}/*.s"
    "${CMAKE_SOURCE_DIR}/*.S"
    "${CMAKE_SOURCE_DIR}/*.asm"
)
list(FILTER QODER_USER_SOURCES EXCLUDE REGEX "/(Drivers|cmake|build[^/]*|CMakeFiles|Middlewares)/")
list(FILTER QODER_USER_SOURCES EXCLUDE REGEX "system_stm32.*\.c$")
set(QODER_USER_CXX_SOURCES "")
foreach(_src IN LISTS QODER_USER_SOURCES)
    get_filename_component(_ext "${_src}" EXT)
    if(_ext MATCHES "\\.(cc|cpp|cxx)$")
        list(APPEND QODER_USER_CXX_SOURCES "${_src}")
    endif()
endforeach()
if(QODER_USER_CXX_SOURCES)
    enable_language(CXX)
endif()
target_sources(${CMAKE_PROJECT_NAME} PRIVATE ${QODER_USER_SOURCES})

file(GLOB_RECURSE QODER_USER_HEADERS CONFIGURE_DEPENDS
    "${CMAKE_SOURCE_DIR}/*.h"
    "${CMAKE_SOURCE_DIR}/*.hh"
    "${CMAKE_SOURCE_DIR}/*.hpp"
    "${CMAKE_SOURCE_DIR}/*.hxx"
)
list(FILTER QODER_USER_HEADERS EXCLUDE REGEX "/(Drivers|cmake|build[^/]*|CMakeFiles|Middlewares)/")
set(QODER_USER_INCLUDE_DIRS "")
foreach(_hdr IN LISTS QODER_USER_HEADERS)
    get_filename_component(_dir "${_hdr}" DIRECTORY)
    list(APPEND QODER_USER_INCLUDE_DIRS "${_dir}")
endforeach()
list(REMOVE_DUPLICATES QODER_USER_INCLUDE_DIRS)
target_include_directories(${CMAKE_PROJECT_NAME} PRIVATE ${QODER_USER_INCLUDE_DIRS})

# [附加] .vscode 自动生成/刷新（依赖模板目录；缺失则静默跳过，不影响编译）
if(EXISTS "__QODER_AUTO_CMAKE__")
    include("__QODER_AUTO_CMAKE__")
endif()
# ==================== QODER_AUTO_CONFIG END ====================
'@
$injectBlock = $injectBlock.Replace("__QODER_AUTO_CMAKE__", $autoCmakePosix).Trim()

$cmakeText = Get-Content $cmakeFile -Raw
$blockPattern = '(?s)# ==================== QODER_AUTO_CONFIG ====================.*?# ==================== QODER_AUTO_CONFIG END ====================' 
if ($cmakeText -match $blockPattern) {
    # Replace the complete block so projects initialized by older skill
    # versions also receive the current source/header/IOC behavior.
    $cmakeText = [regex]::Replace($cmakeText, $blockPattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $injectBlock }, 1)
    [System.IO.File]::WriteAllText($cmakeFile, $cmakeText, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "  [OK] CMakeLists.txt 已升级自动配置块" -ForegroundColor Green
} elseif ($cmakeText -match "QODER_AUTO_CONFIG") {
    Write-Host "  [错误] CMakeLists.txt 含有不完整的 QODER_AUTO_CONFIG 标记，未追加新配置；请先人工检查该文件" -ForegroundColor Red
    exit 1
} else {
    [System.IO.File]::AppendAllText($cmakeFile, "`r`n$injectBlock`r`n", (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "  [OK] CMakeLists.txt 已注入：内联全层收集 + .vscode 自动生成钩子" -ForegroundColor Green
}

# ============ 2. 立即生成 .vscode（确保首次打开 VSCode 前 settings.json 就位） ============
Write-Host "  -- 立即生成 .vscode 配置 --"
$generatorArgs = @('-ProjectDir', $ProjectDir)
if ($BundleDir) { $generatorArgs += @('-BundleDir', $BundleDir) }
if ($CubeCLTDir) { $generatorArgs += @('-CubeCLTDir', $CubeCLTDir) }
if ($OpenOCDDir) { $generatorArgs += @('-OpenOCDDir', $OpenOCDDir) }
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $GENERATOR @generatorArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "  [错误] .vscode 生成失败（退出码 $LASTEXITCODE）" -ForegroundColor Red
} else {
    Write-Host "  [OK] .vscode 已就位" -ForegroundColor Green
}

# ============ 摘要 ============
Write-Host ""
Write-Host "================ 初始化完成 ================" -ForegroundColor Cyan
Write-Host "1. 用 VSCode 打开: $ProjectDir"
Write-Host "2. 等 ST 扩展自动 Configure（.vscode 已在，configure 会再刷新一次，幂等）"
Write-Host "3. ST-Link: Ctrl+Shift+D 选 'STM32Cube: Launch ST-Link GDB Server' -> F5"
Write-Host "   DAPLink: 选 'STM32 Debug (DAPLink)' -> F5（preLaunchTask 自动编译）"
Write-Host "4. 新文件放任意层（Application/Modules/src 等），保存后直接 Build，自动收录"
Write-Host ""
Write-Host "之后 CubeMX 改了芯片/引脚重新生成，直接打开 VSCode 即可："
Write-Host "configure 会自动刷新 .vscode 的芯片型号（device/svdFile/target.cfg）。"
Write-Host ""
