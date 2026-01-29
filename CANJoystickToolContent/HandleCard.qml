import QtQuick 6.5
import QtQuick.Layouts
import CANJoystickTool

// 手柄控制卡片 - HANDLE
AluminumPanel {
    id: root

    // 卡片尺寸
    panelWidth: 360
    panelHeight: 360

    // FNR状态
    property string fnrState: "N"     // "F", "N", "R"

    // 按钮状态 (6个按钮)
    property var buttonStates: [false, false, false, false, false, false]

    // 信号
    signal fnrChanged(string state)
    signal buttonClicked(int index)

    // 主内容区域
    Item {
        anchors.fill: parent

        // ========== 顶部标题栏 ==========
        Row {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 4
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            height: 24
            spacing: 8

            // 标题
            Text {
                text: "HANDLE"
                color: "#4b5563"
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 0.8
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // FNR状态标签 - 右上角
        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 4
            anchors.rightMargin: 4
            width: 36
            height: 18
            radius: 4
            color: {
                switch(root.fnrState) {
                    case "F": return "#dcfce7"  // green-100
                    case "R": return "#ffedd5"  // orange-100
                    default: return "#e5e7eb"   // gray-200
                }
            }

            // 内凹效果
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 1
                border.color: "#1A000000"
            }

            Text {
                anchors.centerIn: parent
                text: {
                    switch(root.fnrState) {
                        case "F": return "FWD"
                        case "R": return "REV"
                        default: return "NEU"
                    }
                }
                color: {
                    switch(root.fnrState) {
                        case "F": return "#16a34a"  // green-600
                        case "R": return "#ea580c"  // orange-600
                        default: return "#4b5563"   // gray-600
                    }
                }
                font.pixelSize: 10
                font.family: "JetBrains Mono, Consolas, monospace"
                font.weight: Font.Bold
            }
        }

        // ========== 主体区域 ==========
        Row {
            id: content
            anchors.top: header.bottom
            anchors.topMargin: 16
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 12

            // 左列: FNR翘板开关
            Item {
                width: 100
                height: parent.height

                Column {
                    anchors.centerIn: parent
                    spacing: 8

                    RockerSwitch {
                        id: fnrSwitch
                        switchState: root.fnrState
                        anchors.horizontalCenter: parent.horizontalCenter

                        onSwitchStateChanged: {
                            root.fnrState = switchState
                            root.fnrChanged(switchState)
                        }
                    }

                    Text {
                        text: "DRIVE"
                        color: Constants.textSecondary
                        font.pixelSize: 8
                        font.weight: Font.Bold
                        font.letterSpacing: 0.5
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }

            // 分隔线
            Rectangle {
                width: 1
                height: parent.height - 40
                anchors.verticalCenter: parent.verticalCenter
                color: "#33000000"
            }

            // 右列: 6按钮矩阵 (2x3 grid)
            Item {
                width: parent.width - 120
                height: parent.height

                Grid {
                    id: buttonGrid
                    anchors.centerIn: parent
                    columns: 2
                    rows: 3
                    rowSpacing: 8
                    columnSpacing: 16

                    // 按钮1: 红色
                    IndustrialButton {
                        variant: "red"
                        label: "BUTTON 1"
                        ledActive: root.buttonStates[0]
                        onClicked: root.buttonClicked(0)
                    }

                    // 按钮2: 灰色
                    IndustrialButton {
                        variant: "grey"
                        label: "BUTTON 2"
                        ledActive: root.buttonStates[1]
                        onClicked: root.buttonClicked(1)
                    }

                    // 按钮3: 绿色
                    IndustrialButton {
                        variant: "green"
                        label: "BUTTON 3"
                        ledActive: root.buttonStates[2]
                        onClicked: root.buttonClicked(2)
                    }

                    // 按钮4: 橙色
                    IndustrialButton {
                        variant: "orange"
                        label: "BUTTON 4"
                        ledActive: root.buttonStates[3]
                        onClicked: root.buttonClicked(3)
                    }

                    // 按钮5: 黑色
                    IndustrialButton {
                        variant: "black"
                        label: "BUTTON 5"
                        ledActive: root.buttonStates[4]
                        onClicked: root.buttonClicked(4)
                    }

                    // 按钮6: 蓝色
                    IndustrialButton {
                        variant: "blue"
                        label: "BUTTON 6"
                        ledActive: root.buttonStates[5]
                        onClicked: root.buttonClicked(5)
                    }
                }
            }
        }
    }
}
