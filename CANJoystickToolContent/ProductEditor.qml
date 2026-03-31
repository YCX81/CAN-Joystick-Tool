import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import CANJoystickTool

Item {
    id: root
    signal exitRequested()

    property var layoutManager: typeof LayoutManager !== 'undefined' ? LayoutManager : null
    property var currentConfig: ({})
    property string currentFilePath: ""
    property bool hasUnsavedChanges: false
    property int activeCellIndex: 0

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
    function refreshCanvasMode() {
        if (activeCellIndex < 0 || activeCellIndex >= 4) { isCanvasMode = false; return }
        var cell = cellRepeater.itemAt(activeCellIndex)
        isCanvasMode = cell !== null && cell.cellType === "canvas"
    }
    onActiveCellIndexChanged: refreshCanvasMode()

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
        case "roller": return { type: "HorizontalRoller", perItem: false, label: compDef.label || "" }
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
        var canvasW = canvas.panelWidth - 32

        for (var i = 0; i < resolved.length; i++) {
            var mapping = mapToCanvasType(resolved[i])
            if (!mapping) continue

            if (mapping.perItem) {
                // Buttons: lay out in grid
                var cols = 4, spacing = 5
                var btnSize = ComponentRegistry.getDefinition(mapping.type)
                var bw = btnSize ? btnSize.defaultWidth : 56
                var bh = btnSize ? btnSize.defaultHeight : 80
                for (var b = 0; b < mapping.count; b++) {
                    var bx = 10 + (b % cols) * (bw + spacing)
                    var by = y + Math.floor(b / cols) * (bh + spacing)
                    canvas.addComponent(mapping.type, bx, by, { variant: "red", label: (b+1).toString() })
                }
                y += Math.ceil(mapping.count / cols) * (bh + spacing) + 10
            } else {
                // Single component
                var def = ComponentRegistry.getDefinition(mapping.type)
                var w = def ? def.defaultWidth : 200
                var h = def ? def.defaultHeight : 100
                if (x + w > canvasW) { x = 10; y += maxRowH + 8; maxRowH = 0 }
                var config = def ? ComponentRegistry.getDefaultConfig(mapping.type) : {}
                if (mapping.label) config.label = mapping.label
                canvas.addComponent(mapping.type, x, y, config)
                x += w + 8
                maxRowH = Math.max(maxRowH, h)
            }
        }
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

            // For canvas cells: populate with visual components or auto-generate from component IDs
            if (cell.cellType === "canvas" && cell.canvasItem) {
                var vis = c.visualComponents || []
                if (vis.length > 0) {
                    // Load saved visual layout
                    cell.canvasItem.clear()
                    for (var j = 0; j < vis.length; j++)
                        cell.canvasItem.addComponent(vis[j].type, vis[j].x||0, vis[j].y||0, vis[j].config||{})
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
                cd.visualComponents = []
                var comps = cell.canvasItem.toJSON().components || []
                for (var j = 0; j < comps.length; j++)
                    cd.visualComponents.push({ type: comps[j].type, x: comps[j].x, y: comps[j].y, config: comps[j].config })
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
        anchors.top: topBar.bottom; anchors.topMargin: 6
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.leftMargin: 6; anchors.rightMargin: 6; anchors.bottomMargin: 6; spacing: 6

        // ---- Product List ----
        Rectangle {
            Layout.preferredWidth: 170; Layout.fillHeight: true
            color: "white"; radius: 8; border.width: 1; border.color: dtBorder
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 8; spacing: 4
                Label { text: "产品列表"; font.pixelSize: 11; font.bold: true; color: dtText }
                Rectangle { Layout.fillWidth: true; height: 1; color: dtBorder }
                ListView {
                    id: productList; Layout.fillWidth: true; Layout.fillHeight: true
                    model: productModel; clip: true; spacing: 1; currentIndex: -1
                    delegate: Rectangle {
                        width: productList.width; height: 28; radius: 4
                        color: productList.currentIndex === index ? "#e8f0fe" : (pha.containsMouse ? dtBg : "transparent")
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 6; spacing: 4
                            Rectangle { width: 5; height: 5; radius: 2.5; color: productList.currentIndex === index ? dtAccent : dtTextMuted }
                            Label { Layout.fillWidth: true; text: model.name; font.pixelSize: 10; color: dtText; elide: Text.ElideRight }
                        }
                        MouseArea { id: pha; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { productList.currentIndex = index; loadProduct(index) } }
                    }
                }
            }
        }

        // ---- Center: Preview Layout ----
        Item {
            Layout.fillWidth: true; Layout.fillHeight: true

            // Joystick preview (left) - simplified, no AluminumPanel
            Rectangle {
                id: joyPrev
                anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.left: parent.left
                width: Math.max(120, parent.width * 0.22)
                radius: 12; color: "#eaeaec"
                border.width: 1; border.color: dtBorder

                Column {
                    anchors.fill: parent; anchors.margins: 8; spacing: 4
                    Row {
                        width: parent.width
                        Text { text: "XY 轴 (BJM)"; color: dtTextSec; font.pixelSize: 10; font.weight: Font.Bold }
                        Item { width: parent.width - 80; height: 1 }
                        StatusIndicator { indicatorSize: 6; active: false }
                    }
                    Item {
                        width: parent.width; height: parent.height - 20
                        JoystickPad {
                            anchors.centerIn: parent
                            padSize: Math.min(parent.width, parent.height) * 0.85
                            width: padSize; height: padSize; xValue: 0; yValue: 0; enabled: false
                        }
                    }
                }
            }

            // 2x2 Grid (right)
            Item {
                id: gridArea
                anchors.top: parent.top; anchors.bottom: parent.bottom
                anchors.left: joyPrev.right; anchors.leftMargin: 6; anchors.right: parent.right
                property real cellW: (width - 6) / 2
                property real cellH: (height - 6) / 2

                Repeater {
                    id: cellRepeater; model: 4

                    Rectangle {
                        id: cellCard
                        x: (index % 2) * (gridArea.cellW + 6)
                        y: Math.floor(index / 2) * (gridArea.cellH + 6)
                        width: gridArea.cellW; height: gridArea.cellH
                        radius: 12; color: "#eaeaec"
                        border.width: 1; border.color: dtBorder
                        z: activeCellIndex === index ? 10 : 0

                        property string cellTitle: ""
                        property string cellType: "empty"
                        property var cellCompIds: []
                        property alias canvasItem: cvLoader.item

                        MouseArea { anchors.fill: parent; z: -1; onClicked: { activeCellIndex = index } }

                        // Header row
                        Row {
                            id: hdr; anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                            anchors.margins: 8; height: 20; spacing: 4

                            Text {
                                text: cellCard.cellTitle; color: dtTextSec
                                font.pixelSize: 10; font.weight: Font.Bold
                                width: parent.width - 75; elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            ComboBox {
                                width: 70; height: 20; font.pixelSize: 8; flat: true; z: 10
                                model: cellTypeOptions.map(function(o){ return o.label })
                                currentIndex: { for(var i=0;i<cellTypeOptions.length;i++) if(cellTypeOptions[i].value===cellCard.cellType) return i; return 3 }
                                onActivated: { cellCard.cellType = cellTypeOptions[currentIndex].value; hasUnsavedChanges = true; root.refreshCanvasMode() }
                            }
                        }

                        // Content area
                        Item {
                            id: body; anchors.top: hdr.bottom; anchors.topMargin: 2
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.bottom: parent.bottom; anchors.margins: 4

                            // === CAN Raw Frames ===
                            Column {
                                visible: cellCard.cellType === "rawFrames"
                                anchors.fill: parent; anchors.margins: 6; spacing: 3
                                Repeater {
                                    model: [
                                        { lbl: "BJM",  cid: "0x18FDD633", hex: "01 00 01 00 FF 00 00 FF" },
                                        { lbl: "EJM",  cid: "0x18FDD733", hex: "01 00 01 00 FF FF FF FF" },
                                        { lbl: "ADDR", cid: "0x18EEFF33", hex: "33 05 00 00 00 00 00 00" }
                                    ]
                                    Column {
                                        spacing: 0; width: parent ? parent.width : 0
                                        Row { spacing: 5
                                            Text { text: modelData.lbl; color: dtAccent; font.pixelSize: 8; font.bold: true; width: 30 }
                                            Text { text: modelData.cid; color: dtTextSec; font.pixelSize: 8; font.family: "Consolas" }
                                        }
                                        Text { text: modelData.hex; color: dtText; font.pixelSize: 9; font.family: "Consolas"; leftPadding: 36 }
                                    }
                                }
                                Text { text: "等待CAN报文..."; color: dtTextMuted; font.pixelSize: 9 }
                            }

                            // === Device Info ===
                            Column {
                                visible: cellCard.cellType === "deviceInfo"
                                anchors.fill: parent; anchors.margins: 6; spacing: 6
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
                                        Text { text: modelData.val; color: dtAccent; font.pixelSize: 10; font.bold: true }
                                    }
                                }
                            }

                            // === Canvas (DesignCanvas free-form) ===
                            Loader {
                                id: cvLoader; anchors.fill: parent; active: cellCard.cellType === "canvas"
                                sourceComponent: DesignCanvas {
                                    panelWidth: body.width; panelHeight: body.height; borderRadius: 4
                                    productBindings: currentConfig.components || []
                                    onLayoutModified: hasUnsavedChanges = true
                                }
                            }

                            // === Empty ===
                            Text { visible: cellCard.cellType === "empty"; anchors.centerIn: parent; text: "空白"; color: dtTextMuted; font.pixelSize: 10 }
                        }
                    }
                }
            }
        }

        // ---- Right: Component Panel + Binding Status ----
        ColumnLayout {
            Layout.preferredWidth: 200; Layout.maximumWidth: 200; Layout.fillHeight: true; spacing: 6

            // Component Panel (upper 60%)
            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.maximumHeight: root.height * 0.55
                color: "white"; radius: 8; border.width: 1; border.color: dtBorder

                ComponentPanel {
                    id: componentPanel; anchors.fill: parent; panelWidth: 200; visible: root.isCanvasMode
                    neuBg: dtBg; neuLightShadow: "#ffffff"; neuDarkShadow: dtBorder; neuSurface: "white"
                    neuTextPrimary: dtText; neuTextSecondary: dtTextSec; neuAccent: dtAccent

                    onComponentRequested: function(ct) {
                        if (activeCellIndex < 0) return
                        var cell = cellRepeater.itemAt(activeCellIndex)
                        if (!cell || cell.cellType !== "canvas" || !cell.canvasItem) return
                        var def = ComponentRegistry.getDefinition(ct); var cfg = def ? ComponentRegistry.getDefaultConfig(ct) : {}
                        cell.canvasItem.addComponent(ct, (cell.canvasItem.panelWidth-(def?def.defaultWidth:100))/2, (cell.canvasItem.panelHeight-(def?def.defaultHeight:100))/2, cfg)
                        hasUnsavedChanges = true; refreshBindingStatus()
                    }
                    onComponentDragStarted: function(ct,gx,gy) { dp.componentType=ct; dp.visible=true; var p=root.mapFromGlobal(gx,gy); dp.x=p.x-28; dp.y=p.y-28 }
                    onComponentDragMoved: function(gx,gy) { var p=root.mapFromGlobal(gx,gy); dp.x=p.x-28; dp.y=p.y-28 }
                    onComponentDragEnded: function(gx,gy) {
                        dp.visible = false
                        for (var i = 0; i < cellRepeater.count; i++) {
                            var cell = cellRepeater.itemAt(i)
                            if (!cell || cell.cellType !== "canvas" || !cell.canvasItem) continue
                            var pos = cell.canvasItem.mapFromGlobal(gx, gy)
                            if (pos.x >= 0 && pos.x <= cell.canvasItem.width && pos.y >= 0 && pos.y <= cell.canvasItem.height) {
                                activeCellIndex = i
                                var def = ComponentRegistry.getDefinition(dp.componentType)
                                var cfg = def ? ComponentRegistry.getDefaultConfig(dp.componentType) : {}
                                cell.canvasItem.addComponent(dp.componentType, pos.x-(def?def.defaultWidth/2:50), pos.y-(def?def.defaultHeight/2:50), cfg)
                                hasUnsavedChanges = true; refreshBindingStatus(); return
                            }
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent; spacing: 8; width: 160; visible: !root.isCanvasMode
                    Label { anchors.horizontalCenter: parent.horizontalCenter; text: "组件面板"; font.pixelSize: 13; font.bold: true; color: dtText }
                    Rectangle { width: parent.width; height: 1; color: dtBorder }
                    Label { width: parent.width; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                        text: "选择「画布」类型的\n卡片后可拖放组件"; font.pixelSize: 10; color: dtTextSec; lineHeight: 1.4 }
                }
            }

            // Binding Status Panel (lower part, fills remaining space)
            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true
                color: "white"; radius: 8; border.width: 1; border.color: dtBorder
                visible: !!currentConfig.components

                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 8; spacing: 4

                    Label { text: "绑定状态"; font.pixelSize: 11; font.bold: true; color: dtText }
                    Rectangle { Layout.fillWidth: true; height: 1; color: dtBorder }

                    ListView {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        clip: true; spacing: 2
                        model: bindingStatusModel

                        delegate: Row {
                            width: parent ? parent.width : 0; spacing: 4; height: 18

                            // Status dot: green=bound, red=unbound
                            Rectangle {
                                width: 8; height: 8; radius: 4; anchors.verticalCenter: parent.verticalCenter
                                color: model.bound ? dtSuccess : "#ff3b30"
                            }
                            Text {
                                text: model.compId; font.pixelSize: 9; font.bold: true
                                color: model.bound ? dtText : dtTextMuted
                                anchors.verticalCenter: parent.verticalCenter; width: 70; elide: Text.ElideRight
                            }
                            Text {
                                text: model.bound ? model.boundTo : "未绑定"
                                font.pixelSize: 8; color: model.bound ? dtAccent : "#ff3b30"
                                anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                                width: parent.width - 86
                            }
                        }
                    }
                }
            }
        }
    }

    // Drag proxy
    Rectangle { id: dp; visible: false; z: 9999; opacity: 0.85; width: 56; height: 56; radius: 6
        color: "#f0f0f2"; border.width: 1; border.color: dtAccent; property string componentType: ""
        Text { anchors.centerIn: parent; text: dp.componentType; font.pixelSize: 7; color: dtText; wrapMode: Text.Wrap; width: 50; horizontalAlignment: Text.AlignHCenter } }

    Shortcut { sequence: "Ctrl+S"; onActivated: saveProduct() }
}
