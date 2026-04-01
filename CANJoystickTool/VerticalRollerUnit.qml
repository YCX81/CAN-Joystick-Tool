import QtQuick 6.5
import CANJoystickTool

// 垂直滚轮复合单元 - RollerWheel(V) 上方 + DigitalDisplay 下方
Item {
    id: root

    property real value: 0.0
    property string label: ""

    property real unitScale: 0.75
    width: 90 * unitScale
    height: 240 * unitScale

    Item {
        width: 90; height: 240
        scale: root.unitScale
        transformOrigin: Item.TopLeft

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
            color: Constants.textMuted
            font.pixelSize: 10
            font.weight: Font.Medium
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
    } // scale container
}
