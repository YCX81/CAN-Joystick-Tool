import QtQuick 6.5
import CANJoystickTool

// 智能对齐辅助线系统 - 类似Figma的对齐吸附功能
Item {
    id: root

    // 配置
    property int threshold: 5           // 吸附阈值 (像素)
    property int guideThickness: 1      // 辅助线粗细
    property color guideColor: Constants.accentColor
    property color distanceColor: "#ff6b6b"

    // 当前正在拖拽的项目
    property var draggingItem: null

    // 所有可对齐的项目列表
    property var items: []

    // 当前显示的辅助线
    property var activeGuides: ({ vertical: [], horizontal: [] })

    // 是否启用
    property bool enabled: true

    // 绘制辅助线
    Canvas {
        id: guideCanvas
        anchors.fill: parent
        z: 1000  // 确保在最上层

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            if (!enabled || !draggingItem) return

            ctx.strokeStyle = guideColor.toString()
            ctx.lineWidth = guideThickness
            ctx.setLineDash([4, 4])  // 虚线

            // 绘制垂直辅助线
            for (var i = 0; i < activeGuides.vertical.length; i++) {
                var vg = activeGuides.vertical[i]
                ctx.beginPath()
                ctx.moveTo(vg.pos, 0)
                ctx.lineTo(vg.pos, height)
                ctx.stroke()
            }

            // 绘制水平辅助线
            for (var j = 0; j < activeGuides.horizontal.length; j++) {
                var hg = activeGuides.horizontal[j]
                ctx.beginPath()
                ctx.moveTo(0, hg.pos)
                ctx.lineTo(width, hg.pos)
                ctx.stroke()
            }
        }
    }

    // 开始拖拽时调用
    function startDrag(item) {
        draggingItem = item
        activeGuides = { vertical: [], horizontal: [] }
    }

    // 结束拖拽时调用
    function endDrag() {
        draggingItem = null
        activeGuides = { vertical: [], horizontal: [] }
        guideCanvas.requestPaint()
    }

    // 计算对齐并返回吸附后的位置
    function getSnappedPosition(item, proposedX, proposedY) {
        if (!enabled || items.length === 0) {
            return { x: proposedX, y: proposedY }
        }

        var result = { x: proposedX, y: proposedY }
        var itemBounds = {
            x: proposedX,
            y: proposedY,
            width: item.width,
            height: item.height,
            centerX: proposedX + item.width / 2,
            centerY: proposedY + item.height / 2,
            right: proposedX + item.width,
            bottom: proposedY + item.height
        }

        activeGuides = { vertical: [], horizontal: [] }

        // 检测与每个其他项目的对齐
        for (var i = 0; i < items.length; i++) {
            var other = items[i]
            if (other === item) continue

            var otherBounds = other.getBounds ? other.getBounds() : {
                x: other.x,
                y: other.y,
                width: other.width,
                height: other.height,
                centerX: other.x + other.width / 2,
                centerY: other.y + other.height / 2,
                right: other.x + other.width,
                bottom: other.y + other.height
            }

            // ========== 垂直对齐检测 (X轴) ==========

            // 左边缘对齐
            if (Math.abs(itemBounds.x - otherBounds.x) < threshold) {
                result.x = otherBounds.x
                addVerticalGuide(otherBounds.x, "left-left")
            }
            // 右边缘对齐
            if (Math.abs(itemBounds.right - otherBounds.right) < threshold) {
                result.x = otherBounds.right - item.width
                addVerticalGuide(otherBounds.right, "right-right")
            }
            // 左对右
            if (Math.abs(itemBounds.x - otherBounds.right) < threshold) {
                result.x = otherBounds.right
                addVerticalGuide(otherBounds.right, "left-right")
            }
            // 右对左
            if (Math.abs(itemBounds.right - otherBounds.x) < threshold) {
                result.x = otherBounds.x - item.width
                addVerticalGuide(otherBounds.x, "right-left")
            }
            // 中心对齐
            if (Math.abs(itemBounds.centerX - otherBounds.centerX) < threshold) {
                result.x = otherBounds.centerX - item.width / 2
                addVerticalGuide(otherBounds.centerX, "center")
            }

            // ========== 水平对齐检测 (Y轴) ==========

            // 上边缘对齐
            if (Math.abs(itemBounds.y - otherBounds.y) < threshold) {
                result.y = otherBounds.y
                addHorizontalGuide(otherBounds.y, "top-top")
            }
            // 下边缘对齐
            if (Math.abs(itemBounds.bottom - otherBounds.bottom) < threshold) {
                result.y = otherBounds.bottom - item.height
                addHorizontalGuide(otherBounds.bottom, "bottom-bottom")
            }
            // 上对下
            if (Math.abs(itemBounds.y - otherBounds.bottom) < threshold) {
                result.y = otherBounds.bottom
                addHorizontalGuide(otherBounds.bottom, "top-bottom")
            }
            // 下对上
            if (Math.abs(itemBounds.bottom - otherBounds.y) < threshold) {
                result.y = otherBounds.y - item.height
                addHorizontalGuide(otherBounds.y, "bottom-top")
            }
            // 中心对齐
            if (Math.abs(itemBounds.centerY - otherBounds.centerY) < threshold) {
                result.y = otherBounds.centerY - item.height / 2
                addHorizontalGuide(otherBounds.centerY, "center")
            }
        }

        // 画布边缘对齐
        checkCanvasEdgeAlignment(itemBounds, result)

        guideCanvas.requestPaint()
        return result
    }

    // 检测画布边缘对齐
    function checkCanvasEdgeAlignment(itemBounds, result) {
        var canvasCenterX = width / 2
        var canvasCenterY = height / 2

        // 画布左边缘
        if (Math.abs(itemBounds.x) < threshold) {
            result.x = 0
            addVerticalGuide(0, "canvas-left")
        }
        // 画布右边缘
        if (Math.abs(itemBounds.right - width) < threshold) {
            result.x = width - itemBounds.width
            addVerticalGuide(width, "canvas-right")
        }
        // 画布水平中心
        if (Math.abs(itemBounds.centerX - canvasCenterX) < threshold) {
            result.x = canvasCenterX - itemBounds.width / 2
            addVerticalGuide(canvasCenterX, "canvas-center-x")
        }

        // 画布上边缘
        if (Math.abs(itemBounds.y) < threshold) {
            result.y = 0
            addHorizontalGuide(0, "canvas-top")
        }
        // 画布下边缘
        if (Math.abs(itemBounds.bottom - height) < threshold) {
            result.y = height - itemBounds.height
            addHorizontalGuide(height, "canvas-bottom")
        }
        // 画布垂直中心
        if (Math.abs(itemBounds.centerY - canvasCenterY) < threshold) {
            result.y = canvasCenterY - itemBounds.height / 2
            addHorizontalGuide(canvasCenterY, "canvas-center-y")
        }
    }

    // 添加垂直辅助线 (去重)
    function addVerticalGuide(pos, type) {
        for (var i = 0; i < activeGuides.vertical.length; i++) {
            if (Math.abs(activeGuides.vertical[i].pos - pos) < 1) return
        }
        activeGuides.vertical.push({ pos: pos, type: type })
    }

    // 添加水平辅助线 (去重)
    function addHorizontalGuide(pos, type) {
        for (var i = 0; i < activeGuides.horizontal.length; i++) {
            if (Math.abs(activeGuides.horizontal[i].pos - pos) < 1) return
        }
        activeGuides.horizontal.push({ pos: pos, type: type })
    }

    // 更新项目列表
    function updateItems(newItems) {
        items = newItems
    }

    // 清除辅助线
    function clearGuides() {
        activeGuides = { vertical: [], horizontal: [] }
        guideCanvas.requestPaint()
    }
}
