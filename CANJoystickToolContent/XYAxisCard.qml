import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import CANJoystickTool

// 摇杆卡片组件 - 可复用于 Grid 布局
AluminumPanel {
    id: root

    // 可配置属性
    property string title: "XY AXIS"
    property alias joystickPad: joystick

    // 默认尺寸
    panelWidth: 360
    panelHeight: 360

    // 内部容器
    Item {
        anchors.fill: parent
        anchors.margins: 12

        // ========== 顶部信息栏 ==========
        RowLayout {
            id: headerRow
            anchors.top: parent.top
            width: parent.width * 0.88
            anchors.horizontalCenter: parent.horizontalCenter
            height: 32
            spacing: 0

            // 左侧标题
            Text {
                text: root.title
                color: Constants.textPrimary
                font.pixelSize: 14
                font.bold: true
                font.letterSpacing: 1.2
                Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
            }

            // 弹簧，占位用
            Item { Layout.fillWidth: true }

            // 右侧状态指示灯
            RowLayout {
                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                spacing: 12

                // 拖动状态
                StatusIndicator {
                    id: mainStatus
                    indicatorSize: 10
                    active: joystick.isDragging
                    activeColor: Constants.accentColor
                }

                // 边缘状态
                StatusIndicator {
                    id: edgeStatus
                    indicatorSize: 10
                    active: joystick.isAtEdge
                    activeColor: Constants.successColor
                    blinking: joystick.isAtEdge
                }
            }
        }

        // ========== 主要Grid布局 ==========
        Item {
            id: layoutGrid
            anchors.top: headerRow.bottom
            anchors.topMargin: 10
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom

            // 保持间距设置
            property int gap: 8
            property int sideColumnWidth: 50
            property int bottomRowHeight: 44

            // 摇杆尺寸计算
            property int joystickSize: Math.min(
                width - sideColumnWidth - gap,
                height - bottomRowHeight - gap
            )

            // 1. 摇杆区域
            Item {
                id: joystickCell
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.leftMargin: (layoutGrid.width - width - layoutGrid.sideColumnWidth - layoutGrid.gap) / 2
                width: layoutGrid.joystickSize
                height: layoutGrid.joystickSize

                JoystickPad {
                    id: joystick
                    anchors.fill: parent
                    padSize: parent.width
                    returnToCenter: true
                }
            }

            // 2. 右侧: Y轴
            Item {
                id: yAxisCell
                anchors.top: joystickCell.top
                anchors.bottom: joystickCell.bottom
                anchors.left: joystickCell.right
                anchors.leftMargin: layoutGrid.gap
                width: layoutGrid.sideColumnWidth

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 4

                    AxisValueBar {
                        Layout.fillHeight: true
                        Layout.alignment: Qt.AlignHCenter
                        width: 12
                        orientation: "vertical"
                        value: -joystick.yValue  // 反转方向，向上为正
                        active: joystick.isDragging
                        label: "Y"
                    }
                }
            }

            // 3. 底部: X轴
            Item {
                id: xAxisCell
                anchors.top: joystickCell.bottom
                anchors.topMargin: layoutGrid.gap + (layoutGrid.sideColumnWidth - 12) / 2
                anchors.left: joystickCell.left
                anchors.right: joystickCell.right
                height: layoutGrid.bottomRowHeight

                Item {
                    anchors.fill: parent

                    RowLayout {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 20
                        spacing: 8

                        AxisValueBar {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            height: 12
                            orientation: "horizontal"
                            value: joystick.xValue
                            active: joystick.isDragging
                            label: "X"
                        }
                    }
                }
            }
        }
    }
}
