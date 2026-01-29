import QtQuick 6.5
import QtQuick.Effects

// 双向轴值进度条 - 完全复刻JoystickTool.html设计
// 支持horizontal(水平)和vertical(垂直)两种方向
Item {
    id: root

    // 轴值 (-1.0 到 1.0)
    property real value: 0.0
    property real minValue: -1.0
    property real maxValue: 1.0

    // 方向: "horizontal" 或 "vertical"
    property string orientation: "horizontal"
    property bool isHorizontal: orientation === "horizontal"

    // 外观配置
    property color trackColor: "#dcdcdc"         // track-well背景
    property color fillColor: "#6b7280"          // Gray-500 填充色
    property color fillColorActive: "#4b5563"    // Gray-600 激活填充色
    property color centerMarkColor: "#26000000"  // 15%黑 中心刻度线
    property color textColorLabel: "#86868b"     // 标签色
    property color textColorValue: "#6b7280"     // 数值色

    // 激活状态 (拖动时)
    property bool active: false

    // 显示选项
    property bool showLabel: true
    property bool showValue: true
    property string label: "X"
    property int decimals: 0
    property string valueUnit: "%"

    // 尺寸: 12px轨道, 8px填充条
    property int trackSize: 12
    property int barSize: 8

    // 根据方向计算尺寸
    width: isHorizontal ? 200 : 64
    height: isHorizontal ? 64 : 200

    // 计算归一化值 (0-1范围)
    property real normalizedValue: (value - minValue) / (maxValue - minValue)
    // 中心点位置 (0-1范围), 对于-1到1范围, centerPoint = 0.5
    property real centerPoint: -minValue / (maxValue - minValue)

    // 计算填充条的位置和尺寸
    property real fillRatio: Math.abs(normalizedValue - centerPoint)
    property real fillStart: value >= 0 ? centerPoint : (centerPoint - fillRatio)

    // ========== 水平方向布局 ==========
    Item {
        id: horizontalLayout
        visible: isHorizontal
        anchors.fill: parent

        // 进度条区域
        Item {
            id: hTrackContainer
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: trackSize

            // 圆角遮罩源
            Item {
                id: hTrackMask
                anchors.fill: parent
                layer.enabled: true
                visible: false

                Rectangle {
                    anchors.fill: parent
                    radius: 999
                    color: "#FFFFFF"
                }
            }

            // 轨道主体 - 应用MultiEffect圆角剪裁
            Rectangle {
                id: hTrack
                anchors.fill: parent
                color: trackColor
                radius: 999

                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: hTrackMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }

                // 内凹阴影 - 顶部深色
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 4
                    radius: parent.radius
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#26000000" }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                // 内凹高光 - 底部亮色
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 4
                    radius: parent.radius
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0; color: "#CCFFFFFF" }
                    }
                }

                // 中心刻度线 - 垂直
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.topMargin: 2
                    anchors.bottomMargin: 2
                    width: 1
                    color: centerMarkColor
                    z: 1
                }

                // 填充条
                Rectangle {
                    id: hFillBar
                    anchors.verticalCenter: parent.verticalCenter
                    height: barSize
                    radius: 999
                    color: active ? fillColorActive : fillColor

                    // 定位和宽度计算
                    x: fillStart * parent.width
                    width: fillRatio * parent.width

                    z: 2

                    Behavior on color {
                        ColorAnimation { duration: 50 }
                    }
                }
            }
        }

        // 标签和数值行
        Item {
            visible: showLabel || showValue
            anchors.top: hTrackContainer.bottom
            anchors.topMargin: 6
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            height: 16

            Text {
                visible: showLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "AXIS " + label
                color: textColorLabel
                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 0.5
            }

            Text {
                visible: showValue
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: (value * 100).toFixed(decimals) + valueUnit
                color: textColorValue
                font.pixelSize: 10
                font.family: "JetBrains Mono, Consolas, monospace"
                font.bold: true
            }
        }
    }

    // ========== 垂直方向布局 ==========
    Item {
        id: verticalLayout
        visible: !isHorizontal
        anchors.fill: parent

        // 进度条区域 - 左侧
        Item {
            id: vTrackContainer
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: trackSize

            // 圆角遮罩源
            Item {
                id: vTrackMask
                anchors.fill: parent
                layer.enabled: true
                visible: false

                Rectangle {
                    anchors.fill: parent
                    radius: 999
                    color: "#FFFFFF"
                }
            }

            // 轨道主体 - 应用MultiEffect圆角剪裁
            Rectangle {
                id: vTrack
                anchors.fill: parent
                color: trackColor
                radius: 999

                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: vTrackMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }

                // 内凹阴影 - 左侧深色
                Rectangle {
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    width: 4
                    radius: parent.radius
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#26000000" }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                // 内凹高光 - 右侧亮色
                Rectangle {
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    width: 4
                    radius: parent.radius
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0; color: "#CCFFFFFF" }
                    }
                }

                // 中心刻度线 - 水平
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 2
                    anchors.rightMargin: 2
                    height: 1
                    color: centerMarkColor
                    z: 1
                }

                // 填充条 - 垂直方向
                // Y轴正值向上, 负值向下 (QML中y坐标向下增加)
                Rectangle {
                    id: vFillBar
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: barSize
                    radius: 999
                    color: active ? fillColorActive : fillColor

                    // 使用统一的fillRatio计算
                    // 正值时：从(centerPoint - fillRatio)开始，向下延伸
                    // 负值时：从centerPoint开始，向下延伸
                    y: (value >= 0 ? (centerPoint - fillRatio) : centerPoint) * parent.height
                    height: fillRatio * parent.height

                    z: 2

                    Behavior on color {
                        ColorAnimation { duration: 50 }
                    }
                }
            }
        }

        // 标签 - 轨道顶部右侧，留边距，右对齐
        Text {
            id: vLabel
            visible: showLabel
            anchors.top: parent.top
            anchors.topMargin: 4
            anchors.left: vTrackContainer.right
            anchors.leftMargin: 6
            width: 36  // 与数值同宽
            text: "AXIS " + label
            color: textColorLabel
            font.pixelSize: 9
            font.bold: true
            font.letterSpacing: 0.5
            horizontalAlignment: Text.AlignRight
        }

        // 数值 - 轨道底部右侧，固定宽度右对齐
        Text {
            id: vValue
            visible: showValue
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4
            anchors.left: vTrackContainer.right
            anchors.leftMargin: 6
            width: 36  // 预留 "-100%" 的宽度
            text: (value * 100).toFixed(decimals) + valueUnit
            color: textColorValue
            font.pixelSize: 10
            font.family: "JetBrains Mono, Consolas, monospace"
            font.bold: true
            horizontalAlignment: Text.AlignRight
        }
    }
}
