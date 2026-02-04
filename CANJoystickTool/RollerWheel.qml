import QtQuick 6.5
import QtQuick.Effects

// 滚轮核心组件 - 模拟真实滚轮纹理和交互
Item {
    id: root

    // 配置属性
    property string orientation: "vertical"    // "vertical" 或 "horizontal"
    property real value: 0.0                   // -1.0 到 1.0
    property real minValue: -1.0
    property real maxValue: 1.0

    // 外观配置
    property color housingColor: Constants.rollerHousingColor
    property color wheelColor: Constants.rollerWheelColor
    property color indicatorColor: Constants.rollerIndicatorColor

    // 交互状态
    property bool isDragging: false

    // 信号 (value属性自带valueChanged信号，无需重复定义)
    signal rollerDoubleClicked()

    // 默认尺寸 (宽度为原来的1.5倍)
    width: orientation === "vertical" ? 72 : 200
    height: orientation === "vertical" ? 200 : 60

    // 外壳 (roller-housing)
    Rectangle {
        id: housing
        anchors.fill: parent
        radius: 12
        color: housingColor

        // 内凹阴影效果 - 顶部/左侧暗
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                orientation: root.orientation === "vertical" ?
                             Gradient.Horizontal : Gradient.Vertical
                GradientStop { position: 0.0; color: "#26000000" }  // 15%黑
                GradientStop { position: 0.2; color: "transparent" }
                GradientStop { position: 0.8; color: "transparent" }
                GradientStop { position: 1.0; color: "#15FFFFFF" }  // 8%白高光
            }
        }

        // 滚轮容器
        Item {
            id: wheelContainer
            anchors.fill: parent
            anchors.margins: 4

            // 滚轮主体 - 使用layer+mask实现圆角裁剪
            Rectangle {
                id: wheelBody
                anchors.fill: parent
                radius: 12
                color: wheelColor  // 黑色底色 #222222

                // 启用layer实现真正的圆角遮罩
                layer.enabled: true
                layer.smooth: true
                layer.samples: 4  // 多重采样抗锯齿
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                    maskSource: ShaderEffectSource {
                        sourceItem: Rectangle {
                            width: wheelBody.width
                            height: wheelBody.height
                            radius: 12
                            antialiasing: true
                        }
                    }
                }

                // 条纹纹理 (Canvas绘制)
                Canvas {
                    id: stripeCanvas
                    anchors.fill: parent

                    // 纹理偏移量，随value变化 (与指针同向移动)
                    // 竖向用负值，横向用正值
                    property real textureOffset: root.orientation === "vertical" ?
                        -root.value * 90 : root.value * 90

                    onTextureOffsetChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)

                        // 刻度线参数
                        var period = 16
                        var greyWidth = 4

                        if (root.orientation === "vertical") {
                            // 水平条纹 (竖向滚轮)
                            var startY = (textureOffset % period) - period * 2
                            for (var y = startY; y < height + period; y += period) {
                                // 深灰刻度线 (0-4px)
                                ctx.fillStyle = "#2a2a2a"
                                ctx.fillRect(0, y, width, greyWidth)
                                // 纯黑区域增强对比 (5-8px)
                                ctx.fillStyle = "#000000"
                                ctx.fillRect(0, y + 5, width, 3)
                            }
                        } else {
                            // 垂直条纹 (横向滚轮)
                            var startX = (textureOffset % period) - period * 2
                            for (var x = startX; x < width + period; x += period) {
                                ctx.fillStyle = "#2a2a2a"
                                ctx.fillRect(x, 0, greyWidth, height)
                                ctx.fillStyle = "#000000"
                                ctx.fillRect(x + 5, 0, 3, height)
                            }
                        }
                    }

                    Component.onCompleted: requestPaint()
                }

                // 滚轮边缘渐变效果 (模拟圆柱形)
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        // 竖向滚轮用垂直渐变(to bottom)，横向滚轮用水平渐变(to right)
                        orientation: root.orientation === "vertical" ?
                                     Gradient.Vertical : Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#E6000000" }   // 90%黑
                        GradientStop { position: 0.5; color: "#26FFFFFF" }   // 15%白高光
                        GradientStop { position: 1.0; color: "#E6000000" }   // 90%黑
                    }
                }

                // 内凹阴影边框
                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: "transparent"
                    border.width: 1
                    border.color: "#26FFFFFF"
                }

                // 内凹阴影效果 (inset 0 0 4px rgba(0,0,0,0.9))
                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: "transparent"
                    border.width: 4
                    border.color: "#E6000000"  // 90% black
                    opacity: 0.5
                }
            }

            // 指示器 (roller-indicator)
            Rectangle {
                id: indicator
                color: indicatorColor
                radius: 2

                // 垂直滚轮: 水平指示线
                width: root.orientation === "vertical" ? parent.width * 0.8 : 5
                height: root.orientation === "vertical" ? 5 : parent.height * 0.8

                // 居中定位作为基准
                anchors.centerIn: parent

                // 指针随值移动
                transform: Translate {
                    x: root.orientation === "horizontal" ? root.value * 90 : 0
                    y: root.orientation === "vertical" ? -root.value * 90 : 0
                }

                // 发光效果
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: indicatorColor
                    shadowBlur: 0.6
                    blurMax: 6
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
                }
            }
        }
    }

    // 拖拽交互区域
    MouseArea {
        id: dragArea
        anchors.fill: parent
        hoverEnabled: true

        property real startValue
        property real startPos

        cursorShape: root.orientation === "vertical" ? Qt.SizeVerCursor : Qt.SizeHorCursor

        onPressed: function(mouse) {
            root.isDragging = true
            startValue = root.value
            startPos = root.orientation === "vertical" ? mouse.y : mouse.x
        }

        onPositionChanged: function(mouse) {
            if (!root.isDragging) return

            var currentPos = root.orientation === "vertical" ? mouse.y : mouse.x
            var delta = currentPos - startPos
            var range = root.orientation === "vertical" ? height : width

            // 敏感度系数
            var sensitivity = 1.5

            // 垂直滚轮: 向上拖动增加值 (delta为负)
            var deltaValue = root.orientation === "vertical" ?
                             -delta / range * 2 * sensitivity :
                             delta / range * 2 * sensitivity

            var newValue = Math.max(minValue, Math.min(maxValue, startValue + deltaValue))
            if (newValue !== root.value) {
                root.value = newValue
            }
        }

        onReleased: {
            root.isDragging = false
        }

        onDoubleClicked: {
            root.value = 0
            root.rollerDoubleClicked()
        }
    }
}
