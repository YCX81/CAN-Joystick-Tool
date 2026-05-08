import QtQuick 6.5
import QtQuick.Effects
import CANJoystickTool

// 水平FNR开关单元 - 与竖版 FNRSwitchUnit 等大，翘板横置在上，FNR状态栏在下
Item {
    id: root

    property string switchState: "N"
    property bool readOnly: false
    property string label: "FNR"

    signal fnrChanged(string state)

    readonly property real designWidth: 196
    readonly property real designHeight: 130
    readonly property real contentScale: Math.min(width / designWidth, height / designHeight)

    implicitWidth: designWidth * 0.75
    implicitHeight: designHeight * 0.75

    Item {
        width: root.designWidth; height: root.designHeight
        anchors.centerIn: parent
        scale: root.contentScale

    // 翘板开关 (旋转90度变横置)
    Item {
        id: rockerContainer
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: parent.width
        height: parent.height - fnrIndicator.height - 8

        RockerSwitch {
            id: rocker
            anchors.centerIn: parent
            switchWidth: 86
            switchHeight: 150
            switchState: root.switchState
            readOnly: root.readOnly
            rotation: -90

            onSwitchStateChanged: {
                root.switchState = switchState
                root.fnrChanged(switchState)
            }
        }
    }

    // FNR 状态指示器 (横排 F N R) - 与竖版完全一致的样式
    Rectangle {
        id: fnrIndicator
        width: 78
        height: 30
        radius: 8
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        color: Constants.rollerHousingColor

        Rectangle {
            anchors.fill: parent; radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#26000000" }
                GradientStop { position: 0.2; color: "transparent" }
                GradientStop { position: 0.8; color: "transparent" }
                GradientStop { position: 1.0; color: "#15FFFFFF" }
            }
        }

        Rectangle {
            id: screen
            anchors.fill: parent; anchors.margins: 3; radius: 5; color: "#1a1a1a"

            Rectangle { anchors.fill: parent; radius: parent.radius; color: "transparent"; border.width: 1; border.color: "#26FFFFFF" }
            Rectangle { anchors.fill: parent; radius: parent.radius; color: "transparent"; border.width: 3; border.color: "#E6000000"; opacity: 0.5 }
            Rectangle {
                anchors.fill: parent; radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#40000000" }
                    GradientStop { position: 0.3; color: "transparent" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            Row {
                anchors.centerIn: parent; spacing: 3

                Repeater {
                    model: [
                        { key: "F", activeColor: "#22c55e" },
                        { key: "N", activeColor: "#6b7280" },
                        { key: "R", activeColor: "#ef4444" }
                    ]
                    Rectangle {
                        width: 20; height: 18; radius: 3
                        color: root.switchState === modelData.key ? modelData.activeColor : "transparent"
                        border.width: root.switchState === modelData.key ? 0 : 1
                        border.color: "#333333"
                        Text {
                            anchors.centerIn: parent; text: modelData.key
                            font.family: "JetBrains Mono"; font.pixelSize: 11; font.bold: true
                            color: root.switchState === modelData.key ? "#FFFFFF" : "#505050"
                            layer.enabled: root.switchState === modelData.key
                            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#FFFFFF"; shadowBlur: 0.3; blurMax: 4 }
                        }
                    }
                }
            }
        }
    }
    } // scale container
}
