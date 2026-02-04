import QtQuick 6.5
import QtQuick.Layouts
import QtQuick.Effects
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


        // ========== 主体区域 ========== 匹配HTML: flex gap-5 px-2 pb-2
        Row {
            id: content
            anchors.top: header.bottom
            anchors.topMargin: 24   // 匹配HTML: mb-6
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 20             // 匹配HTML: gap-5 (20px)

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

                    // FNR 状态指示器 - DigitalDisplay 风格 + 框选高亮
                    Rectangle {
                        id: fnrIndicator
                        width: 78
                        height: 30
                        radius: 8
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: Constants.rollerHousingColor  // #d4d4d4

                        // 外壳内凹阴影效果
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "#26000000" }
                                GradientStop { position: 0.2; color: "transparent" }
                                GradientStop { position: 0.8; color: "transparent" }
                                GradientStop { position: 1.0; color: "#15FFFFFF" }
                            }
                        }

                        // 屏幕区域
                        Rectangle {
                            id: screen
                            anchors.fill: parent
                            anchors.margins: 3
                            radius: 5
                            color: "#1a1a1a"

                            // 屏幕内凹阴影边框
                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                color: "transparent"
                                border.width: 1
                                border.color: "#26FFFFFF"
                            }

                            // 屏幕内凹阴影
                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                color: "transparent"
                                border.width: 3
                                border.color: "#E6000000"
                                opacity: 0.5
                            }

                            // 顶部阴影渐变
                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: "#40000000" }
                                    GradientStop { position: 0.3; color: "transparent" }
                                    GradientStop { position: 1.0; color: "transparent" }
                                }
                            }

                            // F - N - R 带框显示
                            Row {
                                anchors.centerIn: parent
                                spacing: 3

                                // F 框
                                Rectangle {
                                    width: 20
                                    height: 18
                                    radius: 3
                                    color: root.fnrState === "F" ? "#22c55e" : "transparent"
                                    border.width: root.fnrState === "F" ? 0 : 1
                                    border.color: "#333333"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "F"
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: root.fnrState === "F" ? "#FFFFFF" : "#505050"

                                        layer.enabled: root.fnrState === "F"
                                        layer.effect: MultiEffect {
                                            shadowEnabled: true
                                            shadowColor: "#FFFFFF"
                                            shadowBlur: 0.3
                                            blurMax: 4
                                        }
                                    }
                                }

                                // N 框
                                Rectangle {
                                    width: 20
                                    height: 18
                                    radius: 3
                                    color: root.fnrState === "N" ? "#6b7280" : "transparent"
                                    border.width: root.fnrState === "N" ? 0 : 1
                                    border.color: "#333333"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "N"
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: root.fnrState === "N" ? "#FFFFFF" : "#505050"

                                        layer.enabled: root.fnrState === "N"
                                        layer.effect: MultiEffect {
                                            shadowEnabled: true
                                            shadowColor: "#FFFFFF"
                                            shadowBlur: 0.3
                                            blurMax: 4
                                        }
                                    }
                                }

                                // R 框
                                Rectangle {
                                    width: 20
                                    height: 18
                                    radius: 3
                                    color: root.fnrState === "R" ? "#ef4444" : "transparent"
                                    border.width: root.fnrState === "R" ? 0 : 1
                                    border.color: "#333333"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "R"
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: root.fnrState === "R" ? "#FFFFFF" : "#505050"

                                        layer.enabled: root.fnrState === "R"
                                        layer.effect: MultiEffect {
                                            shadowEnabled: true
                                            shadowColor: "#FFFFFF"
                                            shadowBlur: 0.3
                                            blurMax: 4
                                        }
                                    }
                                }
                            }
                        }
                    }

                }
            }

            // 分隔线 - 匹配HTML: w-[1px] h-full bg-gray-300/50
            Rectangle {
                width: 1
                height: parent.height - 20
                anchors.verticalCenter: parent.verticalCenter
                color: "#80d1d5db"   // gray-300/50
            }

            // 右列: 6按钮矩阵 (2x3 grid) - 匹配HTML: gap-x-4 (16px) gap-y-6 (24px)
            Item {
                width: parent.width - 120
                height: parent.height

                Grid {
                    id: buttonGrid
                    anchors.centerIn: parent
                    columns: 2
                    rows: 3
                    rowSpacing: 16      // 调整为更接近HTML的 gap-y-6 (原本24px，但考虑按钮自带label间距)
                    columnSpacing: 16   // 匹配HTML: gap-x-4 (16px)

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
