cmake_minimum_required(VERSION 3.16)

project(CANJoystickTool VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Quick QuickControls2 Widgets)

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(CANJoystickTool
    main.cpp
    LayoutManager.h
    LayoutManager.cpp
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
    VERSION 1.0
    RESOURCE_PREFIX /qt/qml
    SOURCES
        LayoutManager.h
        LayoutManager.cpp
    QML_FILES
        # Singleton 组件
        CANJoystickTool/Constants.qml
        CANJoystickTool/ComponentRegistry.qml
        CANJoystickTool/CardTemplateManager.qml
        # 基础组件
        CANJoystickTool/AluminumPanel.qml
        CANJoystickTool/AxisValueBar.qml
        CANJoystickTool/DirectoryFontLoader.qml
        CANJoystickTool/EventListModel.qml
        CANJoystickTool/EventListSimulator.qml
        CANJoystickTool/JoystickPad.qml
        CANJoystickTool/StatusIndicator.qml
        CANJoystickTool/RollerWheel.qml
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
        CANJoystickTool/HorizontalFNRUnit.qml
        CANJoystickTool/HorizontalFNRRightUnit.qml
        # 布局设计器组件
        CANJoystickTool/DraggableWrapper.qml
        CANJoystickTool/DesignCanvas.qml
        CANJoystickTool/ComponentPanel.qml
        # 内容页面
        CANJoystickToolContent/App.qml
        CANJoystickToolContent/Screen01.qml
        CANJoystickToolContent/XYAxisCard.qml
        CANJoystickToolContent/RollersCard.qml
        CANJoystickToolContent/HandleCard.qml
        CANJoystickToolContent/LayoutDesigner.qml
        CANJoystickToolContent/CustomCard.qml
        CANJoystickToolContent/ProductEditor.qml
    RESOURCES
        qtquickcontrols2.conf
)

target_link_libraries(CANJoystickTool PRIVATE
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Widgets
)

if(WIN32)
    set_target_properties(CANJoystickTool PROPERTIES WIN32_EXECUTABLE TRUE)
endif()
