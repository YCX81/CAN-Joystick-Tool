import QtQuick 6.5
import CANJoystickTool

// 水平滚轮复合单元 - RollerWheel(H) + DigitalDisplay
Item {
    id: root

    property real value: 0.0
    property bool invertInput: false
    property string label: ""
    readonly property real outputValue: invertInput ? -value : value

    readonly property real designWidth: 200
    readonly property real designHeight: 108
    readonly property real contentScale: Math.min(width / designWidth, height / designHeight)

    implicitWidth: designWidth * 0.75
    implicitHeight: designHeight * 0.75

    Item {
        width: root.designWidth; height: root.designHeight
        anchors.centerIn: parent
        scale: root.contentScale

    Column {
        anchors.centerIn: parent
        spacing: 12

        // 水平滚轮
        RollerWheel {
            id: roller
            orientation: "horizontal"
            value: root.outputValue
            anchors.horizontalCenter: parent.horizontalCenter

            onValueChanged: {
                root.value = root.invertInput ? -value : value
            }
        }

        // 下方显示区
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8

            // 数字显示
            DigitalDisplay {
                id: display
                value: Math.round(root.outputValue * 100)
                label: "%"
            }

            // 自定义标签
            Text {
                visible: root.label !== ""
                text: root.label
                color: Constants.textSecondary
                font.pixelSize: 18
                font.weight: Font.DemiBold
                anchors.verticalCenter: display.verticalCenter
            }
        }
    }
    } // scale container
}
