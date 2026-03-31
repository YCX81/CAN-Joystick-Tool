import QtQuick 6.5
import QtQuick.Effects

// 水平FNR开关单元 - 与竖版FNRSwitchUnit完全相同样式，只是横向排列
// 翘板在左，FNR状态指示器在右
Item {
    id: root

    property string switchState: "N"
    property bool readOnly: false
    property string label: "FNR"

    signal fnrChanged(string state)

    width: 220
    height: 100

    Row {
        anchors.centerIn: parent
        spacing: 8

        // 翘板开关 (旋转90度)
        Item {
            width: root.height
            height: root.height

            RockerSwitch {
                id: rocker
                anchors.centerIn: parent
                switchWidth: 60
                switchHeight: root.height - 10
                switchState: root.switchState
                readOnly: root.readOnly
                rotation: 0

                onSwitchStateChanged: {
                    root.switchState = switchState
                    root.fnrChanged(switchState)
                }
            }
        }

        // FNR 状态指示器 - 与竖版 FNRSwitchUnit 完全一致
        Rectangle {
            id: fnrIndicator
            width: 78
            height: 30
            radius: 8
            anchors.verticalCenter: parent.verticalCenter
            color: Constants.rollerHousingColor

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

                Rectangle {
                    anchors.fill: parent; radius: parent.radius
                    color: "transparent"; border.width: 1; border.color: "#26FFFFFF"
                }
                Rectangle {
                    anchors.fill: parent; radius: parent.radius
                    color: "transparent"; border.width: 3; border.color: "#E6000000"; opacity: 0.5
                }
                Rectangle {
                    anchors.fill: parent; radius: parent.radius
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#40000000" }
                        GradientStop { position: 0.3; color: "transparent" }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                // F - N - R 带框显示 (与竖版完全一致)
                Row {
                    anchors.centerIn: parent
                    spacing: 3

                    Rectangle {
                        width: 20; height: 18; radius: 3
                        color: root.switchState === "F" ? "#22c55e" : "transparent"
                        border.width: root.switchState === "F" ? 0 : 1
                        border.color: "#333333"
                        Text {
                            anchors.centerIn: parent; text: "F"
                            font.family: "JetBrains Mono"; font.pixelSize: 11; font.bold: true
                            color: root.switchState === "F" ? "#FFFFFF" : "#505050"
                            layer.enabled: root.switchState === "F"
                            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#FFFFFF"; shadowBlur: 0.3; blurMax: 4 }
                        }
                    }

                    Rectangle {
                        width: 20; height: 18; radius: 3
                        color: root.switchState === "N" ? "#6b7280" : "transparent"
                        border.width: root.switchState === "N" ? 0 : 1
                        border.color: "#333333"
                        Text {
                            anchors.centerIn: parent; text: "N"
                            font.family: "JetBrains Mono"; font.pixelSize: 11; font.bold: true
                            color: root.switchState === "N" ? "#FFFFFF" : "#505050"
                            layer.enabled: root.switchState === "N"
                            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#FFFFFF"; shadowBlur: 0.3; blurMax: 4 }
                        }
                    }

                    Rectangle {
                        width: 20; height: 18; radius: 3
                        color: root.switchState === "R" ? "#ef4444" : "transparent"
                        border.width: root.switchState === "R" ? 0 : 1
                        border.color: "#333333"
                        Text {
                            anchors.centerIn: parent; text: "R"
                            font.family: "JetBrains Mono"; font.pixelSize: 11; font.bold: true
                            color: root.switchState === "R" ? "#FFFFFF" : "#505050"
                            layer.enabled: root.switchState === "R"
                            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#FFFFFF"; shadowBlur: 0.3; blurMax: 4 }
                        }
                    }
                }
            }
        }
    }
}
