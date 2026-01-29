import QtQuick 6.5
import QtQuick.Effects

// FNR三态翘板开关 - 带3D翘动效果
Item {
    id: root

    // 尺寸
    property int switchWidth: 78
    property int switchHeight: 142

    // 状态: "F" (Forward), "N" (Neutral), "R" (Reverse)
    property string switchState: "N"

    // 颜色配置
    property color housingColor: Constants.rockerHousingColor
    property color rockerGradientStart: Constants.rockerGradientStart
    property color rockerGradientEnd: Constants.rockerGradientEnd
    property color forwardGlow: Constants.fnrForwardColor
    property color neutralGlow: Constants.fnrNeutralColor
    property color reverseGlow: Constants.fnrReverseColor

    width: switchWidth
    height: switchHeight

    // 外壳 (fnr-housing)
    Rectangle {
        id: housing
        anchors.fill: parent
        radius: 8
        color: housingColor

        // 外壳内凹效果
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.lighter(housingColor, 1.3) }
            GradientStop { position: 0.1; color: housingColor }
            GradientStop { position: 0.9; color: housingColor }
            GradientStop { position: 1.0; color: Qt.darker(housingColor, 1.2) }
        }

        // 外壳阴影
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#4D000000"
            shadowBlur: 0.6
            blurMax: 8
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 4
        }

        // 内凹边框
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 1
            border.color: "#33FFFFFF"
        }

        // 翘板容器
        Item {
            id: rockerContainer
            anchors.fill: parent
            anchors.margins: 4

            // 翘板主体 (rocker-switch)
            Rectangle {
                id: rocker
                anchors.fill: parent
                radius: 4

                // 翘板渐变 - 根据状态变化
                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: root.switchState === "F" ? Qt.darker(rockerGradientStart, 1.2) :
                               root.switchState === "R" ? rockerGradientEnd : rockerGradientStart
                    }
                    GradientStop {
                        position: 0.4
                        color: root.switchState === "F" ? rockerGradientStart :
                               root.switchState === "R" ? rockerGradientStart : rockerGradientEnd
                    }
                    GradientStop {
                        position: 1.0
                        color: root.switchState === "F" ? rockerGradientEnd :
                               root.switchState === "R" ? Qt.darker(rockerGradientStart, 1.2) : rockerGradientEnd
                    }
                }

                // 3D变换
                transform: [
                    Rotation {
                        id: rockerRotation
                        origin.x: rocker.width / 2
                        origin.y: rocker.height / 2
                        axis { x: 1; y: 0; z: 0 }  // 绕X轴旋转
                        angle: root.switchState === "F" ? 18 :
                               root.switchState === "R" ? -18 : 0

                        Behavior on angle {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutQuad
                            }
                        }
                    }
                ]

                // 翘板内容
                Column {
                    anchors.fill: parent
                    spacing: 0

                    // F区域 (Forward)
                    Item {
                        width: parent.width
                        height: parent.height / 3

                        // 条纹装饰
                        Canvas {
                            id: topRidges
                            anchors.top: parent.top
                            anchors.topMargin: 8
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width * 0.7
                            height: 12

                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                ctx.strokeStyle = "#26000000"
                                ctx.lineWidth = 1
                                for (var y = 0; y < height; y += 3) {
                                    ctx.beginPath()
                                    ctx.moveTo(0, y)
                                    ctx.lineTo(width, y)
                                    ctx.stroke()
                                }
                            }
                            Component.onCompleted: requestPaint()
                        }

                        Text {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: 4
                            text: "F"
                            font.pixelSize: 16
                            font.weight: Font.ExtraBold
                            color: root.switchState === "F" ? "#FFFFFF" : "#40000000"

                            // 发光效果
                            layer.enabled: root.switchState === "F"
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: forwardGlow
                                shadowBlur: 1.0
                                blurMax: 16
                                shadowHorizontalOffset: 0
                                shadowVerticalOffset: 0
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.switchState = "F"
                                // state changed to("F")
                            }
                        }
                    }

                    // N区域 (Neutral)
                    Item {
                        width: parent.width
                        height: parent.height / 3

                        // 上分隔线
                        Rectangle {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 1
                            color: "#1A000000"
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "N"
                            font.pixelSize: 16
                            font.weight: Font.ExtraBold
                            color: root.switchState === "N" ? "#FFFFFF" : "#40000000"

                            layer.enabled: root.switchState === "N"
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: neutralGlow
                                shadowBlur: 1.0
                                blurMax: 16
                                shadowHorizontalOffset: 0
                                shadowVerticalOffset: 0
                            }
                        }

                        // 下分隔线
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 1
                            color: "#1A000000"
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.switchState = "N"
                                // state changed to("N")
                            }
                        }
                    }

                    // R区域 (Reverse)
                    Item {
                        width: parent.width
                        height: parent.height / 3

                        Text {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: -4
                            text: "R"
                            font.pixelSize: 16
                            font.weight: Font.ExtraBold
                            color: root.switchState === "R" ? "#FFFFFF" : "#40000000"

                            layer.enabled: root.switchState === "R"
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: reverseGlow
                                shadowBlur: 1.0
                                blurMax: 16
                                shadowHorizontalOffset: 0
                                shadowVerticalOffset: 0
                            }
                        }

                        // 条纹装饰
                        Canvas {
                            id: bottomRidges
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 8
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width * 0.7
                            height: 12

                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                ctx.strokeStyle = "#26000000"
                                ctx.lineWidth = 1
                                for (var y = 0; y < height; y += 3) {
                                    ctx.beginPath()
                                    ctx.moveTo(0, y)
                                    ctx.lineTo(width, y)
                                    ctx.stroke()
                                }
                            }
                            Component.onCompleted: requestPaint()
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.switchState = "R"
                                // state changed to("R")
                            }
                        }
                    }
                }

                // 翘板表面光效
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#66FFFFFF" }
                        GradientStop { position: 0.15; color: "transparent" }
                        GradientStop { position: 0.5; color: "#0D000000" }
                        GradientStop { position: 0.85; color: "transparent" }
                        GradientStop { position: 1.0; color: "#4DFFFFFF" }
                    }
                }

                // 翘板边框高光
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    border.width: 1
                    border.color: "#80FFFFFF"
                }

                // 按压阴影效果
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    visible: root.switchState === "F"
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#4D000000" }
                        GradientStop { position: 0.3; color: "transparent" }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    visible: root.switchState === "R"
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.7; color: "transparent" }
                        GradientStop { position: 1.0; color: "#4D000000" }
                    }
                }
            }
        }
    }
}
