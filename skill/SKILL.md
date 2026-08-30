---
name: stm32-cmake-vscode
description: "Portable Windows workflow for STM32CubeMX CMake projects in VS Code: initialize a generated project with a right-click PowerShell script, auto-discover C/C++/assembly sources and headers, reconfigure after .ioc/CMake changes, preserve custom Cortex-Debug and AmphiLink configurations, and build/debug without hand-editing paths. Use when creating, migrating, configuring, building, or debugging STM32CubeMX CMake projects for developers who already have CubeMX installed."
---

# STM32CubeMX CMake + VS Code

Use the bundled PowerShell scripts in `scripts/` for deterministic project setup. Treat generated project files and user-owned VS Code entries as user data: preserve unknown configurations and stop on parse failures rather than overwriting them.

## Prerequisites

- Windows PowerShell and STM32CubeMX configured to generate a CMake project.
- VS Code with CMake Tools, Cortex-Debug, and Ninja. STM32Cube VS Code extensions are optional: when their `cube-cmake`/`cube` commands are unavailable, the scripts fall back to the normal CMake executable and leave standard clangd configuration untouched.
- ARM GNU toolchain and an OpenOCD build compatible with the selected probe.
- Optional AmphiLink CFG Tool for wired CMSIS-DAP (`303A:83B3`) or wireless debugging.

Keep installation locations outside the skill. The scripts discover common installs and accept portable overrides through `STM32_BUNDLE_DIR`, `STM32CLT_DIR`, and `OPENOCD_DIR`, or explicit parameters.

## Initialize a project

After CubeMX generates the CMake project, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\init_stm32_project.ps1 -ProjectDir "C:\path\to\project"
```

The initializer validates `.ioc` and `CMakeLists.txt`, copies the generator and CMake hook into the project's `cmake/` directory, injects an idempotent `QODER_AUTO_CONFIG` block, and creates `.vscode` files. Register the Windows Explorer action once with `-Register`; remove it with `-Unregister`.

For non-default tool locations, pass `-BundleDir`, `-CubeCLTDir`, or `-OpenOCDDir`, or set the matching environment variables before running the initializer. Never bake a maintainer's absolute path into a distributed skill.

## Expected automation

The injected CMake block uses `file(GLOB_RECURSE ... CONFIGURE_DEPENDS)` for user `.c`, `.cc`, `.cpp`, `.cxx`, `.s`, `.S`, and `.asm` files, derives include directories from `.h`, `.hh`, `.hpp`, and `.hxx` files, excludes generated and common test/example/tool trees, and registers the actual `.ioc` files as configure dependencies. Override the `QODER_SOURCE_EXCLUDE_DIRS` cache variable when a project needs a different policy. The next Build therefore rechecks new files and CubeMX changes. The hook invokes the project-local `generate_vscode.ps1` during Configure and passes the actual `CMAKE_BINARY_DIR`, so custom preset output directories remain aligned with the generated ELF path.

Global VS Code preferences should be set deliberately:

```jsonc
"cmake.configureOnOpen": true,
"cmake.configureOnEdit": true,
"cmake.modifyLists.addNewSourceFiles": "no",
"cmake.modifyLists.removeDeletedSourceFiles": "no"
```

Do not enable source-file auto-editing together with the recursive collection block; the two mechanisms race and can produce parser errors in CubeMX subprojects. CMake Tools uses `no`, `yes`, or `ask` for these settings; `never` is not a valid value.

## Generate and preserve debug configuration

`generate_vscode.ps1` maintains only the named ST-Link and DAPLink entries. It preserves AmphiLink CFG Tool and other custom `launch.json` entries, preserves unrelated tasks, and refuses to overwrite JSONC or malformed files. If tool discovery is incomplete, retain an existing complete DAPLink entry instead of replacing it with a partial one.

Use AmphiLink CFG Tool to select the wired device, verify the ELF and target config, then save the managed Cortex-Debug entry. The generated generic DAPLink entry is for ordinary CMSIS-DAP; AmphiLink requires the extension-managed `amphilink-cfg-openocd.cfg` entry with USB bulk and VID/PID settings. The ELF must exist before saving; build the project first when the extension shows "Build the project to create the ELF first".

## Verification sequence

1. Initialize a clean CubeMX CMake project.
2. Configure and build Debug with the project's ARM toolchain preset. The generator follows the active CMake binary directory, including custom preset output paths.
3. Add a harmless `.c`/`.h` pair and build again; verify the new object is listed without editing CMake manually.
4. Change a CubeMX setting, regenerate, then build; verify CMake re-runs Configure and the ELF links.
5. Launch ST-Link or AmphiLink Cortex-Debug, set a breakpoint in `main`, and verify Continue, Step Over, Restart, and a clean Stop.
6. For FreeRTOS, inspect `xTickCount` or `xTaskGetTickCount()` after the scheduler starts; disable the tick breakpoint afterward.

Do not flash firmware or install USB drivers automatically. Those are hardware-impacting operations and require explicit user confirmation. If a non-default tool directory is supplied, the initializer stores it in the project-local `cmake/stm32-cmake-vscode-tools.json` so later Configure runs use the same tools; keep that machine-specific file out of shared source control when appropriate. For troubleshooting, load [references/troubleshooting.md](references/troubleshooting.md); for portability and path policy, load [references/portable-setup.md](references/portable-setup.md).
