import QtQuick 6.5
import QtQuick.Effects

// 状态指示灯 - Ive风格浅色LED设计
Item {
    id: root

    // 指示灯状态
    property bool active: false
    property bool blinking: false
    property int blinkInterval: 500

    // 颜色配置 - 默认青色
    property color activeColor: "#00e0ff"
    property color inactiveColor: "#d0d0d0"
    property color glowColor: activeColor

    // 尺寸
    property int indicatorSize: 16

    width: indicatorSize
    height: indicatorSize

    // 闪烁定时器
    Timer {
        id: blinkTimer
        interval: root.blinkInterval
        repeat: true
        running: root.blinking
        onTriggered: internalActive = !internalActive
    }

    property bool internalActive: active
    onActiveChanged: internalActive = active

    // 外环 - 浅色金属边框
    Rectangle {
        id: outerRing
        anchors.fill: parent
        radius: width / 2

        gradient: Gradient {
            GradientStop { position: 0.0; color: "#e8e8e8" }
            GradientStop { position: 0.4; color: "#d8d8d8" }
            GradientStop { position: 1.0; color: "#c0c0c0" }
        }

        // 外环阴影
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#30000000"
            shadowBlur: 0.3
            shadowVerticalOffset: 1
            shadowHorizontalOffset: 0
        }
    }

    // 内凹效果
    Rectangle {
        id: innerRing
        anchors.fill: parent
        anchors.margins: 2
        radius: width / 2
        color: "#f0f0f0"

        // 内凹阴影
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: parent.height * 0.4
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#15000000" }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
    }

    // LED灯体
    Rectangle {
        id: ledBody
        anchors.fill: parent
        anchors.margins: 3
        radius: width / 2

        color: internalActive ? activeColor : inactiveColor

        Behavior on color {
            ColorAnimation { duration: 150 }
        }

        // 高光点
        Rectangle {
            width: parent.width * 0.3
            height: parent.height * 0.3
            x: parent.width * 0.2
            y: parent.height * 0.15
            radius: width / 2
            color: "#70ffffff"
            visible: internalActive
        }

        // 底部暗部
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width * 0.6
            height: parent.height * 0.3
            radius: height / 2
            color: "#10000000"
            visible: internalActive
        }
    }

    // 发光效果层
    Rectangle {
        id: glowLayer
        anchors.centerIn: parent
        width: indicatorSize * 2.5
        height: indicatorSize * 2.5
        radius: width / 2
        color: "transparent"
        visible: internalActive

        layer.enabled: internalActive
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1.0
            blurMax: 32
        }

        Rectangle {
            anchors.centerIn: parent
            width: indicatorSize
            height: indicatorSize
            radius: width / 2
            color: glowColor
            opacity: 0.5
        }
    }

    // 状态变化动画
    states: [
        State {
            name: "active"
            when: internalActive
            PropertyChanges { target: glowLayer; opacity: 1.0 }
        },
        State {
            name: "inactive"
            when: !internalActive
            PropertyChanges { target: glowLayer; opacity: 0 }
        }
    ]

    transitions: [
        Transition {
            from: "*"; to: "*"
            NumberAnimation {
                properties: "opacity"
                duration: 200
                easing.type: Easing.InOutQuad
            }
        }
    ]
}
