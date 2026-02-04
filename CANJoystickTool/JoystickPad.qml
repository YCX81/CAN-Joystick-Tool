import QtQuick 6.5
import QtQuick.Effects

// XY摇杆控制区域 - Ive风格浅色Neumorphic设计
Item {
    id: root

    // 输出值 (-1.0 到 1.0)
    property real xValue: 0.0
    property real yValue: 0.0

    // 配置
    property int padSize: 380
    property int handleSize: 64
    property real deadzone: 0.0
    property real edgeThreshold: 0.95  // 触发边缘光效的阈值
    property bool returnToCenter: true
    property int returnDuration: 500

    // 颜色配置 - Ive风格浅色
    property color grooveColor: "#e6e6e6"
    property color gridColor: "#08000000"  // 3%透明度黑色
    property color handleBaseColor: "#e0e0e0"
    property color handleHighlight: "#ffffff"
    property color edgeGlowColor: "#9934c759"  // 绿色边缘光 60%透明度
    property color activeGlowColor: "#00e0ff"  // 青色

    // 模式: "omnidirectional"(万向), "cross"(十字), "vertical"(Y轴), "horizontal"(X轴)
    property string mode: "omnidirectional"

    // 状态
    property bool isDragging: false
    property bool isAtEdge: false

    // 信号
    signal moved(real x, real y)
    signal released()
    signal edgeReached(string direction)

    width: padSize
    height: padSize

    // 计算边缘状态
    onXValueChanged: checkEdge()
    onYValueChanged: checkEdge()

    function checkEdge() {
        var wasAtEdge = isAtEdge
        isAtEdge = Math.abs(xValue) > edgeThreshold || Math.abs(yValue) > edgeThreshold

        if (isAtEdge && !wasAtEdge) {
            var dir = ""
            if (Math.abs(xValue) > edgeThreshold) dir += xValue > 0 ? "right" : "left"
            if (Math.abs(yValue) > edgeThreshold) dir += yValue > 0 ? "down" : "up"
            edgeReached(dir)
        }
    }

    // 计算边缘发光强度 - 渐进式从threshold到1.0
    function calcGlowIntensity(value, threshold) {
        var absVal = Math.abs(value)
        if (absVal <= threshold) return 0
        return Math.min((absVal - threshold) / (1.0 - threshold), 1.0)
    }

    // 圆角遮罩源 - 使用layer.enabled强制渲染纹理，即使visible:false
    Item {
        id: grooveMask
        anchors.fill: parent
        layer.enabled: true  // 关键：强制渲染到FBO纹理
        visible: false       // 不显示，但纹理仍会被创建

        Rectangle {
            anchors.fill: parent
            radius: 36
            color: "#FFFFFF"
        }
    }

    // 凹槽底座 - Neumorphic内凹效果
    Rectangle {
        id: groove
        anchors.fill: parent
        radius: 36
        color: grooveColor
        border.width: 1
        border.color: "#4DFFFFFF"

        // 使用 MultiEffect 的 mask 实现真正的圆角裁剪
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: grooveMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        // 内陷阴影效果 - 仅万向模式显示
        Item {
            id: insetShadows
            anchors.fill: parent
            visible: mode === "omnidirectional"

            // 左上内阴影 (模拟凹陷)
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 20
                radius: groove.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#1F000000" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // 左侧内阴影
            Rectangle {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                width: 20
                radius: groove.radius
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#1F000000" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // 右下内高光
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 20
                radius: groove.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: "#FFFFFFFF" }
                }
            }

            // 右侧内高光
            Rectangle {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                width: 20
                radius: groove.radius
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: "#CCFFFFFF" }
                }
            }
        }

        // 网格背景 - 仅万向模式显示
        Canvas {
            id: gridCanvas
            anchors.fill: parent
            anchors.margins: 12
            visible: mode === "omnidirectional"

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.strokeStyle = gridColor.toString()
                ctx.lineWidth = 1

                var step = 40

                // 垂直线
                for (var x = step; x < width; x += step) {
                    ctx.beginPath()
                    ctx.moveTo(x, 0)
                    ctx.lineTo(x, height)
                    ctx.stroke()
                }

                // 水平线
                for (var y = step; y < height; y += step) {
                    ctx.beginPath()
                    ctx.moveTo(0, y)
                    ctx.lineTo(width, y)
                    ctx.stroke()
                }

                // 中心十字线 - 凹槽效果（暗线+亮线）
                var cx = Math.floor(width / 2)
                var cy = Math.floor(height / 2)

                // 暗线（左/上侧阴影）
                ctx.strokeStyle = "#18000000"  // 约9%黑色
                ctx.lineWidth = 1
                ctx.beginPath()
                ctx.moveTo(cx, 0)
                ctx.lineTo(cx, height)
                ctx.moveTo(0, cy)
                ctx.lineTo(width, cy)
                ctx.stroke()

                // 亮线（右/下侧高光），偏移1像素
                ctx.strokeStyle = "#30FFFFFF"  // 约19%白色
                ctx.lineWidth = 1
                ctx.beginPath()
                ctx.moveTo(cx + 1, 0)
                ctx.lineTo(cx + 1, height)
                ctx.moveTo(0, cy + 1)
                ctx.lineTo(width, cy + 1)
                ctx.stroke()
            }

            Component.onCompleted: requestPaint()
        }

        // ============================================================
        // 轨道凹槽 - 根据模式显示不同形状
        // ============================================================
        Item {
            id: trackGroove
            anchors.fill: parent
            anchors.margins: 12
            visible: mode !== "omnidirectional"

            property int grooveWidth: 24  // 凹槽宽度
            property int cornerRadius: 8  // 内凹圆角半径
            property color grooveBase: "#d8d8d8"  // 凹槽底色
            property color shadowColor: "#12000000"  // 浅阴影
            property color highlightColor: "#20FFFFFF"  // 浅高光

            // 凹槽形状 - 用Canvas绘制
            Canvas {
                id: trackCanvas
                anchors.fill: parent

                property string currentMode: mode

                onCurrentModeChanged: requestPaint()

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)

                    var cx = width / 2
                    var cy = height / 2
                    var gw = trackGroove.grooveWidth / 2  // 半宽
                    var r = trackGroove.cornerRadius

                    ctx.fillStyle = trackGroove.grooveBase.toString()
                    ctx.beginPath()

                    if (mode === "cross") {
                        // 十字形 - 内凹圆角 + 端点圆角
                        var er = gw  // 端点圆角半径（半圆）

                        // 从上端点开始，顺时针绘制
                        ctx.moveTo(cx - gw, er)  // 上端点左边
                        ctx.arcTo(cx - gw, 0, cx, 0, er)  // 上端点左上圆角
                        ctx.arcTo(cx + gw, 0, cx + gw, er, er)  // 上端点右上圆角
                        ctx.lineTo(cx + gw, cy - gw - r)  // 向下到右上内凹
                        ctx.quadraticCurveTo(cx + gw, cy - gw, cx + gw + r, cy - gw)  // 右上内凹圆角
                        ctx.lineTo(width - er, cy - gw)  // 右端点上边
                        ctx.arcTo(width, cy - gw, width, cy, er)  // 右端点右上圆角
                        ctx.arcTo(width, cy + gw, width - er, cy + gw, er)  // 右端点右下圆角
                        ctx.lineTo(cx + gw + r, cy + gw)  // 向左到右下内凹
                        ctx.quadraticCurveTo(cx + gw, cy + gw, cx + gw, cy + gw + r)  // 右下内凹圆角
                        ctx.lineTo(cx + gw, height - er)  // 向下到下端点
                        ctx.arcTo(cx + gw, height, cx, height, er)  // 下端点右下圆角
                        ctx.arcTo(cx - gw, height, cx - gw, height - er, er)  // 下端点左下圆角
                        ctx.lineTo(cx - gw, cy + gw + r)  // 向上到左下内凹
                        ctx.quadraticCurveTo(cx - gw, cy + gw, cx - gw - r, cy + gw)  // 左下内凹圆角
                        ctx.lineTo(er, cy + gw)  // 左端点下边
                        ctx.arcTo(0, cy + gw, 0, cy, er)  // 左端点左下圆角
                        ctx.arcTo(0, cy - gw, er, cy - gw, er)  // 左端点左上圆角
                        ctx.lineTo(cx - gw - r, cy - gw)  // 向右到左上内凹
                        ctx.quadraticCurveTo(cx - gw, cy - gw, cx - gw, cy - gw - r)  // 左上内凹圆角
                        ctx.closePath()
                    } else if (mode === "vertical") {
                        // Y轴 - 垂直凹槽，两端圆角
                        ctx.roundedRect(cx - gw, 0, trackGroove.grooveWidth, height, gw, gw)
                    } else if (mode === "horizontal") {
                        // X轴 - 水平凹槽，两端圆角
                        ctx.roundedRect(0, cy - gw, width, trackGroove.grooveWidth, gw, gw)
                    }

                    ctx.fill()
                }

                Component.onCompleted: requestPaint()
            }

            // ============================================================
            // 阴影层 - 使用 MultiEffect mask 裁剪到凹槽形状
            // ============================================================
            Item {
                id: shadowMask
                anchors.fill: parent
                layer.enabled: true
                visible: false

                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)

                        var cx = width / 2
                        var cy = height / 2
                        var gw = trackGroove.grooveWidth / 2
                        var r = trackGroove.cornerRadius

                        ctx.fillStyle = "#FFFFFF"
                        ctx.beginPath()

                        if (mode === "cross") {
                            var er = gw
                            ctx.moveTo(cx - gw, er)
                            ctx.arcTo(cx - gw, 0, cx, 0, er)
                            ctx.arcTo(cx + gw, 0, cx + gw, er, er)
                            ctx.lineTo(cx + gw, cy - gw - r)
                            ctx.quadraticCurveTo(cx + gw, cy - gw, cx + gw + r, cy - gw)
                            ctx.lineTo(width - er, cy - gw)
                            ctx.arcTo(width, cy - gw, width, cy, er)
                            ctx.arcTo(width, cy + gw, width - er, cy + gw, er)
                            ctx.lineTo(cx + gw + r, cy + gw)
                            ctx.quadraticCurveTo(cx + gw, cy + gw, cx + gw, cy + gw + r)
                            ctx.lineTo(cx + gw, height - er)
                            ctx.arcTo(cx + gw, height, cx, height, er)
                            ctx.arcTo(cx - gw, height, cx - gw, height - er, er)
                            ctx.lineTo(cx - gw, cy + gw + r)
                            ctx.quadraticCurveTo(cx - gw, cy + gw, cx - gw - r, cy + gw)
                            ctx.lineTo(er, cy + gw)
                            ctx.arcTo(0, cy + gw, 0, cy, er)
                            ctx.arcTo(0, cy - gw, er, cy - gw, er)
                            ctx.lineTo(cx - gw - r, cy - gw)
                            ctx.quadraticCurveTo(cx - gw, cy - gw, cx - gw, cy - gw - r)
                            ctx.closePath()
                        } else if (mode === "vertical") {
                            ctx.roundedRect(cx - gw, 0, trackGroove.grooveWidth, height, gw, gw)
                        } else if (mode === "horizontal") {
                            ctx.roundedRect(0, cy - gw, width, trackGroove.grooveWidth, gw, gw)
                        }

                        ctx.fill()
                    }

                    property string currentMode: mode
                    onCurrentModeChanged: requestPaint()
                    Component.onCompleted: requestPaint()
                }
            }

            // 阴影内容层
            Item {
                id: shadowLayer
                anchors.fill: parent
                visible: mode !== "omnidirectional"

                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: shadowMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }

                // 垂直阴影（Y轴和十字模式的垂直部分）
                Item {
                    visible: mode === "vertical" || mode === "cross"
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: trackGroove.grooveWidth

                    // 左侧阴影
                    Rectangle {
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        width: parent.width * 0.4
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: trackGroove.shadowColor }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }
                    // 右侧高光
                    Rectangle {
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        width: parent.width * 0.4
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 1.0; color: trackGroove.highlightColor }
                        }
                    }
                }

                // 水平阴影（X轴和十字模式的水平部分）
                Item {
                    visible: mode === "horizontal" || mode === "cross"
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: trackGroove.grooveWidth

                    // 上侧阴影
                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: parent.height * 0.4
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: trackGroove.shadowColor }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }
                    // 下侧高光
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: parent.height * 0.4
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 1.0; color: trackGroove.highlightColor }
                        }
                    }
                }
            }
        }

        // ============================================================
        // 边缘发光效果 - 万向模式整边发光，其他模式圆形边界发光
        // ============================================================
        Item {
            id: edgeGlowContainer
            anchors.fill: parent
            z: 1

            property color glowColorBase: Qt.rgba(52/255, 199/255, 89/255, 1.0)
            property int animDuration: 250
            property int circleSize: 60  // 圆形发光尺寸

            // ---- 右边缘发光 ----
            Rectangle {
                id: rightGlow
                property real intensity: xValue > 0 ? root.calcGlowIntensity(xValue, edgeThreshold) : 0
                property bool isCircleMode: mode !== "omnidirectional"

                anchors.right: parent.right
                anchors.rightMargin: isCircleMode ? -20 : -15
                width: isCircleMode ? edgeGlowContainer.circleSize : 30
                radius: isCircleMode ? edgeGlowContainer.circleSize / 2 : 4
                color: edgeGlowContainer.glowColorBase
                opacity: intensity * 0.6
                visible: intensity > 0.01 && (mode === "omnidirectional" || mode === "cross" || mode === "horizontal")

                states: [
                    State {
                        name: "circle"
                        when: rightGlow.isCircleMode
                        AnchorChanges {
                            target: rightGlow
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.top: undefined
                            anchors.bottom: undefined
                        }
                        PropertyChanges { target: rightGlow; height: edgeGlowContainer.circleSize }
                    },
                    State {
                        name: "bar"
                        when: !rightGlow.isCircleMode
                        AnchorChanges {
                            target: rightGlow
                            anchors.verticalCenter: undefined
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                        }
                    }
                ]

                layer.enabled: visible
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: 1.0
                    blurMax: rightGlow.isCircleMode ? 40 : 35
                }
            }

            // ---- 左边缘发光 ----
            Rectangle {
                id: leftGlow
                property real intensity: xValue < 0 ? root.calcGlowIntensity(xValue, edgeThreshold) : 0
                property bool isCircleMode: mode !== "omnidirectional"

                anchors.left: parent.left
                anchors.leftMargin: isCircleMode ? -20 : -15
                width: isCircleMode ? edgeGlowContainer.circleSize : 30
                radius: isCircleMode ? edgeGlowContainer.circleSize / 2 : 4
                color: edgeGlowContainer.glowColorBase
                opacity: intensity * 0.6
                visible: intensity > 0.01 && (mode === "omnidirectional" || mode === "cross" || mode === "horizontal")

                states: [
                    State {
                        name: "circle"
                        when: leftGlow.isCircleMode
                        AnchorChanges {
                            target: leftGlow
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.top: undefined
                            anchors.bottom: undefined
                        }
                        PropertyChanges { target: leftGlow; height: edgeGlowContainer.circleSize }
                    },
                    State {
                        name: "bar"
                        when: !leftGlow.isCircleMode
                        AnchorChanges {
                            target: leftGlow
                            anchors.verticalCenter: undefined
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                        }
                    }
                ]

                layer.enabled: visible
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: 1.0
                    blurMax: leftGlow.isCircleMode ? 40 : 35
                }
            }

            // ---- 下边缘发光 ----
            Rectangle {
                id: bottomGlow
                property real intensity: yValue > 0 ? root.calcGlowIntensity(yValue, edgeThreshold) : 0
                property bool isCircleMode: mode !== "omnidirectional"

                anchors.bottom: parent.bottom
                anchors.bottomMargin: isCircleMode ? -20 : -15
                height: isCircleMode ? edgeGlowContainer.circleSize : 30
                radius: isCircleMode ? edgeGlowContainer.circleSize / 2 : 4
                color: edgeGlowContainer.glowColorBase
                opacity: intensity * 0.6
                visible: intensity > 0.01 && (mode === "omnidirectional" || mode === "cross" || mode === "vertical")

                states: [
                    State {
                        name: "circle"
                        when: bottomGlow.isCircleMode
                        AnchorChanges {
                            target: bottomGlow
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.left: undefined
                            anchors.right: undefined
                        }
                        PropertyChanges { target: bottomGlow; width: edgeGlowContainer.circleSize }
                    },
                    State {
                        name: "bar"
                        when: !bottomGlow.isCircleMode
                        AnchorChanges {
                            target: bottomGlow
                            anchors.horizontalCenter: undefined
                            anchors.left: parent.left
                            anchors.right: parent.right
                        }
                    }
                ]

                layer.enabled: visible
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: 1.0
                    blurMax: bottomGlow.isCircleMode ? 40 : 35
                }
            }

            // ---- 上边缘发光 ----
            Rectangle {
                id: topGlow
                property real intensity: yValue < 0 ? root.calcGlowIntensity(yValue, edgeThreshold) : 0
                property bool isCircleMode: mode !== "omnidirectional"

                anchors.top: parent.top
                anchors.topMargin: isCircleMode ? -20 : -15
                height: isCircleMode ? edgeGlowContainer.circleSize : 30
                radius: isCircleMode ? edgeGlowContainer.circleSize / 2 : 4
                color: edgeGlowContainer.glowColorBase
                opacity: intensity * 0.6
                visible: intensity > 0.01 && (mode === "omnidirectional" || mode === "cross" || mode === "vertical")

                states: [
                    State {
                        name: "circle"
                        when: topGlow.isCircleMode
                        AnchorChanges {
                            target: topGlow
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.left: undefined
                            anchors.right: undefined
                        }
                        PropertyChanges { target: topGlow; width: edgeGlowContainer.circleSize }
                    },
                    State {
                        name: "bar"
                        when: !topGlow.isCircleMode
                        AnchorChanges {
                            target: topGlow
                            anchors.horizontalCenter: undefined
                            anchors.left: parent.left
                            anchors.right: parent.right
                        }
                    }
                ]

                layer.enabled: visible
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: 1.0
                    blurMax: topGlow.isCircleMode ? 40 : 35
                }

                Behavior on intensity {
                    NumberAnimation { duration: edgeGlowContainer.animDuration; easing.type: Easing.OutQuad }
                }
            }
        }

        // 手柄容器
        Item {
            id: handleContainer
            z: 2  // 确保手柄在边缘发光层之上
            anchors.fill: parent
            anchors.margins: handleSize / 2 + 4  // 32 + 4 = 36

            // 手柄
            Rectangle {
                id: handle
                width: handleSize
                height: handleSize
                radius: handleSize / 2

                x: (parent.width / 2) + (xValue * parent.width / 2) - width/2
                y: (parent.height / 2) + (yValue * parent.height / 2) - height/2

                // 手柄渐变
                gradient: Gradient {
                    GradientStop { position: 0.0; color: handleHighlight }
                    GradientStop { position: 0.4; color: "#f0f0f0" }
                    GradientStop { position: 1.0; color: handleBaseColor }
                }

                // 内边框
                border.width: 1
                border.color: "#33FFFFFF"

                // 手柄阴影
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: "#26000000"
                    shadowBlur: 1.0
                    blurMax: 24
                    shadowHorizontalOffset: 12 + xValue * 7
                    shadowVerticalOffset: 12 + yValue * 7
                }

                // 手柄顶部高光
                Rectangle {
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.topMargin: 4
                    width: parent.width * 0.5
                    height: parent.height * 0.25
                    radius: height / 2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#50ffffff" }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                // 中心点
                Item {
                    id: knobLight
                    anchors.centerIn: parent
                    width: 8
                    height: 8

                    // 发光层 - 用小圆点+大模糊模拟自然光晕衰减
                    Rectangle {
                        id: glowLayer
                        anchors.centerIn: parent
                        width: 8   // 小尺寸光源
                        height: 8
                        radius: 4
                        color: activeGlowColor
                        opacity: isDragging ? 0.9 : 0
                        visible: opacity > 0

                        Behavior on opacity {
                            NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                        }

                        layer.enabled: visible
                        layer.effect: MultiEffect {
                            blurEnabled: true
                            blur: 1.0
                            blurMax: 20  // 大模糊范围产生自然扩散
                        }
                    }

                    // 主体圆点 - 使用线性渐变模拟内凹效果
                    Rectangle {
                        id: knobLightMain
                        anchors.centerIn: parent
                        width: 8
                        height: 8
                        radius: 4

                        // 135度渐变：左上暗，右下亮
                        gradient: Gradient {
                            orientation: Gradient.Vertical
                            GradientStop {
                                position: 0.0
                                color: isDragging ? activeGlowColor : "#909090"
                                Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutQuad } }
                            }
                            GradientStop {
                                position: 1.0
                                color: isDragging ? Qt.lighter(activeGlowColor, 1.2) : "#b0b0b0"
                                Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutQuad } }
                            }
                        }

                        // 底部高光阴影
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            shadowEnabled: !isDragging
                            shadowColor: "#80FFFFFF"
                            shadowBlur: 0.1
                            shadowVerticalOffset: 1
                            shadowHorizontalOffset: 0
                        }
                    }
                }

                // 回中动画
                Behavior on x {
                    enabled: !isDragging
                    NumberAnimation {
                        duration: returnDuration
                        easing.type: Easing.OutBack
                        easing.overshoot: 0.5
                    }
                }
                Behavior on y {
                    enabled: !isDragging
                    NumberAnimation {
                        duration: returnDuration
                        easing.type: Easing.OutBack
                        easing.overshoot: 0.5
                    }
                }
            }
        }
    }

    // 拖拽交互区域 - 必须在groove外部以接收完整鼠标事件
    MouseArea {
        id: dragArea
        anchors.fill: parent

        onPressed: function(mouse) {
            isDragging = true
            updatePosition(mouse.x, mouse.y)
        }

        onPositionChanged: function(mouse) {
            if (isDragging) {
                updatePosition(mouse.x, mouse.y)
            }
        }

        onReleased: function(mouse) {
            isDragging = false
            if (returnToCenter) {
                xValue = 0
                yValue = 0
            }
            root.released()
        }

        function updatePosition(mouseX, mouseY) {
            var containerWidth = handleContainer.width
            var containerHeight = handleContainer.height
            var centerX = width / 2
            var centerY = height / 2

            // 计算相对于中心的偏移
            var dx = mouseX - centerX
            var dy = mouseY - centerY

            // 归一化到 -1 ~ 1
            var nx = dx / (containerWidth / 2)
            var ny = dy / (containerHeight / 2)

            // 方形限制
            if (Math.abs(nx) > 1) nx = nx > 0 ? 1 : -1
            if (Math.abs(ny) > 1) ny = ny > 0 ? 1 : -1

            // 应用死区
            if (Math.abs(nx) < deadzone) nx = 0
            if (Math.abs(ny) < deadzone) ny = 0

            // 根据模式限制移动方向
            if (mode === "vertical") {
                nx = 0  // Y轴模式：锁定水平方向
            } else if (mode === "horizontal") {
                ny = 0  // X轴模式：锁定垂直方向
            } else if (mode === "cross") {
                // 十字模式：只能沿十字轨道移动，选择主要方向
                if (Math.abs(nx) > Math.abs(ny)) {
                    ny = 0  // 水平方向为主，锁定垂直
                } else {
                    nx = 0  // 垂直方向为主，锁定水平
                }
            }

            xValue = nx
            yValue = ny
            moved(xValue, yValue)
        }
    }
}
