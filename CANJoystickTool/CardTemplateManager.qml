pragma Singleton
import QtQuick 6.5

// 卡片模板管理器 - 管理用户创建的组件组合模板
QtObject {
    id: root

    // 模板列表
    property var templates: []

    // 存储路径 (由LayoutManager设置)
    property string storagePath: ""

    // 信号
    signal templateAdded(var template)
    signal templateRemoved(int index)
    signal templatesLoaded()
    signal templatesSaved()

    // 添加模板
    function addTemplate(template) {
        // 确保有唯一ID
        if (!template.id) {
            template.id = generateTemplateId()
        }

        // 确保有创建时间
        if (!template.created) {
            template.created = new Date().toISOString()
        }

        templates.push(template)
        templateAdded(template)
        return template.id
    }

    // 移除模板
    function removeTemplate(templateId) {
        for (var i = 0; i < templates.length; i++) {
            if (templates[i].id === templateId) {
                templates.splice(i, 1)
                templateRemoved(i)
                return true
            }
        }
        return false
    }

    // 获取模板
    function getTemplate(templateId) {
        for (var i = 0; i < templates.length; i++) {
            if (templates[i].id === templateId) {
                return templates[i]
            }
        }
        return null
    }

    // 更新模板
    function updateTemplate(templateId, updates) {
        var template = getTemplate(templateId)
        if (template) {
            for (var key in updates) {
                template[key] = updates[key]
            }
            template.modified = new Date().toISOString()
            return true
        }
        return false
    }

    // 复制模板
    function duplicateTemplate(templateId) {
        var original = getTemplate(templateId)
        if (original) {
            var copy = JSON.parse(JSON.stringify(original))
            copy.id = generateTemplateId()
            copy.name = original.name + " (Copy)"
            copy.created = new Date().toISOString()
            delete copy.modified
            return addTemplate(copy)
        }
        return null
    }

    // 从选中组件创建模板
    function createFromSelection(name, description, selectedComponents) {
        if (!selectedComponents || selectedComponents.length === 0) {
            return null
        }

        // 计算边界框
        var bounds = calculateBoundingBox(selectedComponents)

        var template = {
            id: generateTemplateId(),
            version: "1.0",
            name: name || "Untitled Card",
            description: description || "",
            created: new Date().toISOString(),
            boundingBox: {
                width: bounds.width,
                height: bounds.height
            },
            components: []
        }

        // 记录组件相对位置
        for (var i = 0; i < selectedComponents.length; i++) {
            var comp = selectedComponents[i]
            template.components.push({
                type: comp.componentType,
                offsetX: comp.x - bounds.x,
                offsetY: comp.y - bounds.y,
                config: JSON.parse(JSON.stringify(comp.componentConfig || {}))
            })
        }

        addTemplate(template)
        return template
    }

    // 计算边界框
    function calculateBoundingBox(items) {
        if (items.length === 0) {
            return { x: 0, y: 0, width: 0, height: 0 }
        }

        var minX = Infinity, minY = Infinity
        var maxX = -Infinity, maxY = -Infinity

        for (var i = 0; i < items.length; i++) {
            var item = items[i]
            minX = Math.min(minX, item.x)
            minY = Math.min(minY, item.y)
            maxX = Math.max(maxX, item.x + item.width)
            maxY = Math.max(maxY, item.y + item.height)
        }

        return {
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        }
    }

    // 生成模板ID
    function generateTemplateId() {
        return "card_" + Date.now() + "_" + Math.random().toString(36).substr(2, 9)
    }

    // 序列化为JSON
    function toJSON() {
        return {
            version: "1.0",
            templates: templates
        }
    }

    // 从JSON恢复
    function fromJSON(data) {
        templates = []
        if (data && data.templates) {
            for (var i = 0; i < data.templates.length; i++) {
                templates.push(data.templates[i])
            }
        }
        templatesLoaded()
    }

    // 清空所有模板
    function clear() {
        templates = []
    }

    // 获取模板数量
    function count() {
        return templates.length
    }

    // 搜索模板
    function search(query) {
        if (!query) return templates

        var lowerQuery = query.toLowerCase()
        return templates.filter(function(t) {
            return t.name.toLowerCase().indexOf(lowerQuery) >= 0 ||
                   (t.description && t.description.toLowerCase().indexOf(lowerQuery) >= 0)
        })
    }

    // 按创建时间排序
    function sortByCreated(ascending) {
        templates.sort(function(a, b) {
            var dateA = new Date(a.created)
            var dateB = new Date(b.created)
            return ascending ? (dateA - dateB) : (dateB - dateA)
        })
    }

    // 按名称排序
    function sortByName(ascending) {
        templates.sort(function(a, b) {
            var nameA = a.name.toLowerCase()
            var nameB = b.name.toLowerCase()
            if (ascending) {
                return nameA < nameB ? -1 : (nameA > nameB ? 1 : 0)
            } else {
                return nameA > nameB ? -1 : (nameA < nameB ? 1 : 0)
            }
        })
    }

    // 导出单个模板
    function exportTemplate(templateId) {
        var template = getTemplate(templateId)
        if (template) {
            return JSON.stringify(template, null, 2)
        }
        return null
    }

    // 导入模板
    function importTemplate(jsonString) {
        try {
            var template = JSON.parse(jsonString)
            if (template.type && template.components) {
                // 这是旧格式，需要转换
                template.boundingBox = template.boundingBox || { width: 100, height: 100 }
            }
            // 分配新ID避免冲突
            template.id = generateTemplateId()
            template.created = new Date().toISOString()
            return addTemplate(template)
        } catch (e) {
            console.error("Failed to import template:", e)
            return null
        }
    }

    // 验证模板结构
    function validateTemplate(template) {
        if (!template) return false
        if (!template.name) return false
        if (!template.components || !Array.isArray(template.components)) return false
        if (template.components.length === 0) return false

        for (var i = 0; i < template.components.length; i++) {
            var comp = template.components[i]
            if (!comp.type) return false
        }

        return true
    }
}
