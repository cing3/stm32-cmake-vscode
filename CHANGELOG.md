# Changelog

All notable changes to this project are documented here.

## [Unreleased]

### Added

- Windows CMake fixture validation covering initialization, source discovery, build, AmphiLink launch hardening, and generator-failure handling.

### Fixed

- Initialization now rejects zero or multiple root-level `.ioc` files instead of selecting an arbitrary file.
- Existing VS Code JSON files now receive file-specific shape validation before any project files are changed.
- Repeated Configure runs no longer turn scalar settings into `{ "Length": ... }` objects or collapse one-element JSON arrays.
- The VS Code generator restores its managed JSON files if a caught write failure occurs partway through generation.
- Existing user-defined `set remotetimeout` commands are preserved.
- Explorer registration now preserves explicitly supplied tool-directory overrides and rejects missing directories.
- Repeated generation now preserves JSON arrays in `settings.json` and repairs array fields corrupted by older generator output.
- Debug tasks and Cortex-Debug ELF selection now follow the active CMake preset instead of the most recently configured directory.
- Initialization rollback now reports any managed files that could not be restored.
- Source discovery now skips excluded directory trees during traversal, preventing build outputs from causing false `GLOB mismatch` reconfiguration.
- Generic DAPLink configurations now include the discovered OpenOCD script search directory.
- Invalid project paths, explicit tool directories, manifest field types, and non-object task/debug entries now fail before generation.
- AmphiLink Cortex-Debug entries now receive an automatic `CMake Build` pre-launch task and a 10-second wireless GDB timeout during Configure.
- Source exclusions now compare exact relative directory components instead of an absolute-path regular expression.
- Initialization and Configure now stop visibly when `.vscode` generation fails, preventing stale debug configurations from being used.
- Initialized projects now stop Configure if the project-local automation hook itself is missing.

## [1.1.1] - 2026-08-30

### Added

- Documented project-root selection, project and Skill relocation, cross-computer tool-path refresh, multiple `.ioc` handling, and JSONC recovery.

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
