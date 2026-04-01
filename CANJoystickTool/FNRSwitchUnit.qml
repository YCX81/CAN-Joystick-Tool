import QtQuick 6.5
import QtQuick.Effects
import CANJoystickTool

// FNR开关复合单元 - RockerSwitch + DigitalDisplay风格状态指示器 (与卡片一致)
Item {
    id: root

    // 状态
    property string switchState: "N"
    property string label: "FNR"

    // 信号
    signal fnrChanged(string state)

    width: 86
    height: 196

    // 翘板开关
    RockerSwitch {
        id: rocker
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        switchState: root.switchState

        onSwitchStateChanged: {
            root.switchState = switchState
            root.fnrChanged(switchState)
        }
    }

    // FNR 状态指示器 - DigitalDisplay 风格 + 框选高亮 (与HandleCard一致)
    Rectangle {
        id: fnrIndicator
        width: 78
        height: 30
        radius: 8
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: rocker.bottom
        anchors.topMargin: 8
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
                    color: root.switchState === "F" ? "#22c55e" : "transparent"
                    border.width: root.switchState === "F" ? 0 : 1
                    border.color: "#333333"

                    Text {
                        anchors.centerIn: parent
                        text: "F"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 11
                        font.bold: true
                        color: root.switchState === "F" ? "#FFFFFF" : "#505050"

                        layer.enabled: root.switchState === "F"
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
                    color: root.switchState === "N" ? "#6b7280" : "transparent"
                    border.width: root.switchState === "N" ? 0 : 1
                    border.color: "#333333"

                    Text {
                        anchors.centerIn: parent
                        text: "N"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 11
                        font.bold: true
                        color: root.switchState === "N" ? "#FFFFFF" : "#505050"

                        layer.enabled: root.switchState === "N"
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
                    color: root.switchState === "R" ? "#ef4444" : "transparent"
                    border.width: root.switchState === "R" ? 0 : 1
                    border.color: "#333333"

                    Text {
                        anchors.centerIn: parent
                        text: "R"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 11
                        font.bold: true
                        color: root.switchState === "R" ? "#FFFFFF" : "#505050"

                        layer.enabled: root.switchState === "R"
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
