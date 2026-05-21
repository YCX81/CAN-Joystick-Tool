import QtQuick 6.5
import QtQuick.Effects

// 铝合金面板容器
Item {
    id: root

    // 面板尺寸
    property int panelWidth: 400
    property int panelHeight: 400
    property int borderRadius: 44
    property int contentMargins: 16

    // 颜色配置
    property color lightColor: "#f2f2f2"
    property color darkColor: "#dcdcdc"
    property color shadowColor: "#b0b0b0"
    property color highlightColor: "#ffffff"
    property bool panelChromeVisible: true

    width: panelWidth
    height: panelHeight

    // 左上高光阴影层
    Rectangle {
        id: topLeftShadow
        anchors.fill: parent
        anchors.leftMargin: -30
        anchors.topMargin: -30
        anchors.rightMargin: 30
        anchors.bottomMargin: 30
        radius: borderRadius + 10
        color: highlightColor
        opacity: 0.5
        visible: root.panelChromeVisible

        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1.0
            blurMax: 60
        }
    }

    // 右下深色阴影层
    Rectangle {
        id: bottomRightShadow
        anchors.fill: parent
        anchors.leftMargin: 30
        anchors.topMargin: 30
        anchors.rightMargin: -30
        anchors.bottomMargin: -30
        radius: borderRadius + 10
        color: shadowColor
        opacity: 0.6
        visible: root.panelChromeVisible

        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1.0
            blurMax: 60
        }
    }

    // 主面板 - 135°斜向渐变 (使用Canvas实现)
    Canvas {
        id: mainPanelCanvas
        anchors.fill: parent
        visible: root.panelChromeVisible

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            // 创建135°斜向渐变 (从左上到右下)
            var gradient = ctx.createLinearGradient(0, 0, width, height)
            gradient.addColorStop(0.0, lightColor.toString())
            gradient.addColorStop(0.5, "#e8e8e8")
            gradient.addColorStop(1.0, darkColor.toString())

            ctx.fillStyle = gradient

            // 绘制圆角矩形
            var r = borderRadius
            ctx.beginPath()
            ctx.moveTo(r, 0)
            ctx.lineTo(width - r, 0)
            ctx.quadraticCurveTo(width, 0, width, r)
            ctx.lineTo(width, height - r)
            ctx.quadraticCurveTo(width, height, width - r, height)
            ctx.lineTo(r, height)
            ctx.quadraticCurveTo(0, height, 0, height - r)
            ctx.lineTo(0, r)
            ctx.quadraticCurveTo(0, 0, r, 0)
            ctx.closePath()
            ctx.fill()
        }

        Component.onCompleted: requestPaint()
        // Repaint only once after initial layout is done
        Timer {
            id: repaintTimer
            interval: 100; repeat: false
            running: false
            onTriggered: mainPanelCanvas.requestPaint()
        }
        onWidthChanged: repaintTimer.restart()
        onHeightChanged: repaintTimer.restart()
    }

    // 内边框高光
    Rectangle {
        anchors.fill: parent
        radius: borderRadius
        color: "transparent"
        border.width: 1
        border.color: "#80FFFFFF"  // 50%白
        visible: root.panelChromeVisible
    }

    // 噪点纹理层 (disabled for performance — too slow on large panels)
    // If needed, use a pre-rendered noise texture image instead

    // 内容区域
    default property alias content: contentArea.data

    Item {
        id: contentArea
        anchors.fill: parent
        anchors.margins: root.contentMargins
    }
}
