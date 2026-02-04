import QtQuick 6.5
import QtQuick.Effects

// 工业按钮组件 - 带LED指示灯
Item {
    id: root

    // 尺寸
    property int bezelSize: 56       // 外圈尺寸
    property int capSize: 40         // 内按钮尺寸

    // 颜色变体
    property string variant: "grey"  // red, grey, green, orange, black, blue
    property color buttonColor: {
        switch(variant) {
            case "red": return Constants.buttonRedColor
            case "green": return Constants.buttonGreenColor
            case "orange": return Constants.buttonOrangeColor
            case "blue": return Constants.buttonBlueColor
            case "black": return Constants.buttonBlackColor
            default: return Constants.buttonGreyColor  // grey
        }
    }
    property color buttonColorLight: Qt.lighter(buttonColor, 1.4)
    property color buttonColorDark: Qt.darker(buttonColor, 1.3)

    // LED颜色 (默认与按钮同色)
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

        // 外圈 (button-bezel)
        Rectangle {
            id: bezel
            anchors.fill: parent
            radius: width / 2
            color: "transparent"

            // 外圈渐变
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#2a2a2a" }
                GradientStop { position: 0.5; color: "#1a1a1a" }
                GradientStop { position: 1.0; color: "#000000" }
            }

            // 外圈阴影和高光
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#4D000000"
                shadowBlur: 0.5
                blurMax: 6
                shadowHorizontalOffset: 3
                shadowVerticalOffset: 3
            }

            // 高光边框
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 1
                border.color: "#33FFFFFF"
            }

            // 内阴影环
            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: width / 2
                color: "transparent"
                border.width: 2
                border.color: "#1A000000"
            }

            // 内按钮 (button-cap) - Canvas实现径向渐变
            Item {
                id: cap
                anchors.centerIn: parent
                width: capSize
                height: capSize

                // 按下效果
                scale: root.isPressed ? 0.92 : 1.0
                y: root.isPressed ? 2 : 0

                Behavior on scale {
                    NumberAnimation { duration: 50; easing.type: Easing.OutQuad }
                }
                Behavior on y {
                    NumberAnimation { duration: 50; easing.type: Easing.OutQuad }
                }

                // 按钮阴影
                layer.enabled: !root.isPressed
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: "#4D000000"
                    shadowBlur: 0.5
                    blurMax: 5
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 3
                }

                // 径向渐变按钮 (radial-gradient at 35% 30%)
                Canvas {
                    id: capCanvas
                    anchors.fill: parent

                    property color btnLight: buttonColorLight
                    property color btnMain: buttonColor
                    property color btnDark: buttonColorDark

                    onBtnLightChanged: requestPaint()
                    onBtnMainChanged: requestPaint()
                    onBtnDarkChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)

                        var centerX = width * 0.35
                        var centerY = height * 0.30
                        var radius = width / 2

                        // 绘制圆形裁剪区域
                        ctx.save()
                        ctx.beginPath()
                        ctx.arc(width / 2, height / 2, radius, 0, 2 * Math.PI)
                        ctx.clip()

                        // 径向渐变 (从高光点向外扩散)
                        var gradient = ctx.createRadialGradient(
                            centerX, centerY, 0,
                            centerX, centerY, radius * 1.5
                        )
                        gradient.addColorStop(0, btnLight.toString())
                        gradient.addColorStop(0.4, btnMain.toString())
                        gradient.addColorStop(1, btnDark.toString())

                        ctx.fillStyle = gradient
                        ctx.fillRect(0, 0, width, height)

                        ctx.restore()
                    }

                    Component.onCompleted: requestPaint()
                }

                // 圆形遮罩边框
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 1
                    border.color: "#00000000"
                }

                // 顶部高光 (blur效果)
                Rectangle {
                    id: highlight
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.topMargin: parent.height * 0.08
                    anchors.horizontalCenterOffset: -parent.width * 0.08
                    width: parent.width * 0.45
                    height: parent.height * 0.30
                    radius: height / 2
                    rotation: -45
                    opacity: 0.7

                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#FFFFFFFF" }
                        GradientStop { position: 1.0; color: "transparent" }
                    }

                    // 模糊效果
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blur: 0.3
                        blurMax: 4
                    }
                }

                // 按下时的内凹阴影
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    visible: root.isPressed
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#40000000" }
                        GradientStop { position: 0.4; color: "transparent" }
                    }
                }

                // 边缘高光
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 1
                    border.color: root.isPressed ? "#1AFFFFFF" : "#33FFFFFF"
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

        // LED指示灯
        Rectangle {
            id: led
            width: 6
            height: 6
            radius: 3
            anchors.verticalCenter: parent.verticalCenter

            color: ledActive ? ledColor : "#555555"
            border.width: 1
            border.color: "#26FFFFFF"

            // LED发光效果
            layer.enabled: ledActive
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: ledColor
                shadowBlur: 1.0
                blurMax: 8
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
            }

            // 内部高光
            Rectangle {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -1
                width: 2
                height: 2
                radius: 1
                color: ledActive ? "#80FFFFFF" : "#26FFFFFF"
            }
        }

        // 标签
        Text {
            text: root.label
            color: Constants.textSecondary
            font.pixelSize: 8
            font.weight: Font.Bold
            font.letterSpacing: 0.5
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
