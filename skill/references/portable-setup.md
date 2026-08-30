# Portable Setup

The skill contains no project-specific paths. Keep all machine-dependent values in the caller's environment or command line:

```powershell
$env:STM32CLT_DIR = 'C:\tools\STM32CubeCLT'
$env:OPENOCD_DIR = 'C:\tools\openocd'
$env:STM32_BUNDLE_DIR = "$env:LOCALAPPDATA\stm32cube\bundles\gnu-tools-for-stm32"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\init_stm32_project.ps1 -ProjectDir 'C:\work\board'
```

`BundleDir` supplies the GNU bundle used by clangd. `CubeCLTDir` supplies GDB, SVD, and CMake for DAPLink. `OpenOCDDir` supplies `openocd.exe` and its scripts. The generator writes discovered paths into the target project's `.vscode` files; that is expected and local to the project.

If explicit `-BundleDir`, `-CubeCLTDir`, or `-OpenOCDDir` arguments are used, the initializer also writes `cmake/stm32-cmake-vscode-tools.json` in the project. This is a local machine-path manifest used by later Configure runs; do not commit it to a shared repository unless that is intentional.

The initializer copies both `qoder_stm32_auto.cmake` and `generate_vscode.ps1` into `<project>/cmake/`. This avoids a runtime dependency on the skill installation directory. Do not copy a project's `.vscode`, `.ioc`, build directory, device MAC, COM port, or personal user settings into the skill package.

The core workflow requires CMake Tools, Cortex-Debug, Ninja, an ARM GNU toolchain, and OpenOCD. The ST STM32 VS Code extensions (`stmicroelectronics.stm32-vscode-extension` and its build/clangd companions) are optional; the generator detects their `cube-cmake` and `cube` commands and falls back when they are absent. The hook invokes Windows PowerShell 5.1, so the bundled generator must remain compatible with that runtime.
