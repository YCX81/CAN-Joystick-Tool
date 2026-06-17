import QtQuick 6.5
import CANJoystickTool

// Rotary potentiometer composite unit - knob + value display + editable label.
Item {
    id: root

    property real value: 0.0
    property real minValue: 0.0
    property real maxValue: 360.0
    property real minimumAngle: 0.0
    property real maximumAngle: 360.0
    property string displayUnit: "°"
    property string label: ""
    property bool readOnly: false
    property real unitScale: 1.0

    readonly property real designWidth: 112
    readonly property real designHeight: 154
    readonly property real contentScale: Math.min(width / designWidth, height / designHeight)
    readonly property real clampedValue: Math.max(minValue, Math.min(maxValue, value))
    readonly property real normalizedValue: maxValue > minValue ? (clampedValue - minValue) / (maxValue - minValue) : 0.5
    readonly property real angleDegrees: minimumAngle + normalizedValue * (maximumAngle - minimumAngle)

    implicitWidth: designWidth * 0.75
    implicitHeight: designHeight * 0.75
    width: implicitWidth * unitScale
    height: implicitHeight * unitScale

    Item {
        width: root.designWidth
        height: root.designHeight
        anchors.centerIn: parent
        scale: root.contentScale

        Column {
            anchors.centerIn: parent
            spacing: 8

            RotaryPotentiometer {
                id: potentiometer
                value: root.value
                minValue: root.minValue
                maxValue: root.maxValue
                minimumAngle: root.minimumAngle
                maximumAngle: root.maximumAngle
                readOnly: root.readOnly
                anchors.horizontalCenter: parent.horizontalCenter

                onValueChanged: {
                    if (!root.readOnly)
                        root.value = value
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                DigitalDisplay {
                    id: display
                    value: Math.round(root.angleDegrees)
                    label: root.displayUnit
                }

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
    }
}
