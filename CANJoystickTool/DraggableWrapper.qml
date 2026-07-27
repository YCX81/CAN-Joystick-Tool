import QtQuick 6.5
import QtQuick.Effects
import CANJoystickTool

// 可拖拽组件包装器 - 自由拖放、多选、右键菜单（无吸附）
Item {
    id: root

    property string componentId: ""
    property string componentType: ""
    property var componentConfig: ({})
    property Item wrappedComponent: null
    property string bindingId: ""  // Maps to product JSON components[].id
    property string xBindingId: "" // MiniJoystick X-axis component binding
    property string yBindingId: "" // MiniJoystick Y-axis component binding

    property bool selected: false
    property bool isEditing: true
    property bool isDragging: false

    property var canvas: null

    property color selectionColor: Constants.accentColor
    property int selectionBorderWidth: 2
    property int handleSize: 8

    signal componentClicked(var mouse)
    signal componentDoubleClicked(var mouse)
    signal rightClicked(var mouse)
    signal dragStarted()
    signal dragEnded()
    signal componentMoved(real newX, real newY)
    signal deleteRequested()
    signal labelEditRequested()
    signal contextMenuRequested(real mx, real my)

    width: resolvedComponentWidth()
    height: resolvedComponentHeight()

    // 拖拽偏移量（在父坐标系下）
    property real dragOffsetX: 0
    property real dragOffsetY: 0

    // 主交互区域 — z:10 确保在编辑模式下位于内部组件之上，阻止内部 MouseArea 抢夺事件
    MouseArea {
        id: dragArea
        anchors.fill: parent
        z: isEditing ? 10 : -1
        hoverEnabled: true
        cursorShape: isEditing ? (isDragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onPressed: function(mouse) {
            if (!isEditing) return

            if (mouse.button === Qt.RightButton) {
                if (!root.selected) {
                    if (canvas) canvas.clearSelection()
                    root.selected = true
                }
                root.rightClicked(mouse)
                if (canvas) {
                    var canvasPos = root.mapToItem(canvas, mouse.x, mouse.y)
                    root.contextMenuRequested(canvasPos.x, canvasPos.y)
                }
                return
            }

            if (mouse.button === Qt.LeftButton) {
                if (mouse.modifiers & Qt.ControlModifier) {
                    root.selected = !root.selected
                } else if (!root.selected) {
                    if (canvas) canvas.clearSelection()
                    root.selected = true
                }

                // 记录鼠标按下时在父坐标系中的偏移
                var parentPos = root.mapToItem(root.parent, mouse.x, mouse.y)
                dragOffsetX = parentPos.x - root.x
                dragOffsetY = parentPos.y - root.y
                isDragging = true
                dragStarted()
            }

            root.componentClicked(mouse)
        }

        onPositionChanged: function(mouse) {
            if (!isDragging || !isEditing) return

            // 始终在父坐标系中计算位置，避免坐标反馈循环
            var parentPos = root.mapToItem(root.parent, mouse.x, mouse.y)
            var newX = parentPos.x - dragOffsetX
            var newY = parentPos.y - dragOffsetY

            var clamped = clampToDragBounds(newX, newY)

            root.x = clamped.x
            root.y = clamped.y
            componentMoved(root.x, root.y)
        }

        onReleased: function(mouse) {
            if (!isDragging) return
            isDragging = false
            dragEnded()
        }

        onDoubleClicked: function(mouse) {
            if (mouse.button === Qt.LeftButton) {
                if (ComponentRegistry.hasEditableLabel(root.componentType)) {
                    root.labelEditRequested()
                }
            }
            root.componentDoubleClicked(mouse)
        }
    }

    // 键盘快捷键
    Keys.onPressed: function(event) {
        if (!isEditing || !selected) return

        if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
            deleteRequested()
            event.accepted = true
        }

        var step = event.modifiers & Qt.ShiftModifier ? 10 : 1

        var newX = root.x
        var newY = root.y

        if (event.key === Qt.Key_Left) {
            newX -= step; event.accepted = true
        } else if (event.key === Qt.Key_Right) {
            newX += step; event.accepted = true
        } else if (event.key === Qt.Key_Up) {
            newY -= step; event.accepted = true
        } else if (event.key === Qt.Key_Down) {
            newY += step; event.accepted = true
        }

        if (event.accepted) {
            var clamped = clampToDragBounds(newX, newY)
            root.x = clamped.x
            root.y = clamped.y
            componentMoved(root.x, root.y)
        }
    }

    focus: selected
    activeFocusOnTab: isEditing

    opacity: isDragging ? 0.85 : 1.0
    Behavior on opacity { NumberAnimation { duration: 100 } }

    // 组件加载器
    Loader {
        id: componentLoader
        onLoaded: {
            root.wrappedComponent = item
            applyConfig()
        }
    }

    function loadComponent(type) {
        componentType = type
        var source = getComponentSource(type)
        if (source) componentLoader.source = source
    }

    function getComponentSource(type) {
        if (type.indexOf("Button") === 0) return "IndustrialButton.qml"
        if (type === "FNRSwitch") return "FNRSwitchUnit.qml"
        if (type === "HorizontalFNR") return "HorizontalFNRUnit.qml"
        if (type === "HorizontalFNRRight") return "HorizontalFNRRightUnit.qml"
        if (type === "VerticalRoller") return "VerticalRollerUnit.qml"
        if (type === "HorizontalRoller") return "HorizontalRollerUnit.qml"
        if (type === "RotaryPotentiometer") return "RotaryPotentiometerUnit.qml"
        if (type === "MiniJoystick") return "MiniJoystickUnit.qml"
        var mapping = {
            "IndustrialButton": "IndustrialButton.qml",
            "RollerWheel": "RollerWheel.qml",
            "RotaryPotentiometer": "RotaryPotentiometer.qml",
            "JoystickPad": "JoystickPad.qml",
            "DigitalDisplay": "DigitalDisplay.qml",
            "StatusIndicator": "StatusIndicator.qml",
            "RockerSwitch": "RockerSwitch.qml",
            "AxisValueBar": "AxisValueBar.qml"
        }
        return mapping[type] || ""
    }

    function hasPositiveSize(value) {
        return value !== undefined && value !== null && value > 0
    }

    function registryDefaultSize() {
        return ComponentRegistry.getDefaultSize(componentType)
    }

    function mergedDefaultConfig() {
        var merged = ComponentRegistry.getDefaultConfig(componentType)
        var current = componentConfig || {}
        for (var key in current)
            merged[key] = current[key]
        return merged
    }

    function resolveSize(explicitSize, implicitSize, defaultSize) {
        if (hasPositiveSize(explicitSize))
            return explicitSize
        if (hasPositiveSize(implicitSize))
            return implicitSize
        return defaultSize
    }

    function resolvedComponentWidth() {
        var item = componentLoader.item
        var defaultSize = registryDefaultSize()
        return item ? resolveSize(item.width, item.implicitWidth, defaultSize.width) : defaultSize.width
    }

    function resolvedComponentHeight() {
        var item = componentLoader.item
        var defaultSize = registryDefaultSize()
        return item ? resolveSize(item.height, item.implicitHeight, defaultSize.height) : defaultSize.height
    }

    function dragBoundWidth() {
        var item = root.parent || canvas
        return item && item.width > 0 ? item.width : 9999
    }

    function dragBoundHeight() {
        var item = root.parent || canvas
        return item && item.height > 0 ? item.height : 9999
    }

    function clampToDragBounds(x, y) {
        if (canvas && canvas.clampComponentToCanvas)
            return canvas.clampComponentToCanvas(x, y, root.width, root.height)

        var maxX = Math.max(0, dragBoundWidth() - root.width)
        var maxY = Math.max(0, dragBoundHeight() - root.height)
        return {
            x: Math.max(0, Math.min(x, maxX)),
            y: Math.max(0, Math.min(y, maxY))
        }
    }

    function ensureWrappedComponentSize() {
        if (!wrappedComponent)
            return

        var defaultSize = registryDefaultSize()
        wrappedComponent.width = defaultSize.width
        wrappedComponent.height = defaultSize.height
        root.width = defaultSize.width
        root.height = defaultSize.height
    }

    function applyConfig() {
        if (!wrappedComponent) return
        componentConfig = mergedDefaultConfig()
        for (var key in componentConfig) {
            if (wrappedComponent.hasOwnProperty(key))
                wrappedComponent[key] = componentConfig[key]
        }
        ensureWrappedComponentSize()
    }

    function updateConfig(newConfig) {
        for (var key in newConfig)
            componentConfig[key] = newConfig[key]
        applyConfig()
    }

    function getLabel() {
        if (wrappedComponent && wrappedComponent.hasOwnProperty("label"))
            return wrappedComponent.label
        return componentConfig.label || ""
    }

    function setLabel(newLabel) {
        componentConfig.label = newLabel
        if (wrappedComponent && wrappedComponent.hasOwnProperty("label"))
            wrappedComponent.label = newLabel
    }

    function getBounds() {
        return {
            x: root.x, y: root.y,
            width: root.width, height: root.height,
            centerX: root.x + root.width / 2,
            centerY: root.y + root.height / 2,
            right: root.x + root.width,
            bottom: root.y + root.height
        }
    }

    function toJSON() {
        return {
            id: componentId,
            type: componentType,
            x: root.x,
            y: root.y,
            config: componentConfig,
            bindingId: bindingId,
            xBindingId: xBindingId,
            yBindingId: yBindingId
        }
    }

    function fromJSON(data) {
        componentId = data.id || ""
        componentType = data.type || ""
        root.x = data.x || 0
        root.y = data.y || 0
        componentConfig = data.config || {}
        bindingId = data.bindingId || ""
        xBindingId = data.xBindingId || ""
        yBindingId = data.yBindingId || ""
        if (componentType) loadComponent(componentType)
    }
}
