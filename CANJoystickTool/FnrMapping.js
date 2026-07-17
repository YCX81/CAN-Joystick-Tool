.pragma library

function parseLegacyBinding(bindingId) {
    var value = String(bindingId || "").trim()
    var match = /^(.+)\.fnr:(\d+)\s*,\s*(\d+)(?:\s*,\s*(\d+))?$/.exec(value)
    if (!match)
        return null

    if (match[4] !== undefined) {
        return {
            sourceId: match[1],
            forward: Number(match[2]),
            neutral: Number(match[3]),
            reverse: Number(match[4])
        }
    }
    return {
        sourceId: match[1],
        forward: Number(match[2]),
        reverse: Number(match[3])
    }
}

function buttonOptions(visibleButtonIndices, count, includeUnwired) {
    var indexes = []
    var supplied = visibleButtonIndices || []
    for (var i = 0; i < supplied.length; i++) {
        var index = Number(supplied[i])
        if (index >= 0 && indexes.indexOf(index) < 0)
            indexes.push(index)
    }
    if (indexes.length === 0) {
        for (var j = 0; j < Number(count || 0); j++)
            indexes.push(j)
    }
    indexes.sort(function(a, b) { return a - b })

    var result = []
    if (includeUnwired)
        result.push({ index: -1, number: 0, label: "未接线（F/R均松开为N）" })
    for (var k = 0; k < indexes.length; k++) {
        result.push({
            index: indexes[k],
            number: indexes[k] + 1,
            label: "按钮" + (indexes[k] + 1)
        })
    }
    return result
}

function validateSelection(forward, neutral, reverse) {
    if (!(forward >= 0))
        return "请选择F按钮。"
    if (!(reverse >= 0))
        return "请选择R按钮。"
    if (forward === reverse || (neutral >= 0 && (neutral === forward || neutral === reverse)))
        return "F、N、R不能绑定同一个按钮。"
    return ""
}

function buildButtonMapping(source, forward, neutral, reverse) {
    var result = {
        source: String(source || ""),
        forward: Number(forward),
        reverse: Number(reverse)
    }
    if (neutral >= 0)
        result.neutral = Number(neutral)
    return result
}
