pragma ComponentBehavior: Bound
import QtQuick 6.5
import CANJoystickTool

// Two-axis composite unit. Its vertical rhythm exactly matches VerticalRoller:
// 200-unit body + 8-unit gap + 36-unit display, matching VerticalRoller.
Item {
    id: root
    objectName: "miniJoystickUnit"

    property real xValue: 0.0
    property real yValue: 0.0
    property real minValue: -1.0
    property real maxValue: 1.0
    property string label: ""
    property bool readOnly: true
    property bool animationEnabled: true
    property bool invertX: false
    property bool invertY: false
    property string gateMode: "omnidirectional"
    property real unitScale: 1.0

    signal moved(real x, real y)
    signal released()

    readonly property int designWidth: 244
    readonly property int designHeight: 240
    readonly property real contentScale: width > 0 && height > 0
                                         ? Math.min(width / designWidth, height / designHeight)
                                         : 1
    readonly property real visualX: joystick.visualX
    readonly property real visualY: joystick.visualY
    readonly property real displayXValue: joystick.normalizedX * 100
    readonly property real displayYValue: joystick.normalizedY * 100

    implicitWidth: designWidth
    implicitHeight: designHeight
    width: implicitWidth * unitScale
    height: implicitHeight * unitScale

    Item {
        id: designSpace
        width: root.designWidth
        height: root.designHeight
        anchors.centerIn: parent
        scale: root.contentScale

        MiniJoystick {
            id: joystick
            objectName: "miniJoystickControl"
            x: 0
            y: -2
            width: 200
            height: 200
            xValue: root.xValue
            yValue: root.yValue
            minValue: root.minValue
            maxValue: root.maxValue
            readOnly: root.readOnly
            animationEnabled: root.animationEnabled
            invertX: root.invertX
            invertY: root.invertY
            gateMode: root.gateMode

            onMoved: function(x, y) {
                if (!root.readOnly) {
                    root.xValue = x
                    root.yValue = y
                }
                root.moved(x, y)
            }
            onReleased: root.released()
        }

        DigitalDisplay {
            id: xDisplay
            objectName: "miniJoystickXDisplay"
            x: 60
            y: 206
            width: 80
            height: 36
            value: Math.round(root.displayXValue)
            label: "%"
        }

        Item {
            id: yDisplaySlot
            objectName: "miniJoystickYDisplaySlot"
            x: 208
            y: 58
            width: 36
            height: 80

            DigitalDisplay {
                id: yDisplay
                objectName: "miniJoystickYDisplay"
                anchors.centerIn: parent
                width: 80
                height: 36
                rotation: 90
                value: Math.round(root.displayYValue)
                label: "%"
            }
        }

        Text {
            visible: root.label !== ""
            x: joystick.x + (joystick.width - width) / 2
            y: 188
            z: 6
            text: root.label
            color: Constants.rollerIndicatorColor
            font.pixelSize: 9
            font.weight: Font.DemiBold
        }
    }
}
