// Copyright (C) 2021 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import CANJoystickTool

Window {
    id: window
    width: Constants.width
    height: Constants.height

    visible: true
    title: {
        if (currentView === "designer") return "CANJoystickTool - Layout Designer"
        if (currentView === "products") return "CANJoystickTool - Product Config Editor"
        return "CANJoystickTool"
    }
    color: Constants.backgroundColor

    property string currentView: "main" // "main", "designer", "products"

    // 根据窗口实际大小计算缩放比例
    property real scaleFactor: Math.min(window.width / Constants.width,
                                        window.height / Constants.height)

    // 主界面
    Screen01 {
        id: mainScreen
        visible: currentView === "main"
        transformOrigin: Item.Center
        scale: window.scaleFactor
        anchors.centerIn: parent
    }

    // 布局设计器
    LayoutDesigner {
        id: layoutDesigner
        visible: currentView === "designer"
        anchors.fill: parent

        onExitRequested: {
            currentView = "main"
        }
    }

    // 产品配置编辑器
    ProductEditor {
        id: productEditor
        visible: currentView === "products"
        anchors.fill: parent

        onExitRequested: {
            currentView = "main"
        }
    }

    // 底部按钮栏 (主界面)
    Row {
        visible: currentView === "main"
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 16
        spacing: 8
        z: 100

        Button {
            id: productButton
            text: "Products"
            font.pixelSize: 11

            background: Rectangle {
                color: productButton.pressed ? Qt.darker("#ff9500", 1.1) :
                       (productButton.hovered ? Qt.lighter("#ff9500", 1.1) : "#ff9500")
                radius: 4
            }

            contentItem: Text {
                text: parent.text
                color: "#ffffff"
                font: parent.font
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            onClicked: currentView = "products"

            ToolTip.visible: hovered
            ToolTip.text: "Open Product Config Editor (Ctrl+P)"
        }

        Button {
            id: designerButton
            text: "Designer"
            font.pixelSize: 11

            background: Rectangle {
                color: designerButton.pressed ? Qt.darker(Constants.accentColor, 1.1) :
                       (designerButton.hovered ? Qt.lighter(Constants.accentColor, 1.1) : Constants.accentColor)
                radius: 4
            }

            contentItem: Text {
                text: parent.text
                color: "#ffffff"
                font: parent.font
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            onClicked: currentView = "designer"

            ToolTip.visible: hovered
            ToolTip.text: "Open Layout Designer (Ctrl+D)"
        }
    }

    // 快捷键
    Shortcut {
        sequence: "Ctrl+D"
        onActivated: currentView = (currentView === "designer" ? "main" : "designer")
    }

    Shortcut {
        sequence: "Ctrl+P"
        onActivated: currentView = (currentView === "products" ? "main" : "products")
    }

    Shortcut {
        sequence: "Escape"
        enabled: currentView !== "main"
        onActivated: currentView = "main"
    }
}
