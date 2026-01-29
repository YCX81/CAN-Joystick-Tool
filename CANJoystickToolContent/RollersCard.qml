import QtQuick 6.5
import QtQuick.Layouts
import CANJoystickTool

// 双滚轮控制卡片 - ROLLERS
AluminumPanel {
    id: root

    // 卡片尺寸
    panelWidth: 360
    panelHeight: 360

    // 输出值
    readonly property real trimValue: trimRoller.value      // 竖向滚轮 (TRIM)
    readonly property real panValue: panRoller.value        // 横向滚轮 (PAN)

    // 状态
    property bool isActive: trimRoller.isDragging || panRoller.isDragging

    // 信号
    signal trimChanged(real value)
    signal panChanged(real value)

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
                text: "ROLLERS"
                color: "#4b5563"
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 0.8
                anchors.verticalCenter: parent.verticalCenter
            }

            // 弹簧占位
            Item { Layout.fillWidth: true; width: 10; height: 1 }
        }

        // 状态指示灯 - 右上角
        StatusIndicator {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 4
            anchors.rightMargin: 4
            indicatorSize: 8
            active: root.isActive
            activeColor: Constants.successColor
        }

        // ========== 主体区域 ==========
        Item {
            id: content
            anchors.top: header.bottom
            anchors.topMargin: 8
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8

            // 竖向滚轮组 (TRIM) - 左上区域
            Item {
                id: trimGroup
                anchors.left: parent.left
                anchors.leftMargin: 32
                anchors.top: parent.top
                anchors.topMargin: 8
                width: 120
                height: 220

                Row {
                    anchors.fill: parent
                    spacing: 8

                    // 滚轮
                    RollerWheel {
                        id: trimRoller
                        orientation: "vertical"
                        width: 48
                        height: 200
                        anchors.verticalCenter: parent.verticalCenter

                        onValueChanged: root.trimChanged(trimRoller.value)
                    }

                    // 进度条 + 标签
                    Column {
                        spacing: 0
                        anchors.verticalCenter: parent.verticalCenter
                        height: 200

                        // 标签
                        Text {
                            text: "TRIM"
                            color: Constants.textSecondary
                            font.pixelSize: 8
                            font.weight: Font.Bold
                            font.letterSpacing: 0.5
                        }

                        Item { width: 1; height: 4 }

                        // 进度条
                        AxisValueBar {
                            orientation: "vertical"
                            value: trimRoller.value
                            active: trimRoller.isDragging
                            fillColor: Constants.rollerIndicatorColor
                            fillColorActive: Qt.darker(Constants.rollerIndicatorColor, 1.1)
                            showLabel: false
                            showValue: false
                            width: 12
                            height: 170
                        }

                        Item { width: 1; height: 4 }

                        // 数值
                        Text {
                            text: (trimRoller.value * 100).toFixed(0)
                            color: Constants.textSecondary
                            font.pixelSize: 10
                            font.family: "JetBrains Mono, Consolas, monospace"
                            font.weight: Font.Bold
                        }
                    }
                }
            }

            // 横向滚轮组 (PAN) - 右下区域
            Item {
                id: panGroup
                anchors.right: parent.right
                anchors.rightMargin: 32
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                width: 220
                height: 100

                Column {
                    anchors.fill: parent
                    spacing: 8
                    anchors.horizontalCenter: parent.horizontalCenter

                    // 滚轮
                    RollerWheel {
                        id: panRoller
                        orientation: "horizontal"
                        width: 200
                        height: 40
                        anchors.horizontalCenter: parent.horizontalCenter

                        onValueChanged: root.panChanged(panRoller.value)
                    }

                    // 进度条
                    AxisValueBar {
                        orientation: "horizontal"
                        value: panRoller.value
                        active: panRoller.isDragging
                        fillColor: Constants.rollerIndicatorColor
                        fillColorActive: Qt.darker(Constants.rollerIndicatorColor, 1.1)
                        showLabel: false
                        showValue: false
                        width: 200
                        height: 12
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    // 标签和数值行
                    Item {
                        width: 200
                        height: 16
                        anchors.horizontalCenter: parent.horizontalCenter

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 2
                            text: "PAN"
                            color: Constants.textSecondary
                            font.pixelSize: 8
                            font.weight: Font.Bold
                            font.letterSpacing: 0.5
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 2
                            text: (panRoller.value * 100).toFixed(0)
                            color: Constants.textSecondary
                            font.pixelSize: 10
                            font.family: "JetBrains Mono, Consolas, monospace"
                            font.weight: Font.Bold
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }
        }
    }
}
