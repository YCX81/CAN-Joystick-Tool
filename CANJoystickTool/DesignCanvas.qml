import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Effects
import CANJoystickTool

// 设计画布 - 480x480 AluminumPanel，自由拖放组件（无吸附）
AluminumPanel {
    id: root

    panelWidth: 480
    panelHeight: 480
    contentMargins: 0

    property int canvasWidth: 480
    property int canvasHeight: 480
    property string scaleMode: "uniform"

    // 组件列表
    property var components: []
    property var selectedComponents: []

    // 信号
    signal componentAdded(var component)
    signal componentRemoved(var component)
    signal selectionChanged(var selected)
    signal layoutModified()

    // 唯一ID
    property int nextComponentId: 1
    function generateId() {
        return "comp_" + (nextComponentId++)
    }

    // 组件容器 — 直接绑定 root 尺寸，确保不受 contentArea margins 影响
    Item {
        id: componentContainer
        width: root.width
        height: root.height
        z: 1
        clip: true
    }

    // 框选矩形
    Rectangle {
        id: selectionRect
        visible: false
        color: Qt.rgba(Constants.accentColor.r, Constants.accentColor.g, Constants.accentColor.b, 0.1)
        border.width: 1
        border.color: Constants.accentColor
        z: 99
    }

    // 主交互区域
    MouseArea {
        id: canvasMouseArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        z: -1

        property real selectionStartX: 0
        property real selectionStartY: 0
        property bool isSelecting: false

        onPressed: function(mouse) {
            if (mouse.button === Qt.LeftButton) {
                if (!(mouse.modifiers & Qt.ControlModifier)) {
                    clearSelection()
                }
                isSelecting = true
                selectionStartX = mouse.x
                selectionStartY = mouse.y
                selectionRect.x = mouse.x
                selectionRect.y = mouse.y
                selectionRect.width = 0
                selectionRect.height = 0
            }
            labelEditor.visible = false
        }

        onPositionChanged: function(mouse) {
            if (!isSelecting) return
            var x = Math.min(selectionStartX, mouse.x)
            var y = Math.min(selectionStartY, mouse.y)
            var w = Math.abs(mouse.x - selectionStartX)
            var h = Math.abs(mouse.y - selectionStartY)
            selectionRect.x = x
            selectionRect.y = y
            selectionRect.width = w
            selectionRect.height = h
            selectionRect.visible = w > 5 || h > 5
        }

        onReleased: function(mouse) {
            if (isSelecting && selectionRect.visible) {
                selectComponentsInRect(
                    selectionRect.x, selectionRect.y,
                    selectionRect.width, selectionRect.height
                )
            }
            isSelecting = false
            selectionRect.visible = false
        }
    }

    // ========== 右键上下文菜单 ==========
    Rectangle {
        id: contextMenu
        visible: false
        z: 200
        width: 180
        height: menuColumn.height + 12
        radius: 12
        color: "#f0f0f4"
        border.width: 1
        border.color: "#18000000"

        property var targetComponent: null

        Column {
            id: menuColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 6

            ContextMenuItem {
                text: "Edit Label"
                visible: contextMenu.targetComponent &&
                         ComponentRegistry.hasEditableLabel(contextMenu.targetComponent.componentType)
                height: visible ? 30 : 0
                onTriggered: {
                    contextMenu.visible = false
                    showLabelEditor(contextMenu.targetComponent)
                }
            }

            ContextMenuItem {
                text: contextMenu.targetComponent && contextMenu.targetComponent.bindingId
                      ? ("Binding: " + contextMenu.targetComponent.bindingId) : "Set Binding..."
                height: 30
                onTriggered: {
                    contextMenu.visible = false
                    showBindingEditor(contextMenu.targetComponent)
                }
            }

            Rectangle {
                width: parent.width - 12
                anchors.horizontalCenter: parent.horizontalCenter
                height: 1
                color: "#15000000"
            }

            ContextMenuItem {
                text: "Copy"
                shortcut: "Ctrl+C"
                onTriggered: { contextMenu.visible = false; copySelected() }
            }

            ContextMenuItem {
                text: "Delete"
                shortcut: "Del"
                isDestructive: true
                onTriggered: { contextMenu.visible = false; deleteSelected() }
            }

            Rectangle {
                width: parent.width - 12
                anchors.horizontalCenter: parent.horizontalCenter
                height: 1
                color: "#15000000"
            }

            ContextMenuItem {
                text: "Bring to Front"
                onTriggered: { contextMenu.visible = false; bringToFront(contextMenu.targetComponent) }
            }

            ContextMenuItem {
                text: "Send to Back"
                onTriggered: { contextMenu.visible = false; sendToBack(contextMenu.targetComponent) }
            }
        }
    }

    // 点击空白处关闭菜单 — 在菜单内部处理，不用 overlay
    Connections {
        target: canvasMouseArea
        function onPressed(mouse) {
            if (contextMenu.visible) contextMenu.visible = false
            if (bindingEditor.visible) bindingEditor.visible = false
        }
    }

    // 上下文菜单项
    component ContextMenuItem: Rectangle {
        id: menuItem
        property string text: ""
        property string shortcut: ""
        property bool isDestructive: false
        signal triggered()

        width: parent.width
        height: 30
        radius: 6
        color: menuItemMouse.containsMouse ? "#12000000" : "transparent"

        Text {
            text: menuItem.text
            color: menuItem.isDestructive ? Constants.errorColor :
                   (menuItemMouse.containsMouse ? "#2a2a2e" : "#505058")
            font.pixelSize: 12
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            visible: menuItem.shortcut !== ""
            text: menuItem.shortcut
            color: "#909098"
            font.pixelSize: 10
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
        }

        MouseArea {
            id: menuItemMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: menuItem.triggered()
        }
    }

    // ========== 标签编辑器 ==========
    Rectangle {
        id: labelEditor
        visible: false
        z: 201
        width: 160
        height: 42
        radius: 10
        color: "#f0f0f4"
        border.width: 1
        border.color: "#18000000"

        property var targetComponent: null

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#30000000"
            shadowBlur: 0.3
            shadowVerticalOffset: 4
        }

        // 凹陷输入框
        Rectangle {
            anchors.fill: parent
            anchors.margins: 5
            radius: 6
            color: Qt.darker(root.color, 1.05)

            // 内凹效果
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#15000000" }
                    GradientStop { position: 0.3; color: "transparent" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
        }

        TextField {
            id: labelField
            anchors.fill: parent
            anchors.margins: 5
            color: Constants.rollerIndicatorColor
            font.pixelSize: 13
            font.family: "Consolas"
            font.weight: Font.Bold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            selectByMouse: true
            placeholderText: "Label..."
            placeholderTextColor: "#a0a0a8"

            background: Rectangle {
                color: "transparent"
            }

            onAccepted: {
                if (labelEditor.targetComponent) {
                    labelEditor.targetComponent.setLabel(text)
                    root.layoutModified()
                }
                labelEditor.visible = false
            }

            Keys.onEscapePressed: {
                labelEditor.visible = false
            }
        }
    }

    // ========== 绑定编辑器 ==========
    Rectangle {
        id: bindingEditor
        visible: false; z: 202
        width: 200; radius: 10
        color: "#f0f0f4"; border.width: 1; border.color: "#18000000"
        height: bindingCol.height + 16

        property var targetComponent: null
        property var filteredBindings: []

        Column {
            id: bindingCol
            anchors.left: parent.left; anchors.right: parent.right
            anchors.top: parent.top; anchors.margins: 8
            spacing: 4

            Text { text: "设置数据绑定"; font.pixelSize: 11; font.bold: true; color: "#2a2a2e" }

            Text {
                text: "当前: " + (bindingEditor.targetComponent ? (bindingEditor.targetComponent.bindingId || "无") : "无")
                font.pixelSize: 9; color: "#76767e"
            }

            Rectangle { width: parent.width; height: 1; color: "#15000000" }

            // Clear binding
            Rectangle {
                width: parent.width; height: 26; radius: 4
                color: clearMA.containsMouse ? "#08000000" : "transparent"
                Text { anchors.centerIn: parent; text: "清除绑定"; font.pixelSize: 10; color: "#ff453a" }
                MouseArea { id: clearMA; anchors.fill: parent; hoverEnabled: true
                    onClicked: { if (bindingEditor.targetComponent) bindingEditor.targetComponent.bindingId = ""; bindingEditor.visible = false; layoutModified() }
                }
            }

            // Filtered binding options
            Repeater {
                model: bindingEditor.filteredBindings
                Rectangle {
                    width: bindingCol.width; height: 26; radius: 4
                    color: {
                        var isCurrent = bindingEditor.targetComponent && bindingEditor.targetComponent.bindingId === modelData.bindId
                        return isCurrent ? "#e8f0fe" : (bma.containsMouse ? "#08000000" : "transparent")
                    }
                    Row {
                        anchors.fill: parent; anchors.leftMargin: 8; spacing: 6
                        Rectangle { width: 6; height: 6; radius: 3; anchors.verticalCenter: parent.verticalCenter; color: modelData.color || "#007aff" }
                        Text { text: modelData.bindId; font.pixelSize: 9; font.bold: true; color: "#2a2a2e"; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: modelData.desc || ""; font.pixelSize: 8; color: "#76767e"; anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea { id: bma; anchors.fill: parent; hoverEnabled: true
                        onClicked: {
                            if (bindingEditor.targetComponent) bindingEditor.targetComponent.bindingId = modelData.bindId
                            bindingEditor.visible = false; layoutModified()
                        }
                    }
                }
            }

            // Hint when no options
            Text {
                visible: bindingEditor.filteredBindings.length === 0
                text: "无匹配的绑定项"; font.pixelSize: 9; color: "#a0a0a8"
            }
        }
    }

    // bindingEditor close is handled by canvasMouseArea Connections above

    // Available bindings (set from ProductEditor via property)
    property var productBindings: []

    // Detect component category
    function getBindCategory(wrapperType) {
        if (wrapperType.indexOf("Button") === 0) return "button"
        if (wrapperType === "VerticalRoller" || wrapperType === "HorizontalRoller") return "roller"
        if (wrapperType === "FNRSwitch" || wrapperType === "HorizontalFNR" || wrapperType === "HorizontalFNRRight") return "fnr"
        return "other"
    }

    // Build filtered bindings based on component type
    function getFilteredBindings(wrapperType) {
        var result = []
        var allComps = productBindings || []
        var cat = getBindCategory(wrapperType)

        for (var i = 0; i < allComps.length; i++) {
            var comp = allComps[i]

            if (cat === "button" && comp.type === "buttonGroup") {
                var count = comp.count || 8
                for (var b = 0; b < count; b++) {
                    result.push({ bindId: comp.id + "." + b, desc: "按钮" + (b+1), color: "#ff3b30" })
                }
            } else if (cat === "roller" && comp.type === "roller") {
                result.push({ bindId: comp.id, desc: comp.label || "轴", color: "#ff9500" })
            } else if (cat === "fnr" && comp.type === "fnrSwitch") {
                // FNR 直接绑定到 fnrSwitch 组件（按钮映射在 JSON 中定义）
                result.push({ bindId: comp.id, desc: comp.label || "FNR", color: "#af52de" })
            } else if (cat === "fnr" && comp.type === "indicator") {
                result.push({ bindId: comp.id, desc: comp.label || "指示器", color: "#5856d6" })
            }
        }

        // Fallback: show all non-joystick components
        if (result.length === 0) {
            for (var j = 0; j < allComps.length; j++) {
                var c = allComps[j]
                if (c.type === "joystick") continue
                result.push({ bindId: c.id, desc: c.label || c.type, color: "#007aff" })
            }
        }

        return result
    }

    function showBindingEditor(wrapper) {
        bindingEditor.targetComponent = wrapper
        bindingEditor.filteredBindings = getFilteredBindings(wrapper.componentType)
        var cx = wrapper.x + wrapper.width / 2
        var cy = wrapper.y + wrapper.height + 10
        if (cy + 200 > root.height) cy = wrapper.y - 200
        bindingEditor.x = Math.max(10, Math.min(cx - 90, root.width - 200))
        bindingEditor.y = Math.max(10, Math.min(cy, root.height - 100))
        bindingEditor.visible = true
    }

    // ========== 功能函数 ==========

    function addComponent(type, x, y, config) {
        var component = Qt.createComponent("DraggableWrapper.qml")
        if (component.status === Component.Ready) {
            var wrapper = component.createObject(componentContainer, {
                componentId: generateId(),
                componentType: type,
                componentConfig: config || {},
                x: x,
                y: y,
                canvas: root,
                isEditing: true
            })
            if (wrapper) {
                wrapper.loadComponent(type)
                setupWrapperConnections(wrapper)
                components.push(wrapper)
                componentAdded(wrapper)
                layoutModified()
                return wrapper
            }
        } else if (component.status === Component.Error) {
            console.error("Error creating component:", component.errorString())
        }
        return null
    }

    function setupWrapperConnections(wrapper) {
        wrapper.componentClicked.connect(function(mouse) {
            if (mouse.button === Qt.LeftButton) {
                wrapper.forceActiveFocus()
            }
        })

        wrapper.deleteRequested.connect(function() { removeComponent(wrapper) })
        wrapper.componentMoved.connect(function() { layoutModified() })
        wrapper.onSelectedChanged.connect(function() { updateSelectedComponents() })

        wrapper.contextMenuRequested.connect(function(mx, my) {
            showContextMenu(wrapper, mx, my)
        })

        wrapper.labelEditRequested.connect(function() {
            showLabelEditor(wrapper)
        })
    }

    function showContextMenu(wrapper, mx, my) {
        contextMenu.targetComponent = wrapper
        contextMenu.x = Math.min(mx, root.width - contextMenu.width - 8)
        contextMenu.y = Math.min(my, root.height - contextMenu.height - 8)
        contextMenu.visible = true
    }

    function showLabelEditor(wrapper) {
        labelEditor.targetComponent = wrapper
        labelField.text = wrapper.getLabel()
        var cx = wrapper.x + wrapper.width / 2
        var cy = wrapper.y - 50
        if (cy < 10) cy = wrapper.y + wrapper.height + 10
        labelEditor.x = Math.max(10, Math.min(cx - labelEditor.width / 2, root.width - labelEditor.width - 10))
        labelEditor.y = Math.max(10, Math.min(cy, root.height - labelEditor.height - 10))
        labelEditor.visible = true
        labelField.forceActiveFocus()
        labelField.selectAll()
    }

    function removeComponent(wrapper) {
        var idx = components.indexOf(wrapper)
        if (idx >= 0) {
            components.splice(idx, 1)
            componentRemoved(wrapper)
            wrapper.destroy()
            updateSelectedComponents()
            layoutModified()
        }
    }

    function copySelected() {
        for (var i = 0; i < selectedComponents.length; i++) {
            var comp = selectedComponents[i]
            addComponent(comp.componentType, comp.x + 20, comp.y + 20,
                         JSON.parse(JSON.stringify(comp.componentConfig)))
        }
    }

    function bringToFront(wrapper) {
        if (wrapper) wrapper.z = getMaxZ() + 1
    }

    function sendToBack(wrapper) {
        if (wrapper) wrapper.z = getMinZ() - 1
    }

    function getMaxZ() {
        var maxZ = 0
        for (var i = 0; i < components.length; i++)
            if (components[i].z > maxZ) maxZ = components[i].z
        return maxZ
    }

    function getMinZ() {
        var minZ = 0
        for (var i = 0; i < components.length; i++)
            if (components[i].z < minZ) minZ = components[i].z
        return minZ
    }

    function updateSelectedComponents() {
        selectedComponents = []
        for (var i = 0; i < components.length; i++) {
            if (components[i].selected)
                selectedComponents.push(components[i])
        }
        selectionChanged(selectedComponents)
    }

    function clearSelection() {
        for (var i = 0; i < components.length; i++)
            components[i].selected = false
        selectedComponents = []
        selectionChanged(selectedComponents)
    }

    function selectAll() {
        for (var i = 0; i < components.length; i++)
            components[i].selected = true
        updateSelectedComponents()
    }

    function selectComponentsInRect(rx, ry, rw, rh) {
        for (var i = 0; i < components.length; i++) {
            var comp = components[i]
            var intersects = !(comp.x > rx + rw || comp.x + comp.width < rx ||
                              comp.y > ry + rh || comp.y + comp.height < ry)
            if (intersects) comp.selected = true
        }
        updateSelectedComponents()
    }

    function deleteSelected() {
        var toDelete = selectedComponents.slice()
        for (var i = 0; i < toDelete.length; i++)
            removeComponent(toDelete[i])
    }

    function instantiateCardTemplate(template, dropX, dropY) {
        var instances = []
        var comps = template.components || []
        for (var i = 0; i < comps.length; i++) {
            var comp = comps[i]
            var wrapper = addComponent(
                comp.type, dropX + (comp.offsetX || 0),
                dropY + (comp.offsetY || 0), comp.config || {}
            )
            if (wrapper) instances.push(wrapper)
        }
        return instances
    }

    function saveSelectionAsCardTemplate(name, description) {
        if (selectedComponents.length === 0) return null
        var bounds = calculateBoundingBox(selectedComponents)
        var template = {
            version: "1.0", name: name || "Untitled Card",
            description: description || "", created: new Date().toISOString(),
            boundingBox: { width: bounds.width, height: bounds.height },
            components: []
        }
        for (var i = 0; i < selectedComponents.length; i++) {
            var comp = selectedComponents[i]
            template.components.push({
                type: comp.componentType,
                offsetX: comp.x - bounds.x,
                offsetY: comp.y - bounds.y,
                config: comp.componentConfig
            })
        }
        return template
    }

    function calculateBoundingBox(items) {
        if (items.length === 0) return { x: 0, y: 0, width: 0, height: 0 }
        var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
        for (var i = 0; i < items.length; i++) {
            var item = items[i]
            minX = Math.min(minX, item.x); minY = Math.min(minY, item.y)
            maxX = Math.max(maxX, item.x + item.width); maxY = Math.max(maxY, item.y + item.height)
        }
        return { x: minX, y: minY, width: maxX - minX, height: maxY - minY }
    }

    function toJSON() {
        var data = {
            version: "1.0",
            canvas: { width: canvasWidth, height: canvasHeight, scaleMode: scaleMode || "uniform" },
            components: []
        }
        for (var i = 0; i < components.length; i++)
            data.components.push(components[i].toJSON())
        return data
    }

    function applyCanvasMetadata(canvas) {
        canvasWidth = canvas && canvas.width ? canvas.width : panelWidth
        canvasHeight = canvas && canvas.height ? canvas.height : panelHeight
        scaleMode = canvas && canvas.scaleMode ? canvas.scaleMode : "uniform"
    }

    function fromJSON(data) {
        while (components.length > 0) removeComponent(components[0])
        applyCanvasMetadata(data.canvas)
        var comps = data.components || []
        for (var i = 0; i < comps.length; i++) {
            var compData = comps[i]
            var wrapper = addComponent(compData.type, compData.x, compData.y, compData.config)
            if (wrapper && compData.id) wrapper.componentId = compData.id
            if (wrapper && compData.bindingId) wrapper.bindingId = compData.bindingId
        }
        nextComponentId = components.length + 1
    }

    // Get all bindingIds used by components on this canvas
    function getUsedBindings() {
        var used = []
        for (var i = 0; i < components.length; i++) {
            var bid = components[i].bindingId
            if (bid && bid !== "") used.push(bid)
        }
        return used
    }

    function clear() {
        while (components.length > 0) removeComponent(components[0])
        nextComponentId = 1
    }

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
            selectAll(); event.accepted = true
        } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
            deleteSelected(); event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
            contextMenu.visible = false; labelEditor.visible = false
            clearSelection(); event.accepted = true
        } else if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
            copySelected(); event.accepted = true
        }
    }

    focus: true
}
