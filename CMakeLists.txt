cmake_minimum_required(VERSION 3.16)

project(CANJoystickTool VERSION 0.4.13 LANGUAGES CXX)

include(CTest)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Quick QuickControls2 Widgets Sql Network)

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(CANJoystickTool
    main.cpp
    LayoutManager.h
    LayoutManager.cpp
    ProductConfigV3Validator.h
    ProductConfigV3Validator.cpp
)

qt_add_resources(CANJoystickTool "app_icon"
    PREFIX "/"
    FILES
        assets/app_icon.png
)

# 标记 Singleton QML 文件（必须在 qt_add_qml_module 之前）
set_source_files_properties(CANJoystickTool/Constants.qml
    PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
set_source_files_properties(CANJoystickTool/ComponentRegistry.qml
    PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
set_source_files_properties(CANJoystickTool/CardTemplateManager.qml
    PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(CANJoystickTool
    URI CANJoystickTool
    VERSION 0.4.1
    RESOURCE_PREFIX /qt/qml
    SOURCES
        LayoutManager.h
        LayoutManager.cpp
    QML_FILES
        # Singleton 组件
        CANJoystickTool/Constants.qml
        CANJoystickTool/ComponentRegistry.qml
        CANJoystickTool/CardTemplateManager.qml
        CANJoystickTool/FnrMapping.js
        # 基础组件
        CANJoystickTool/AluminumPanel.qml
        CANJoystickTool/AxisValueBar.qml
        CANJoystickTool/DirectoryFontLoader.qml
        CANJoystickTool/EventListModel.qml
        CANJoystickTool/EventListSimulator.qml
        CANJoystickTool/JoystickPad.qml
        CANJoystickTool/StatusIndicator.qml
        CANJoystickTool/RollerWheel.qml
        CANJoystickTool/RotaryPotentiometer.qml
        CANJoystickTool/MiniJoystick.qml
        CANJoystickTool/DigitalDisplay.qml
        CANJoystickTool/RockerSwitch.qml
        CANJoystickTool/IndustrialButton.qml
        CANJoystickTool/ToolCard.qml
        CANJoystickTool/SectionHeader.qml
        CANJoystickTool/StatusDot.qml
        CANJoystickTool/CompactButton.qml
        # 复合单元组件
        CANJoystickTool/FNRSwitchUnit.qml
        CANJoystickTool/VerticalRollerUnit.qml
        CANJoystickTool/HorizontalRollerUnit.qml
        CANJoystickTool/RotaryPotentiometerUnit.qml
        CANJoystickTool/MiniJoystickUnit.qml
        CANJoystickTool/HorizontalFNRUnit.qml
        CANJoystickTool/HorizontalFNRRightUnit.qml
        # 可视化编辑组件
        CANJoystickTool/DraggableWrapper.qml
        CANJoystickTool/DesignCanvas.qml
        CANJoystickTool/ComponentPanel.qml
        # 内容页面
        CANJoystickToolContent/App.qml
        CANJoystickToolContent/XYAxisCard.qml
        CANJoystickToolContent/RollersCard.qml
        CANJoystickToolContent/HandleCard.qml
        CANJoystickToolContent/CustomCard.qml
        CANJoystickToolContent/ProductConfigV3EditorAdapter.js
        CANJoystickToolContent/ProductEditor.qml
    RESOURCES
        qtquickcontrols2.conf
)

target_link_libraries(CANJoystickTool PRIVATE
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Widgets
    Qt6::Sql
    Qt6::Network
)

if(WIN32)
    get_target_property(QT_QMAKE_EXECUTABLE Qt6::qmake IMPORTED_LOCATION)
    get_filename_component(QT_BIN_DIR "${QT_QMAKE_EXECUTABLE}" DIRECTORY)
    get_filename_component(QT_PREFIX_DIR "${QT_BIN_DIR}" DIRECTORY)
    get_filename_component(CXX_RUNTIME_DIR "${CMAKE_CXX_COMPILER}" DIRECTORY)
    set(QT_SQLITE_DRIVER "${QT_PREFIX_DIR}/plugins/sqldrivers/qsqlite.dll")
    set(WINDEPLOYQT_EXECUTABLE "${QT_BIN_DIR}/windeployqt.exe")
endif()

function(add_qt_runtime_test test_name target_name)
    if(WIN32)
        add_test(NAME ${test_name}
            COMMAND "${CMAKE_COMMAND}" -E env
                "PATH=${QT_BIN_DIR};${CXX_RUNTIME_DIR};$ENV{PATH}"
                "QT_PLUGIN_PATH=${QT_PREFIX_DIR}/plugins"
                "$<TARGET_FILE:${target_name}>" ${ARGN})
    else()
        add_test(NAME ${test_name} COMMAND "$<TARGET_FILE:${target_name}>" ${ARGN})
    endif()
endfunction()

if(BUILD_TESTING)
    add_executable(product_config_builder_smoke
        tests/product_config_builder_smoke.cpp
        LayoutManager.h
        LayoutManager.cpp
        ProductConfigV3Validator.h
        ProductConfigV3Validator.cpp
    )
    target_include_directories(product_config_builder_smoke PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
    target_link_libraries(product_config_builder_smoke PRIVATE
        Qt6::Quick
        Qt6::QuickControls2
        Qt6::Widgets
        Qt6::Sql
        Qt6::Network
    )
    add_qt_runtime_test(product_config_builder_smoke product_config_builder_smoke)

    add_executable(catalog_active_hydration_smoke
        tests/catalog_active_hydration_smoke.cpp
        LayoutManager.h
        LayoutManager.cpp
        ProductConfigV3Validator.h
        ProductConfigV3Validator.cpp
    )
    target_include_directories(catalog_active_hydration_smoke PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
    target_link_libraries(catalog_active_hydration_smoke PRIVATE
        Qt6::Quick
        Qt6::QuickControls2
        Qt6::Widgets
        Qt6::Sql
        Qt6::Network
    )
    add_qt_runtime_test(catalog_active_hydration_smoke catalog_active_hydration_smoke)

    add_executable(layoutmanager_database_smoke
        tests/layoutmanager_database_smoke.cpp
        LayoutManager.h
        LayoutManager.cpp
        ProductConfigV3Validator.h
        ProductConfigV3Validator.cpp
    )
    target_include_directories(layoutmanager_database_smoke PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
    target_link_libraries(layoutmanager_database_smoke PRIVATE
        Qt6::Quick
        Qt6::QuickControls2
        Qt6::Widgets
        Qt6::Sql
        Qt6::Network
    )
    add_qt_runtime_test(layoutmanager_database_smoke layoutmanager_database_smoke)

    add_executable(product_config_deletion_smoke
        tests/product_config_deletion_smoke.cpp
        LayoutManager.h
        LayoutManager.cpp
        ProductConfigV3Validator.h
        ProductConfigV3Validator.cpp
    )
    target_include_directories(product_config_deletion_smoke PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
    target_link_libraries(product_config_deletion_smoke PRIVATE
        Qt6::Quick
        Qt6::QuickControls2
        Qt6::Widgets
        Qt6::Sql
        Qt6::Network
    )
    add_qt_runtime_test(product_config_deletion_smoke product_config_deletion_smoke)

    add_executable(product_config_v3_creation_policy_smoke
        tests/product_config_v3_creation_policy_smoke.cpp
        LayoutManager.h
        LayoutManager.cpp
        ProductConfigV3Validator.h
        ProductConfigV3Validator.cpp
    )
    target_include_directories(product_config_v3_creation_policy_smoke PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
    target_link_libraries(product_config_v3_creation_policy_smoke PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Qml
        Qt6::Sql
        Qt6::Network
    )
    add_qt_runtime_test(product_config_v3_creation_policy_smoke product_config_v3_creation_policy_smoke)

    add_executable(catalog_save_publish_smoke
        tests/catalog_save_publish_smoke.cpp
        LayoutManager.h
        LayoutManager.cpp
        ProductConfigV3Validator.h
        ProductConfigV3Validator.cpp
    )
    target_include_directories(catalog_save_publish_smoke PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
    target_link_libraries(catalog_save_publish_smoke PRIVATE
        Qt6::Quick
        Qt6::QuickControls2
        Qt6::Widgets
        Qt6::Sql
        Qt6::Network
    )
    add_qt_runtime_test(catalog_save_publish_smoke catalog_save_publish_smoke)

    add_executable(fnr_mapping_smoke
        tests/fnr_mapping_smoke.cpp
    )
    target_compile_definitions(fnr_mapping_smoke PRIVATE
        FNR_MAPPING_SOURCE="${CMAKE_CURRENT_SOURCE_DIR}/CANJoystickTool/FnrMapping.js"
    )
    target_link_libraries(fnr_mapping_smoke PRIVATE Qt6::Quick)
    add_qt_runtime_test(fnr_mapping_smoke fnr_mapping_smoke)

    add_executable(mini_joystick_behavior_smoke
        tests/mini_joystick_behavior_smoke.cpp
    )
    target_link_libraries(mini_joystick_behavior_smoke PRIVATE
        Qt6::Quick
        Qt6::QuickControls2
    )
    add_qt_runtime_test(
        mini_joystick_behavior_smoke
        mini_joystick_behavior_smoke
        "${CMAKE_CURRENT_SOURCE_DIR}"
        "${CMAKE_CURRENT_BINARY_DIR}"
    )

    add_executable(product_config_v3_validator_smoke
        tests/product_config_v3_validator_smoke.cpp
        ProductConfigV3Validator.h
        ProductConfigV3Validator.cpp
    )
    target_include_directories(product_config_v3_validator_smoke PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
    target_compile_definitions(product_config_v3_validator_smoke PRIVATE
        PRODUCT_CONFIG_V3_EXAMPLES_DIR="${CMAKE_CURRENT_SOURCE_DIR}/examples/product-config-v3"
    )
    target_link_libraries(product_config_v3_validator_smoke PRIVATE Qt6::Core)
    add_qt_runtime_test(product_config_v3_validator_smoke product_config_v3_validator_smoke)

    add_executable(product_config_v3_editor_adapter_smoke
        tests/product_config_v3_editor_adapter_smoke.cpp
    )
    target_compile_definitions(product_config_v3_editor_adapter_smoke PRIVATE
        PRODUCT_CONFIG_V3_EDITOR_ADAPTER_SOURCE="${CMAKE_CURRENT_SOURCE_DIR}/CANJoystickToolContent/ProductConfigV3EditorAdapter.js"
    )
    target_link_libraries(product_config_v3_editor_adapter_smoke PRIVATE Qt6::Quick)
    add_qt_runtime_test(
        product_config_v3_editor_adapter_smoke
        product_config_v3_editor_adapter_smoke
    )

    add_executable(product_editor_creation_lifecycle_smoke
        tests/product_editor_creation_lifecycle_smoke.cpp
    )
    target_compile_definitions(product_editor_creation_lifecycle_smoke PRIVATE
        PRODUCT_EDITOR_QML_SOURCE="${CMAKE_CURRENT_SOURCE_DIR}/CANJoystickToolContent/ProductEditor.qml"
        PRODUCT_CONFIG_V3_EDITOR_ADAPTER_SOURCE="${CMAKE_CURRENT_SOURCE_DIR}/CANJoystickToolContent/ProductConfigV3EditorAdapter.js"
    )
    target_link_libraries(product_editor_creation_lifecycle_smoke PRIVATE Qt6::Core)
    add_qt_runtime_test(
        product_editor_creation_lifecycle_smoke
        product_editor_creation_lifecycle_smoke
    )

    add_executable(layoutmanager_v3_validation_smoke
        tests/layoutmanager_v3_validation_smoke.cpp
        LayoutManager.h
        LayoutManager.cpp
        ProductConfigV3Validator.h
        ProductConfigV3Validator.cpp
    )
    target_include_directories(layoutmanager_v3_validation_smoke PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
    target_compile_definitions(layoutmanager_v3_validation_smoke PRIVATE
        PRODUCT_CONFIG_V3_EXAMPLES_DIR="${CMAKE_CURRENT_SOURCE_DIR}/examples/product-config-v3"
    )
    target_link_libraries(layoutmanager_v3_validation_smoke PRIVATE
        Qt6::Quick
        Qt6::QuickControls2
        Qt6::Widgets
        Qt6::Sql
        Qt6::Network
    )
    add_qt_runtime_test(layoutmanager_v3_validation_smoke layoutmanager_v3_validation_smoke)
endif()

if(WIN32 AND EXISTS "${QT_SQLITE_DRIVER}")
    add_custom_command(TARGET CANJoystickTool POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory
            "$<TARGET_FILE_DIR:CANJoystickTool>/sqldrivers"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${QT_SQLITE_DRIVER}"
            "$<TARGET_FILE_DIR:CANJoystickTool>/sqldrivers/qsqlite.dll"
    )
endif()

if(WIN32 AND EXISTS "${WINDEPLOYQT_EXECUTABLE}")
    # A Release build must be runnable outside the Qt developer shell.  Keep
    # the Qt DLLs, MinGW runtime, plugins, and QML modules beside the editor.
    add_custom_command(TARGET CANJoystickTool POST_BUILD
        COMMAND "${WINDEPLOYQT_EXECUTABLE}"
            --compiler-runtime
            --qmldir "${CMAKE_CURRENT_SOURCE_DIR}"
            "$<TARGET_FILE:CANJoystickTool>"
        VERBATIM
    )
elseif(WIN32)
    message(WARNING "windeployqt was not found; CANJoystickTool will not be self-contained: ${WINDEPLOYQT_EXECUTABLE}")
endif()

if(WIN32 AND BUILD_TESTING)
    add_test(NAME editor_runtime_deployment
        COMMAND powershell -NoProfile -ExecutionPolicy Bypass
                -File "${CMAKE_CURRENT_SOURCE_DIR}/tests/Test-EditorReleaseRuntime.ps1"
                -EditorPath "$<TARGET_FILE:CANJoystickTool>"
    )
endif()

if(WIN32)
    target_sources(CANJoystickTool PRIVATE app.rc)
    set_target_properties(CANJoystickTool PROPERTIES WIN32_EXECUTABLE TRUE)
endif()
