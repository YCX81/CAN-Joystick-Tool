import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Effects
import CANJoystickTool

// 设计画布 - 尺寸由编辑器预设或 JSON 画布元数据控制，自由拖放组件（无吸附）
AluminumPanel {
    id: root

    panelWidth: Constants.homeCardDesignSize
    panelHeight: Constants.homeCardDesignSize
    contentMargins: 0

    property int canvasWidth: Constants.homeCardDesignSize
    property int canvasHeight: Constants.homeCardDesignSize
    property string scaleMode: "uniform"
    readonly property real canvasScale: canvasWidth > 0 && canvasHeight > 0
                                        ? Math.min(width / canvasWidth, height / canvasHeight)
                                        : 1

    // 组件列表
    property var components: []
    property var selectedComponents: []

    // 信号
    signal componentAdded(var component)
    signal componentRemoved(var component)
    signal selectionChanged(var selected)
    signal layoutModified()
    signal canvasPressed()

    // 唯一ID
    property int nextComponentId: 1
    function generateId() {
        return "comp_" + (nextComponentId++)
    }

    // 组件容器 — 直接绑定 root 尺寸，确保不受 contentArea margins 影响
    Item {
        id: componentContainer
        x: (root.width - width * scale) / 2
        y: (root.height - height * scale) / 2
        width: root.canvasWidth
        height: root.canvasHeight
        scale: root.canvasScale
        transformOrigin: Item.TopLeft
        z: 1
        clip: true
    }

    // 框选矩形
    Rectangle {
        id: selectionRect
        parent: componentContainer
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
        z: 0

        property real selectionStartX: 0
        property real selectionStartY: 0
        property bool isSelecting: false

        onPressed: function(mouse) {
            root.canvasPressed()
            if (mouse.button === Qt.LeftButton) {
                if (!(mouse.modifiers & Qt.ControlModifier)) {
                    clearSelection()
                }
                var pos = displayToCanvasPoint(mouse.x, mouse.y)
                isSelecting = true
                selectionStartX = pos.x
                selectionStartY = pos.y
                selectionRect.x = pos.x
                selectionRect.y = pos.y
                selectionRect.width = 0
                selectionRect.height = 0
            }
            labelEditor.closeLabelEditor(false)
        }

        onPositionChanged: function(mouse) {
            if (!isSelecting) return
            var pos = displayToCanvasPoint(mouse.x, mouse.y)
            var x = Math.min(selectionStartX, pos.x)
            var y = Math.min(selectionStartY, pos.y)
            var w = Math.abs(pos.x - selectionStartX)
            var h = Math.abs(pos.y - selectionStartY)
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
    Popup {
        id: contextMenu
        parent: Overlay.overlay ? Overlay.overlay : root
        width: 180
        height: menuColumn.implicitHeight + 12
        padding: 0
        modal: false
        dim: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        property var targetComponent: null

        background: Rectangle {
            radius: 12
            color: "#f0f0f4"
            border.width: 1
            border.color: "#18000000"
        }

        contentItem: Item {
            implicitWidth: contextMenu.width
            implicitHeight: menuColumn.height + 12

            Column {
                id: menuColumn
                x: 6
                y: 6
                width: parent.width - 12

                ContextMenuItem {
                    text: "Edit Label"
                    visible: contextMenu.targetComponent &&
                             ComponentRegistry.hasEditableLabel(contextMenu.targetComponent.componentType)
                    height: visible ? 30 : 0
                    onTriggered: {
                        contextMenu.close()
                        showLabelEditor(contextMenu.targetComponent)
                    }
                }

                ContextMenuItem {
                    text: contextMenu.targetComponent && contextMenu.targetComponent.bindingId
                          ? ("Binding: " + contextMenu.targetComponent.bindingId) : "Set Binding..."
                    height: 30
                    onTriggered: {
                        contextMenu.close()
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
                    onTriggered: { contextMenu.close(); copySelected() }
                }

                ContextMenuItem {
                    text: "Delete"
                    shortcut: "Del"
                    isDestructive: true
                    onTriggered: { contextMenu.close(); deleteSelected() }
                }

                Rectangle {
                    width: parent.width - 12
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: 1
                    color: "#15000000"
                }

                ContextMenuItem {
                    text: "Bring to Front"
                    onTriggered: { contextMenu.close(); bringToFront(contextMenu.targetComponent) }
                }

                ContextMenuItem {
                    text: "Send to Back"
                    onTriggered: { contextMenu.close(); sendToBack(contextMenu.targetComponent) }
                }
            }
        }
    }

    // 点击空白处关闭菜单
    Connections {
        target: canvasMouseArea
        function onPressed(mouse) {
            if (contextMenu.opened) contextMenu.close()
            if (bindingEditor.opened) bindingEditor.close()
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
        property string originalLabel: ""
        property bool shouldRestoreLabel: false

        function closeLabelEditor(commit) {
            if (commit && targetComponent) {
                targetComponent.setLabel(labelField.text)
                root.layoutModified()
                shouldRestoreLabel = false
            }
            visible = false
        }

        onVisibleChanged: {
            if (visible)
                return
            if (shouldRestoreLabel && targetComponent)
                targetComponent.setLabel(originalLabel)
            targetComponent = null
            originalLabel = ""
            shouldRestoreLabel = false
        }

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
                labelEditor.closeLabelEditor(true)
            }

            Keys.onEscapePressed: {
                labelEditor.closeLabelEditor(false)
            }
        }
    }

    // ========== 绑定编辑器 ==========
    Popup {
        id: bindingEditor
        parent: Overlay.overlay ? Overlay.overlay : root
        width: 220
        height: Math.min(bindingCol.implicitHeight + 16, maxPopupHeight)
        padding: 0
        modal: false
        dim: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        property var targetComponent: null
        property var filteredBindings: []
        readonly property real maxPopupHeight: Math.max(150, Math.min(360, popupHostHeight(bindingEditor) - 16))

        background: Rectangle {
            radius: 10
            color: "#f0f0f4"
            border.width: 1
            border.color: "#18000000"
        }

        contentItem: Flickable {
            id: bindingFlick
            implicitWidth: bindingEditor.width
            implicitHeight: bindingEditor.height
            contentWidth: width
            contentHeight: bindingCol.implicitHeight + 16
            boundsBehavior: Flickable.StopAtBounds
            clip: contentHeight > height

            ScrollBar.vertical: ScrollBar {
                policy: bindingFlick.contentHeight > bindingFlick.height
                        ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            }

            Column {
                id: bindingCol
                x: 8
                y: 8
                width: bindingFlick.width - 16
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
                        onClicked: {
                            if (bindingEditor.targetComponent)
                                bindingEditor.targetComponent.bindingId = ""
                            bindingEditor.close()
                            root.layoutModified()
                        }
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
                                if (bindingEditor.targetComponent)
                                    bindingEditor.targetComponent.bindingId = modelData.bindId
                                bindingEditor.close()
                                root.layoutModified()
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
    }

    // bindingEditor also closes through Popup.CloseOnPressOutside.

    // Available bindings (set from ProductEditor via property)
    property var productBindings: []

    // Detect component category
    function getBindCategory(wrapperType) {
        if (wrapperType.indexOf("Button") === 0) return "button"
        if (wrapperType === "VerticalRoller"
                || wrapperType === "HorizontalRoller"
                || wrapperType === "RotaryPotentiometer") return "roller"
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
            } else if (cat === "roller" && (comp.type === "roller"
                       || comp.type === "potentiometer")) {
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
                if (c.type === "joystick" || c.type === "buttonGroup") continue
                result.push({ bindId: c.id, desc: c.label || c.type, color: "#007aff" })
            }
        }

        return result
    }

    function popupHost(popup) {
        return popup.parent || root
    }

    function popupHostWidth(popup) {
        var host = popupHost(popup)
        return host && host.width > 0 ? host.width : root.width
    }

    function popupHostHeight(popup) {
        var host = popupHost(popup)
        return host && host.height > 0 ? host.height : root.height
    }

    function popupEffectiveHeight(popup, fallbackHeight) {
        if (popup.height > 0) return popup.height
        if (popup.implicitHeight > 0) return popup.implicitHeight
        return fallbackHeight || 0
    }

    function clampPopupToHost(popup, hostX, hostY, fallbackHeight) {
        var margin = 8
        var maxX = Math.max(margin, popupHostWidth(popup) - popup.width - margin)
        var maxY = Math.max(margin, popupHostHeight(popup) - popupEffectiveHeight(popup, fallbackHeight) - margin)
        popup.x = Math.max(margin, Math.min(hostX, maxX))
        popup.y = Math.max(margin, Math.min(hostY, maxY))
    }

    function placePopupFromRootPoint(popup, rootX, rootY, fallbackHeight) {
        var host = popupHost(popup)
        var pos = root.mapToItem(host, rootX, rootY)
        clampPopupToHost(popup, pos.x, pos.y, fallbackHeight)
    }

    function placeBindingEditorForWrapper(wrapper) {
        var host = popupHost(bindingEditor)
        var bottomPos = wrapper.mapToItem(host, wrapper.width / 2, wrapper.height)
        var topPos = wrapper.mapToItem(host, wrapper.width / 2, 0)
        var popupHeight = popupEffectiveHeight(bindingEditor, 220)
        var desiredX = bottomPos.x - bindingEditor.width / 2
        var desiredY = bottomPos.y + 10
        if (desiredY + popupHeight > popupHostHeight(bindingEditor) - 8)
            desiredY = topPos.y - popupHeight - 10
        clampPopupToHost(bindingEditor, desiredX, desiredY, 220)
    }

    function showBindingEditor(wrapper) {
        if (!wrapper) return
        bindingEditor.targetComponent = wrapper
        bindingEditor.filteredBindings = getFilteredBindings(wrapper.componentType)
        placeBindingEditorForWrapper(wrapper)
        bindingEditor.open()
        Qt.callLater(function() {
            if (bindingEditor.opened && bindingEditor.targetComponent === wrapper)
                placeBindingEditorForWrapper(wrapper)
        })
    }

    // ========== 功能函数 ==========

    function boundedCanvasWidth() {
        return canvasWidth
    }

    function boundedCanvasHeight() {
        return canvasHeight
    }

    function roundedCanvasRadius() {
        return Math.max(0, Math.min(borderRadius, boundedCanvasWidth() / 2, boundedCanvasHeight() / 2))
    }

    function clampRectToCanvas(x, y, width, height) {
        return {
            x: Math.max(0, Math.min(x || 0, Math.max(0, boundedCanvasWidth() - width))),
            y: Math.max(0, Math.min(y || 0, Math.max(0, boundedCanvasHeight() - height)))
        }
    }

    function pushPointInsideCorner(pointX, pointY, centerX, centerY, radius) {
        var dx = pointX - centerX
        var dy = pointY - centerY
        var dist = Math.sqrt(dx * dx + dy * dy)
        if (dist <= radius || dist <= 0)
            return { x: pointX, y: pointY, changed: false }
        var factor = radius / dist
        return {
            x: centerX + dx * factor,
            y: centerY + dy * factor,
            changed: true
        }
    }

    function clampComponentToCanvas(x, y, width, height) {
        var pos = clampRectToCanvas(x, y, width, height)
        var r = roundedCanvasRadius()
        if (r <= 0)
            return pos

        var cw = boundedCanvasWidth()
        var ch = boundedCanvasHeight()
        for (var i = 0; i < 4; i++) {
            pos = clampRectToCanvas(pos.x, pos.y, width, height)

            if (pos.x < r && pos.y < r) {
                var tl = pushPointInsideCorner(pos.x, pos.y, r, r, r)
                if (tl.changed) {
                    pos.x = Math.max(pos.x, tl.x)
                    pos.y = Math.max(pos.y, tl.y)
                }
            }

            if (pos.x + width > cw - r && pos.y < r) {
                var tr = pushPointInsideCorner(pos.x + width, pos.y, cw - r, r, r)
                if (tr.changed) {
                    pos.x = Math.min(pos.x, tr.x - width)
                    pos.y = Math.max(pos.y, tr.y)
                }
            }

            if (pos.x < r && pos.y + height > ch - r) {
                var bl = pushPointInsideCorner(pos.x, pos.y + height, r, ch - r, r)
                if (bl.changed) {
                    pos.x = Math.max(pos.x, bl.x)
                    pos.y = Math.min(pos.y, bl.y - height)
                }
            }

            if (pos.x + width > cw - r && pos.y + height > ch - r) {
                var br = pushPointInsideCorner(pos.x + width, pos.y + height, cw - r, ch - r, r)
                if (br.changed) {
                    pos.x = Math.min(pos.x, br.x - width)
                    pos.y = Math.min(pos.y, br.y - height)
                }
            }
        }

        return clampRectToCanvas(pos.x, pos.y, width, height)
    }

    function displayToCanvasPoint(x, y) {
        var scale = canvasScale > 0 ? canvasScale : 1
        return {
            x: (x - componentContainer.x) / scale,
            y: (y - componentContainer.y) / scale
        }
    }

    function clampedDropPosition(type, x, y) {
        var size = ComponentRegistry.getDefaultSize(type)
        return clampComponentToCanvas(x, y, size.width, size.height)
    }

    function addComponent(type, x, y, config) {
        var component = Qt.createComponent("DraggableWrapper.qml")
        if (component.status === Component.Ready) {
            var pos = clampedDropPosition(type, x, y)
            var wrapper = component.createObject(componentContainer, {
                componentId: generateId(),
                componentType: type,
                componentConfig: config || {},
                x: pos.x,
                y: pos.y,
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
        if (bindingEditor.opened) bindingEditor.close()
        placePopupFromRootPoint(contextMenu, mx, my, 180)
        contextMenu.open()
    }

    function showLabelEditor(wrapper) {
        if (labelEditor.visible)
            labelEditor.closeLabelEditor(false)
        labelEditor.targetComponent = wrapper
        labelEditor.originalLabel = wrapper.getLabel()
        labelEditor.shouldRestoreLabel = true
        labelField.text = labelEditor.originalLabel
        wrapper.setLabel("")
        var topPos = wrapper.mapToItem(root, wrapper.width / 2, 0)
        var bottomPos = wrapper.mapToItem(root, wrapper.width / 2, wrapper.height)
        var cx = topPos.x
        var cy = topPos.y - 50
        if (cy < 10) cy = bottomPos.y + 10
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
        canvasWidth = canvas && canvas.width ? canvas.width : Constants.homeCardDesignSize
        canvasHeight = canvas && canvas.height ? canvas.height : Constants.homeCardDesignSize
        scaleMode = canvas && canvas.scaleMode ? canvas.scaleMode : "uniform"
    }

    function fromJSON(data) {
        while (components.length > 0) removeComponent(components[0])
        data = data || {}
        var targetWidth = canvasWidth > 0 ? canvasWidth : Constants.homeCardDesignSize
        var targetHeight = canvasHeight > 0 ? canvasHeight : Constants.homeCardDesignSize
        var sourceWidth = data.canvas && data.canvas.width ? data.canvas.width : targetWidth
        var sourceHeight = data.canvas && data.canvas.height ? data.canvas.height : targetHeight
        var sx = sourceWidth > 0 ? targetWidth / sourceWidth : 1
        var sy = sourceHeight > 0 ? targetHeight / sourceHeight : 1
        canvasWidth = targetWidth
        canvasHeight = targetHeight
        scaleMode = data.canvas && data.canvas.scaleMode ? data.canvas.scaleMode : "uniform"
        var comps = data.components || []
        for (var i = 0; i < comps.length; i++) {
            var compData = comps[i]
            var wrapper = addComponent(compData.type, (compData.x || 0) * sx, (compData.y || 0) * sy, compData.config)
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
            contextMenu.close(); labelEditor.closeLabelEditor(false)
            clearSelection(); event.accepted = true
        } else if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
            copySelected(); event.accepted = true
        }
    }

    focus: true
}
