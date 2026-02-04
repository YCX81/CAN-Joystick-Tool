import QtQuick 6.5
import QtQuick.Effects

// 数字显示框 - 与RollerWheel风格一致的LED屏幕效果
Item {
    id: root
    width: 80
    height: 36

    // 公开属性
    property int value: 0
    property string label: "%"
    property color accentColor: Constants.rollerIndicatorColor
    property color housingColor: Constants.rollerHousingColor
    property color screenColor: "#1a1a1a"

    // 外壳 (与RollerWheel一致)
    Rectangle {
        id: housing
        anchors.fill: parent
        radius: 8
        color: housingColor

        // 内凹阴影效果 - 左侧暗右侧亮
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#26000000" }  // 15%黑
                GradientStop { position: 0.2; color: "transparent" }
                GradientStop { position: 0.8; color: "transparent" }
                GradientStop { position: 1.0; color: "#15FFFFFF" }  // 8%白高光
            }
        }

        // 屏幕区域
        Rectangle {
            id: screen
            anchors.fill: parent
            anchors.margins: 3
            radius: 5
            color: screenColor

            // 屏幕内凹阴影边框
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 1
                border.color: "#26FFFFFF"
            }

            // 屏幕内凹阴影效果
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 3
                border.color: "#E6000000"
                opacity: 0.5
            }

            // 顶部阴影渐变
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#40000000" }
                    GradientStop { position: 0.3; color: "transparent" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // 数值显示
            Row {
                anchors.centerIn: parent
                spacing: 2

                // 数值文本
                Text {
                    id: valueText
                    text: root.value
                    color: root.accentColor
                    font.family: "JetBrains Mono, Consolas, monospace"
                    font.pixelSize: 16
                    font.bold: true
                    verticalAlignment: Text.AlignVCenter

                    // 文字发光效果
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: root.accentColor
                        shadowBlur: 0.5
                        blurMax: 8
                        shadowHorizontalOffset: 0
                        shadowVerticalOffset: 0
                    }
                }

                // 单位符号
                Text {
                    text: root.label
                    color: Qt.darker(root.accentColor, 1.2)
                    font.family: "Arial"
                    font.pixelSize: 10
                    font.bold: true
                    anchors.bottom: valueText.bottom
                    anchors.bottomMargin: 1
                    opacity: 0.8
                }
            }
        }
    }
}
