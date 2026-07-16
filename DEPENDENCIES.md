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
- The authoritative catalog database is `CANJoystickDownloadTool/data/production_data.db`.
  Start the matching DownloadTool once before publishing a completed product so it can create or
  migrate the database. The editor validates the schema version and never creates or alters it.
- `CANJOYSTICK_DATABASE_PATH` and `CANJOYSTICK_DATA_DIR` can explicitly select that authoritative
  database. Without an override, the editor probes canonical `data/production_data.db` candidates
  and skips stale or legacy databases.
- Manual CAN-mapping drafts are saved as JSON only. They are not published to the production
  catalog and cannot overwrite a released product configuration.
- It does not vendor `firmware/`, `tools/openocd/`, or `libs/controlcan/`.
- Build directories, Qt Creator user files, QML caches, and generated SQLite driver copies remain ignored local output.
