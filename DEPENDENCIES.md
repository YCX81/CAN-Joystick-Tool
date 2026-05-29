# CANJoystickTool Dependencies

This editor intentionally has no local production database, firmware assets, ControlCAN dependency, or bundled OpenOCD runtime.

## Required local toolchain

- Qt 6.7.2 MinGW 64-bit, or another Qt 6.5+ MinGW kit with `Quick`, `QuickControls2`, `Widgets`, and `Sql`.
- CMake 3.16+ and Ninja.
- MinGW 11.2 64-bit for the Qt application.

The project copies Qt's SQLite driver from the active Qt kit after build:

```cmake
plugins/sqldrivers/qsqlite.dll
```

That copied DLL belongs in `build/`, not in the source tree.

## Data boundary

- The editor reads and writes product JSON files selected by the user.
- It does not own `downloadrecord/production_data.db`.
- It does not vendor `firmware/`, `tools/openocd/`, or `libs/controlcan/`.
- Build directories, Qt Creator user files, QML caches, and generated SQLite driver copies remain ignored local output.
