pragma Singleton
import QtQuick 6.5

// 组件注册表 - 定义所有可用的拖拽复合组件
QtObject {
    id: root

    // 组件分类
    readonly property var categories: [
        {
            id: "buttons",
            name: "Buttons",
            components: ["ButtonRed", "ButtonGreen", "ButtonOrange", "ButtonBlue", "ButtonBlack", "ButtonGrey"]
        },
        {
            id: "fnr",
            name: "FNR",
            components: ["FNRSwitch", "HorizontalFNR", "HorizontalFNRRight"]
        },
        {
            id: "rollers",
            name: "Rollers",
            components: ["VerticalRoller", "HorizontalRoller", "RotaryPotentiometer"]
        }
    ]

    // 组件定义 - 复合单元
    readonly property var componentDefinitions: ({
        "ButtonRed": {
            name: "Red",
            description: "红色工业按钮",
            defaultWidth: 56,
            defaultHeight: 88,
            thumbnailScale: 0.55,
            defaultConfig: {
                variant: "red",
                bezelSize: 56,
                capSize: 40,
                label: "BTN"
            },
            hasLabel: true
        },

        "ButtonGreen": {
            name: "Green",
            description: "绿色工业按钮",
            defaultWidth: 56,
            defaultHeight: 88,
            thumbnailScale: 0.55,
            defaultConfig: {
                variant: "green",
                bezelSize: 56,
                capSize: 40,
                label: "BTN"
            },
            hasLabel: true
        },

        "ButtonOrange": {
            name: "Orange",
            description: "橙色工业按钮",
            defaultWidth: 56,
            defaultHeight: 88,
            thumbnailScale: 0.55,
            defaultConfig: {
                variant: "orange",
                bezelSize: 56,
                capSize: 40,
                label: "BTN"
            },
            hasLabel: true
        },

        "ButtonBlue": {
            name: "Blue",
            description: "蓝色工业按钮",
            defaultWidth: 56,
            defaultHeight: 88,
            thumbnailScale: 0.55,
            defaultConfig: {
                variant: "blue",
                bezelSize: 56,
                capSize: 40,
                label: "BTN"
            },
            hasLabel: true
        },

        "ButtonBlack": {
            name: "Black",
            description: "黑色工业按钮",
            defaultWidth: 56,
            defaultHeight: 88,
            thumbnailScale: 0.55,
            defaultConfig: {
                variant: "black",
                bezelSize: 56,
                capSize: 40,
                label: "BTN"
            },
            hasLabel: true
        },

        "ButtonGrey": {
            name: "Grey",
            description: "灰色工业按钮",
            defaultWidth: 56,
            defaultHeight: 88,
            thumbnailScale: 0.55,
            defaultConfig: {
                variant: "grey",
                bezelSize: 56,
                capSize: 40,
                label: "BTN"
            },
            hasLabel: true
        },

        "FNRSwitch": {
            name: "FNR Switch",
            description: "FNR翘板开关 + 状态指示",
            defaultWidth: 86,
            defaultHeight: 196,
            thumbnailScale: 0.35,
            defaultConfig: {
                switchState: "N",
                label: "FNR"
            },
            hasLabel: true
        },

        "VerticalRoller": {
            name: "Vertical",
            description: "垂直滚轮 + 数字显示",
            defaultWidth: 90,
            defaultHeight: 240,
            thumbnailScale: 0.30,
            defaultConfig: {
                value: 0,
                label: ""
            },
            hasLabel: true
        },

        "HorizontalFNR": {
            name: "H-FNR (F←)",
            description: "水平FNR开关 F在左",
            defaultWidth: 196,
            defaultHeight: 130,
            thumbnailScale: 0.30,
            defaultConfig: {
                switchState: "N",
                label: "FNR"
            },
            hasLabel: true
        },

        "HorizontalFNRRight": {
            name: "H-FNR (→F)",
            description: "水平FNR开关 F在右",
            defaultWidth: 196,
            defaultHeight: 130,
            thumbnailScale: 0.30,
            defaultConfig: {
                switchState: "N",
                label: "FNR"
            },
            hasLabel: true
        },

        "HorizontalRoller": {
            name: "Horizontal",
            description: "水平滚轮 + 数字显示",
            defaultWidth: 200,
            defaultHeight: 108,
            thumbnailScale: 0.35,
            defaultConfig: {
                value: 0,
                label: ""
            },
            hasLabel: true
        },

        "RotaryPotentiometer": {
            name: "Rotary",
            description: "正视旋转电位计 + 数字显示",
            defaultWidth: 112,
            defaultHeight: 154,
            thumbnailScale: 0.42,
            defaultConfig: {
                value: 0,
                minValue: 0,
                maxValue: 360,
                minimumAngle: 0,
                maximumAngle: 360,
                displayUnit: "°",
                label: ""
            },
            hasLabel: true
        }
    })

    // 获取组件定义
    function getDefinition(componentType) {
        return componentDefinitions[componentType] || null
    }

    // 获取组件默认配置
    function getDefaultConfig(componentType) {
        var def = getDefinition(componentType)
        return def ? JSON.parse(JSON.stringify(def.defaultConfig)) : {}
    }

    // 获取组件默认尺寸
    function getDefaultSize(componentType) {
        var def = getDefinition(componentType)
        return def ? { width: def.defaultWidth, height: def.defaultHeight } : { width: 100, height: 100 }
    }

    // 获取所有组件类型列表
    function getAllComponentTypes() {
        return Object.keys(componentDefinitions)
    }

    // 获取分类下的组件列表
    function getComponentsInCategory(categoryId) {
        for (var i = 0; i < categories.length; i++) {
            if (categories[i].id === categoryId) {
                return categories[i].components
            }
        }
        return []
    }

    // 组件是否有可编辑标签
    function hasEditableLabel(componentType) {
        var def = getDefinition(componentType)
        return def ? (def.hasLabel || false) : false
    }

    // 创建组件拖拽数据
    function createDragData(componentType, config) {
        return JSON.stringify({
            type: "component",
            componentType: componentType,
            config: config || getDefaultConfig(componentType)
        })
    }
}
