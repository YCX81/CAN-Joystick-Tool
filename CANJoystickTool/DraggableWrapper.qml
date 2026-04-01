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

    width: componentLoader.item ? componentLoader.item.width : 100
    height: componentLoader.item ? componentLoader.item.height : 100

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

            // 限制在画布边界内
            var boundW = canvas ? canvas.width : (root.parent ? root.parent.width : 9999)
            var boundH = canvas ? canvas.height : (root.parent ? root.parent.height : 9999)
            newX = Math.max(0, Math.min(newX, boundW - root.width))
            newY = Math.max(0, Math.min(newY, boundH - root.height))

            root.x = newX
            root.y = newY
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

        if (event.key === Qt.Key_Left) {
            root.x -= step; event.accepted = true
        } else if (event.key === Qt.Key_Right) {
            root.x += step; event.accepted = true
        } else if (event.key === Qt.Key_Up) {
            root.y -= step; event.accepted = true
        } else if (event.key === Qt.Key_Down) {
            root.y += step; event.accepted = true
        }

        if (event.accepted) componentMoved(root.x, root.y)
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
        if (type === "VerticalRoller") return "VerticalRollerUnit.qml"
        if (type === "HorizontalRoller") return "HorizontalRollerUnit.qml"
        var mapping = {
            "IndustrialButton": "IndustrialButton.qml",
            "RollerWheel": "RollerWheel.qml",
            "JoystickPad": "JoystickPad.qml",
            "DigitalDisplay": "DigitalDisplay.qml",
            "StatusIndicator": "StatusIndicator.qml",
            "RockerSwitch": "RockerSwitch.qml",
            "AxisValueBar": "AxisValueBar.qml"
        }
        return mapping[type] || ""
    }

    function applyConfig() {
        if (!wrappedComponent) return
        for (var key in componentConfig) {
            if (wrappedComponent.hasOwnProperty(key))
                wrappedComponent[key] = componentConfig[key]
        }
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
        return { id: componentId, type: componentType, x: root.x, y: root.y, config: componentConfig, bindingId: bindingId }
    }

    function fromJSON(data) {
        componentId = data.id || ""
        componentType = data.type || ""
        root.x = data.x || 0
        root.y = data.y || 0
        componentConfig = data.config || {}
        bindingId = data.bindingId || ""
        if (componentType) loadComponent(componentType)
    }
}
