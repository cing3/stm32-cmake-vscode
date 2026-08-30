# STM32 CMake + VS Code Skill

A portable Codex skill for developers who use STM32CubeMX and want a low-friction CMake + VS Code workflow with Cortex-Debug and optional AmphiLink CFG Tool support.

## Features

- Automatic CMake project generation from STM32CubeMX `.ioc` files
- Seamless VS Code integration with Cortex-Debug
- Optional AmphiLink CFG Tool support
- Fallback to standard CMake when STM32-specific VS Code extensions are unavailable
- Auto-detection of new C/C++/assembly files

## Workflow

1. Generate a CMake project in STM32CubeMX
2. Run `scripts/init_stm32_project.ps1` once (optionally with `-Register` for Windows Explorer integration)
3. Open the project in VS Code
4. Build or press F5 - new files are detected automatically
5. For AmphiLink: use AmphiLink CFG Tool to save USB-bulk managed Cortex-Debug entry after ELF exists

## Installation

### Prerequisites

- STM32CubeMX
- CMake
- VS Code with Cortex-Debug extension (optional)
- PowerShell 5.1+

### Setup

1. Download the latest release from [Releases](https://github.com/YOUR_USERNAME/stm32-cmake-vscode/releases)
2. Extract the skill directory to your preferred location
3. Follow the usage instructions in the skill documentation

## Usage

```powershell
# Initialize a new STM32 project
.\scripts\init_stm32_project.ps1

# With Windows Explorer integration
.\scripts\init_stm32_project.ps1 -Register
```

## Documentation

- [Portable Setup Guide](skill/references/portable-setup.md)
- [Troubleshooting](skill/references/troubleshooting.md)

## Validation

The scripts pass PowerShell parsing and the skill passes validation tests. The automation has been tested against STM32H7 CubeMX projects with:

- ARM GCC toolchain
- FreeRTOS
- Assembly startup files
- Source auto-collection
- CubeMX reconfigure
- Cortex-Debug sessions

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- STM32CubeMX for project generation
- CMake for build system
- VS Code and Cortex-Debug for development environment