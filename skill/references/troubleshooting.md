# Troubleshooting

## Parse error in `cmake/stm32cubemx/CMakeLists.txt`

Set `cmake.modifyLists.addNewSourceFiles` and `cmake.modifyLists.removeDeletedSourceFiles` to `no`, reload the VS Code window, and let the top-level `CONFIGURE_DEPENDS` block collect user files. CMake Tools accepts `no`, `yes`, or `ask`; `never` is invalid. The CubeMX subproject should not be edited by CMake Tools.

## Save is disabled in AmphiLink CFG Tool

The extension requires an existing ELF, a target config, a selected device, and a complete debug environment. Build first and confirm the ELF path exists. A red ELF field or “Build the project to create the ELF first” is not a USB discovery failure.

## Wired device is visible but OpenOCD cannot find it

Confirm the device is `AmphiLink (CMSIS-DAP V2)` with VID/PID `303A:83B3`. Windows error code 28 means the USB driver is missing; install WinUSB for that exact device with Zadig and reconnect it. Do not replace drivers for unrelated ESP32 or serial devices.

## Configure cannot run the auto hook

Confirm the project contains `cmake/qoder_stm32_auto.cmake` and `cmake/generate_vscode.ps1`. If explicit tool paths were used, also confirm `cmake/stm32-cmake-vscode-tools.json` exists. Re-run the initializer to repair missing project-local copies. The hook must use `${CMAKE_CURRENT_LIST_DIR}/generate_vscode.ps1`, not a maintainer-specific absolute path.

## Build uses MinGW instead of ARM GCC

Use the project's `CMakePresets.json` or pass `-DCMAKE_TOOLCHAIN_FILE=cmake/gcc-arm-none-eabi.cmake` on a fresh build directory. The generated debug task follows `build/<CMAKE_BUILD_TYPE>`; if a custom preset uses another binary directory, update that preset convention before debugging. Do not diagnose Cortex-M assembler errors from a host compiler build as a source-collection failure.

## STM32Cube pack reports “No index file found”

This is normally an extension package-index/network issue and is separate from CMake syntax. Verify the project can Configure/Build with its existing device files before repairing the package cache.
