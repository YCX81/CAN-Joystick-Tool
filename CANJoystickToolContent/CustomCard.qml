import QtQuick 6.5
import CANJoystickTool

// 自定义卡片 - 运行时渲染用户创建的布局
AluminumPanel {
    id: root

    // 布局配置
    property var layoutConfig: null
    property string layoutName: ""

    // 设计基线 (从布局配置中读取, 默认 480×480)
    readonly property int designPanelWidth: layoutConfig ? (layoutConfig.canvas.width || 480) : 480
    readonly property int designPanelHeight: layoutConfig ? (layoutConfig.canvas.height || 480) : 480
    readonly property real contentScale: Math.min(panelWidth / designPanelWidth, panelHeight / designPanelHeight)

    // 卡片尺寸默认与设计一致, 外部可任意指定; 内部组件随之等比缩放
    panelWidth: designPanelWidth
    panelHeight: designPanelHeight
    contentMargins: 0  // 与 DesignCanvas 一致, 组件坐标基于完整画布

    // 组件实例列表
    property var componentInstances: []

    // 信号 - 用于绑定数据
    signal componentValueChanged(string componentId, string propertyName, var value)

    // 组件容器 — 设计空间, 自动等比缩放到面板大小
    Item {
        id: componentArea
        width: root.designPanelWidth
        height: root.designPanelHeight
        anchors.centerIn: parent
        scale: root.contentScale
    }

    // 从布局配置加载
    function loadFromConfig(config) {
        // 清除现有组件
        clearComponents()

        if (!config || !config.components) return

        layoutConfig = config
        layoutName = config.name || ""

        // 创建组件
        for (var i = 0; i < config.components.length; i++) {
            var compData = config.components[i]
            createComponentInstance(compData)
        }
    }

    // 创建组件实例
    function createComponentInstance(compData) {
        var source = getComponentSource(compData.type)
        if (!source) {
            console.warn("Unknown component type:", compData.type)
            return null
        }

        var component = Qt.createComponent(source)
        if (component.status === Component.Ready) {
            var props = compData.config || {}
            props.x = compData.x || 0
            props.y = compData.y || 0

            var instance = component.createObject(componentArea, props)
            if (instance) {
                instance.componentId = compData.id || ""
                componentInstances.push(instance)

                // 连接信号
                connectComponentSignals(instance, compData)

                return instance
            }
        } else if (component.status === Component.Error) {
            console.error("Error creating component:", component.errorString())
        }

        return null
    }

    // 连接组件信号
    function connectComponentSignals(instance, compData) {
        var type = compData.type
        // 按钮变体统一处理
        if (type.indexOf("Button") === 0 || type === "IndustrialButton") {
            if (instance.clicked) {
                instance.clicked.connect(function() {
                    componentValueChanged(compData.id, "pressed", true)
                })
            }
            return
        }

        switch (type) {
            case "VerticalRoller":
            case "HorizontalRoller":
            case "RotaryPotentiometer":
            case "RollerWheel":
                if (instance.valueChanged) {
                    instance.valueChanged.connect(function() {
                        componentValueChanged(compData.id, "value", instance.value)
                    })
                }
                break

            case "FNRSwitch":
                if (instance.fnrChanged) {
                    instance.fnrChanged.connect(function(state) {
                        componentValueChanged(compData.id, "switchState", state)
                    })
                }
                break

            case "RockerSwitch":
                if (instance.stateChanged) {
                    instance.stateChanged.connect(function(state) {
                        componentValueChanged(compData.id, "switchState", state)
                    })
                }
                break

            case "JoystickPad":
                if (instance.moved) {
                    instance.moved.connect(function(x, y) {
                        componentValueChanged(compData.id, "xValue", x)
                        componentValueChanged(compData.id, "yValue", y)
                    })
                }
                break
        }
    }

    // 获取组件QML源
    function getComponentSource(type) {
        var prefix = "qrc:/qt/qml/CANJoystickTool/CANJoystickTool/"
        // 按钮变体 → IndustrialButton
        if (type.indexOf("Button") === 0) return prefix + "IndustrialButton.qml"
        // 复合单元
        if (type === "FNRSwitch") return prefix + "FNRSwitchUnit.qml"
        if (type === "VerticalRoller") return prefix + "VerticalRollerUnit.qml"
        if (type === "HorizontalRoller") return prefix + "HorizontalRollerUnit.qml"
        if (type === "RotaryPotentiometer") return prefix + "RotaryPotentiometerUnit.qml"
        // 基础组件 (向后兼容)
        var mapping = {
            "IndustrialButton": prefix + "IndustrialButton.qml",
            "RollerWheel": prefix + "RollerWheel.qml",
            "RotaryPotentiometer": prefix + "RotaryPotentiometer.qml",
            "JoystickPad": prefix + "JoystickPad.qml",
            "DigitalDisplay": prefix + "DigitalDisplay.qml",
            "StatusIndicator": prefix + "StatusIndicator.qml",
            "RockerSwitch": prefix + "RockerSwitch.qml",
            "AxisValueBar": prefix + "AxisValueBar.qml"
        }
        return mapping[type] || ""
    }

    // 清除所有组件
    function clearComponents() {
        for (var i = 0; i < componentInstances.length; i++) {
            if (componentInstances[i]) {
                componentInstances[i].destroy()
            }
        }
        componentInstances = []
    }

    // 通过ID获取组件
    function getComponent(componentId) {
        for (var i = 0; i < componentInstances.length; i++) {
            if (componentInstances[i].componentId === componentId) {
                return componentInstances[i]
            }
        }
        return null
    }

    // 设置组件属性
    function setComponentProperty(componentId, propertyName, value) {
        var comp = getComponent(componentId)
        if (comp && comp.hasOwnProperty(propertyName)) {
            comp[propertyName] = value
        }
    }

    // 获取组件属性
    function getComponentProperty(componentId, propertyName) {
        var comp = getComponent(componentId)
        if (comp && comp.hasOwnProperty(propertyName)) {
            return comp[propertyName]
        }
        return undefined
    }

    // 应用数据绑定 (用于卡片模板中的组件间绑定)
    function applyBindings(bindings) {
        if (!bindings) return

        for (var i = 0; i < bindings.length; i++) {
            var binding = bindings[i]
            applyBinding(binding)
        }
    }

    // 应用单个绑定
    function applyBinding(binding) {
        var sourceComp = getComponent(binding.sourceId)
        var targetComp = getComponent(binding.targetId)

        if (!sourceComp || !targetComp) return

        // 创建绑定
        var sourceProp = binding.sourceProperty
        var targetProp = binding.targetProperty
        var transform = binding.transform // 可选的转换函数，如 "value * 100"

        // 使用 Binding 对象创建绑定
        var bindingObj = Qt.createQmlObject(
            'import QtQuick 2.15; Binding { target: null; property: ""; value: 0 }',
            root
        )

        bindingObj.target = targetComp
        bindingObj.property = targetProp

        if (transform) {
            // 如果有转换，需要动态计算
            // 简单实现：假设 transform 是 "value * 100" 形式
            bindingObj.value = Qt.binding(function() {
                var value = sourceComp[sourceProp]
                // 安全地评估转换表达式
                try {
                    return eval(transform.replace("$0", "sourceComp").replace("value", String(value)))
                } catch (e) {
                    return value
                }
            })
        } else {
            bindingObj.value = Qt.binding(function() {
                return sourceComp[sourceProp]
            })
        }
    }

    Component.onDestruction: {
        clearComponents()
    }
}
