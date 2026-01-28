// 主界面 - CAN Joystick Tool
import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import CANJoystickTool

Rectangle {
    id: root
    width: Constants.width
    height: Constants.height
    color: Constants.backgroundColor  // #f5f5f7 浅色背景

    // 主布局
    RowLayout {
        anchors.fill: parent
        anchors.margins: 40
        spacing: 40

        // 左侧：铝合金面板 + 摇杆
        AluminumPanel {
            id: mainPanel
            panelWidth: 420
            panelHeight: 520
            Layout.alignment: Qt.AlignTop

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 20

                // 标题栏
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    Text {
                        text: "XY CONTROLLER"
                        color: Constants.textPrimary  // 深色文字
                        font.pixelSize: 16
                        font.bold: true
                        font.letterSpacing: 2
                    }

                    Item { Layout.fillWidth: true }

                    StatusIndicator {
                        id: mainStatus
                        indicatorSize: 16
                        active: joystick.isDragging
                        activeColor: Constants.accentColor  // 青色
                    }

                    StatusIndicator {
                        id: edgeStatus
                        indicatorSize: 16
                        active: joystick.isAtEdge
                        activeColor: Constants.successColor  // 绿色
                        blinking: joystick.isAtEdge
                        blinkInterval: 300
                    }
                }

                // 摇杆区域
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    JoystickPad {
                        id: joystick
                        anchors.centerIn: parent
                        returnToCenter: true
                        returnDuration: 500  // HTML: 0.5s
                    }
                }
            }
        }

        // 右侧面板
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 30

            // 轴值卡片 - 半透明白色
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 280
                radius: 12
                color: "#4dffffff"  // white/30
                border.width: 1
                border.color: "#80ffffff"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 20

                    Text {
                        text: "AXIS VALUES"
                        color: Constants.textSecondary
                        font.pixelSize: 14
                        font.bold: true
                        font.letterSpacing: 2
                    }

                    AxisValueBar {
                        id: xAxisBar
                        Layout.fillWidth: true
                        value: joystick.xValue
                        label: "X"
                        barHeight: 32
                    }

                    AxisValueBar {
                        id: yAxisBar
                        Layout.fillWidth: true
                        value: joystick.yValue
                        label: "Y"
                        barHeight: 32
                    }

                    // Z轴滑块
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Text {
                            text: "Z:"
                            color: Constants.textSecondary
                            font.pixelSize: 12
                            font.family: "Consolas"
                        }

                        Slider {
                            id: zSlider
                            Layout.fillWidth: true
                            from: -1.0
                            to: 1.0
                            value: 0.0
                            stepSize: 0.01

                            background: Rectangle {
                                x: zSlider.leftPadding
                                y: zSlider.topPadding + zSlider.availableHeight / 2 - height / 2
                                width: zSlider.availableWidth
                                height: 10
                                radius: 5
                                color: "#e8e8e8"

                                Rectangle {
                                    x: zSlider.visualPosition < 0.5
                                       ? zSlider.visualPosition * parent.width
                                       : parent.width / 2
                                    width: Math.abs(zSlider.visualPosition - 0.5) * parent.width
                                    height: parent.height
                                    radius: 5
                                    color: "#4b5563"  // 深灰填充
                                }
                            }

                            handle: Rectangle {
                                x: zSlider.leftPadding + zSlider.visualPosition * (zSlider.availableWidth - width)
                                y: zSlider.topPadding + zSlider.availableHeight / 2 - height / 2
                                width: 6
                                height: 16
                                radius: 3
                                color: "#374151"  // gray-700
                            }
                        }

                        Text {
                            text: (zSlider.value >= 0 ? "+" : "") + zSlider.value.toFixed(2)
                            color: "#4b5563"  // 深灰
                            font.pixelSize: 12
                            font.family: "Consolas"
                            font.bold: true
                            Layout.preferredWidth: 60
                        }
                    }
                }
            }

            // 原始数值显示 - 半透明白色卡片
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 160
                radius: 12
                color: "#4dffffff"
                border.width: 1
                border.color: "#80ffffff"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 16

                    Text {
                        text: "RAW VALUES"
                        color: Constants.textSecondary
                        font.pixelSize: 14
                        font.bold: true
                        font.letterSpacing: 2
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 3
                        rowSpacing: 12
                        columnSpacing: 32

                        // X轴
                        Text {
                            text: "X:"
                            color: Constants.textMuted
                            font.pixelSize: 16
                            font.family: "Consolas"
                        }
                        Text {
                            text: (joystick.xValue >= 0 ? "+" : "") + joystick.xValue.toFixed(4)
                            color: Constants.textPrimary
                            font.pixelSize: 16
                            font.family: "Consolas"
                            font.bold: true
                        }
                        Item { Layout.fillWidth: true }

                        // Y轴
                        Text {
                            text: "Y:"
                            color: Constants.textMuted
                            font.pixelSize: 16
                            font.family: "Consolas"
                        }
                        Text {
                            text: (joystick.yValue >= 0 ? "+" : "") + joystick.yValue.toFixed(4)
                            color: Constants.textPrimary
                            font.pixelSize: 16
                            font.family: "Consolas"
                            font.bold: true
                        }
                        Item { Layout.fillWidth: true }

                        // Z轴
                        Text {
                            text: "Z:"
                            color: Constants.textMuted
                            font.pixelSize: 16
                            font.family: "Consolas"
                        }
                        Text {
                            text: (zSlider.value >= 0 ? "+" : "") + zSlider.value.toFixed(4)
                            color: Constants.textPrimary
                            font.pixelSize: 16
                            font.family: "Consolas"
                            font.bold: true
                        }
                        Item { Layout.fillWidth: true }
                    }
                }
            }

            // 状态指示器面板 - 半透明白色卡片
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 100
                radius: 12
                color: "#4dffffff"
                border.width: 1
                border.color: "#80ffffff"

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 32

                    Text {
                        text: "STATUS"
                        color: Constants.textSecondary
                        font.pixelSize: 14
                        font.bold: true
                        font.letterSpacing: 2
                    }

                    Item { Layout.fillWidth: true }

                    // CONN 指示灯
                    ColumnLayout {
                        spacing: 6
                        StatusIndicator {
                            Layout.alignment: Qt.AlignHCenter
                            indicatorSize: 14
                            active: true
                            activeColor: Constants.successColor
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "CONN"
                            color: Constants.textMuted
                            font.pixelSize: 10
                            font.bold: true
                        }
                    }

                    // TX 指示灯
                    ColumnLayout {
                        spacing: 6
                        StatusIndicator {
                            Layout.alignment: Qt.AlignHCenter
                            indicatorSize: 14
                            active: joystick.isDragging
                            activeColor: Constants.accentColor
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "TX"
                            color: Constants.textMuted
                            font.pixelSize: 10
                            font.bold: true
                        }
                    }

                    // RX 指示灯
                    ColumnLayout {
                        spacing: 6
                        StatusIndicator {
                            Layout.alignment: Qt.AlignHCenter
                            indicatorSize: 14
                            active: false
                            activeColor: Constants.warningColor
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "RX"
                            color: Constants.textMuted
                            font.pixelSize: 10
                            font.bold: true
                        }
                    }

                    // ERR 指示灯
                    ColumnLayout {
                        spacing: 6
                        StatusIndicator {
                            Layout.alignment: Qt.AlignHCenter
                            indicatorSize: 14
                            active: false
                            activeColor: Constants.errorColor
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "ERR"
                            color: Constants.textMuted
                            font.pixelSize: 10
                            font.bold: true
                        }
                    }
                }
            }

            // 底部状态和锁定按钮区域
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 80
                radius: 12
                color: "#4dffffff"
                border.width: 1
                border.color: "#80ffffff"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    // OUTPUT 状态行
                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: "OUTPUT"
                            color: Constants.textMuted
                            font.pixelSize: 10
                            font.family: "Consolas"
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: joystick.isDragging ? "TRANSMITTING" : "IDLE"
                            color: joystick.isDragging ? Constants.accentColor : Constants.textMuted
                            font.pixelSize: 10
                            font.bold: joystick.isDragging
                            font.letterSpacing: joystick.isDragging ? 1 : 0

                            Behavior on color { ColorAnimation { duration: 300 } }
                        }
                    }

                    // LOCK CONTROLS 按钮
                    Button {
                        id: lockButton
                        Layout.fillWidth: true
                        text: "LOCK CONTROLS"
                        checkable: true
                        font.pixelSize: 10
                        font.bold: true
                        font.letterSpacing: 2
                        padding: 10

                        background: Rectangle {
                            radius: 8
                            color: lockButton.checked ? "#374151" : "#4b5563"

                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        contentItem: Text {
                            text: lockButton.text
                            color: "#f3f4f6"
                            font: lockButton.font
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        onCheckedChanged: {
                            // 锁定时禁用摇杆交互
                            joystick.enabled = !checked
                            zSlider.enabled = !checked
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
