pragma ComponentBehavior: Bound
import QtQuick 6.5
import QtQuick.Effects
import CANJoystickTool

// Front-view rotary potentiometer with an animated rotating knob.
Item {
    id: root

    property real value: 0.0
    property real minValue: 0.0
    property real maxValue: 360.0
    property real minimumAngle: 0.0
    property real maximumAngle: 360.0

    property color knobColor: "#090a0b"
    property color rimColor: "#1d1f21"
    property color indicatorColor: Constants.rollerIndicatorColor
    property bool readOnly: false
    property bool isDragging: false

    signal potentiometerDoubleClicked()

    readonly property int designWidth: 112
    readonly property int designHeight: 112
    readonly property real contentScale: Math.min(width / designWidth, height / designHeight)
    readonly property real clampedValue: Math.max(minValue, Math.min(maxValue, value))
    readonly property real normalizedValue: maxValue > minValue ? (clampedValue - minValue) / (maxValue - minValue) : 0.5
    readonly property real angleDegrees: minimumAngle + normalizedValue * (maximumAngle - minimumAngle)
    readonly property real rotationAngle: angleDegrees

    implicitWidth: designWidth
    implicitHeight: designHeight

    onValueChanged: {
        if (value !== clampedValue)
            value = clampedValue
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
            width: 96
            height: 96
            radius: 48
            color: "#000000"
            opacity: 0.32
            y: 7

            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 0.8
                blurMax: 18
            }
        }

        Item {
            id: knob
            anchors.centerIn: parent
            width: 100
            height: 100
            property real animatedAngle: root.rotationAngle

            Behavior on animatedAngle {
                NumberAnimation {
                    duration: root.isDragging ? 90 : 220
                    easing.type: Easing.OutCubic
                }
            }

            Canvas {
                id: knobCanvas
                anchors.fill: parent
                property real textureAngle: knob.animatedAngle * Math.PI / 180

                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onTextureAngleChanged: requestPaint()

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)

                    var cx = width / 2
                    var cy = height / 2
                    var outerRadius = Math.min(width, height) / 2 - 2
                    var innerToothRadius = outerRadius - 7
                    var faceRadius = outerRadius - 11

                    var outer = ctx.createRadialGradient(cx * 0.40, cy * 0.32, 4, cx, cy, outerRadius)
                    outer.addColorStop(0.0, "#3b3e40")
                    outer.addColorStop(0.36, root.rimColor.toString())
                    outer.addColorStop(0.74, "#111214")
                    outer.addColorStop(1.0, "#050506")
                    ctx.beginPath()
                    ctx.arc(cx, cy, outerRadius, 0, Math.PI * 2)
                    ctx.fillStyle = outer
                    ctx.fill()

                    var grooves = 44
                    var step = Math.PI * 2 / grooves
                    ctx.save()
                    ctx.lineCap = "round"
                    ctx.lineWidth = 2.4
                    for (var i = 0; i < grooves; i++) {
                        var a = i * step + textureAngle
                        var shade = 48 + Math.round(36 * (Math.sin(a + Math.PI * 0.32) + 1) / 2)
                        ctx.beginPath()
                        ctx.moveTo(cx + Math.cos(a) * (outerRadius - 1.8), cy + Math.sin(a) * (outerRadius - 1.8))
                        ctx.lineTo(cx + Math.cos(a) * (innerToothRadius + 0.5), cy + Math.sin(a) * (innerToothRadius + 0.5))
                        ctx.strokeStyle = "rgb(" + shade + "," + shade + "," + shade + ")"
                        ctx.stroke()
                    }
                    ctx.restore()

                    var rim = ctx.createRadialGradient(cx * 0.38, cy * 0.30, 5, cx, cy, innerToothRadius)
                    rim.addColorStop(0.0, "#303235")
                    rim.addColorStop(0.34, "#191b1d")
                    rim.addColorStop(0.76, "#0b0c0d")
                    rim.addColorStop(1.0, "#030404")
                    ctx.beginPath()
                    ctx.arc(cx, cy, innerToothRadius - 1, 0, Math.PI * 2)
                    ctx.fillStyle = rim
                    ctx.fill()

                    var face = ctx.createRadialGradient(cx * 0.38, cy * 0.30, 2, cx, cy, faceRadius)
                    face.addColorStop(0.0, "#222426")
                    face.addColorStop(0.22, "#101214")
                    face.addColorStop(0.78, root.knobColor.toString())
                    face.addColorStop(1.0, "#020303")
                    ctx.beginPath()
                    ctx.arc(cx, cy, faceRadius, 0, Math.PI * 2)
                    ctx.fillStyle = face
                    ctx.fill()

                    var inset = ctx.createRadialGradient(cx, cy, faceRadius * 0.35, cx, cy, faceRadius)
                    inset.addColorStop(0.0, "rgba(0, 0, 0, 0.00)")
                    inset.addColorStop(0.76, "rgba(0, 0, 0, 0.12)")
                    inset.addColorStop(1.0, "rgba(0, 0, 0, 0.58)")
                    ctx.beginPath()
                    ctx.arc(cx, cy, faceRadius, 0, Math.PI * 2)
                    ctx.fillStyle = inset
                    ctx.fill()

                    ctx.beginPath()
                    ctx.arc(cx * 0.82, cy * 0.75, faceRadius * 0.12, 0, Math.PI * 2)
                    ctx.strokeStyle = "rgba(255, 255, 255, 0.04)"
                    ctx.lineWidth = 1
                    ctx.stroke()

                    ctx.beginPath()
                    ctx.arc(cx, cy, faceRadius + 0.5, 0, Math.PI * 2)
                    ctx.strokeStyle = "rgba(255, 255, 255, 0.09)"
                    ctx.lineWidth = 1
                    ctx.stroke()
                }

                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: "#60000000"
                    shadowBlur: 0.36
                    shadowHorizontalOffset: 2
                    shadowVerticalOffset: 3
                }

                Component.onCompleted: requestPaint()
            }

            Rectangle {
                id: indicatorBar
                readonly property real barAngle: Math.PI / 2 + knob.animatedAngle * Math.PI / 180
                readonly property real barRadius: 25

                width: 6
                height: 26
                radius: 3
                x: knob.width / 2 + Math.cos(barAngle) * barRadius - width / 2
                y: knob.height / 2 + Math.sin(barAngle) * barRadius - height / 2
                rotation: barAngle * 180 / Math.PI - 90
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

                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: root.indicatorColor
                    shadowBlur: 0.62
                    blurMax: 8
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
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
            startValue = root.value
            startY = mouse.y
        }

        onPositionChanged: function(mouse) {
            if (!root.isDragging)
                return
            var range = Math.max(1, root.height)
            var delta = mouse.y - startY
            var span = root.maxValue - root.minValue
            var nextValue = startValue - delta / range * span * 1.35
            root.value = Math.max(root.minValue, Math.min(root.maxValue, nextValue))
        }

        onReleased: root.isDragging = false
        onCanceled: root.isDragging = false

        onDoubleClicked: {
            root.value = root.minValue
            root.potentiometerDoubleClicked()
        }

        onWheel: function(wheel) {
            var span = root.maxValue - root.minValue
            var step = span / 40
            root.value = Math.max(root.minValue, Math.min(root.maxValue, root.value + wheel.angleDelta.y / 120 * step))
            wheel.accepted = true
        }
    }
}
