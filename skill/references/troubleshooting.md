# Troubleshooting

## Always operate on the project root

Run the initializer and open the folder that directly contains the project's `.ioc` and top-level `CMakeLists.txt`. Do not run it from `cmake/`, `cmake/stm32cubemx/`, `build/`, or a VS Code workspace that contains several projects. If the script reports that `.ioc` or `CMakeLists.txt` is missing, correct `-ProjectDir` first; do not create placeholder files.

## The project or Skill was moved

Moving an initialized project within the same computer is supported because the generator and CMake hook are copied into the project's `cmake/` directory and relative build paths use `${workspaceFolder}`. After moving it, open the new project root in VS Code and run Configure once so `.vscode/launch.json` is refreshed.

Moving the project to another computer requires the tools to be installed or supplied again with `-BundleDir`, `-CubeCLTDir`, and `-OpenOCDDir`, or the matching environment variables. The file `cmake/stm32-cmake-vscode-tools.json` contains machine-specific paths; remove it or overwrite it for the new computer, and do not commit it to a shared repository.

Moving the Skill repository itself does not break an already initialized project, but it does break a Windows Explorer action registered with `-Register`, because that registry entry stores the old script path. Run `-Unregister` and then `-Register` from the new Skill location.

## The wrong `.ioc` file is used

Keep exactly one main `.ioc` file in the project root. The scripts select the first root-level `.ioc` returned by the filesystem. If a project has several configurations, put secondary `.ioc` files in another directory or initialize each project separately; do not rely on selection order.

## VS Code configuration is not regenerated

The generator writes pure JSON and deliberately leaves JSONC or malformed `launch.json`, `tasks.json`, and `settings.json` untouched. If a file contains comments or has invalid JSON, back it up, convert it to valid JSON or fix the syntax, then run Configure again. The generator preserves unknown debug entries, including AmphiLink entries, so do not delete the entire file unless you intend to recreate all custom entries.

For AmphiLink entries, Configure also restores `preLaunchTask: CMake Build` and `preLaunchCommands: ["set remotetimeout 10"]` when the extension-created entry does not contain them. The extension may replace its managed entry when Save is clicked; run Configure once after that save so the workflow fields are restored.

## Parse error in `cmake/stm32cubemx/CMakeLists.txt`

Set `cmake.modifyLists.addNewSourceFiles` and `cmake.modifyLists.removeDeletedSourceFiles` to `no`, reload the VS Code window, and let the top-level `CONFIGURE_DEPENDS` block collect user files. CMake Tools accepts `no`, `yes`, or `ask`; `never` is invalid. The CubeMX subproject should not be edited by CMake Tools.

## Save is disabled in AmphiLink CFG Tool

The extension requires an existing ELF, a target config, a selected device, and a complete debug environment. Build first and confirm the ELF path exists. A red ELF field or “Build the project to create the ELF first” is not a USB discovery failure.

## Wired device is visible but OpenOCD cannot find it

Confirm the device is `AmphiLink (CMSIS-DAP V2)` with VID/PID `303A:83B3`. Windows error code 28 means the USB driver is missing; install WinUSB for that exact device with Zadig and reconnect it. Do not replace drivers for unrelated ESP32 or serial devices.

## Configure cannot run the auto hook

Confirm the project contains `cmake/qoder_stm32_auto.cmake` and `cmake/generate_vscode.ps1`. If explicit tool paths were used, also confirm `cmake/stm32-cmake-vscode-tools.json` exists. Re-run the initializer to repair missing project-local copies; Configure intentionally stops when the hook is missing. The hook must use `${CMAKE_CURRENT_LIST_DIR}/generate_vscode.ps1`, not a maintainer-specific absolute path.

If Configure reports `qoder .vscode auto-generate failed`, read the captured stdout/stderr in the CMake output. Configure intentionally stops in this case so an old ELF/debug path cannot be mistaken for a current configuration. Fix the local generator/tool/JSON issue, then Configure again.

## Build uses MinGW instead of ARM GCC

Use the project's `CMakePresets.json` or pass `-DCMAKE_TOOLCHAIN_FILE=cmake/gcc-arm-none-eabi.cmake` on a fresh build directory. The generated debug task follows CMake's actual binary directory, including custom presets. If the ELF path is still stale after changing a preset's `binaryDir`, re-run Configure to refresh `.vscode`. Do not diagnose Cortex-M assembler errors from a host compiler build as a source-collection failure.

## An unrelated test or example source is being compiled

Automatic discovery excludes common `tests`, `examples`, and `tools` directory names by exact, case-insensitive path component relative to the project root. A parent folder outside the project with one of those names is not excluded. Add project-specific names with `-DQODER_SOURCE_EXCLUDE_DIRS="..."` in the configure preset, or provide the complete replacement list when a default exclusion is intentional.

## Wireless GDB reports keep-alive warnings

The generated DAPLink and AmphiLink entries send `set remotetimeout 10` before launch. This allows a wireless CMSIS-DAP link to spend longer on a reset or register operation before GDB reports an idle timeout. It does not repair a device-side TCP disconnect; for `CMSIS-DAP: connection closed by peer`, check the AmphiLink device state, network reachability, and whether another debug client is connected.

## STM32Cube pack reports “No index file found”

This is normally an extension package-index/network issue and is separate from CMake syntax. Verify the project can Configure/Build with its existing device files before repairing the package cache.
