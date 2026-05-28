import QtQuick 6.5
import CANJoystickTool

// 垂直滚轮复合单元 - RollerWheel(V) 上方 + DigitalDisplay 下方
Item {
    id: root

    property real value: 0.0
    property string label: ""

    readonly property real designWidth: 90
    readonly property real designHeight: 240
    readonly property real contentScale: Math.min(width / designWidth, height / designHeight)

    implicitWidth: designWidth * 0.75
    implicitHeight: designHeight * 0.75

    Item {
        width: root.designWidth; height: root.designHeight
        anchors.centerIn: parent
        scale: root.contentScale

    Column {
        anchors.centerIn: parent
        spacing: 8

        // 垂直滚轮
        RollerWheel {
            id: roller
            orientation: "vertical"
            value: root.value
            anchors.horizontalCenter: parent.horizontalCenter

            onValueChanged: {
                root.value = value
            }
        }

        // 数字显示
        DigitalDisplay {
            id: display
            value: Math.round(root.value * 100)
            label: "%"
            anchors.horizontalCenter: parent.horizontalCenter
        }

        // 自定义标签
        Text {
            visible: root.label !== ""
            text: root.label
            color: Constants.textSecondary
            font.pixelSize: 18
            font.weight: Font.DemiBold
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
    } // scale container
}
