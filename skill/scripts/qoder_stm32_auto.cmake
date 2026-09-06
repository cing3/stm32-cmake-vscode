# =============================================================================
# qoder_stm32_auto.cmake  —— 附加功能：.vscode 自动生成/刷新
#   Injected by init_stm32_project.ps1 into the top-level CMakeLists.txt.
#   核心的「全层收集源文件」已内联进工程 CMakeLists.txt（不依赖本文件），
#   本文件只负责在每次 configure 时从 .ioc 重新生成 .vscode
#   （CubeMX 改了芯片/引脚后，打开工程自动跟上）。
#   初始化后的工程如果丢失本文件，会由 CMakeLists.txt 明确阻断 Configure，
#   避免在缺少 .vscode 自动刷新时继续使用过期调试路径。
#
#   可移植性：用 ${CMAKE_CURRENT_LIST_DIR} 定位本文件所在目录（= 模板目录），
#   因此本文件随模板目录整体拷贝到任意位置均能正常工作，无需改路径。
#   CubeMX 默认单配置预设使用 build/<presetName>；这里把该目录传给生成器，
#   使 Debug/Release 的 ELF 和 DAPLink 预启动构建保持一致。
# =============================================================================
execute_process(
    # Use CMake's actual binary directory so custom presets and multi-config
    # layouts do not force the generated debug entry into build/Debug.
    COMMAND "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe" -NoProfile -ExecutionPolicy Bypass -File
        "${CMAKE_CURRENT_LIST_DIR}/generate_vscode.ps1"
        -ProjectDir "${CMAKE_SOURCE_DIR}"
        -ProjectName "${CMAKE_PROJECT_NAME}"
        -BuildDir "${CMAKE_BINARY_DIR}"
    RESULT_VARIABLE QODER_GEN_RC
    OUTPUT_VARIABLE QODER_GEN_OUT
    ERROR_VARIABLE QODER_GEN_ERR
)
if(NOT QODER_GEN_RC EQUAL 0)
    message(FATAL_ERROR "qoder .vscode auto-generate failed (rc=${QODER_GEN_RC}). Configure stopped so a stale debug configuration cannot be used. stdout=${QODER_GEN_OUT} stderr=${QODER_GEN_ERR}")
endif()
