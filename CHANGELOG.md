# Changelog

All notable changes to this project are documented here.

## [1.0.0] - 2026-08-30

### Added

- Portable STM32CubeMX CMake + VS Code skill.
- PowerShell project initializer with optional Windows Explorer integration.
- Automatic C/C++/assembly source and header discovery.
- Automatic `.ioc`-triggered CMake reconfiguration.
- Cortex-Debug/OpenOCD and optional AmphiLink workflow documentation.
- Fallback behavior when STM32-specific VS Code extensions are unavailable.

### Fixed

- Corrected CMake Tools source-list settings to avoid parser races.
- Added PowerShell 5.1 compatibility and project-local tool path manifests.
- Preserved user-owned debug configurations and handled Debug/Release build paths.
