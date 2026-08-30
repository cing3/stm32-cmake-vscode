# Changelog

All notable changes to this project are documented here.

## [1.1.0] - 2026-08-30

### Added

- Follow the active CMake binary directory for custom presets and output layouts.
- Configurable source-discovery exclusions, including common test/example/tool trees.
- GitHub Actions validation for skill structure, PowerShell syntax, and path hygiene.

### Fixed

- Clarified custom build-directory behavior and automatic source-discovery boundaries.

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
