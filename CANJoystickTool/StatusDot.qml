import QtQuick 6.5
import CANJoystickTool

Item {
    id: root

    property string status: "neutral"
    property string text: ""
    property bool active: true
    property bool blinking: false
    property int dotSize: 8
    property int spacing: 6
    property color dotColor: statusColor()
    property color inactiveColor: Constants.border
    property color textColor: Constants.textSecondary

    readonly property bool lit: active && (!blinking || blinkOn)
    property bool blinkOn: true

    implicitWidth: dot.width + (label.visible ? spacing + label.implicitWidth : 0)
    implicitHeight: Math.max(dot.height, label.implicitHeight)

    function statusColor() {
        if (status === "success")
            return Constants.success
        if (status === "warning")
            return Constants.warning
        if (status === "error")
            return Constants.error
        if (status === "accent")
            return Constants.accent
        return Constants.textMuted
    }

    Timer {
        interval: 500
        repeat: true
        running: root.blinking
        onTriggered: root.blinkOn = !root.blinkOn
        onRunningChanged: {
            if (!running)
                root.blinkOn = true
        }
    }

    Row {
        anchors.fill: parent
        spacing: root.spacing

        Rectangle {
            id: dot
            width: root.dotSize
            height: root.dotSize
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: root.lit ? root.dotColor : root.inactiveColor
            border.width: 1
            border.color: root.lit ? Qt.darker(root.dotColor, 1.08) : Constants.borderLight
            opacity: root.active ? 1 : 0.65

            Behavior on color {
                ColorAnimation { duration: 120 }
            }
        }

        Text {
            id: label
            text: root.text
            visible: text.length > 0
            anchors.verticalCenter: parent.verticalCenter
            color: root.textColor
            font.pixelSize: 11
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }
}
