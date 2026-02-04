import QtQuick 6.5
import QtQuick.Effects

// FNR三态翘板开关 - 带3D翘动效果
Item {
    id: root

    // 尺寸
    property int switchWidth: 86
    property int switchHeight: 150

    // 状态: "F" (Forward), "N" (Neutral), "R" (Reverse)
    property string switchState: "N"

    // 颜色配置
    property color housingColor: Constants.rockerHousingColor
    property color rockerGradientStart: Constants.rockerGradientStart
    property color rockerGradientEnd: Constants.rockerGradientEnd
    property color rockerDark: "#b45309"  // 按压时的深色
    property color rockerShadow: "#92400e"  // 厚度阴影色
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

        // 顶部内高光
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 6
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#33FFFFFF" }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        // 底部内阴影
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 6
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: "#80000000" }
            }
        }

        // 翘板容器 - 带透视效果
        Item {
            id: rockerContainer
            anchors.fill: parent
            anchors.margins: 4

            // 厚度阴影层 - 模拟翘板翘起时的底部厚度
            // F状态: 底部可见 (0 6px 0 #92400e)
            Rectangle {
                id: bottomThickness
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: root.switchState === "F" ? 6 : 0
                radius: 4
                color: rockerShadow

                Behavior on height {
                    NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                }
            }

            // R状态: 顶部可见 (0 -6px 0 #92400e)
            Rectangle {
                id: topThickness
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: root.switchState === "R" ? 6 : 0
                radius: 4
                color: rockerShadow

                Behavior on height {
                    NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                }
            }

            // 翘板主体 (rocker-switch)
            Rectangle {
                id: rocker
                anchors.fill: parent
                anchors.topMargin: root.switchState === "R" ? 6 : 0
                anchors.bottomMargin: root.switchState === "F" ? 6 : 0
                radius: 4

                Behavior on anchors.topMargin {
                    NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                }
                Behavior on anchors.bottomMargin {
                    NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                }

                // 翘板渐变
                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: root.switchState === "F" ? rockerDark :
                               root.switchState === "R" ? rockerGradientEnd : rockerGradientStart
                    }
                    GradientStop {
                        position: 0.4
                        color: root.switchState === "F" ? "#d97706" :
                               root.switchState === "R" ? "#d97706" : rockerGradientEnd
                    }
                    GradientStop {
                        position: 1.0
                        color: root.switchState === "F" ? rockerGradientEnd :
                               root.switchState === "R" ? rockerDark : rockerGradientEnd
                    }
                }

                // 3D变换 - 增强透视效果
                transform: [
                    Rotation {
                        id: rockerRotation
                        origin.x: rocker.width / 2
                        origin.y: rocker.height / 2
                        axis { x: 1; y: 0; z: 0 }
                        angle: root.switchState === "F" ? 12 :
                               root.switchState === "R" ? -12 : 0

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
                        Rectangle {
                            id: topRidges
                            anchors.top: parent.top
                            anchors.topMargin: 10
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width * 0.7
                            height: 12
                            color: "transparent"

                            // 使用Repeater生成条纹
                            Column {
                                anchors.fill: parent
                                spacing: 1
                                Repeater {
                                    model: 4
                                    Rectangle {
                                        width: parent.width
                                        height: 2
                                        color: index % 2 === 0 ? "#26000000" : "#1AFFFFFF"
                                    }
                                }
                            }
                        }

                        // F字母 - 增强发光效果
                        Text {
                            id: textF
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: 6
                            text: "F"
                            font.pixelSize: 14
                            font.weight: Font.Black
                            color: root.switchState === "F" ? "#FFFFFF" : "#1a1a1a"
                            style: root.switchState !== "F" ? Text.Raised : Text.Normal
                            styleColor: "#4DFFFFFF"

                            // 双层发光效果
                            layer.enabled: root.switchState === "F"
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: forwardGlow
                                shadowBlur: 1.0
                                blurMax: 24
                                shadowHorizontalOffset: 0
                                shadowVerticalOffset: 0
                            }
                        }

                        // 额外发光层
                        Text {
                            visible: root.switchState === "F"
                            anchors.centerIn: textF
                            text: "F"
                            font: textF.font
                            color: "transparent"
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: forwardGlow
                                shadowBlur: 0.5
                                blurMax: 8
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.switchState = "F"
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

                            Rectangle {
                                anchors.top: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 1
                                color: "#4DFFFFFF"
                            }
                        }

                        // N字母
                        Text {
                            id: textN
                            anchors.centerIn: parent
                            text: "N"
                            font.pixelSize: 14
                            font.weight: Font.Black
                            color: root.switchState === "N" ? "#FFFFFF" : "#1a1a1a"
                            style: root.switchState !== "N" ? Text.Raised : Text.Normal
                            styleColor: "#4DFFFFFF"

                            layer.enabled: root.switchState === "N"
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: neutralGlow
                                shadowBlur: 1.0
                                blurMax: 24
                                shadowHorizontalOffset: 0
                                shadowVerticalOffset: 0
                            }
                        }

                        // 额外发光层
                        Text {
                            visible: root.switchState === "N"
                            anchors.centerIn: textN
                            text: "N"
                            font: textN.font
                            color: "transparent"
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: neutralGlow
                                shadowBlur: 0.5
                                blurMax: 8
                            }
                        }

                        // 下分隔线
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 1
                            color: "#1A000000"

                            Rectangle {
                                anchors.top: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 1
                                color: "#4DFFFFFF"
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.switchState = "N"
                        }
                    }

                    // R区域 (Reverse)
                    Item {
                        width: parent.width
                        height: parent.height / 3

                        // R字母
                        Text {
                            id: textR
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: -6
                            text: "R"
                            font.pixelSize: 14
                            font.weight: Font.Black
                            color: root.switchState === "R" ? "#FFFFFF" : "#1a1a1a"
                            style: root.switchState !== "R" ? Text.Raised : Text.Normal
                            styleColor: "#4DFFFFFF"

                            layer.enabled: root.switchState === "R"
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: reverseGlow
                                shadowBlur: 1.0
                                blurMax: 24
                                shadowHorizontalOffset: 0
                                shadowVerticalOffset: 0
                            }
                        }

                        // 额外发光层
                        Text {
                            visible: root.switchState === "R"
                            anchors.centerIn: textR
                            text: "R"
                            font: textR.font
                            color: "transparent"
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: reverseGlow
                                shadowBlur: 0.5
                                blurMax: 8
                            }
                        }

                        // 条纹装饰
                        Rectangle {
                            id: bottomRidges
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 10
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width * 0.7
                            height: 12
                            color: "transparent"

                            Column {
                                anchors.fill: parent
                                spacing: 1
                                Repeater {
                                    model: 4
                                    Rectangle {
                                        width: parent.width
                                        height: 2
                                        color: index % 2 === 0 ? "#26000000" : "#1AFFFFFF"
                                    }
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.switchState = "R"
                        }
                    }
                }

                // 翘板表面光效
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#66FFFFFF" }  // 40%白
                        GradientStop { position: 0.20; color: "transparent" }
                        GradientStop { position: 0.50; color: "#0D000000" }  // 5%黑
                        GradientStop { position: 0.80; color: "transparent" }
                        GradientStop { position: 1.0; color: "#4DFFFFFF" }  // 30%白
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

                // 按压阴影效果 - F状态
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    opacity: root.switchState === "F" ? 1.0 : 0.0
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#99000000" }   // 60% black - 深阴影
                        GradientStop { position: 0.15; color: "#80000000" }  // 50% black
                        GradientStop { position: 0.35; color: "#40000000" }  // 25% black
                        GradientStop { position: 0.55; color: "transparent" }
                        GradientStop { position: 1.0; color: "transparent" }
                    }

                    Behavior on opacity {
                        NumberAnimation { duration: 150 }
                    }
                }

                // 按压阴影效果 - R状态
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    opacity: root.switchState === "R" ? 1.0 : 0.0
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.45; color: "transparent" }
                        GradientStop { position: 0.65; color: "#40000000" }
                        GradientStop { position: 0.85; color: "#80000000" }
                        GradientStop { position: 1.0; color: "#99000000" }
                    }

                    Behavior on opacity {
                        NumberAnimation { duration: 150 }
                    }
                }

                // 额外的顶部/底部阴影强调
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 8
                    radius: parent.radius
                    visible: root.switchState === "F"
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#66000000" }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 8
                    radius: parent.radius
                    visible: root.switchState === "R"
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0; color: "#66000000" }
                    }
                }
            }
        }
    }
}
