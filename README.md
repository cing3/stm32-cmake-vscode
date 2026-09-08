# STM32 CMake + VS Code Skill

A portable Codex skill for developers who already use STM32CubeMX and want a low-friction CMake + VS Code workflow with automatic source discovery, Cortex-Debug, and optional AmphiLink CFG Tool support.

## What It Does

CubeMX remains responsible for creating and regenerating the CMake project. This skill initializes that generated project once, then keeps VS Code and CMake configuration synchronized:

- Right-click or run one PowerShell script to initialize a project.
- Automatically collect new C/C++/assembly sources and header include directories while excluding the active build directory, generated trees, and common test/example/tool trees.
- Reconfigure when the `.ioc` file or CMake inputs change.
- Generate ST-Link and generic CMSIS-DAP debug entries while preserving and hardening custom AmphiLink entries.
- Fall back to ordinary CMake and clangd when STM32-specific VS Code extensions are unavailable.

The default source exclusions can be customized through the CMake cache variable `QODER_SOURCE_EXCLUDE_DIRS`.

## Requirements

- Windows PowerShell 5.1 or newer
- STM32CubeMX configured to generate a CMake project
- VS Code with CMake Tools, Ninja, and Cortex-Debug
- ARM GNU toolchain and OpenOCD compatible with the target probe
- Optional: STM32Cube VS Code extensions for the `cube-cmake`/`cube` tools
- Optional: AmphiLink CFG Tool for AmphiLink hardware

## Install

The skill root is the `skill` directory. Use that directory when installing or importing the skill into Codex.

You can either clone this repository or download the latest `.skill` file from [Releases](https://github.com/cing3/stm32-cmake-vscode/releases/latest).

## Use

After creating the CMake project in CubeMX, run this from the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\skill\scripts\init_stm32_project.ps1 -ProjectDir "D:\work\my-stm32-project"
```

To register the Windows Explorer action once:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\skill\scripts\init_stm32_project.ps1 -Register
```

Explicit `-BundleDir`, `-CubeCLTDir`, and `-OpenOCDDir` values supplied with `-Register` are saved in the Explorer command and passed to every initialized project. Environment variables remain the better choice when the tool locations are shared by several shells and editors.

Then open the CubeMX project in VS Code and configure/build normally. The generated debug entry follows CMake's actual binary directory, including custom preset output paths.

For AmphiLink, build the ELF first, select the device in AmphiLink CFG Tool, and save its managed Cortex-Debug configuration. AmphiLink CFG Tool 1.1.0 replaces its complete launch entry when Save is clicked, so run CMake Configure once after an AmphiLink Save. Configure makes the entry follow the active CMake launch target and restores the `CMake Build` pre-launch task and default 10-second GDB remote timeout. The generic DAPLink entry is intended for ordinary CMSIS-DAP probes.

When troubleshooting, operate on the project root containing the `.ioc` and top-level `CMakeLists.txt`. Moving a project requires one Configure; moving the Skill installation requires `-Unregister` followed by `-Register`. Cross-computer moves require refreshing tool paths, and a project root should contain only one main `.ioc`. See [Troubleshooting](skill/references/troubleshooting.md) for recovery steps when VS Code JSON files are malformed or use JSONC comments.

## Documentation

- [Skill instructions](skill/SKILL.md)
- [Portable setup](skill/references/portable-setup.md)
- [Troubleshooting](skill/references/troubleshooting.md)

## Safety

The scripts do not flash firmware or install USB drivers automatically. Machine-specific tool paths are kept in the target project's `cmake/stm32-cmake-vscode-tools.json`; do not commit that file to shared projects.

## Validation

The scripts pass PowerShell 5.1 parsing and the skill passes the Codex skill validator. GitHub Actions repeats the structural, syntax, and path-hygiene checks and runs a Windows CMake fixture that initializes, configures, builds, checks AmphiLink launch hardening, validates malformed/multiple-input failures and rollback, verifies exact source-directory exclusions and custom output directories, and asserts that generator failures stop Configure. The automation has been exercised against STM32H7 projects with ARM GCC, FreeRTOS, assembly startup files, automatic source collection, CubeMX reconfiguration, and Debug/Release presets.

## License

MIT. See [LICENSE](LICENSE).
