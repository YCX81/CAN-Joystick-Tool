import QtQuick 6.5
import CANJoystickTool

// Rotary potentiometer composite unit - knob + value display + editable label.
Item {
    id: root
    objectName: "rotaryPotentiometerUnit"

    property real value: 0.0
    property real minValue: 0.0
    property real maxValue: 100.0
    property real minimumAngle: 30.0
    property real maximumAngle: 330.0
    property string displayUnit: "%"
    property string label: ""
    property bool readOnly: false
    property real unitScale: 1.0
    property bool animationEnabled: true
    property bool demoAnimation: false
    property int demoDuration: 1200
    property real demoValue: minValue
    property real animatedValue: clampValue(value)

    readonly property real designWidth: 112
    readonly property real designHeight: 154
    readonly property real contentScale: width > 0 && height > 0
                                         ? Math.min(width / designWidth, height / designHeight)
                                         : 1
    readonly property real clampedValue: clampValue(value)
    readonly property real clampedDemoValue: clampValue(demoValue)
    readonly property real clampedAnimatedValue: clampValue(animatedValue)
    readonly property real visualValue: demoAnimation ? clampedDemoValue : clampedAnimatedValue
    readonly property real normalizedValue: maxValue > minValue
                                            ? (visualValue - minValue) / (maxValue - minValue)
                                            : 0.5
    readonly property real angleDegrees: minimumAngle + normalizedValue * (maximumAngle - minimumAngle)

    implicitWidth: designWidth
    implicitHeight: designHeight
    width: implicitWidth * unitScale
    height: implicitHeight * unitScale

    function clampValue(candidate) {
        var numberValue = Number(candidate)
        if (isNaN(numberValue))
            return minValue
        return Math.max(minValue, Math.min(maxValue, numberValue))
    }

    onValueChanged: {
        if (!demoAnimation)
            animatedValue = clampValue(value)
    }

    onDemoAnimationChanged: {
        if (demoAnimation) {
            demoValue = minValue
        } else {
            animatedValue = clampValue(value)
        }
    }

    onMinValueChanged: {
        demoValue = clampValue(demoValue)
        animatedValue = clampValue(animatedValue)
    }

    onMaxValueChanged: {
        demoValue = clampValue(demoValue)
        animatedValue = clampValue(animatedValue)
    }

    Behavior on animatedValue {
        enabled: root.animationEnabled && !root.demoAnimation
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    SequentialAnimation {
        id: demoSweep
        running: root.demoAnimation
        loops: Animation.Infinite
        alwaysRunToEnd: false

        ScriptAction { script: root.demoValue = root.minValue }
        NumberAnimation {
            target: root
            property: "demoValue"
            from: root.minValue
            to: root.maxValue
            duration: root.demoDuration
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: root
            property: "demoValue"
            from: root.maxValue
            to: root.minValue
            duration: root.demoDuration
            easing.type: Easing.InOutSine
        }
    }

    Item {
        id: designSpace
        width: root.designWidth
        height: root.designHeight
        anchors.centerIn: parent
        scale: root.contentScale

        RotaryPotentiometer {
            id: potentiometer
            objectName: "rotaryPotentiometerKnob"
            x: (parent.width - width) / 2
            y: 0
            width: root.designWidth
            height: root.designWidth
            value: root.visualValue
            minValue: root.minValue
            maxValue: root.maxValue
            minimumAngle: root.minimumAngle
            maximumAngle: root.maximumAngle
            readOnly: root.readOnly || root.demoAnimation
            animationEnabled: root.animationEnabled

            onValueChanged: {
                if (!root.readOnly && !root.demoAnimation)
                    root.value = value
            }
        }

        Row {
            id: readoutRow
            objectName: "rotaryPotentiometerReadout"
            anchors.horizontalCenter: parent.horizontalCenter
            y: 118
            spacing: 8

            DigitalDisplay {
                id: display
                value: Math.round(root.visualValue)
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
