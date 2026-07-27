pragma ComponentBehavior: Bound
import QtQuick 6.5
import CANJoystickTool

// Compact dark XY pad: a square molded surface, coordinate references and a
// free-moving puck. There is deliberately no visible shaft.
Item {
    id: root
    objectName: "miniJoystick"

    property real xValue: 0.0
    property real yValue: 0.0
    property real minValue: -1.0
    property real maxValue: 1.0
    property bool readOnly: true
    property bool animationEnabled: true
    property bool isDragging: false
    property color housingColor: Constants.rollerHousingColor

    signal moved(real x, real y)
    signal released()
    signal joystickDoubleClicked()

    readonly property int designWidth: 124
    readonly property int designHeight: 124
    readonly property string visualStyle: "xy-pad-top-view"
    readonly property bool topView: true
    readonly property bool decorativeTicksEnabled: false
    readonly property real shadowOffsetX: 3
    readonly property real shadowOffsetY: 3
    readonly property string housingShadowStyle: "inset"
    readonly property bool externalHousingShadowEnabled: false
    readonly property bool housingFillsBounds: true
    readonly property string outerHousingStyle: "roller-flat"
    readonly property bool metallicHousingRimEnabled: false
    readonly property real travelRadius: 42
    readonly property real contentScale: width > 0 && height > 0
                                         ? Math.min(width / designWidth, height / designHeight)
                                         : 1
    readonly property real visualX: clampToUnit(animatedX)
    readonly property real visualY: clampToUnit(animatedY)

    property real animatedX: clampToUnit(normalizeAxis(xValue))
    property real animatedY: clampToUnit(normalizeAxis(yValue))

    implicitWidth: designWidth
    implicitHeight: designHeight
    width: implicitWidth
    height: implicitHeight

    function clampToUnit(candidate) {
        var numeric = Number(candidate)
        if (isNaN(numeric))
            return 0
        return Math.max(-1, Math.min(1, numeric))
    }

    function normalizeAxis(candidate) {
        var numeric = Number(candidate)
        if (isNaN(numeric) || maxValue <= minValue)
            return 0
        var bounded = Math.max(minValue, Math.min(maxValue, numeric))
        return (bounded - minValue) / (maxValue - minValue) * 2 - 1
    }

    function denormalizeAxis(candidate) {
        var normalized = clampToUnit(candidate)
        return minValue + (normalized + 1) * 0.5 * (maxValue - minValue)
    }

    function syncAnimatedValues() {
        animatedX = clampToUnit(normalizeAxis(xValue))
        animatedY = clampToUnit(normalizeAxis(yValue))
    }

    function setInteractivePosition(mouseX, mouseY) {
        var center = designWidth / 2
        var localX = (mouseX - (width - designWidth * contentScale) / 2) / contentScale
        var localY = (mouseY - (height - designHeight * contentScale) / 2) / contentScale
        var nx = clampToUnit((localX - center) / travelRadius)
        var ny = clampToUnit((localY - center) / travelRadius)
        xValue = denormalizeAxis(nx)
        yValue = denormalizeAxis(ny)
        moved(xValue, yValue)
    }

    onXValueChanged: syncAnimatedValues()
    onYValueChanged: syncAnimatedValues()
    onMinValueChanged: syncAnimatedValues()
    onMaxValueChanged: syncAnimatedValues()

    Behavior on animatedX {
        enabled: root.animationEnabled && !root.isDragging
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }

    Behavior on animatedY {
        enabled: root.animationEnabled && !root.isDragging
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }

    Item {
        id: designSpace
        width: root.designWidth
        height: root.designHeight
        anchors.centerIn: parent
        scale: root.contentScale

        Canvas {
            id: padSurface
            anchors.fill: parent
            antialiasing: true

            function roundedRectPath(ctx, x, y, width, height, radius) {
                var right = x + width
                var bottom = y + height
                ctx.beginPath()
                ctx.moveTo(x + radius, y)
                ctx.lineTo(right - radius, y)
                ctx.quadraticCurveTo(right, y, right, y + radius)
                ctx.lineTo(right, bottom - radius)
                ctx.quadraticCurveTo(right, bottom, right - radius, bottom)
                ctx.lineTo(x + radius, bottom)
                ctx.quadraticCurveTo(x, bottom, x, bottom - radius)
                ctx.lineTo(x, y + radius)
                ctx.quadraticCurveTo(x, y, x + radius, y)
                ctx.closePath()
            }

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)

                // Flat housing, exactly matching RollerWheel.
                roundedRectPath(ctx, 0, 0, 124, 124, 20)
                ctx.fillStyle = root.housingColor.toString()
                ctx.fill()

                // Broad, nearly flat molded XY surface.
                var surface = ctx.createLinearGradient(9, 6, 116, 120)
                surface.addColorStop(0.0, "#303336")
                surface.addColorStop(0.20, "#242729")
                surface.addColorStop(0.72, "#17191b")
                surface.addColorStop(1.0, "#0c0d0e")
                roundedRectPath(ctx, 4, 4, 116, 116, 17)
                ctx.fillStyle = surface
                ctx.fill()

                // Roller-style inset shading, clipped entirely inside the pad.
                ctx.save()
                roundedRectPath(ctx, 4, 4, 116, 116, 17)
                ctx.clip()

                var topInset = ctx.createLinearGradient(0, 4, 0, 26)
                topInset.addColorStop(0.0, "rgba(0, 0, 0, 0.58)")
                topInset.addColorStop(1.0, "rgba(0, 0, 0, 0.0)")
                ctx.fillStyle = topInset
                ctx.fillRect(4, 4, 116, 22)

                var leftInset = ctx.createLinearGradient(4, 0, 26, 0)
                leftInset.addColorStop(0.0, "rgba(0, 0, 0, 0.52)")
                leftInset.addColorStop(1.0, "rgba(0, 0, 0, 0.0)")
                ctx.fillStyle = leftInset
                ctx.fillRect(4, 4, 22, 116)

                var bottomInset = ctx.createLinearGradient(0, 98, 0, 120)
                bottomInset.addColorStop(0.0, "rgba(255, 255, 255, 0.0)")
                bottomInset.addColorStop(1.0, "rgba(255, 255, 255, 0.085)")
                ctx.fillStyle = bottomInset
                ctx.fillRect(4, 98, 116, 22)

                var rightInset = ctx.createLinearGradient(98, 0, 120, 0)
                rightInset.addColorStop(0.0, "rgba(255, 255, 255, 0.0)")
                rightInset.addColorStop(1.0, "rgba(255, 255, 255, 0.075)")
                ctx.fillStyle = rightInset
                ctx.fillRect(98, 4, 22, 116)
                ctx.restore()

                // A subtle vignette keeps the central surface tactile.
                var vignette = ctx.createRadialGradient(48, 42, 8, 62, 62, 68)
                vignette.addColorStop(0.0, "rgba(255, 255, 255, 0.045)")
                vignette.addColorStop(0.58, "rgba(0, 0, 0, 0.02)")
                vignette.addColorStop(1.0, "rgba(0, 0, 0, 0.34)")
                roundedRectPath(ctx, 5, 5, 114, 114, 16)
                ctx.fillStyle = vignette
                ctx.fill()

                // Sparse low-contrast grain suggests injection-molded plastic.
                ctx.fillStyle = "rgba(255, 255, 255, 0.020)"
                for (var i = 0; i < 90; ++i) {
                    var px = 13 + ((i * 37) % 97)
                    var py = 12 + ((i * 53) % 98)
                    ctx.fillRect(px, py, 0.7, 0.7)
                }

            }
        }

        // Square center-to-edge travel geometry used by the cap.
        Item {
            id: socket
            objectName: "miniJoystickSocket"
            x: 20
            y: 20
            width: 84
            height: 84
            property real radius: 8
        }

        Rectangle {
            id: xAxis
            objectName: "miniJoystickXAxis"
            x: 18
            y: 61.5
            width: 88
            height: 1
            color: "#2cffffff"
        }

        Rectangle {
            id: yAxis
            objectName: "miniJoystickYAxis"
            x: 61.5
            y: 18
            width: 1
            height: 88
            color: "#2cffffff"
        }

        Rectangle {
            id: centerMark
            objectName: "miniJoystickCenterMark"
            x: 55
            y: 55
            width: 14
            height: 14
            radius: 7
            color: "#202326"
            border.width: 1
            border.color: "#596065"

            Rectangle {
                anchors.centerIn: parent
                width: 3
                height: 3
                radius: 1.5
                color: "#0a0b0c"
            }
        }

        Item {
            id: thumb
            objectName: "miniJoystickThumb"
            width: 40
            height: 40
            x: (parent.width - width) / 2 + root.visualX * root.travelRadius
            y: (parent.height - height) / 2 + root.visualY * root.travelRadius
            z: 2

            Behavior on x {
                enabled: root.animationEnabled && !root.isDragging
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            Behavior on y {
                enabled: root.animationEnabled && !root.isDragging
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            Canvas {
                id: thumbSurface
                objectName: "miniJoystickThumbTop"
                anchors.fill: parent
                antialiasing: true

                function fillCircle(ctx, centerX, centerY, radius, fill) {
                    ctx.beginPath()
                    ctx.arc(centerX, centerY, radius, 0, Math.PI * 2)
                    ctx.closePath()
                    ctx.fillStyle = fill
                    ctx.fill()
                }

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)

                    ctx.save()
                    ctx.shadowColor = "rgba(0, 0, 0, 0.78)"
                    ctx.shadowBlur = 7
                    ctx.shadowOffsetX = root.shadowOffsetX
                    ctx.shadowOffsetY = root.shadowOffsetY
                    fillCircle(ctx, 20, 19, 17, "#090a0b")
                    ctx.restore()

                    var cap = ctx.createRadialGradient(14, 12, 2, 20, 20, 19)
                    cap.addColorStop(0.0, "#414548")
                    cap.addColorStop(0.30, "#292c2f")
                    cap.addColorStop(0.78, "#17191b")
                    cap.addColorStop(1.0, "#070808")
                    fillCircle(ctx, 20, 19, 17.5, cap)

                    ctx.strokeStyle = "rgba(225, 229, 232, 0.42)"
                    ctx.lineWidth = 0.9
                    ctx.beginPath()
                    ctx.arc(20, 19, 16.8, 0, Math.PI * 2)
                    ctx.stroke()

                    ctx.save()
                    ctx.shadowColor = "rgba(255, 151, 0, 0.72)"
                    ctx.shadowBlur = 4
                    fillCircle(ctx, 20, 19, 2.4, "#ff9700")
                    ctx.restore()
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: !root.readOnly
        hoverEnabled: true
        cursorShape: root.isDragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        onPressed: function(mouse) {
            root.isDragging = true
            root.setInteractivePosition(mouse.x, mouse.y)
        }

        onPositionChanged: function(mouse) {
            if (root.isDragging)
                root.setInteractivePosition(mouse.x, mouse.y)
        }

        onReleased: {
            root.isDragging = false
            root.released()
        }

        onDoubleClicked: {
            root.xValue = root.denormalizeAxis(0)
            root.yValue = root.denormalizeAxis(0)
            root.moved(root.xValue, root.yValue)
            root.joystickDoubleClicked()
        }
    }
}
