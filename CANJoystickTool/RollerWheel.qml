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

    // 默认尺寸
    width: orientation === "vertical" ? 48 : 200
    height: orientation === "vertical" ? 200 : 40

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

            // 滚轮遮罩
            Rectangle {
                id: wheelMask
                anchors.fill: parent
                radius: 8
                color: "#FFFFFF"
                visible: false
            }

            // 滚轮主体
            Item {
                id: wheelBody
                anchors.fill: parent

                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: wheelMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }

                // 黑色底色
                Rectangle {
                    anchors.fill: parent
                    color: wheelColor
                }

                // 条纹纹理 (Canvas绘制)
                Canvas {
                    id: stripeCanvas
                    anchors.fill: parent

                    // 纹理偏移量，随value变化
                    property real textureOffset: root.value * 90  // 滚动效果

                    onTextureOffsetChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)

                        // 条纹间距
                        var stripeSpacing = 8
                        var stripeWidth = 4

                        if (root.orientation === "vertical") {
                            // 水平条纹 (竖向滚轮)
                            ctx.fillStyle = "#2a2a2a"
                            var startY = (textureOffset % stripeSpacing) - stripeSpacing
                            for (var y = startY; y < height + stripeSpacing; y += stripeSpacing) {
                                ctx.fillRect(0, y, width, stripeWidth)
                            }
                        } else {
                            // 垂直条纹 (横向滚轮)
                            ctx.fillStyle = "#2a2a2a"
                            var startX = (textureOffset % stripeSpacing) - stripeSpacing
                            for (var x = startX; x < width + stripeSpacing; x += stripeSpacing) {
                                ctx.fillRect(x, 0, stripeWidth, height)
                            }
                        }
                    }

                    Component.onCompleted: requestPaint()
                }

                // 滚轮边缘渐变效果 (模拟圆柱形)
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: root.orientation === "vertical" ?
                                     Gradient.Horizontal : Gradient.Vertical
                        GradientStop { position: 0.0; color: "#E6000000" }   // 90%黑
                        GradientStop { position: 0.15; color: "#40000000" }
                        GradientStop { position: 0.5; color: "#26FFFFFF" }   // 中心亮
                        GradientStop { position: 0.85; color: "#40000000" }
                        GradientStop { position: 1.0; color: "#E6000000" }
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
            }

            // 指示器 (roller-indicator)
            Rectangle {
                id: indicator
                color: indicatorColor
                radius: 2

                // 垂直滚轮: 水平指示线
                width: root.orientation === "vertical" ? parent.width * 0.8 : 4
                height: root.orientation === "vertical" ? 4 : parent.height * 0.8

                // 居中定位
                anchors.centerIn: parent

                // 发光效果
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: indicatorColor
                    shadowBlur: 0.8
                    blurMax: 8
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
