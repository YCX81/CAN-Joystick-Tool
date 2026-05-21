import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Effects
import CANJoystickTool

// DownloadTool-style component layout designer.
Item {
    id: root

    property string layoutName: "Untitled"
    property bool hasUnsavedChanges: false
    property int selectedCount: canvas.selectedComponents.length
    property string canvasPreset: "square"
    property int canvasDesignWidth: Constants.homeCardDesignSize
    property int canvasDesignHeight: Constants.homeCardDesignSize

    signal exitRequested()

    property var layoutManager: typeof LayoutManager !== 'undefined' ? LayoutManager : null

    readonly property color surfaceBg: Constants.bgPrimary
    readonly property color panelBg: Constants.bgCard
    readonly property color fieldBg: Constants.bgInput
    readonly property color lineColor: Constants.border
    readonly property color mutedColor: Constants.textMuted
    readonly property color accentColor: Constants.accent
    readonly property color hardwareAccent: Constants.accentColor

    Component.onCompleted: loadCardTemplates()

    Rectangle {
        anchors.fill: parent
        color: root.surfaceBg
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        Rectangle {
            Layout.fillWidth: true
            height: 48
            radius: 8
            color: root.panelBg
            border.width: 1
            border.color: root.lineColor

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                CompactAction {
                    label: "返回"
                    onClicked: root.exitRequested()
                }

                Rectangle {
                    width: 1
                    height: 22
                    color: root.lineColor
                }

                ColumnLayout {
                    spacing: 0
                    Layout.minimumWidth: 180

                    Label {
                        text: "组件库设计器"
                        color: Constants.textPrimary
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Label {
                        text: layoutName + (hasUnsavedChanges ? " *" : "")
                        color: root.mutedColor
                        font.pixelSize: 10
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                StatusPill {
                    label: canvas.components.length + " 组件"
                    dotColor: canvas.components.length > 0 ? Constants.success : root.mutedColor
                }

                StatusPill {
                    label: selectedCount > 0 ? selectedCount + " 已选择" : "未选择"
                    dotColor: selectedCount > 0 ? root.accentColor : root.mutedColor
                }

                Item { Layout.fillWidth: true }

                CompactAction {
                    label: "新建"
                    onClicked: newLayout()
                }

                CompactAction {
                    label: "打开"
                    onClicked: fileDialog.open()
                }

                CompactAction {
                    label: "保存"
                    emphasized: hasUnsavedChanges
                    onClicked: saveLayout()
                }

                CompactAction {
                    label: "保存为卡片"
                    actionEnabled: selectedCount > 0
                    emphasized: selectedCount > 0
                    onClicked: saveAsCardDialog.open()
                }

                Rectangle {
                    width: 1
                    height: 22
                    color: root.lineColor
                }

                CompactAction {
                    label: "首页比例 " + Constants.homeCardDesignSize + "x" + Constants.homeCardDesignSize
                    emphasized: canvasPreset === "square"
                    onClicked: setCanvasPreset("square")
                }

                CompactAction {
                    label: "重置方形"
                    emphasized: false
                    onClicked: setCanvasPreset("square")
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 248
                Layout.fillHeight: true
                radius: 8
                color: root.panelBg
                border.width: 1
                border.color: root.lineColor
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    PanelHeader {
                        title: "组件库"
                        subtitle: "拖放到中间画布"
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: root.lineColor
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ComponentPanel {
                            id: componentPanel
                            anchors.fill: parent
                            panelWidth: parent.width
                            neuBg: root.panelBg
                            neuLightShadow: "#ffffff"
                            neuDarkShadow: root.lineColor
                            neuSurface: root.panelBg
                            neuTextPrimary: Constants.textPrimary
                            neuTextSecondary: Constants.textSecondary
                            neuAccent: root.accentColor

                            onComponentRequested: function(componentType) {
                                var config = ComponentRegistry.getDefaultConfig(componentType)
                                var size = ComponentRegistry.getDefaultSize(componentType)
                                var cx = canvas.canvasWidth / 2 - size.width / 2
                                var cy = canvas.canvasHeight / 2 - size.height / 2
                                canvas.addComponent(componentType, cx, cy, config)
                            }

                            onComponentDragStarted: function(componentType, globalX, globalY) {
                                dragProxy.componentType = componentType
                                dragProxy.visible = true
                                var lp = root.mapFromGlobal(globalX, globalY)
                                dragProxy.x = lp.x - dragProxy.width / 2
                                dragProxy.y = lp.y - dragProxy.height / 2
                            }

                            onComponentDragMoved: function(globalX, globalY) {
                                var lp = root.mapFromGlobal(globalX, globalY)
                                dragProxy.x = lp.x - dragProxy.width / 2
                                dragProxy.y = lp.y - dragProxy.height / 2
                            }

                            onComponentDragEnded: function(globalX, globalY) {
                                dragProxy.visible = false
                                var displayPos = canvas.mapFromGlobal(globalX, globalY)
                                if (displayPos.x >= 0 && displayPos.x <= canvas.width &&
                                    displayPos.y >= 0 && displayPos.y <= canvas.height) {
                                    var canvasPos = canvas.displayToCanvasPoint(displayPos.x, displayPos.y)
                                    var config = ComponentRegistry.getDefaultConfig(dragProxy.componentType)
                                    var size = ComponentRegistry.getDefaultSize(dragProxy.componentType)
                                    canvas.addComponent(dragProxy.componentType,
                                                        canvasPos.x - size.width / 2,
                                                        canvasPos.y - size.height / 2,
                                                        config)
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 8
                color: root.panelBg
                border.width: 1
                border.color: root.lineColor
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        height: 26
                        spacing: 8

                        Label {
                            text: "布局画布"
                            color: Constants.textPrimary
                            font.pixelSize: 12
                            font.bold: true
                        }

                        Label {
                            text: canvas.canvasWidth + " x " + canvas.canvasHeight
                            color: Constants.textSecondary
                            font.pixelSize: 10
                            font.family: "Consolas"
                        }

                        Item { Layout.fillWidth: true }

                        Label {
                            text: hasUnsavedChanges ? "有未保存修改" : "已同步"
                            color: hasUnsavedChanges ? Constants.warning : Constants.success
                            font.pixelSize: 10
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 8
                        color: root.fieldBg
                        border.width: 1
                        border.color: root.lineColor

                        Item {
                            id: canvasArea
                            anchors.fill: parent
                            anchors.margins: 16

                            DesignCanvas {
                                id: canvas
                                anchors.centerIn: parent
                                panelWidth: root.canvasDesignWidth
                                panelHeight: root.canvasDesignHeight
                                canvasWidth: root.canvasDesignWidth
                                canvasHeight: root.canvasDesignHeight

                                onSelectionChanged: function(selected) {
                                    selectedCount = selected.length
                                }

                                onLayoutModified: {
                                    root.hasUnsavedChanges = true
                                    selectedCount = canvas.selectedComponents.length
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: 260
                Layout.fillHeight: true
                radius: 8
                color: root.panelBg
                border.width: 1
                border.color: root.lineColor
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    PanelHeader {
                        title: "检查器"
                        subtitle: selectedCount > 0 ? "当前选择" : "布局摘要"
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: root.lineColor
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.margins: 12
                        spacing: 10

                        InfoRow {
                            name: "布局名称"
                            value: root.layoutName
                        }

                        InfoRow {
                            name: "组件数量"
                            value: canvas.components.length.toString()
                        }

                        InfoRow {
                            name: "已选择"
                            value: selectedCount.toString()
                        }

                        InfoRow {
                            name: "画布尺寸"
                            value: canvas.canvasWidth + " x " + canvas.canvasHeight
                        }

                        InfoRow {
                            name: "目标比例"
                            value: "首页方形卡片"
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: root.lineColor
                        }

                        Label {
                            text: selectedCount > 0 ? "可用操作" : "组件库说明"
                            color: Constants.textPrimary
                            font.pixelSize: 11
                            font.bold: true
                        }

                        Label {
                            Layout.fillWidth: true
                            text: selectedCount > 0
                                  ? "右键组件可编辑标签、设置绑定、复制、删除或调整层级。保存为卡片会把当前选择写入模板库。"
                                  : "默认画布使用 DownloadTool 卡片 body 比例。左侧组件库先产出稳定 JSON 和视觉组件，后续 CAN 数据运行态可直接消费这些绑定。"
                            color: Constants.textSecondary
                            font.pixelSize: 10
                            wrapMode: Text.WordWrap
                            lineHeight: 1.35
                        }

                        CompactAction {
                            Layout.fillWidth: true
                            label: "保存所选为卡片"
                            actionEnabled: selectedCount > 0
                            emphasized: selectedCount > 0
                            onClicked: saveAsCardDialog.open()
                        }

                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 34
            radius: 6
            color: root.panelBg
            border.width: 1
            border.color: root.lineColor

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 18

                StatusPill {
                    label: "组件库"
                    dotColor: root.accentColor
                }

                Label {
                    text: "Ctrl+S 保存  |  Delete 删除  |  Ctrl+A 全选  |  右键打开组件菜单"
                    color: Constants.textSecondary
                    font.pixelSize: 10
                }

                Item { Layout.fillWidth: true }

                Label {
                    text: layoutManager ? "模板路径已连接" : "文件服务不可用"
                    color: layoutManager ? Constants.success : Constants.error
                    font.pixelSize: 10
                }
            }
        }
    }

    Item {
        id: dragProxy
        visible: false
        z: 9999
        opacity: 0.88

        property string componentType: ""
        property real thumbScale: 0.55

        width: dragThumbLoader.item ? dragThumbLoader.item.width * thumbScale + 12 : 60
        height: dragThumbLoader.item ? dragThumbLoader.item.height * thumbScale + 12 : 60

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: "#f8f8fa"
            border.width: 1
            border.color: root.accentColor

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
            width: dragThumbLoader.item ? dragThumbLoader.item.width : 0
            height: dragThumbLoader.item ? dragThumbLoader.item.height : 0
            scale: dragProxy.thumbScale
            enabled: false

            Loader {
                id: dragThumbLoader
                active: dragProxy.visible
                sourceComponent: {
                    var t = dragProxy.componentType
                    if (t.indexOf("Button") === 0) return thumbButtonComp
                    if (t === "FNRSwitch") return thumbFNRComp
                    if (t === "VerticalRoller") return thumbVRollerComp
                    if (t === "HorizontalRoller") return thumbHRollerComp
                    if (t === "HorizontalFNR") return thumbHFNRComp
                    if (t === "HorizontalFNRRight") return thumbHFNRRightComp
                    return null
                }
                onLoaded: applyDragThumbConfig(item, dragProxy.componentType)
            }
        }
    }

    Component { id: thumbButtonComp; IndustrialButton {} }
    Component { id: thumbFNRComp; FNRSwitchUnit {} }
    Component { id: thumbVRollerComp; VerticalRollerUnit {} }
    Component { id: thumbHRollerComp; HorizontalRollerUnit {} }
    Component { id: thumbHFNRComp; HorizontalFNRUnit {} }
    Component { id: thumbHFNRRightComp; HorizontalFNRRightUnit {} }

    component CompactAction: Item {
        id: action

        property string label: ""
        property bool emphasized: false
        property bool actionEnabled: true

        signal clicked()

        Layout.preferredHeight: 30
        implicitWidth: Math.max(72, actionText.implicitWidth + 24)
        implicitHeight: 30
        opacity: actionEnabled ? 1.0 : 0.45

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: !action.actionEnabled ? root.fieldBg :
                   actionMouse.pressed ? Qt.darker(action.emphasized ? root.accentColor : root.fieldBg, 1.08) :
                   actionMouse.containsMouse ? (action.emphasized ? Qt.lighter(root.accentColor, 1.08) : "#fafafa") :
                   action.emphasized ? root.accentColor : root.fieldBg
            border.width: action.emphasized ? 0 : 1
            border.color: root.lineColor
        }

        Text {
            id: actionText
            anchors.centerIn: parent
            text: action.label
            color: action.emphasized ? "white" : Constants.textPrimary
            font.pixelSize: 11
            font.bold: action.emphasized
        }

        MouseArea {
            id: actionMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: action.actionEnabled
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: action.clicked()
        }
    }

    component PanelHeader: Item {
        property string title: ""
        property string subtitle: ""

        Layout.fillWidth: true
        height: 52

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 2

            Text {
                text: title
                color: Constants.textPrimary
                font.pixelSize: 12
                font.bold: true
            }

            Text {
                text: subtitle
                color: Constants.textSecondary
                font.pixelSize: 10
                elide: Text.ElideRight
                width: parent.width
            }
        }
    }

    component StatusPill: Row {
        property string label: ""
        property color dotColor: Constants.textMuted

        spacing: 5
        Layout.alignment: Qt.AlignVCenter

        Rectangle {
            width: 8
            height: 8
            radius: 4
            color: dotColor
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: label
            color: Constants.textSecondary
            font.pixelSize: 10
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    component InfoRow: RowLayout {
        property string name: ""
        property string value: ""

        Layout.fillWidth: true
        spacing: 8

        Text {
            text: name
            color: Constants.textSecondary
            font.pixelSize: 10
            Layout.preferredWidth: 72
        }

        Text {
            text: value
            color: Constants.textPrimary
            font.pixelSize: 10
            font.family: "Consolas"
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
    }

    function applyDragThumbConfig(item, type) {
        if (!item) return
        var defaultConfig = ComponentRegistry.getDefaultConfig(type)
        for (var key in defaultConfig) {
            if (item.hasOwnProperty(key)) {
                item[key] = defaultConfig[key]
            }
        }

        var defaultSize = ComponentRegistry.getDefaultSize(type)
        if (defaultSize.width > 0) item.width = defaultSize.width
        if (defaultSize.height > 0) item.height = defaultSize.height
    }

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
            saveLayout()
            event.accepted = true
        }
    }

    focus: true

    Dialog {
        id: saveAsCardDialog
        title: "保存为卡片模板"
        standardButtons: Dialog.Ok | Dialog.Cancel
        modal: true
        anchors.centerIn: parent
        width: 400

        ColumnLayout {
            anchors.fill: parent
            spacing: 16

            Text {
                text: "将 " + canvas.selectedComponents.length + " 个已选择组件保存为可复用卡片模板。"
                color: Constants.textSecondary
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: "卡片名称"
                    color: Constants.textPrimary
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }

                TextField {
                    id: cardNameField
                    Layout.fillWidth: true
                    placeholderText: "输入卡片名称..."
                    font.pixelSize: 12
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: "说明"
                    color: Constants.textPrimary
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }

                TextArea {
                    id: cardDescField
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    placeholderText: "可选说明..."
                    font.pixelSize: 11
                    wrapMode: TextArea.Wrap
                }
            }
        }

        onAccepted: {
            if (cardNameField.text.trim()) {
                saveSelectionAsCard(cardNameField.text.trim(), cardDescField.text.trim())
                cardNameField.text = ""
                cardDescField.text = ""
            }
        }

        onOpened: {
            cardNameField.text = ""
            cardDescField.text = ""
            cardNameField.forceActiveFocus()
        }
    }

    FileDialog {
        id: fileDialog
        title: "选择布局文件"
        nameFilters: ["JSON files (*.json)", "All files (*)"]
        fileMode: FileDialog.OpenFile
        onAccepted: loadLayoutFromFile(selectedFile)
    }

    FileDialog {
        id: saveFileDialog
        title: "保存布局"
        nameFilters: ["JSON files (*.json)"]
        fileMode: FileDialog.SaveFile
        defaultSuffix: "json"
        onAccepted: saveLayoutToFile(selectedFile)
    }

    function newLayout() {
        canvas.clear()
        layoutName = "Untitled"
        selectedCount = 0
        setCanvasPreset("square", false)
        hasUnsavedChanges = false
    }

    function saveLayout() {
        var layoutData = canvas.toJSON()
        layoutData.name = layoutName

        if (layoutManager) {
            if (layoutManager.currentLayoutPath) {
                layoutManager.saveLayout(layoutData)
                hasUnsavedChanges = false
            } else {
                saveFileDialog.open()
            }
        } else {
            saveFileDialog.open()
        }
    }

    function saveLayoutToFile(filePath) {
        var layoutData = canvas.toJSON()
        layoutData.name = layoutName

        if (layoutManager) {
            var path = layoutManager.fromFileUrl(filePath)
            if (layoutManager.saveLayout(layoutData, path)) {
                hasUnsavedChanges = false
                var parts = path.split("/")
                layoutName = parts[parts.length - 1].replace(".json", "")
            }
        }
    }

    function loadLayoutFromFile(filePath) {
        if (layoutManager) {
            var path = typeof filePath === 'string' ? filePath : layoutManager.fromFileUrl(filePath)
            var layoutData = layoutManager.loadLayout(path)
            if (layoutData && Object.keys(layoutData).length > 0) {
                applyCanvasSizeFromData(layoutData.canvas)
                canvas.fromJSON(layoutData)
                layoutName = layoutData.name || "Untitled"
                selectedCount = 0
                hasUnsavedChanges = false
            }
        }
    }

    function saveSelectionAsCard(name, description) {
        var template = CardTemplateManager.createFromSelection(
            name, description, canvas.selectedComponents
        )
        if (template) {
            saveCardTemplates()
        }
    }

    function loadCardTemplates() {
        if (layoutManager) {
            var templates = layoutManager.loadCardTemplates()
            var templateList = []
            for (var i = 0; i < templates.length; i++) {
                templateList.push(templates[i])
            }
            CardTemplateManager.fromJSON({ templates: templateList })
        }
    }

    function saveCardTemplates() {
        if (layoutManager) {
            var data = CardTemplateManager.toJSON()
            layoutManager.saveCardTemplates(data.templates)
        }
    }

    function setCanvasPreset(preset, markModified) {
        setCanvasSize(Constants.homeCardDesignSize,
                      Constants.homeCardDesignSize,
                      "square", markModified)
    }

    function setCanvasSize(width, height, preset, markModified) {
        canvasPreset = preset || "custom"
        canvasDesignWidth = width
        canvasDesignHeight = height
        canvas.panelWidth = width
        canvas.panelHeight = height
        canvas.canvasWidth = width
        canvas.canvasHeight = height
        if (markModified !== false)
            hasUnsavedChanges = true
    }

    function applyCanvasSizeFromData(canvasData) {
        setCanvasPreset("square", false)
    }
}
