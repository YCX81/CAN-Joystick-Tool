.pragma library

function copyObject(source) {
    var result = {}
    source = source || {}
    for (var key in source)
        result[key] = source[key]
    return result
}

function buttonType(variant) {
    switch (String(variant || "red").toLowerCase()) {
    case "green": return "ButtonGreen"
    case "orange": return "ButtonOrange"
    case "blue": return "ButtonBlue"
    case "black": return "ButtonBlack"
    case "grey":
    case "gray": return "ButtonGrey"
    default: return "ButtonRed"
    }
}

function editorTypeForElement(element) {
    var renderer = String((element || {}).renderer || "")
    var properties = (element || {}).properties || {}
    switch (renderer) {
    case "button": return buttonType(properties.buttonVariant)
    case "roller":
        return properties.orientation === "horizontal"
                ? "HorizontalRoller" : "VerticalRoller"
    case "potentiometer": return "RotaryPotentiometer"
    case "fnr":
        return properties.orientation === "vertical"
                ? "FNRSwitch" : "HorizontalFNR"
    case "miniJoystick": return "MiniJoystick"
    default: return ""
    }
}

function visualFromElement(element) {
    var type = editorTypeForElement(element)
    if (!type)
        return null
    var properties = copyObject(element.properties)
    if (element.renderer === "button") {
        properties.variant = properties.buttonVariant || "red"
        delete properties.buttonVariant
    }
    properties._v3ElementId = element.id || ""
    properties._v3Renderer = element.renderer || ""
    properties._v3Width = Number(element.width || 0)
    properties._v3Height = Number(element.height || 0)
    return {
        type: type,
        x: Number(element.x || 0),
        y: Number(element.y || 0),
        config: properties,
        bindingId: element.controlId || ""
    }
}

function emptyCell(index) {
    return {
        row: Math.floor(index / 2),
        col: index % 2,
        title: "",
        cellType: "empty",
        components: []
    }
}

function cellsFromConfig(config) {
    config = config || {}
    if (Number(config.schemaVersion || 0) !== 3)
        return ((((config.layout || {}).grid || {}).cells) || [])

    var cells = [emptyCell(0), emptyCell(1), emptyCell(2), emptyCell(3)]
    var cards = ((config.layout || {}).cards) || []
    for (var i = 0; i < cards.length; ++i) {
        var card = cards[i] || {}
        if (card.kind === "leftRegion")
            continue
        var grid = card.grid || {}
        var index = Number(grid.row || 0) * 2 + Number(grid.column || 0)
        if (index < 0 || index >= cells.length)
            continue
        var cell = emptyCell(index)
        cell.title = card.title || ""
        cell._v3CardId = card.id || ("card" + index)
        cell._v3Grid = copyObject(grid)
        if (card.kind === "controls") {
            cell.cellType = "canvas"
            cell.canvas = copyObject(card.contentCanvas)
            cell.visualComponents = []
            var elements = card.elements || []
            for (var j = 0; j < elements.length; ++j) {
                var visual = visualFromElement(elements[j])
                if (visual) {
                    cell.visualComponents.push(visual)
                    cell.components.push(visual.bindingId)
                }
            }
        } else if (card.kind === "system") {
            cell.cellType = card.systemType || "empty"
            cell._v3SystemProperties = copyObject(card.properties)
        }
        cells[index] = cell
    }
    return cells
}

function rendererForVisual(visual) {
    var type = String((visual || {}).type || "")
    if (type.indexOf("Button") === 0) return "button"
    if (type === "VerticalRoller" || type === "HorizontalRoller") return "roller"
    if (type === "RotaryPotentiometer") return "potentiometer"
    if (type === "FNRSwitch" || type === "HorizontalFNR"
            || type === "HorizontalFNRRight") return "fnr"
    if (type === "MiniJoystick") return "miniJoystick"
    return ""
}

function cleanProperties(visual, renderer) {
    var properties = copyObject((visual || {}).config)
    delete properties._v3ElementId
    delete properties._v3Renderer
    delete properties._v3Width
    delete properties._v3Height
    if (renderer === "button") {
        properties.buttonVariant = properties.variant || "red"
        delete properties.variant
    } else if (renderer === "roller") {
        properties.orientation = visual.type === "HorizontalRoller"
                ? "horizontal" : "vertical"
    } else if (renderer === "fnr") {
        properties.orientation = visual.type === "FNRSwitch"
                ? "vertical" : "horizontal"
    }
    delete properties.value
    delete properties.switchState
    delete properties.xValue
    delete properties.yValue
    delete properties.minValue
    delete properties.maxValue
    delete properties.minimumAngle
    delete properties.maximumAngle
    delete properties.displayUnit
    return properties
}

function elementFromVisual(visual, cardId, index) {
    var renderer = rendererForVisual(visual)
    if (!renderer || !visual.bindingId)
        return null
    var config = visual.config || {}
    return {
        id: config._v3ElementId || (cardId + "Element" + index),
        controlId: visual.bindingId,
        renderer: renderer,
        x: Number(visual.x || 0),
        y: Number(visual.y || 0),
        width: Number(visual.width || config._v3Width || 1),
        height: Number(visual.height || config._v3Height || 1),
        properties: cleanProperties(visual, renderer)
    }
}

function gridForCell(cell, index) {
    var grid = copyObject((cell || {})._v3Grid)
    grid.row = Math.floor(index / 2)
    grid.column = index % 2
    grid.rowSpan = Number(grid.rowSpan || 1)
    grid.columnSpan = Number(grid.columnSpan || 1)
    return grid
}

function cardFromCell(cell, index) {
    cell = cell || emptyCell(index)
    var id = cell._v3CardId || ("cell" + Math.floor(index / 2) + "_" + (index % 2))
    var grid = gridForCell(cell, index)
    if (cell.cellType === "canvas") {
        var elements = []
        var visuals = cell.visualComponents || []
        for (var i = 0; i < visuals.length; ++i) {
            var element = elementFromVisual(visuals[i], id, i)
            if (element)
                elements.push(element)
        }
        return {
            id: id,
            kind: "controls",
            title: cell.title || (index < 2 ? "正面" : "背面"),
            grid: grid,
            contentCanvas: copyObject(cell.canvas),
            elements: elements
        }
    }
    if (cell.cellType === "busStats" || cell.cellType === "recordInfo") {
        var systemCard = {
            id: id,
            kind: "system",
            title: cell.title || (cell.cellType === "busStats" ? "总线统计" : "记录信息"),
            grid: grid,
            systemType: cell.cellType
        }
        var systemProperties = copyObject(cell._v3SystemProperties)
        if (Object.keys(systemProperties).length > 0)
            systemCard.properties = systemProperties
        return systemCard
    }
    return {
        id: id,
        kind: "empty",
        title: cell.title || "",
        grid: grid
    }
}

function applyCellsToConfig(config, cells) {
    if (!config || Number(config.schemaVersion || 0) !== 3)
        return config
    var layout = config.layout || {}
    var oldCards = layout.cards || []
    var cards = []
    var cardsByIndex = {}
    for (var i = 0; i < oldCards.length; ++i) {
        var oldCard = oldCards[i] || {}
        if (oldCard.kind === "leftRegion") {
            cards.push(oldCards[i])
            continue
        }
        var oldGrid = oldCard.grid || {}
        var oldIndex = Number(oldGrid.row || 0) * 2 + Number(oldGrid.column || 0)
        if (oldIndex >= 0 && oldIndex < cells.length)
            cardsByIndex[oldIndex] = oldCard
    }
    for (var j = 0; j < cells.length; ++j) {
        var previous = cardsByIndex[j]
        if (previous) {
            cells[j]._v3CardId = previous.id || cells[j]._v3CardId
            cells[j]._v3Grid = copyObject(previous.grid)
            cells[j]._v3SystemProperties = copyObject(previous.properties)
        }
        cards.push(cardFromCell(cells[j], j))
    }
    layout.cards = cards
    if (layout.grid)
        delete layout.grid.cells
    config.layout = layout
    return config
}
