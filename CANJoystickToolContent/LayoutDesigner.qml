import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Effects
import CANJoystickTool

// 布局设计器 - Light Neumorphism 风格
Item {
    id: root

    property string layoutName: "Untitled"
    property bool hasUnsavedChanges: false

    signal exitRequested()

    property var layoutManager: typeof LayoutManager !== 'undefined' ? LayoutManager : null

    // ========== Neumorphism 配色 (浅色) ==========
    readonly property color neuBg: "#e0e0e5"
    readonly property color neuLightShadow: "#ffffff"
    readonly property color neuDarkShadow: "#bebec3"
    readonly property color neuSurface: "#e4e4e9"
    readonly property color neuTextPrimary: "#2a2a2e"
    readonly property color neuTextSecondary: "#76767e"
    readonly property color neuAccent: Constants.accentColor

    Component.onCompleted: {
        loadCardTemplates()
    }

    // ========== 背景 ==========
    Rectangle {
        anchors.fill: parent
        color: neuBg
    }

    // ========== 中心画布区域 ==========
    Item {
        id: canvasArea
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: componentPanel.left
        anchors.rightMargin: 0

        DesignCanvas {
            id: canvas
            anchors.centerIn: parent


            onSelectionChanged: function(selected) {
                // 无属性面板
            }

            onLayoutModified: {
                root.hasUnsavedChanges = true
            }
        }
    }

    // ========== 右侧组件面板 ==========
    ComponentPanel {
        id: componentPanel
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        panelWidth: 210
        neuBg: root.neuBg
        neuLightShadow: root.neuLightShadow
        neuDarkShadow: root.neuDarkShadow
        neuSurface: root.neuSurface
        neuTextPrimary: root.neuTextPrimary
        neuTextSecondary: root.neuTextSecondary
        neuAccent: root.neuAccent

        onComponentRequested: function(componentType) {
            var def = ComponentRegistry.getDefinition(componentType)
            var config = def ? ComponentRegistry.getDefaultConfig(componentType) : {}
            var areaW = canvas.panelWidth - 32
            var areaH = canvas.panelHeight - 32
            var cx = areaW / 2 - (def ? def.defaultWidth / 2 : 50)
            var cy = areaH / 2 - (def ? def.defaultHeight / 2 : 50)
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
            // 判断是否落在画布上
            var canvasPos = canvas.mapFromGlobal(globalX, globalY)
            if (canvasPos.x >= 0 && canvasPos.x <= canvas.width &&
                canvasPos.y >= 0 && canvasPos.y <= canvas.height) {
                var def = ComponentRegistry.getDefinition(dragProxy.componentType)
                var config = def ? ComponentRegistry.getDefaultConfig(dragProxy.componentType) : {}
                var compW = def ? def.defaultWidth : 100
                var compH = def ? def.defaultHeight : 100
                canvas.addComponent(dragProxy.componentType,
                                    canvasPos.x - compW / 2,
                                    canvasPos.y - compH / 2, config)
            }
        }
    }

    // ========== 拖拽代理 — 加载实际组件缩略图 ==========
    Item {
        id: dragProxy
        visible: false
        z: 9999
        opacity: 0.85

        property string componentType: ""
        property real thumbScale: 0.55

        // 尺寸跟随缩略图
        width: dragThumbLoader.item ? dragThumbLoader.item.width * thumbScale + 12 : 60
        height: dragThumbLoader.item ? dragThumbLoader.item.height * thumbScale + 12 : 60

        // 背景 + 阴影
        Rectangle {
            anchors.fill: parent
            radius: 10
            color: Qt.rgba(neuBg.r, neuBg.g, neuBg.b, 0.8)
            border.width: 1.5
            border.color: neuAccent

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#40000000"
                shadowBlur: 0.5
                shadowVerticalOffset: 6
            }
        }

        // 组件缩略图
        Item {
            anchors.centerIn: parent
            width: dragThumbLoader.item ? dragThumbLoader.item.width : 0
            height: dragThumbLoader.item ? dragThumbLoader.item.height : 0
            scale: dragProxy.thumbScale
            enabled: false  // 禁止所有内部鼠标交互

            Loader {
                id: dragThumbLoader
                active: dragProxy.visible
                sourceComponent: {
                    var t = dragProxy.componentType
                    if (t.indexOf("Button") === 0) return thumbButtonComp
                    if (t === "FNRSwitch") return thumbFNRComp
                    if (t === "VerticalRoller") return thumbVRollerComp
                    if (t === "HorizontalRoller") return thumbHRollerComp
                    return null
                }
                onLoaded: applyDragThumbConfig(item, dragProxy.componentType)
            }
        }
    }

    // 缩略图组件模板
    Component { id: thumbButtonComp; IndustrialButton {} }
    Component { id: thumbFNRComp; FNRSwitchUnit {} }
    Component { id: thumbVRollerComp; VerticalRollerUnit {} }
    Component { id: thumbHRollerComp; HorizontalRollerUnit {} }

    function applyDragThumbConfig(item, type) {
        if (!item) return
        if (type.indexOf("Button") === 0 && item.hasOwnProperty("variant")) {
            item.variant = type.replace("Button", "").toLowerCase()
        }
    }

    // ========== 角落按钮 ==========

    // 左上 - 返回按钮
    NeuButton {
        id: backBtn
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 24
        iconText: "←"
        labelText: "Back"
        neuBg: root.neuBg
        neuLight: root.neuLightShadow
        neuDark: root.neuDarkShadow

        onClicked: root.exitRequested()
    }

    // 右上 - 保存为卡片
    NeuButton {
        id: saveCardBtn
        anchors.right: componentPanel.left
        anchors.top: parent.top
        anchors.topMargin: 24
        anchors.rightMargin: 24
        iconText: "💾"
        labelText: "Save Card"
        isAccent: true
        enabled: canvas.selectedComponents.length > 0
        neuBg: root.neuBg
        neuLight: root.neuLightShadow
        neuDark: root.neuDarkShadow

        onClicked: saveAsCardDialog.open()
    }

    // 右下 - 组件计数
    NeuInfoBadge {
        anchors.right: componentPanel.left
        anchors.bottom: parent.bottom
        anchors.margins: 24
        neuBg: root.neuBg
        text1: canvas.components.length + " components"
        text2: canvas.selectedComponents.length > 0
               ? canvas.selectedComponents.length + " selected" : ""
        accentColor: neuAccent
    }

    // ========== Neumorphic 按钮组件 ==========
    component NeuButton: Item {
        id: neuBtn
        property string iconText: ""
        property string labelText: ""
        property bool isAccent: false
        property bool enabled: true
        property color neuBg: "#e0e0e5"
        property color neuLight: "#ffffff"
        property color neuDark: "#bebec3"

        signal clicked()

        width: btnContent.width + 28
        height: 40
        opacity: enabled ? 1.0 : 0.35

        // 亮阴影 (左上)
        Rectangle {
            visible: !btnMouse.pressed
            anchors.fill: btnMain
            anchors.margins: -1
            anchors.leftMargin: -6
            anchors.topMargin: -6
            anchors.rightMargin: 6
            anchors.bottomMargin: 6
            radius: btnMain.radius + 2
            color: neuBtn.neuLight
            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 0.6
                blurMax: 14
            }
        }

        // 暗阴影 (右下)
        Rectangle {
            visible: !btnMouse.pressed
            anchors.fill: btnMain
            anchors.margins: -1
            anchors.leftMargin: 6
            anchors.topMargin: 6
            anchors.rightMargin: -6
            anchors.bottomMargin: -6
            radius: btnMain.radius + 2
            color: neuBtn.neuDark
            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 0.6
                blurMax: 14
            }
        }

        // 主体
        Rectangle {
            id: btnMain
            anchors.fill: parent
            radius: 12
            color: neuBtn.neuBg

            // 按下时内阴影 - 顶部暗
            Rectangle {
                visible: btnMouse.pressed
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#40000000" }
                    GradientStop { position: 0.4; color: "transparent" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // 按下时内阴影 - 底部亮
            Rectangle {
                visible: btnMouse.pressed
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.6; color: "transparent" }
                    GradientStop { position: 1.0; color: "#15FFFFFF" }
                }
            }

            // 未按下时微妙顶部高光
            Rectangle {
                visible: !btnMouse.pressed
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#30FFFFFF" }
                    GradientStop { position: 0.3; color: "transparent" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
        }

        Row {
            id: btnContent
            anchors.centerIn: parent
            spacing: 6

            Text {
                text: neuBtn.iconText
                color: neuBtn.isAccent ? neuAccent : neuTextPrimary
                font.pixelSize: 14
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: neuBtn.labelText
                color: neuBtn.isAccent ? neuAccent : neuTextPrimary
                font.pixelSize: 12
                font.weight: Font.Medium
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            id: btnMouse
            anchors.fill: parent
            enabled: neuBtn.enabled
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: neuBtn.clicked()
        }
    }

    // ========== Neumorphic 信息徽章 ==========
    component NeuInfoBadge: Item {
        property color neuBg: "#e0e0e5"
        property string text1: ""
        property string text2: ""
        property color accentColor: "#00e0ff"

        width: badgeRow.width + 24
        height: 32

        // 凹陷效果
        Rectangle {
            anchors.fill: parent
            radius: 10
            color: Qt.darker(neuBg, 1.15)

            // 内凹顶部暗阴影
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#30000000" }
                    GradientStop { position: 0.35; color: "transparent" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // 内凹底部亮光
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.7; color: "transparent" }
                    GradientStop { position: 1.0; color: "#20FFFFFF" }
                }
            }
        }

        Row {
            id: badgeRow
            anchors.centerIn: parent
            spacing: 12

            Text {
                text: text1
                color: neuTextSecondary
                font.pixelSize: 10
                font.family: "Consolas"
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                visible: text2 !== ""
                text: text2
                color: accentColor
                font.pixelSize: 10
                font.weight: Font.Medium
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // ========== 快捷键 ==========
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
            saveLayout()
            event.accepted = true
        }
    }

    focus: true

    // ========== 对话框 ==========

    Dialog {
        id: saveAsCardDialog
        title: "Save as Card Template"
        standardButtons: Dialog.Ok | Dialog.Cancel
        modal: true
        anchors.centerIn: parent
        width: 400

        ColumnLayout {
            anchors.fill: parent
            spacing: 16

            Text {
                text: "Save " + canvas.selectedComponents.length + " selected components as a reusable card template."
                color: Constants.textSecondary
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: "Card Name:"
                    color: Constants.textPrimary
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }

                TextField {
                    id: cardNameField
                    Layout.fillWidth: true
                    placeholderText: "Enter card name..."
                    font.pixelSize: 12
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: "Description (optional):"
                    color: Constants.textPrimary
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }

                TextArea {
                    id: cardDescField
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    placeholderText: "Enter description..."
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
        title: "Select Layout File"
        nameFilters: ["JSON files (*.json)", "All files (*)"]
        fileMode: FileDialog.OpenFile
        onAccepted: loadLayoutFromFile(selectedFile)
    }

    FileDialog {
        id: saveFileDialog
        title: "Save Layout"
        nameFilters: ["JSON files (*.json)"]
        fileMode: FileDialog.SaveFile
        defaultSuffix: "json"
        onAccepted: saveLayoutToFile(selectedFile)
    }

    // ========== 功能函数 ==========

    function newLayout() {
        canvas.clear()
        layoutName = "Untitled"
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
                canvas.fromJSON(layoutData)
                layoutName = layoutData.name || "Untitled"
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
}
