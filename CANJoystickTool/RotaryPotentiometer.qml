pragma ComponentBehavior: Bound
import QtQuick 6.5
import CANJoystickTool

// Front-view rotary potentiometer rendered with plain Qt Quick items. Keeping
// the needle out of Canvas/layer effects makes value-driven rotation reliable.
Item {
    id: root
    objectName: "rotaryPotentiometer"

    property real value: 0.0
    property real minValue: 0.0
    property real maxValue: 100.0
    property real minimumAngle: 30.0
    property real maximumAngle: 330.0

    property color knobColor: "#090a0b"
    property color rimColor: "#1d1f21"
    property color indicatorColor: Constants.rollerIndicatorColor
    property bool readOnly: false
    property bool isDragging: false
    property bool animationEnabled: true

    signal potentiometerDoubleClicked()

    readonly property int designWidth: 112
    readonly property int designHeight: 112
    readonly property real contentScale: width > 0 && height > 0
                                         ? Math.min(width / designWidth, height / designHeight)
                                         : 1
    readonly property real clampedValue: clampValue(value)
    readonly property real normalizedValue: maxValue > minValue
                                            ? (clampedValue - minValue) / (maxValue - minValue)
                                            : 0.5
    readonly property real angleDegrees: minimumAngle + normalizedValue * (maximumAngle - minimumAngle)
    readonly property real rotationAngle: angleDegrees
    readonly property real visualRotationAngle: angleDegrees
    readonly property real indicatorRadius: 25
    readonly property int grooveCount: 60

    implicitWidth: designWidth
    implicitHeight: designHeight
    width: implicitWidth
    height: implicitHeight

    function clampValue(candidate) {
        var numberValue = Number(candidate)
        if (isNaN(numberValue))
            return minValue
        return Math.max(minValue, Math.min(maxValue, numberValue))
    }

    function setInteractiveValue(candidate) {
        value = clampValue(candidate)
    }

    Item {
        id: designSpace
        width: root.designWidth
        height: root.designHeight
        anchors.centerIn: parent
        scale: root.contentScale

        Rectangle {
            id: baseShadow
            anchors.centerIn: parent
            width: 94
            height: 94
            radius: width / 2
            color: "#000000"
            opacity: 0.24
            y: 6
        }

        Item {
            id: knob
            objectName: "rotaryPotentiometerKnobFace"
            anchors.centerIn: parent
            width: 100
            height: 100

            Rectangle {
                id: outerRim
                anchors.fill: parent
                radius: width / 2
                z: 1
                color: "#050506"
                border.width: 1
                border.color: "#3a3d40"

                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#333639" }
                    GradientStop { position: 0.35; color: root.rimColor }
                    GradientStop { position: 0.78; color: "#0b0c0d" }
                    GradientStop { position: 1.0; color: "#030404" }
                }
            }

            Item {
                id: gripRing
                anchors.fill: parent
                z: 2
                rotation: root.angleDegrees

                Repeater {
                    id: gripTicks
                    model: root.grooveCount

                    delegate: Item {
                        id: gripTick
                        required property int index
                        anchors.centerIn: parent
                        width: knob.width
                        height: knob.height
                        rotation: gripTick.index * 360 / root.grooveCount

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 3
                            width: 2
                            height: 8
                            radius: 1
                            antialiasing: true
                            color: "#56595c"
                            opacity: 0.74
                        }
                    }
                }
            }

            Rectangle {
                id: innerRim
                anchors.centerIn: parent
                width: 84
                height: 84
                radius: width / 2
                z: 3
                color: "#101214"
                border.width: 1
                border.color: "#222528"

                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#25282a" }
                    GradientStop { position: 0.42; color: "#111315" }
                    GradientStop { position: 1.0; color: "#030404" }
                }
            }

            Rectangle {
                id: face
                anchors.centerIn: parent
                width: 74
                height: 74
                radius: width / 2
                z: 4
                color: root.knobColor
                border.width: 1
                border.color: "#151719"

                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#1d2022" }
                    GradientStop { position: 0.30; color: "#101214" }
                    GradientStop { position: 1.0; color: root.knobColor }
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: 10
                height: 10
                radius: width / 2
                z: 5
                color: "#050607"
                border.width: 1
                border.color: "#15181a"
                opacity: 0.78
            }

            Rectangle {
                x: 32
                y: 21
                width: 24
                height: 10
                radius: 5
                z: 5
                color: "#ffffff"
                opacity: 0.035
            }

            Item {
                id: indicatorNeedle
                objectName: "potentiometerIndicatorBar"
                anchors.centerIn: parent
                width: 1
                height: 1
                z: 6
                rotation: root.angleDegrees
                transformOrigin: Item.Center
                visible: true

                Rectangle {
                    id: indicatorBar
                    width: 6
                    height: 30
                    radius: 3
                    x: -width / 2
                    y: root.indicatorRadius - height / 2
                    color: root.indicatorColor
                    border.width: 1
                    border.color: Qt.lighter(root.indicatorColor, 1.25)

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: 2
                        height: 7
                        radius: 3
                        color: "#ffffff"
                        opacity: 0.32
                    }

                    layer.enabled: false
                }
            }
        }
    }

    MouseArea {
        id: dragArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        enabled: !root.readOnly
        hoverEnabled: true
        cursorShape: Qt.SizeVerCursor

        property real startValue: 0
        property real startY: 0

        onPressed: function(mouse) {
            root.isDragging = true
            startValue = root.clampedValue
            startY = mouse.y
        }

        onPositionChanged: function(mouse) {
            if (!root.isDragging)
                return
            var range = Math.max(1, root.height)
            var delta = mouse.y - startY
            var span = root.maxValue - root.minValue
            root.setInteractiveValue(startValue - delta / range * span * 1.35)
        }

        onReleased: root.isDragging = false
        onCanceled: root.isDragging = false

        onDoubleClicked: {
            root.setInteractiveValue(root.minValue)
            root.potentiometerDoubleClicked()
        }

        onWheel: function(wheel) {
            var span = root.maxValue - root.minValue
            var step = span / 40
            root.setInteractiveValue(root.value + wheel.angleDelta.y / 120 * step)
            wheel.accepted = true
        }
    }
}
