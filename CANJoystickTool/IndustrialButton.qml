import QtQuick 6.5
import QtQuick.Effects

// 工业按钮组件 - 带LED指示灯
// 匹配 pad.html 中的 button-bezel + button-cap 设计
Item {
    id: root

    // 尺寸 - 匹配HTML: bezel w-14 h-14 (56px), cap w-10 h-10 (40px)
    property int bezelSize: 56
    property int capSize: 40

    // 颜色变体
    property string variant: "grey"  // red, grey, green, orange, black, blue

    // 主色、高光色、暗色 - 匹配HTML radial-gradient
    property color buttonColor: {
        switch(variant) {
            case "red": return "#ef4444"       // btn-red-main
            case "green": return "#00d648"     // btn-green-main
            case "orange": return "#f59e0b"    // btn-orange-main
            case "blue": return "#3b82f6"      // btn-blue-main
            case "black": return "#3f3f46"     // btn-black-main
            default: return "#9ca3af"          // btn-grey-main
        }
    }
    property color buttonColorLight: {
        switch(variant) {
            case "red": return "#f87171"
            case "green": return "#4ade80"
            case "orange": return "#fbbf24"
            case "blue": return "#60a5fa"
            case "black": return "#71717a"
            default: return "#e5e7eb"
        }
    }
    property color buttonColorDark: {
        switch(variant) {
            case "red": return "#b91c1c"       // btn-red-dark
            case "green": return "#009e35"     // btn-green-dark
            case "orange": return "#b45309"    // btn-orange-dark
            case "blue": return "#1d4ed8"      // btn-blue-dark
            case "black": return "#18181b"     // btn-black-dark
            default: return "#4b5563"          // btn-grey-dark
        }
    }

    // LED颜色
    property color ledColor: {
        switch(variant) {
            case "red": return "#ff3333"
            case "green": return "#00ff41"
            case "orange": return "#ffaa00"
            case "blue": return "#00e0ff"
            case "black": return "#00ff41"
            default: return "#00ff41"
        }
    }

    // 状态
    property bool isPressed: false
    property bool ledActive: false

    // 标签
    property string label: ""

    // 信号
    signal clicked()

    width: bezelSize
    height: bezelSize + (label !== "" ? 24 : 0)

    // 主按钮区域
    Item {
        id: buttonArea
        width: bezelSize
        height: bezelSize
        anchors.horizontalCenter: parent.horizontalCenter

        // 外圈 (button-bezel) - 匹配HTML多层阴影效果
        Rectangle {
            id: bezel
            anchors.fill: parent
            radius: width / 2

            // 外圈渐变 - 匹配HTML: linear-gradient(145deg, #2a2a2a, #000000)
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: "#2a2a2a" }
                GradientStop { position: 0.5; color: "#1a1a1a" }
                GradientStop { position: 1.0; color: "#000000" }
            }

            // 外圈阴影 - 匹配HTML: 3px 3px 6px rgba(0,0,0,0.3)
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#4D000000"
                shadowBlur: 0.5
                blurMax: 6
                shadowHorizontalOffset: 3
                shadowVerticalOffset: 3
            }

            // 左上高光边框 - 匹配HTML: -1px -1px 3px rgba(255,255,255,0.4)
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 1
                border.color: "#66FFFFFF"
            }

            // 内圈高光 - 匹配HTML: inset 1px 1px 2px rgba(255,255,255,0.1)
            Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: "#1AFFFFFF"
            }

            // 内按钮 (button-cap)
            Item {
                id: cap
                anchors.centerIn: parent
                width: capSize
                height: capSize

                // 按下效果 - 匹配HTML: scale(0.92) translateY(2px)
                scale: root.isPressed ? 0.92 : 1.0
                transform: Translate {
                    y: root.isPressed ? 2 : 0

                    Behavior on y {
                        NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                    }
                }

                Behavior on scale {
                    NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                }

                // 按钮阴影 - 匹配HTML: 0 3px 5px rgba(0,0,0,0.3)
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: !root.isPressed
                    shadowColor: "#4D000000"
                    shadowBlur: 0.5
                    blurMax: 5
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: root.isPressed ? 1 : 3
                }

                // 径向渐变按钮 - 匹配HTML: radial-gradient(circle at 35% 30%, ...)
                Canvas {
                    id: capCanvas
                    anchors.fill: parent

                    property color btnLight: buttonColorLight
                    property color btnMain: buttonColor
                    property color btnDark: buttonColorDark
                    property bool pressed: root.isPressed

                    onBtnLightChanged: requestPaint()
                    onBtnMainChanged: requestPaint()
                    onBtnDarkChanged: requestPaint()
                    onPressedChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)

                        var centerX = width * 0.35
                        var centerY = height * 0.30
                        var radius = width / 2

                        ctx.save()
                        ctx.beginPath()
                        ctx.arc(width / 2, height / 2, radius, 0, 2 * Math.PI)
                        ctx.clip()

                        // 径向渐变 - 匹配HTML: circle at 35% 30%
                        var gradient = ctx.createRadialGradient(
                            centerX, centerY, 0,
                            centerX, centerY, radius * 1.6
                        )
                        gradient.addColorStop(0, btnLight.toString())
                        gradient.addColorStop(0.4, btnMain.toString())
                        gradient.addColorStop(0.9, btnDark.toString())

                        ctx.fillStyle = gradient
                        ctx.fillRect(0, 0, width, height)

                        ctx.restore()
                    }

                    Component.onCompleted: requestPaint()
                }

                // 顶部高光 - 匹配HTML ::after 伪元素
                // filter: blur(2px); opacity: 0.8
                Rectangle {
                    id: highlight
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.topMargin: parent.height * 0.05
                    anchors.horizontalCenterOffset: -parent.width * 0.10
                    width: parent.width * 0.45
                    height: parent.height * 0.30
                    radius: height / 2
                    rotation: -45
                    opacity: root.isPressed ? 0.3 : 0.8
                    visible: variant !== "black"

                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#E6FFFFFF" }  // 90%白
                        GradientStop { position: 1.0; color: "transparent" }
                    }

                    Behavior on opacity {
                        NumberAnimation { duration: 100 }
                    }

                    // 模糊效果 - 匹配HTML: filter: blur(2px)
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blur: 0.4
                        blurMax: 4
                    }
                }

                // 黑色按钮的较弱高光
                Rectangle {
                    visible: variant === "black"
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.topMargin: parent.height * 0.05
                    anchors.horizontalCenterOffset: -parent.width * 0.10
                    width: parent.width * 0.45
                    height: parent.height * 0.30
                    radius: height / 2
                    rotation: -45
                    opacity: root.isPressed ? 0.15 : 0.3

                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#80FFFFFF" }
                        GradientStop { position: 1.0; color: "transparent" }
                    }

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blur: 0.4
                        blurMax: 4
                    }
                }

                // 按下时的内凹阴影 - 匹配HTML: inset 0 4px 8px rgba(0,0,0,0.4)
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    opacity: root.isPressed ? 1.0 : 0.0
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#66000000" }  // 40%黑
                        GradientStop { position: 0.3; color: "#33000000" }
                        GradientStop { position: 0.5; color: "transparent" }
                    }

                    Behavior on opacity {
                        NumberAnimation { duration: 100 }
                    }
                }

                // 底部内阴影 - 匹配HTML: inset 0 -3px 3px rgba(0,0,0,0.2)
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    opacity: root.isPressed ? 0.0 : 1.0
                    gradient: Gradient {
                        GradientStop { position: 0.7; color: "transparent" }
                        GradientStop { position: 1.0; color: "#33000000" }
                    }

                    Behavior on opacity {
                        NumberAnimation { duration: 100 }
                    }
                }

                // 顶部内高光 - 匹配HTML: inset 0 2px 4px rgba(255,255,255,0.7)
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    opacity: root.isPressed ? 0.0 : 1.0
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: variant === "black" ? "#4DFFFFFF" : "#B3FFFFFF" }
                        GradientStop { position: 0.15; color: "transparent" }
                    }

                    Behavior on opacity {
                        NumberAnimation { duration: 100 }
                    }
                }

                // 边缘高光环
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 1
                    border.color: root.isPressed ? "#1AFFFFFF" : "#4DFFFFFF"
                }
            }
        }

        // 点击区域
        MouseArea {
            anchors.fill: parent

            onPressed: {
                root.isPressed = true
                ledFlash.start()
            }

            onReleased: {
                root.isPressed = false
            }

            onClicked: {
                root.clicked()
            }
        }
    }

    // LED指示灯和标签行
    Row {
        anchors.top: buttonArea.bottom
        anchors.topMargin: 6
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 6
        visible: label !== ""

        // LED指示灯 - 匹配HTML: 4px×4px
        Rectangle {
            id: led
            width: 4
            height: 4
            radius: 2
            anchors.verticalCenter: parent.verticalCenter

            // 匹配HTML: background-color: #555 / ledColor
            color: ledActive ? ledColor : "#555555"

            // 匹配HTML: inset 0 1px 2px rgba(0,0,0,0.5)
            border.width: 1
            border.color: ledActive ? Qt.lighter(ledColor, 1.3) : "#1AFFFFFF"

            // LED发光效果 - 匹配HTML: box-shadow: 0 0 6px ledColor
            layer.enabled: ledActive
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: ledColor
                shadowBlur: 1.0
                blurMax: 10
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
            }

            // 内部高光点
            Rectangle {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -0.5
                width: 1.5
                height: 1.5
                radius: 0.75
                color: ledActive ? "#B3FFFFFF" : "#33FFFFFF"
            }
        }

        // 标签 - 匹配HTML: axis-label
        Text {
            text: root.label
            color: Constants.textSecondary
            font.pixelSize: 8
            font.weight: Font.Bold
            font.letterSpacing: 0.05
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // LED闪烁动画
    SequentialAnimation {
        id: ledFlash
        property bool wasActive: false

        onStarted: wasActive = ledActive

        PropertyAction { target: root; property: "ledActive"; value: true }
        PauseAnimation { duration: 200 }
        PropertyAction { target: root; property: "ledActive"; value: ledFlash.wasActive }
    }
}
