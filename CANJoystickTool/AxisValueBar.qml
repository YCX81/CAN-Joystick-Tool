import QtQuick 6.5
import QtQuick.Effects

// 双向轴值进度条 - Ive风格浅色设计
Item {
    id: root

    // 轴值 (-1.0 到 1.0)
    property real value: 0.0
    property real minValue: -1.0
    property real maxValue: 1.0

    // 外观配置 - Ive风格
    property color trackColor: "#80c8c8c8"    // 浅灰半透明
    property color fillColor: "#4b5563"        // gray-600 深灰
    property color thumbColor: "#374151"       // gray-700
    property color textColorValue: "#4b5563"   // 统一深灰

    // 显示选项
    property bool showThumb: true
    property bool showValue: true
    property string label: "X"
    property int decimals: 2

    // 尺寸
    property int barHeight: 24
    property int thumbWidth: 6
    property int thumbHeight: 14

    width: 200
    height: barHeight + (showValue ? 20 : 0)

    // 计算归一化值 (0-1)
    property real normalizedValue: (value - minValue) / (maxValue - minValue)
    // 中心点位置 (0-1)
    property real centerPoint: -minValue / (maxValue - minValue)

    // 轨道背景
    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: barHeight
        radius: barHeight / 2
        color: trackColor

        // 内凹效果 - 浅色Neumorphic
        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: parent.radius - 2
            color: "#e8e8e8"

            // 顶部内阴影
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 6
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#18000000" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
        }

        // 刻度线容器
        Item {
            anchors.fill: parent
            anchors.margins: 4

            // 中心刻度线
            Rectangle {
                anchors.centerIn: parent
                width: 2
                height: parent.height * 0.5
                color: "#c0c0c0"
                radius: 1
            }

            // 左侧刻度
            Repeater {
                model: 4
                Rectangle {
                    x: parent.width * (0.1 + index * 0.1) - width/2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1
                    height: parent.height * 0.25
                    color: "#d0d0d0"
                }
            }

            // 右侧刻度
            Repeater {
                model: 4
                Rectangle {
                    x: parent.width * (0.6 + index * 0.1) - width/2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1
                    height: parent.height * 0.25
                    color: "#d0d0d0"
                }
            }
        }

        // 进度填充区域
        Item {
            id: fillArea
            anchors.fill: parent
            anchors.margins: 4
            clip: true

            // 进度条填充 - 统一深灰色
            Rectangle {
                id: fillBar
                height: parent.height
                radius: height / 2

                // 根据值的正负决定位置和宽度
                x: value >= 0 ? parent.width * centerPoint : parent.width * normalizedValue
                width: Math.abs(value) / (maxValue - minValue) * parent.width

                color: fillColor

                // Behavior on x { NumberAnimation { duration: 50 } }
                // Behavior on width { NumberAnimation { duration: 50 } }
            }
        }

        // 滑块指示器 - 改为竖向椭圆
        Rectangle {
            id: thumb
            visible: showThumb
            width: thumbWidth
            height: thumbHeight
            radius: thumbWidth / 2

            x: fillArea.x + fillArea.width * normalizedValue - width/2
            anchors.verticalCenter: parent.verticalCenter

            color: thumbColor

            // 滑块阴影
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#40000000"
                shadowBlur: 0.3
                shadowVerticalOffset: 2
                shadowHorizontalOffset: 0
            }

            // Behavior on x { NumberAnimation { duration: 50 } }
        }
    }

    // 数值显示
    Row {
        visible: showValue
        anchors.top: track.bottom
        anchors.topMargin: 4
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 8

        Text {
            text: label + ":"
            color: "#86868b"  // textSecondary
            font.pixelSize: 11
            font.family: "Consolas"
        }

        Text {
            text: value >= 0 ? "+" + value.toFixed(decimals) : value.toFixed(decimals)
            color: textColorValue
            font.pixelSize: 11
            font.family: "Consolas"
            font.bold: true

            Behavior on color { ColorAnimation { duration: 100 } }
        }
    }
}
