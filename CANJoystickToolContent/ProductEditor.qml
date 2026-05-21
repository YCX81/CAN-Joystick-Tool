import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import QtQuick.Effects
import CANJoystickTool

Item {
    id: root
    signal exitRequested()

    property var layoutManager: typeof LayoutManager !== 'undefined' ? LayoutManager : null
    property var currentConfig: ({})
    property string currentFilePath: ""
    property bool hasUnsavedChanges: false
    property bool loadingCells: false
    property int activeCellIndex: 0
    readonly property int defaultCanvasWidth: Constants.homeCardDesignSize
    readonly property int defaultCanvasHeight: Constants.homeCardDesignSize
    readonly property real panelWidth: 320

    // DownloadTool colors
    readonly property color dtBg: "#f5f5f7"
    readonly property color dtText: "#1d1d1f"
    readonly property color dtTextSec: "#86868b"
    readonly property color dtTextMuted: "#a1a1a6"
    readonly property color dtAccent: "#007aff"
    readonly property color dtSuccess: "#34c759"
    readonly property color dtWarning: "#ff9500"
    readonly property color dtBorder: "#d2d2d7"

    readonly property var cellTypeOptions: [
        { value: "canvas",     label: "画布" },
        { value: "rawFrames",  label: "报文" },
        { value: "deviceInfo", label: "信息" },
        { value: "empty",      label: "空白" }
    ]

    // Reactive canvas mode
    property bool isCanvasMode: false
    function editableCellAt(idx) {
        if (idx < 0 || idx >= 4)
            return null
        var cell = cellRepeater.itemAt(idx)
        return cell !== null && cell.cellType === "canvas" ? cell : null
    }
    function activeCanvasCell() {
        var cell = editableCellAt(activeCellIndex)
        if (cell)
            return cell
        for (var i = 0; i < cellRepeater.count; i++) {
            cell = editableCellAt(i)
            if (cell)
                return cell
        }
        return null
    }
    function refreshCanvasMode() {
        isCanvasMode = activeCanvasCell() !== null
    }
    onActiveCellIndexChanged: refreshCanvasMode()

    function parseConfigNumber(value) {
        if (value === undefined || value === null || value === "")
            return NaN
        if (typeof value === "number")
            return value
        var text = String(value).trim()
        if (text.length === 0)
            return NaN
        if (text.indexOf("0x") === 0 || text.indexOf("0X") === 0)
            return parseInt(text.substring(2), 16)
        return parseInt(text, 10)
    }

    function hexText(value, width) {
        if (isNaN(value))
            return "--"
        var text = Math.floor(value).toString(16).toUpperCase()
        while (text.length < width)
            text = "0" + text
        return "0x" + text
    }

    function composeJ1939Id(priority, pgn, source, destination) {
        var pf = (pgn >> 8) & 0xFF
        var id = (priority & 0x7) << 26
        id |= (pgn & 0x3FF00) << 8
        id |= ((pf < 240) ? (destination & 0xFF) : (pgn & 0xFF)) << 8
        id |= source & 0xFF
        return id
    }

    function previewFrameLabel(message) {
        var id = String(message.id || "").toLowerCase()
        if (id === "addressclaim" || id === "address_claim")
            return "ADDR"
        if (id === "heartbeat")
            return "HB"
        if (id.length > 0)
            return id.toUpperCase()
        return "MSG"
    }

    function previewFramePeriodMs(message) {
        var period = parseConfigNumber(message.period)
        if (!isNaN(period) && period > 0)
            return period

        var id = String(message.id || "").toLowerCase()
        var can = currentConfig.can || {}
        var canopen = can.canopen || {}
        if (id === "heartbeat") {
            var heartbeat = parseConfigNumber(canopen.heartbeatMs)
            if (!isNaN(heartbeat) && heartbeat > 0)
                return heartbeat
        }
        return NaN
    }

    function previewPeriodText(message) {
        var period = previewFramePeriodMs(message)
        if (isNaN(period) || period <= 0)
            return "事件触发"

        var hz = 1000 / period
        var hzText = hz >= 10 ? Math.round(hz).toString() : hz.toFixed(1)
        return period + " ms / " + hzText + " Hz"
    }

    function previewFrameIdText(message) {
        var product = currentConfig.product || {}
        var protocol = String(product.protocol || "j1939").toLowerCase()

        if (protocol === "canopen") {
            var canId = parseConfigNumber(message.canId)
            if (!isNaN(canId))
                return hexText(canId, 3)
            return "CAN-ID 未配置"
        }

        var pgn = parseConfigNumber(message.pgn)
        if (isNaN(pgn))
            return "PGN 未配置"

        var source = parseConfigNumber(product.sourceAddress)
        if (isNaN(source))
            return "PGN " + hexText(pgn, 4) + " / SA未配置"

        var id = composeJ1939Id(6, pgn, source, 0xFF)
        return hexText(id, 8)
    }

    function previewFrameDetail(message) {
        var product = currentConfig.product || {}
        var protocol = String(product.protocol || "j1939").toLowerCase()
        var parts = []
        parts.push("DLC " + (message.dlc !== undefined ? message.dlc : 8))

        if (protocol === "canopen") {
            var formula = message.cobIdFormula || ""
            if (formula !== "")
                parts.push(formula)
        } else if (message.pgn) {
            parts.push("PGN " + String(message.pgn).toUpperCase())
        }

        var tags = previewFrameTags(message)
        if (tags.length > 0)
            parts.push(tags.join(" / "))

        return parts.join(" · ")
    }

    function previewFrameTags(message) {
        var fields = message.fields || []
        var hasStatus = false
        var hasCrc = false
        var hasSelfCheck = false
        var hasError = false

        for (var i = 0; i < fields.length; i++) {
            var field = fields[i] || {}
            var type = String(field.type || "").toLowerCase()
            var name = String(field.name || "").toLowerCase()
            if (type === "status")
                hasStatus = true
            if (type === "crc" || name.indexOf("crc") >= 0)
                hasCrc = true
            if (type === "selfcheck" || name.indexOf("selfcheck") >= 0 || name.indexOf("self_check") >= 0)
                hasSelfCheck = true
            if (type.indexOf("error") >= 0 || type.indexOf("fault") >= 0 || type.indexOf("diagnostic") >= 0
                    || name.indexOf("error") >= 0 || name.indexOf("fault") >= 0 || name.indexOf("alarm") >= 0)
                hasError = true
        }

        var tags = []
        if (hasStatus) tags.push("状态位")
        if (hasCrc) tags.push("CRC")
        if (hasSelfCheck) tags.push("自检")
        if (hasError) tags.push("错误")
        return tags
    }

    function expectedRawFrameRows() {
        var can = currentConfig.can || {}
        var messages = can.messages || []
        var rows = []
        for (var i = 0; i < messages.length; i++) {
            var message = messages[i] || {}
            rows.push({
                lbl: previewFrameLabel(message),
                cid: previewFrameIdText(message),
                period: previewPeriodText(message),
                detail: previewFrameDetail(message),
                warn: previewFrameWarning(message)
            })
        }
        return rows
    }

    function previewFrameWarning(message) {
        var product = currentConfig.product || {}
        var protocol = String(product.protocol || "j1939").toLowerCase()
        var id = String(message.id || "").toLowerCase()

        if (protocol === "j1939") {
            if (isNaN(parseConfigNumber(message.pgn)))
                return "PGN缺失"
            if (isNaN(parseConfigNumber(product.sourceAddress)))
                return "SA缺失"
        } else if (protocol === "canopen" && isNaN(parseConfigNumber(message.canId))) {
            return "ID缺失"
        }

        if (isNaN(previewFramePeriodMs(message)) && id !== "addressclaim" && id !== "address_claim")
            return "周期未配置"
        return ""
    }

    function previewDiagnosticText() {
        var rows = expectedRawFrameRows()
        var crcCount = 0
        var errorCount = 0
        for (var i = 0; i < rows.length; i++) {
            if (rows[i].detail.indexOf("CRC") >= 0 || rows[i].detail.indexOf("自检") >= 0)
                crcCount++
            if (rows[i].detail.indexOf("错误") >= 0 || rows[i].warn !== "")
                errorCount++
        }
        if (crcCount === 0 && errorCount === 0)
            return "运行态"
        return (crcCount > 0 ? ("校验 " + crcCount) : "") + (errorCount > 0 ? ((crcCount > 0 ? " / " : "") + "告警 " + errorCount) : "")
    }

    Component.onCompleted: loadProductList()

    function loadProductList() {
        if (!layoutManager) return
        var files = layoutManager.getProductFiles()
        productModel.clear()
        for (var i = 0; i < files.length; i++) productModel.append(files[i])
    }

    function loadProduct(idx) {
        if (idx < 0 || idx >= productModel.count) return
        currentFilePath = productModel.get(idx).path
        currentConfig = layoutManager.loadProductConfig(currentFilePath)
        hasUnsavedChanges = false
        loadCells()
    }

    // Resolve component IDs to their definitions
    function resolveComponents(compIds) {
        var result = []
        var allComps = currentConfig.components || []
        for (var i = 0; i < compIds.length; i++) {
            var id = compIds[i]
            if (id === "rawFrames" || id === "deviceInfo") { result.push({ id: id, type: id }); continue }
            for (var j = 0; j < allComps.length; j++) {
                if (allComps[j].id === id) { result.push(allComps[j]); break }
            }
        }
        return result
    }

    // Guess cell type from component list
    function detectCellType(compIds) {
        if (!compIds || compIds.length === 0) return "empty"
        if (compIds.indexOf("rawFrames") >= 0) return "rawFrames"
        if (compIds.indexOf("deviceInfo") >= 0) return "deviceInfo"
        return "canvas"  // buttons, EJM, FNR all go to canvas
    }

    // Map product component definition to DesignCanvas component type
    function mapToCanvasType(compDef) {
        switch (compDef.type) {
        case "buttonGroup": return { type: "ButtonRed", perItem: true, count: compDef.count || 8, label: "" }
        case "roller": return {
            type: compDef.orientation === "vertical" ? "VerticalRoller" : "HorizontalRoller",
            perItem: false,
            label: compDef.label || ""
        }
        case "fnrSwitch": return { type: "HorizontalFNR", perItem: false, label: compDef.label || "FNR" }
        case "counter": return null  // skip, shown inside button area
        case "indicator": return null
        default: return null
        }
    }

    // Auto-populate canvas with product components
    function populateCanvas(canvas, compIds) {
        if (!canvas) return
        canvas.clear()
        var resolved = resolveComponents(compIds)
        var x = 10, y = 10, maxRowH = 0
        var canvasW = canvas.canvasWidth - 10

        for (var i = 0; i < resolved.length; i++) {
            var mapping = mapToCanvasType(resolved[i])
            if (!mapping) continue

            if (mapping.perItem) {
                // Buttons follow the original DownloadTool density: 5 on the
                // first row, then wrap.
                var cols = Math.min(5, mapping.count)
                var colSpacing = 8
                var rowSpacing = 2
                var btnSize = ComponentRegistry.getDefaultSize(mapping.type)
                var bw = btnSize.width || 56
                var bh = btnSize.height || 80
                for (var b = 0; b < mapping.count; b++) {
                    var bx = 4 + (b % cols) * (bw + colSpacing)
                    var by = 4 + Math.floor(b / cols) * (bh + rowSpacing)
                    var buttonConfig = ComponentRegistry.getDefaultConfig(mapping.type)
                    buttonConfig.label = (b + 1).toString()
                    var buttonWrapper = canvas.addComponent(mapping.type, bx, by, buttonConfig)
                    if (buttonWrapper)
                        buttonWrapper.bindingId = resolved[i].id + "." + b
                }
                y += Math.ceil(mapping.count / cols) * (bh + rowSpacing) + 10
            } else {
                // Single component
                var size = ComponentRegistry.getDefaultSize(mapping.type)
                var w = size.width || 200
                var h = size.height || 100
                if (x + w > canvasW) { x = 10; y += maxRowH + 8; maxRowH = 0 }
                var config = ComponentRegistry.getDefaultConfig(mapping.type)
                if (mapping.label) config.label = mapping.label
                var wrapper = canvas.addComponent(mapping.type, x, y, config)
                if (wrapper)
                    wrapper.bindingId = resolved[i].id
                x += w + 8
                maxRowH = Math.max(maxRowH, h)
            }
        }
    }

    function cloneConfig(config) {
        var copy = {}
        config = config || {}
        for (var key in config)
            copy[key] = config[key]
        return copy
    }

    function mergedComponentConfig(type, config) {
        var merged = ComponentRegistry.getDefaultConfig(type)
        config = config || {}
        for (var key in config)
            merged[key] = config[key]
        if (type.indexOf("Button") === 0) {
            var defaults = ComponentRegistry.getDefaultConfig(type)
            merged.bezelSize = defaults.bezelSize
            merged.capSize = defaults.capSize
        }
        return merged
    }

    function sizeForComponentConfig(type, config) {
        var size = ComponentRegistry.getDefaultSize(type)
        config = config || {}
        if (type.indexOf("Button") === 0) {
            var defaults = ComponentRegistry.getDefaultConfig(type)
            config.bezelSize = defaults.bezelSize
            config.capSize = defaults.capSize
        }
        return size
    }

    function clampComponentPosition(canvas, type, x, y, config) {
        var size = sizeForComponentConfig(type, config)
        var targetWidth = canvas.canvasWidth || root.defaultCanvasWidth
        var targetHeight = canvas.canvasHeight || root.defaultCanvasHeight
        var maxX = Math.max(0, targetWidth - size.width)
        var maxY = Math.max(0, targetHeight - size.height)
        return {
            x: Math.max(0, Math.min(x || 0, maxX)),
            y: Math.max(0, Math.min(y || 0, maxY))
        }
    }

    function addVisualComponent(canvas, visual, canvasMeta) {
        var type = visual.type || ""
        var config = mergedComponentConfig(type, visual.config || {})
        var targetWidth = canvas.canvasWidth || root.defaultCanvasWidth
        var targetHeight = canvas.canvasHeight || root.defaultCanvasHeight
        var sourceWidth = canvasMeta && canvasMeta.width ? canvasMeta.width : targetWidth
        var sourceHeight = canvasMeta && canvasMeta.height ? canvasMeta.height : targetHeight
        var sx = sourceWidth > 0 ? targetWidth / sourceWidth : 1
        var sy = sourceHeight > 0 ? targetHeight / sourceHeight : 1
        var pos = clampComponentPosition(canvas, type, (visual.x || 0) * sx, (visual.y || 0) * sy, config)
        var wrapper = canvas.addComponent(type, pos.x, pos.y, config)
        if (wrapper && visual.bindingId)
            wrapper.bindingId = visual.bindingId
        return wrapper
    }

    function labelForCellType(value) {
        for (var i = 0; i < cellTypeOptions.length; i++) {
            if (cellTypeOptions[i].value === value)
                return cellTypeOptions[i].label
        }
        return "空白"
    }

    function setCellType(cell, value) {
        if (!cell || cell.cellType === value)
            return
        cell.cellType = value
        hasUnsavedChanges = true
        refreshCanvasMode()
    }

    function normalizedCanvasMeta(canvasMeta) {
        return {
            width: defaultCanvasWidth,
            height: defaultCanvasHeight,
            scaleMode: canvasMeta && canvasMeta.scaleMode ? canvasMeta.scaleMode : "uniform"
        }
    }

    function sourceCanvasMeta(canvasMeta) {
        var width = canvasMeta && canvasMeta.width ? canvasMeta.width : defaultCanvasWidth
        var height = canvasMeta && canvasMeta.height ? canvasMeta.height : defaultCanvasHeight
        if (width <= 0 || height <= 0) {
            width = defaultCanvasWidth
            height = defaultCanvasHeight
        }
        return { width: width, height: height }
    }

    function loadCells() {
        if (!currentConfig || !currentConfig.layout) return
        var cells = (currentConfig.layout.grid || {}).cells || []

        // Use timer to ensure canvas items are created
        cellLoadTimer.cellData = cells
        cellLoadTimer.start()
    }

    Timer {
        id: cellLoadTimer
        interval: 100; repeat: false
        property var cellData: []
        onTriggered: doLoadCells(cellData)
    }

    function doLoadCells(cells) {
        loadingCells = true
        for (var i = 0; i < cellRepeater.count && i < cells.length; i++) {
            var cell = cellRepeater.itemAt(i)
            if (!cell) continue
            var c = cells[i]
            cell.cellTitle = c.title || ""
            // Map old types to new unified types
            var oldType = c.cellType || detectCellType(c.components)
            if (oldType === "buttons" || oldType === "ejm") oldType = "canvas"
            cell.cellType = oldType
            cell.cellCompIds = c.components || []
            var canvasMeta = normalizedCanvasMeta(c.canvas)
            var savedCanvasMeta = sourceCanvasMeta(c.canvas)
            cell.canvasDesignWidth = canvasMeta.width
            cell.canvasDesignHeight = canvasMeta.height
            cell.canvasScaleMode = canvasMeta.scaleMode

            // For canvas cells: populate with visual components or auto-generate from component IDs
            if (cell.cellType === "canvas" && cell.canvasItem) {
                var vis = c.visualComponents || []
                if (vis.length > 0) {
                    // Load saved visual layout with bindingIds
                    cell.canvasItem.clear()
                    for (var j = 0; j < vis.length; j++) {
                        addVisualComponent(cell.canvasItem, vis[j], savedCanvasMeta)
                    }
                } else if (c.components && c.components.length > 0) {
                    // Auto-populate from component definitions
                    populateCanvas(cell.canvasItem, c.components)
                }
            }
        }
        for (var k = cells.length; k < cellRepeater.count; k++) {
            var ec = cellRepeater.itemAt(k)
            if (ec) { ec.cellTitle = ""; ec.cellType = "empty"; ec.cellCompIds = [] }
        }
        refreshCanvasMode()
        refreshBindingStatus()
        hasUnsavedChanges = false
        loadingCells = false
    }

    function saveProduct() {
        if (!currentFilePath || !currentConfig) return
        var layout = currentConfig.layout || {}
        var grid = layout.grid || {}
        var cells = []
        for (var i = 0; i < cellRepeater.count; i++) {
            var cell = cellRepeater.itemAt(i)
            if (!cell) continue
            var cd = { row: Math.floor(i/2), col: i%2, title: cell.cellTitle, cellType: cell.cellType, components: cell.cellCompIds }
            if (cell.cellType === "canvas" && cell.canvasItem) {
                var canvasData = cell.canvasItem.toJSON()
                cd.canvas = {
                    width: canvasData.canvas.width,
                    height: canvasData.canvas.height,
                    scaleMode: canvasData.canvas.scaleMode || "uniform"
                }
                cd.visualComponents = []
                var comps = canvasData.components || []
                for (var j = 0; j < comps.length; j++)
                    cd.visualComponents.push({ type: comps[j].type, x: comps[j].x, y: comps[j].y, config: comps[j].config, bindingId: comps[j].bindingId || "" })
            }
            cells.push(cd)
        }
        grid.cells = cells; layout.grid = grid; currentConfig.layout = layout
        layoutManager.saveProductConfig(currentConfig, currentFilePath)
        hasUnsavedChanges = false
    }

    ListModel { id: productModel }
    ListModel { id: bindingStatusModel }

    // Collect all bindings from all canvas cells and compare with product components
    function refreshBindingStatus() {
        bindingStatusModel.clear()
        var allComps = currentConfig.components || []
        var usedBindings = []

        // Collect all bindingIds from all canvas cells
        for (var i = 0; i < cellRepeater.count; i++) {
            var cell = cellRepeater.itemAt(i)
            if (!cell || cell.cellType !== "canvas" || !cell.canvasItem) continue
            var used = cell.canvasItem.getUsedBindings()
            for (var j = 0; j < used.length; j++) usedBindings.push(used[j])
        }

        for (var k = 0; k < allComps.length; k++) {
            var comp = allComps[k]
            if (comp.type === "joystick") continue // fixed, skip

            if (comp.type === "buttonGroup") {
                // Expand buttons
                var count = comp.count || 8
                for (var b = 0; b < count; b++) {
                    var btnId = comp.id + "." + b
                    var btnBound = usedBindings.indexOf(btnId) >= 0
                    bindingStatusModel.append({ compId: "BTN" + (b+1), bound: btnBound, boundTo: btnBound ? btnId : "" })
                }
            } else {
                // Single component
                var isBound = usedBindings.indexOf(comp.id) >= 0
                // Also check fnr composite bindings
                if (!isBound) {
                    for (var m = 0; m < usedBindings.length; m++) {
                        if (usedBindings[m].indexOf(comp.id) >= 0) { isBound = true; break }
                    }
                }
                var typeLabel = comp.type === "roller" ? "轴" : (comp.type === "fnrSwitch" ? "FNR" : comp.type)
                bindingStatusModel.append({ compId: comp.label || comp.id, bound: isBound, boundTo: isBound ? comp.id : "" })
            }
        }
    }

    Rectangle { anchors.fill: parent; color: dtBg }

    // ===== Top Bar =====
    Rectangle {
        id: topBar; anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
        height: 44; color: "white"
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: dtBorder }
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 10
            Button { text: "← 返回"; flat: true; font.pixelSize: 11; onClicked: root.exitRequested() }
            Rectangle { width: 1; height: 20; color: dtBorder }
            Label { text: "产品配置编辑器"; font.pixelSize: 14; font.bold: true; color: dtText }
            Rectangle {
                visible: !!currentConfig.product; width: pL.width+10; height: 18; radius: 3
                color: currentConfig.product && currentConfig.product.protocol==="canopen" ? dtWarning : dtSuccess
                Label { id: pL; anchors.centerIn: parent; text: currentConfig.product ? currentConfig.product.name||"" : ""; font.pixelSize: 8; font.bold: true; color: "white" }
            }
            Label { visible: !!currentConfig.product; text: currentConfig.product ? currentConfig.product.description||"" : ""; font.pixelSize: 10; color: dtTextSec; elide: Text.ElideRight; Layout.fillWidth: true }
            Item { Layout.fillWidth: true }
            Button {
                text: hasUnsavedChanges ? "保存 *" : "已保存"; enabled: hasUnsavedChanges && currentFilePath !== ""
                font.pixelSize: 11
                palette.button: hasUnsavedChanges ? dtAccent : "#e5e5ea"
                palette.buttonText: hasUnsavedChanges ? "white" : dtTextMuted
                onClicked: saveProduct()
            }
        }
    }

    // ===== Main =====
    RowLayout {
        anchors.top: topBar.bottom; anchors.topMargin: 8
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.leftMargin: 10; anchors.rightMargin: 10; anchors.bottomMargin: 10; spacing: 10

        Item {
            id: leftSidebar
            Layout.preferredWidth: root.panelWidth
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignTop

            readonly property real gap: Constants.downloadToolCardGap
            readonly property real functionPanelHeight: Math.min(220, Math.max(180, height * 0.28))
            readonly property real dashboardHeight: Math.max(320, height - functionPanelHeight - gap)

            Rectangle {
                id: productListCard
                x: 0
                y: 0
                width: parent.width
                height: Math.min(parent.height, leftSidebar.dashboardHeight)
                color: "white"; radius: 8; border.width: 1; border.color: dtBorder

                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 14; spacing: 8
                    Label { text: "产品列表"; font.pixelSize: 12; font.bold: true; color: dtText }
                    Rectangle { Layout.fillWidth: true; height: 1; color: dtBorder }
                    ListView {
                        id: productList; Layout.fillWidth: true; Layout.fillHeight: true
                        model: productModel; clip: true; spacing: 1; currentIndex: -1
                        delegate: Rectangle {
                            width: productList.width; height: 46; radius: 4
                            color: productList.currentIndex === index ? "#e8f0fe" : (pha.containsMouse ? dtBg : "transparent")
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                spacing: 6
                                Rectangle {
                                    width: 5
                                    height: 28
                                    radius: 2.5
                                    color: productList.currentIndex === index ? dtAccent : dtTextMuted
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Label {
                                        Layout.fillWidth: true
                                        text: model.displayName || model.name
                                        font.pixelSize: 10
                                        font.bold: productList.currentIndex === index
                                        color: dtText
                                        elide: Text.ElideRight
                                    }
                                    Label {
                                        Layout.fillWidth: true
                                        text: (model.protocol || "j1939").toUpperCase() + "  " + (model.description || model.model || "")
                                        font.pixelSize: 8
                                        color: dtTextSec
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                            MouseArea {
                                id: pha
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { productList.currentIndex = index; loadProduct(index) }
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: bindingStatusCard
                x: 0
                y: productListCard.height + leftSidebar.gap
                width: parent.width
                height: Math.max(0, parent.height - y)
                color: "white"; radius: 8; border.width: 1; border.color: dtBorder
                visible: height > 0

                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 12; spacing: 6

                    Label { text: "绑定状态"; font.pixelSize: 12; font.bold: true; color: dtText }
                    Rectangle { Layout.fillWidth: true; height: 1; color: dtBorder }

                    ListView {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        clip: true; spacing: 2
                        model: bindingStatusModel

                        delegate: Row {
                            width: parent ? parent.width : 0; spacing: 4; height: 18

                            Rectangle {
                                width: 8; height: 8; radius: 4; anchors.verticalCenter: parent.verticalCenter
                                color: model.bound ? dtSuccess : "#ff3b30"
                            }
                            Text {
                                text: model.compId; font.pixelSize: 9; font.bold: true
                                color: model.bound ? dtText : dtTextMuted
                                anchors.verticalCenter: parent.verticalCenter; width: 96; elide: Text.ElideRight
                            }
                            Text {
                                text: model.bound ? model.boundTo : "未绑定"
                                font.pixelSize: 8; color: model.bound ? dtAccent : "#ff3b30"
                                anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                                width: Math.max(60, parent.width - 116)
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: previewPane
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 520

            Rectangle {
                anchors.fill: parent
                color: dtBg
                radius: 8
            }

            Item {
                id: dtViewport
                anchors.top: parent.top; anchors.topMargin: 8
                anchors.left: parent.left; anchors.leftMargin: 8
                anchors.right: parent.right; anchors.rightMargin: 8
                anchors.bottom: parent.bottom; anchors.bottomMargin: 8

                readonly property real gap: Constants.downloadToolCardGap
                readonly property real functionPanelHeight: Math.min(220, Math.max(180, height * 0.28))
                readonly property real dashboardHeight: Math.max(320, height - functionPanelHeight - gap)
                readonly property var editorLayout: currentConfig && currentConfig.layout ? currentConfig.layout : ({})
                readonly property var leftLayout: editorLayout.left ? editorLayout.left : ({})
                readonly property real leftWidthRatio: leftLayout.widthRatio ? leftLayout.widthRatio : 0.52
                readonly property real joySlotW: Math.max(0, Math.min(width - gap, width * leftWidthRatio))
                readonly property real joyCardSize: Math.max(0, Math.min(joySlotW, dashboardHeight))
                readonly property real gridW: Math.max(0, width - joySlotW - gap)
                readonly property real gridH: dashboardHeight
                readonly property real cellSize: Math.max(0, Math.min((gridW - gap) / 2, (dashboardHeight - gap) / 2))
                readonly property real gridContentW: cellSize * 2 + gap
                readonly property real gridContentH: cellSize * 2 + gap
                readonly property real gridOffsetX: Math.max(0, (gridW - gridContentW) / 2)
                readonly property real gridOffsetY: Math.max(0, (dashboardHeight - gridContentH) / 2)
                readonly property real cardScale: cellSize / Constants.homeCardDesignSize
                readonly property real joyCardScale: joyCardSize / Constants.homeCardDesignSize
                readonly property real cardMargin: Constants.downloadToolCardMargin * cardScale
                readonly property real joyCardMargin: Constants.downloadToolCardMargin * joyCardScale
                readonly property real cardHeaderHeight: Constants.downloadToolCardHeaderHeight * cardScale
                readonly property real joyCardHeaderHeight: Constants.downloadToolCardHeaderHeight * joyCardScale
                readonly property real cardHeaderGap: Constants.downloadToolCardHeaderGap * cardScale

                Rectangle {
                    id: joyPrev
                    x: Math.max(0, (dtViewport.joySlotW - width) / 2)
                    y: Math.max(0, (dtViewport.dashboardHeight - height) / 2)
                    width: dtViewport.joyCardSize
                    height: dtViewport.joyCardSize
                    radius: Constants.radiusPanel * dtViewport.joyCardScale; color: "#eaeaec"
                    border.width: 1; border.color: dtBorder

                    Item {
                        anchors.fill: parent
                        anchors.margins: dtViewport.joyCardMargin

                        Text {
                            id: joyHeader
                            anchors.top: parent.top
                            anchors.left: parent.left
                            text: "XY 轴 (BJM)"
                            color: dtTextSec
                            font.pixelSize: Math.max(8, 11 * dtViewport.joyCardScale)
                            font.weight: Font.Bold
                            font.letterSpacing: 0.8
                        }

                        StatusIndicator {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            indicatorSize: 8 * dtViewport.joyCardScale
                            active: false
                        }

                        Item {
                            id: joystickArea
                            anchors.top: joyHeader.bottom
                            anchors.topMargin: 8 * dtViewport.joyCardScale
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom

                            property real gap: 8 * dtViewport.joyCardScale
                            property real sideW: 50 * dtViewport.joyCardScale
                            property real axisH: 20 * dtViewport.joyCardScale
                            property real botH: axisH + gap
                            property real joySize: Math.max(1, Math.min(width - sideW - gap,
                                                                        height - botH - gap))

                            JoystickPad {
                                id: joystick
                                anchors.top: parent.top
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.horizontalCenterOffset: -parent.sideW / 2
                                padSize: parent.joySize
                                width: padSize
                                height: padSize
                                xValue: 0
                                yValue: 0
                                enabled: false
                            }

                            ColumnLayout {
                                anchors.top: joystick.top
                                anchors.bottom: joystick.bottom
                                anchors.left: joystick.right
                                anchors.leftMargin: parent.gap
                                width: parent.sideW
                                spacing: 4 * dtViewport.joyCardScale

                                AxisValueBar {
                                    Layout.fillHeight: true
                                    Layout.alignment: Qt.AlignHCenter
                                    width: 12 * dtViewport.joyCardScale
                                    orientation: "vertical"
                                    value: 0
                                    active: false
                                    label: "Y"
                                }
                            }

                            RowLayout {
                                anchors.top: joystick.bottom
                                anchors.topMargin: parent.gap
                                anchors.left: joystick.left
                                anchors.right: joystick.right
                                height: parent.axisH
                                spacing: 8 * dtViewport.joyCardScale

                                AxisValueBar {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    height: 12 * dtViewport.joyCardScale
                                    orientation: "horizontal"
                                    value: 0
                                    active: false
                                    label: "X"
                                }
                            }
                        }
                    }
                }

                Item {
                    id: gridArea
                    x: dtViewport.joySlotW + dtViewport.gap
                    y: 0
                    width: dtViewport.gridW
                    height: dtViewport.gridH

                    property real cellSize: dtViewport.cellSize

                    Repeater {
                        id: cellRepeater; model: 4

                        Rectangle {
                            id: cellCard
                            x: dtViewport.gridOffsetX + (index % 2) * (gridArea.cellSize + dtViewport.gap)
                            y: dtViewport.gridOffsetY + Math.floor(index / 2) * (gridArea.cellSize + dtViewport.gap)
                            width: gridArea.cellSize; height: gridArea.cellSize
                            radius: Constants.radiusPanel * dtViewport.cardScale; color: "#eaeaec"
                            border.width: 1; border.color: activeCellIndex === index ? dtAccent : dtBorder
                            z: activeCellIndex === index ? 10 : 0

                            property string cellTitle: ""
                            property string cellType: "empty"
                            property var cellCompIds: []
                            property int canvasDesignWidth: root.defaultCanvasWidth
                            property int canvasDesignHeight: root.defaultCanvasHeight
                            property string canvasScaleMode: "uniform"
                            property alias canvasItem: cvLoader.item

                            MouseArea { anchors.fill: parent; z: -1; onClicked: { activeCellIndex = index } }

                            Item {
                                id: cellContent
                                anchors.fill: parent
                                anchors.margins: cellCard.cellType === "canvas" ? 0 : dtViewport.cardMargin

                                Row {
                                    id: hdr
                                    anchors.top: parent.top
                                    anchors.topMargin: cellCard.cellType === "canvas" ? dtViewport.cardMargin : 0
                                    anchors.left: parent.left
                                    anchors.leftMargin: cellCard.cellType === "canvas" ? dtViewport.cardMargin : 0
                                    anchors.right: parent.right
                                    anchors.rightMargin: cellCard.cellType === "canvas" ? dtViewport.cardMargin : 0
                                    height: dtViewport.cardHeaderHeight; spacing: 4 * dtViewport.cardScale
                                    z: 20

                                    Text {
                                        text: cellCard.cellTitle; color: dtTextSec
                                        font.pixelSize: Math.max(8, 11 * dtViewport.cardScale); font.weight: Font.Bold; font.letterSpacing: 0.8
                                        width: Math.max(1, parent.width - typeSelector.width - 6)
                                        elide: Text.ElideRight
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Rectangle {
                                        id: typeSelector
                                        width: Math.max(72, 80 * dtViewport.cardScale)
                                        height: Math.max(24, 28 * dtViewport.cardScale)
                                        radius: 4
                                        color: "#f5f5f7"
                                        border.width: 1
                                        border.color: typeMouse.containsMouse ? dtAccent : "#8e8e93"
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            anchors.left: parent.left
                                            anchors.leftMargin: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: root.labelForCellType(cellCard.cellType)
                                            color: dtText
                                            font.pixelSize: Math.max(8, 10 * dtViewport.cardScale)
                                            font.bold: true
                                        }

                                        Canvas {
                                            width: 12; height: 8
                                            anchors.right: parent.right
                                            anchors.rightMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            onPaint: {
                                                var ctx = getContext("2d")
                                                ctx.clearRect(0, 0, width, height)
                                                ctx.fillStyle = dtText
                                                ctx.beginPath()
                                                ctx.moveTo(0, 0)
                                                ctx.lineTo(width, 0)
                                                ctx.lineTo(width / 2, height)
                                                ctx.closePath()
                                                ctx.fill()
                                            }
                                        }

                                        MouseArea {
                                            id: typeMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                activeCellIndex = index
                                                cellTypePopup.openFor(cellCard, typeSelector)
                                            }
                                        }
                                    }
                                }

                                Item {
                                    id: body
                                    anchors.top: cellCard.cellType === "canvas" ? parent.top : hdr.bottom
                                    anchors.topMargin: cellCard.cellType === "canvas" ? 0 : dtViewport.cardHeaderGap
                                    anchors.left: parent.left; anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    z: cellCard.cellType === "canvas" ? 0 : 1

                                    Column {
                                        id: rawFramesPanel
                                        visible: cellCard.cellType === "rawFrames"
                                        anchors.fill: parent
                                        spacing: Math.max(5, 6 * dtViewport.cardScale)
                                        clip: true

                                        readonly property real labelFont: Math.max(10, 12 * dtViewport.cardScale)
                                        readonly property real idFont: Math.max(9, 10 * dtViewport.cardScale)
                                        readonly property real dataFont: Math.max(11, 13 * dtViewport.cardScale)
                                        readonly property real metaFont: Math.max(8, 9 * dtViewport.cardScale)
                                        readonly property string protocolText: currentConfig.product && currentConfig.product.protocol
                                                                           ? currentConfig.product.protocol.toUpperCase()
                                                                           : "J1939"
                                        readonly property string productText: currentConfig.product
                                                                           ? (currentConfig.product.model || currentConfig.product.name || "---")
                                                                           : "---"
                                        readonly property var expectedRows: expectedRawFrameRows()

                                        Flow {
                                            width: parent.width
                                            spacing: 4

                                            Repeater {
                                                model: [
                                                    { label: "协议", value: rawFramesPanel.protocolText },
                                                    { label: "产品", value: rawFramesPanel.productText },
                                                    { label: "报文", value: rawFramesPanel.expectedRows.length + " 条" },
                                                    { label: "异常", value: previewDiagnosticText() }
                                                ]

                                                Rectangle {
                                                    height: Math.max(18, 20 * dtViewport.cardScale)
                                                    width: Math.min(rawInfoText.implicitWidth + 14, body.width)
                                                    radius: height / 2
                                                    color: "#f5f5f7"
                                                    border.width: 1
                                                    border.color: dtBorder

                                                    Text {
                                                        id: rawInfoText
                                                        anchors.centerIn: parent
                                                        text: modelData.label + " " + modelData.value
                                                        color: modelData.label === "异常" ? dtWarning : dtTextSec
                                                        font.pixelSize: rawFramesPanel.metaFont
                                                        font.bold: modelData.label === "异常"
                                                        elide: Text.ElideRight
                                                        width: parent.width - 10
                                                    }
                                                }
                                            }
                                        }

                                        Rectangle {
                                            width: parent.width
                                            height: 1
                                            color: dtBorder
                                            opacity: 0.75
                                        }

                                        Repeater {
                                            model: rawFramesPanel.expectedRows
                                            Row {
                                                width: parent ? parent.width : 0
                                                spacing: Math.max(6, 8 * dtViewport.cardScale)
                                                height: Math.max(36, 42 * dtViewport.cardScale)

                                                Text {
                                                    id: frameLabel
                                                    text: modelData.lbl
                                                    color: modelData.warn !== "" ? dtWarning : dtAccent
                                                    font.pixelSize: rawFramesPanel.labelFont
                                                    font.bold: true
                                                    width: Math.max(36, 42 * dtViewport.cardScale)
                                                    anchors.top: parent.top
                                                    anchors.topMargin: 2
                                                }

                                                Column {
                                                    width: Math.max(1, parent.width - frameLabel.width - parent.spacing)
                                                    spacing: 1

                                                    Row {
                                                        width: parent.width
                                                        spacing: Math.max(5, 6 * dtViewport.cardScale)

                                                        Text {
                                                            id: frameIdText
                                                            text: modelData.cid
                                                            color: modelData.warn !== "" ? dtWarning : dtTextSec
                                                            font.pixelSize: rawFramesPanel.idFont
                                                            font.family: "Consolas"
                                                            font.bold: modelData.warn !== ""
                                                            elide: Text.ElideRight
                                                            width: Math.max(88, parent.width * 0.46)
                                                        }
                                                        Text {
                                                            text: modelData.period
                                                            color: dtText
                                                            font.pixelSize: rawFramesPanel.idFont
                                                            font.family: "Consolas"
                                                            font.bold: true
                                                            elide: Text.ElideRight
                                                            width: Math.max(1, parent.width - frameIdText.width - parent.spacing)
                                                        }
                                                    }
                                                    Text {
                                                        text: modelData.warn !== "" ? (modelData.detail + " · " + modelData.warn) : modelData.detail
                                                        color: modelData.warn !== "" ? dtWarning : dtText
                                                        font.pixelSize: rawFramesPanel.metaFont
                                                        font.family: "Consolas"
                                                        elide: Text.ElideRight
                                                        width: parent.width
                                                    }
                                                }
                                            }
                                        }

                                        Row {
                                            width: parent.width
                                            spacing: 5

                                            Rectangle {
                                                width: 8
                                                height: 8
                                                radius: 4
                                                color: dtTextMuted
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            Text {
                                                text: rawFramesPanel.expectedRows.length > 0
                                                      ? "预览配置：周期来自产品JSON，错误帧/超时由下载工具运行态统计"
                                                      : "未配置CAN报文"
                                                color: dtTextMuted
                                                font.pixelSize: rawFramesPanel.metaFont
                                                elide: Text.ElideRight
                                                width: parent.width - 14
                                            }
                                        }
                                    }

                                    Column {
                                        visible: cellCard.cellType === "deviceInfo"
                                        anchors.fill: parent; spacing: 6
                                        Repeater {
                                            model: [
                                                { label: "烧录时间", val: "2026-03-31 10:00" },
                                                { label: "客户名称", val: currentConfig.product ? currentConfig.product.description||"示例客户" : "示例客户" },
                                                { label: "设备型号", val: currentConfig.product ? currentConfig.product.model||"---" : "---" },
                                                { label: "设备ID",  val: "0x00001234" },
                                                { label: "序列号",  val: "SN001" }
                                            ]
                                            Row {
                                                spacing: 8
                                                Text { text: modelData.label+"："; color: dtTextSec; font.pixelSize: 9; width: 50; horizontalAlignment: Text.AlignRight }
                                                Text { text: modelData.val; color: dtAccent; font.pixelSize: 10; font.bold: true; elide: Text.ElideRight; width: Math.max(80, body.width - 62) }
                                            }
                                        }
                                    }

                                    Item {
                                        id: canvasViewport
                                        anchors.fill: parent
                                        visible: cellCard.cellType === "canvas"
                                        clip: true

                                        readonly property real displayCanvasWidth: Math.max(1, width)
                                        readonly property real displayCanvasHeight: Math.max(1, height)

                                        Loader {
                                            id: cvLoader
                                            active: true
                                            anchors.fill: parent
                                            sourceComponent: DesignCanvas {
                                                panelWidth: canvasViewport.displayCanvasWidth
                                                panelHeight: canvasViewport.displayCanvasHeight
                                                borderRadius: Constants.radiusPanel
                                                panelChromeVisible: false
                                                canvasWidth: cellCard.canvasDesignWidth
                                                canvasHeight: cellCard.canvasDesignHeight
                                                scaleMode: cellCard.canvasScaleMode
                                                productBindings: currentConfig.components || []
                                                onCanvasPressed: {
                                                    root.activeCellIndex = index
                                                }
                                                onLayoutModified: {
                                                    if (!root.loadingCells)
                                                        hasUnsavedChanges = true
                                                    root.refreshBindingStatus()
                                                }
                                            }
                                        }
                                    }

                                    Text { visible: cellCard.cellType === "empty"; anchors.centerIn: parent; text: "空白"; color: dtTextMuted; font.pixelSize: 10 }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: componentDock
                    x: 0
                    y: dtViewport.dashboardHeight + dtViewport.gap
                    width: parent.width
                    height: Math.max(120, parent.height - y)
                    radius: 24
                    color: "#eaeaec"
                    border.width: 1
                    border.color: dtBorder
                    clip: true

                    ComponentPanel {
                        id: componentPanel
                        anchors.fill: parent
                        anchors.margins: Math.max(10, 16 * dtViewport.cardScale)
                        panelWidth: width
                        visible: root.isCanvasMode
                        neuBg: dtBg
                        neuLightShadow: "#ffffff"
                        neuDarkShadow: dtBorder
                        neuSurface: "white"
                        neuTextPrimary: dtText
                        neuTextSecondary: dtTextSec
                        neuAccent: dtAccent

                        onComponentRequested: function(ct) {
                            var cell = root.activeCanvasCell()
                            if (!cell || !cell.canvasItem) return
                            var size = ComponentRegistry.getDefaultSize(ct)
                            var cfg = ComponentRegistry.getDefaultConfig(ct)
                            cell.canvasItem.addComponent(ct,
                                                         (cell.canvasItem.canvasWidth - size.width) / 2,
                                                         (cell.canvasItem.canvasHeight - size.height) / 2,
                                                         cfg)
                            hasUnsavedChanges = true
                            refreshBindingStatus()
                        }

                        onComponentDragStarted: function(ct,gx,gy) {
                            dp.componentType = ct
                            dp.visible = true
                            var p = root.mapFromGlobal(gx, gy)
                            dp.x = p.x - dp.width / 2
                            dp.y = p.y - dp.height / 2
                        }

                        onComponentDragMoved: function(gx,gy) {
                            var p = root.mapFromGlobal(gx, gy)
                            dp.x = p.x - dp.width / 2
                            dp.y = p.y - dp.height / 2
                        }

                        onComponentDragEnded: function(gx,gy) {
                            dp.visible = false
                            for (var i = 0; i < cellRepeater.count; i++) {
                                var cell = cellRepeater.itemAt(i)
                                if (!cell || cell.cellType !== "canvas" || !cell.canvasItem) continue
                                var displayPos = cell.canvasItem.mapFromGlobal(gx, gy)
                                if (displayPos.x >= 0 && displayPos.x <= cell.canvasItem.width
                                        && displayPos.y >= 0 && displayPos.y <= cell.canvasItem.height) {
                                    activeCellIndex = i
                                    var pos = cell.canvasItem.displayToCanvasPoint(displayPos.x, displayPos.y)
                                    var size = ComponentRegistry.getDefaultSize(dp.componentType)
                                    var cfg = ComponentRegistry.getDefaultConfig(dp.componentType)
                                    cell.canvasItem.addComponent(dp.componentType,
                                                                 pos.x - size.width / 2,
                                                                 pos.y - size.height / 2,
                                                                 cfg)
                                    hasUnsavedChanges = true
                                    refreshBindingStatus()
                                    return
                                }
                            }
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 8
                        width: Math.min(parent.width - 32, 320)
                        visible: !root.isCanvasMode

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "组件面板"
                            font.pixelSize: 13
                            font.bold: true
                            color: dtText
                        }
                        Rectangle { width: parent.width; height: 1; color: dtBorder }
                        Label {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                            text: "选择「画布」类型的卡片后可拖放组件"
                            font.pixelSize: 10
                            color: dtTextSec
                            lineHeight: 1.4
                        }
                    }
                }
            }
        }

    }

    Popup {
        id: cellTypePopup
        parent: root
        width: 108
        height: typePopupContent.implicitHeight + 8
        padding: 4
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        z: 10000

        property var targetCell: null

        background: Rectangle {
            radius: 6
            color: "white"
            border.width: 1
            border.color: dtBorder
        }

        contentItem: Column {
            id: typePopupContent
            spacing: 2
            Repeater {
                model: cellTypeOptions
                delegate: Rectangle {
                    width: cellTypePopup.width - 8
                    height: 28
                    radius: 4
                    color: typeChoiceMouse.containsMouse ? "#e8f0fe" : "transparent"

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        color: dtText
                        font.pixelSize: 10
                        font.bold: cellTypePopup.targetCell && cellTypePopup.targetCell.cellType === modelData.value
                    }

                    MouseArea {
                        id: typeChoiceMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.setCellType(cellTypePopup.targetCell, modelData.value)
                            cellTypePopup.close()
                        }
                    }
                }
            }
        }

        function openFor(cell, anchorItem) {
            targetCell = cell
            var pos = anchorItem.mapToItem(root, 0, anchorItem.height + 4)
            x = Math.max(8, Math.min(pos.x, root.width - width - 8))
            y = Math.max(8, Math.min(pos.y, root.height - height - 8))
            open()
        }
    }

    // Drag proxy
    Item {
        id: dp
        visible: false
        z: 9999
        opacity: 0.88

        property string componentType: ""
        property real thumbScale: 0.55

        width: dpThumbLoader.item ? dpThumbLoader.item.width * thumbScale + 12 : 60
        height: dpThumbLoader.item ? dpThumbLoader.item.height * thumbScale + 12 : 60

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: "#f8f8fa"
            border.width: 1
            border.color: dtAccent

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#26000000"
                shadowBlur: 0.35
                shadowVerticalOffset: 4
            }
        }

        Item {
            anchors.centerIn: parent
            width: dpThumbLoader.item ? dpThumbLoader.item.width : 0
            height: dpThumbLoader.item ? dpThumbLoader.item.height : 0
            scale: dp.thumbScale
            enabled: false

            Loader {
                id: dpThumbLoader
                active: dp.visible
                sourceComponent: {
                    var t = dp.componentType
                    if (t.indexOf("Button") === 0) return dpButtonComp
                    if (t === "FNRSwitch") return dpFNRComp
                    if (t === "VerticalRoller") return dpVRollerComp
                    if (t === "HorizontalRoller") return dpHRollerComp
                    if (t === "HorizontalFNR") return dpHFNRComp
                    if (t === "HorizontalFNRRight") return dpHFNRRightComp
                    return null
                }
                onLoaded: root.applyDragThumbConfig(item, dp.componentType)
            }
        }
    }

    Component { id: dpButtonComp; IndustrialButton {} }
    Component { id: dpFNRComp; FNRSwitchUnit {} }
    Component { id: dpVRollerComp; VerticalRollerUnit {} }
    Component { id: dpHRollerComp; HorizontalRollerUnit {} }
    Component { id: dpHFNRComp; HorizontalFNRUnit {} }
    Component { id: dpHFNRRightComp; HorizontalFNRRightUnit {} }

    function applyDragThumbConfig(item, type) {
        if (!item)
            return
        var defaultConfig = ComponentRegistry.getDefaultConfig(type)
        for (var key in defaultConfig) {
            if (item.hasOwnProperty(key))
                item[key] = defaultConfig[key]
        }

        var defaultSize = ComponentRegistry.getDefaultSize(type)
        if (defaultSize.width > 0)
            item.width = defaultSize.width
        if (defaultSize.height > 0)
            item.height = defaultSize.height
    }

    Shortcut { sequence: "Ctrl+S"; onActivated: saveProduct() }
}
