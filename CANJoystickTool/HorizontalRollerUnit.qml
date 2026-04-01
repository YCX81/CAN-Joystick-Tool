import QtQuick 6.5
import CANJoystickTool

// 水平滚轮复合单元 - RollerWheel(H) + DigitalDisplay
Item {
    id: root

    property real value: 0.0
    property string label: ""

    property real unitScale: 0.75
    width: 200 * unitScale
    height: 108 * unitScale

    Item {
        width: 200; height: 108
        scale: root.unitScale
        transformOrigin: Item.TopLeft

    Column {
        anchors.centerIn: parent
        spacing: 12

        // 水平滚轮
        RollerWheel {
            id: roller
            orientation: "horizontal"
            value: root.value
            anchors.horizontalCenter: parent.horizontalCenter

            onValueChanged: {
                root.value = value
            }
        }

        // 下方显示区
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8

            // 数字显示
            DigitalDisplay {
                id: display
                value: Math.round(root.value * 100)
                label: "%"
            }

            // 自定义标签
            Text {
                visible: root.label !== ""
                text: root.label
                color: Constants.textMuted
                font.pixelSize: 10
                font.weight: Font.Medium
                anchors.verticalCenter: display.verticalCenter
            }
        }
    }
    } // scale container
}
