.pragma library

function copyObject(source) {
    var result = {}
    source = source || {}
    for (var key in source)
        result[key] = source[key]
    return result
}

function bindingChannelById(config, channelId) {
    var channels = (config || {}).bindingChannels || []
    for (var i = 0; i < channels.length; ++i) {
        if (String((channels[i] || {}).id || "") === String(channelId || ""))
            return channels[i]
    }
    return null
}

function editorBindingFromChannel(channel) {
    channel = channel || {}
    var kind = String(channel.kind || "")
    var role = String(channel.role || "")
    if (kind === "button") {
        return {
            id: String(channel.id || ""),
            type: "button",
            label: channel.label || String(channel.id || "")
        }
    }
    if (kind === "axis"
            && (role === "roller" || role === "potentiometer"
                || role === "auxiliary")) {
        return {
            id: String(channel.id || ""),
            type: role === "auxiliary" ? "roller" : role,
            label: channel.label || String(channel.id || "")
        }
    }
    return null
}

function ensureBindingChannels(config) {
    config = config || {}
    var existing = config.bindingChannels || []
    if (config.bindingChannels !== undefined
            && config.bindingChannels !== null
            && existing.length > 0)
        return existing

    var channels = []
    var seen = {}
    var buttonKeys = {}
    var axisSignalIds = {}

    function nextChannelId(prefix) {
        var serial = 1
        var candidate = prefix + serial
        while (seen[candidate])
            candidate = prefix + (++serial)
        return candidate
    }

    function uniqueChannelId(preferredId, prefix) {
        var preferred = String(preferredId || "")
        if (preferred && !seen[preferred])
            return preferred
        return nextChannelId(prefix)
    }

    function appendChannel(channel) {
        var id = String((channel || {}).id || "")
        if (!id || seen[id])
            return null
        seen[id] = true
        channels.push(channel)
        if (channel.kind === "button") {
            buttonKeys[String(channel.signalId || "")
                       + ":" + Number(channel.position)] = channel
        } else if (channel.kind === "axis") {
            var axisSignalId = String((channel.axis || {}).signalId || "")
            if (axisSignalId)
                axisSignalIds[axisSignalId] = channel
        }
        return channel
    }

    function appendButtonChannel(signalId, position, preferredId, label) {
        signalId = String(signalId || "")
        position = Number(position)
        if (!signalId || !isFinite(position) || position < 0)
            return null
        var key = signalId + ":" + position
        if (buttonKeys[key])
            return buttonKeys[key]
        var id = uniqueChannelId(
                    preferredId || ("button" + (position + 1)), "button")
        return appendChannel({
            id: id,
            kind: "button",
            label: label || ("按钮 " + (position + 1)),
            signalId: signalId,
            position: position
        })
    }

    function appendAxisChannel(axis, preferredId, label, role,
                               inputMode, topology, sourceControl) {
        axis = axis || {}
        var signalId = String(axis.signalId || "")
        if (!signalId)
            return null
        if (axisSignalIds[signalId])
            return axisSignalIds[signalId]
        var resolvedRole = role || "roller"
        var id = uniqueChannelId(preferredId, "roller")
        var channel = {
            id: id,
            kind: "axis",
            role: resolvedRole,
            inputMode: inputMode || "centered",
            label: label || id.replace(/^roller/i, "滚轮"),
            topology: topology && topology.kind
                    ? copyObject(topology)
                    : { kind: "singleAxis", orientation: "vertical" },
            axis: copyObject(axis)
        }
        sourceControl = sourceControl || {}
        if (sourceControl.zeroAsNeutral !== undefined)
            channel.zeroAsNeutral = sourceControl.zeroAsNeutral
        if (sourceControl.display !== undefined)
            channel.display = copyObject(sourceControl.display)
        return appendChannel(channel)
    }

    var controls = config.controls || []
    for (var i = 0; i < controls.length; ++i) {
        var control = controls[i] || {}
        var type = String(control.type || "")
        var role = String(control.role || "")
        if (type === "button") {
            appendButtonChannel(control.signalId,
                                control.position,
                                control.id,
                                control.label || String(control.id || ""))
        } else if (type === "axis"
                   && (role === "roller" || role === "potentiometer"
                       || role === "auxiliary")) {
            appendAxisChannel(control.axis,
                              control.id,
                              control.label || String(control.id || ""),
                              role,
                              control.inputMode,
                              control.topology,
                              control)
        }
    }

    for (var j = 0; j < controls.length; ++j) {
        var fnr = controls[j] || {}
        if (fnr.type !== "fnr")
            continue
        var fnrPositions = fnr.positions || {}
        appendButtonChannel(fnr.signalId,
                            fnrPositions.forward,
                            "button" + (Number(fnrPositions.forward) + 1),
                            "按钮 " + (Number(fnrPositions.forward) + 1))
        if (fnrPositions.neutralMode === "signal") {
            appendButtonChannel(fnr.signalId,
                                fnrPositions.neutral,
                                "button" + (Number(fnrPositions.neutral) + 1),
                                "按钮 " + (Number(fnrPositions.neutral) + 1))
        }
        appendButtonChannel(fnr.signalId,
                            fnrPositions.reverse,
                            "button" + (Number(fnrPositions.reverse) + 1),
                            "按钮 " + (Number(fnrPositions.reverse) + 1))
    }

    for (var k = 0; k < controls.length; ++k) {
        var joystick = controls[k] || {}
        var joystickId = String(joystick.id || "")
        if (joystick.type !== "joystick"
                || joystickId.indexOf("miniJoystick_") !== 0)
            continue
        appendAxisChannel(joystick.xAxis,
                          "",
                          "",
                          "roller",
                          "centered",
                          { kind: "singleAxis", orientation: "vertical" },
                          {})
        appendAxisChannel(joystick.yAxis,
                          "",
                          "",
                          "roller",
                          "centered",
                          { kind: "singleAxis", orientation: "vertical" },
                          {})
    }
    config.bindingChannels = channels
    return channels
}

function bindingsFromConfig(config) {
    config = config || {}
    if (Number(config.schemaVersion || 0) !== 3)
        return config.components || []

    var bindings = []
    var channels = ensureBindingChannels(config)
    if (channels.length > 0) {
        for (var channelIndex = 0; channelIndex < channels.length; ++channelIndex) {
            var channelBinding = editorBindingFromChannel(channels[channelIndex])
            if (channelBinding)
                bindings.push(channelBinding)
        }
    }
    var controls = config.controls || []
    for (var i = 0; i < controls.length; ++i) {
        var control = controls[i] || {}
        var type = String(control.type || "")
        var role = String(control.role || "")
        var bindingType = ""

        if (channels.length > 0
                && bindingChannelById(config, control.id)
                && (type === "button"
                    || (type === "axis"
                        && (role === "roller" || role === "potentiometer"
                            || role === "auxiliary")))) {
            continue
        } else if (type === "button") {
            bindingType = "button"
        } else if (type === "axis" && (role === "roller" || role === "potentiometer")) {
            bindingType = role
        } else if (type === "fnr") {
            bindingType = "fnrSwitch"
        } else if (type === "indicator") {
            bindingType = "indicator"
        }

        if (bindingType && control.id) {
            bindings.push({
                id: String(control.id),
                type: bindingType,
                label: control.label || String(control.id)
            })
        } else if (channels.length === 0
                   && type === "joystick"
                   && String(control.id || "").indexOf("miniJoystick_") === 0
                   && (control.xAxis || {}).signalId
                   && (control.yAxis || {}).signalId) {
            bindings.push({
                id: String(control.id) + ".xAxis",
                type: "roller",
                label: (control.label || String(control.id)) + " X"
            })
            bindings.push({
                id: String(control.id) + ".yAxis",
                type: "roller",
                label: (control.label || String(control.id)) + " Y"
            })
        }
    }
    return bindings
}

function bindingStatusEntries(config, usedBindings, liveOwners) {
    config = config || {}
    usedBindings = usedBindings || []
    liveOwners = liveOwners || {}
    var used = {}
    for (var i = 0; i < usedBindings.length; ++i)
        used[String(usedBindings[i] || "")] = true

    var controls = config.controls || []
    var channels = ensureBindingChannels(config)
    if (channels.length > 0) {
        var channelEntries = []
        var miniSequence = 0
        var miniLabels = {}
        for (var miniIndex = 0; miniIndex < controls.length; ++miniIndex) {
            var miniControl = controls[miniIndex] || {}
            if (miniControl.type === "joystick"
                    && String(miniControl.id || "").indexOf("miniJoystick_") === 0) {
                ++miniSequence
                miniLabels[String(miniControl.id || "")] =
                        (miniControl.label && miniControl.label !== "迷你摇杆")
                        ? String(miniControl.label)
                        : "迷你摇杆 " + miniSequence
            }
        }

        for (var channelIndex = 0; channelIndex < channels.length; ++channelIndex) {
            var channel = channels[channelIndex] || {}
            var channelId = String(channel.id || "")
            var directOwnerId = ""
            var directOwnerLabel = ""
            var compositeOwnerId = ""
            var compositeOwnerLabel = ""
            for (var controlIndex = 0; controlIndex < controls.length; ++controlIndex) {
                var owner = controls[controlIndex] || {}
                var ownerType = String(owner.type || "")
                if (ownerType === "button"
                        && channel.kind === "button"
                        && String(owner.signalId || "") === String(channel.signalId || "")
                        && Number(owner.position) === Number(channel.position)) {
                    directOwnerId = String(owner.id || "")
                    directOwnerLabel = String(owner.label || directOwnerId)
                    continue
                }
                if (ownerType === "axis"
                        && channel.kind === "axis"
                        && String((owner.axis || {}).signalId || "")
                           === String((channel.axis || {}).signalId || "")) {
                    directOwnerId = String(owner.id || "")
                    directOwnerLabel = String(owner.label || directOwnerId)
                    continue
                }
                if (ownerType === "joystick" && channel.kind === "axis") {
                    var channelSignalId = String((channel.axis || {}).signalId || "")
                    if (String((owner.xAxis || {}).signalId || "") === channelSignalId) {
                        compositeOwnerId = String(owner.id || "")
                        compositeOwnerLabel =
                                String(miniLabels[compositeOwnerId]
                                       || owner.label || compositeOwnerId) + " X"
                        continue
                    }
                    if (String((owner.yAxis || {}).signalId || "") === channelSignalId) {
                        compositeOwnerId = String(owner.id || "")
                        compositeOwnerLabel =
                                String(miniLabels[compositeOwnerId]
                                       || owner.label || compositeOwnerId) + " Y"
                        continue
                    }
                }
                if (ownerType === "fnr"
                        && channel.kind === "button"
                        && String(owner.signalId || "") === String(channel.signalId || "")) {
                    var positions = owner.positions || {}
                    var channelPosition = Number(channel.position)
                    if (Number(positions.forward) === channelPosition) {
                        compositeOwnerId = String(owner.id || "")
                        compositeOwnerLabel =
                                String(owner.label || compositeOwnerId) + "-F"
                        continue
                    }
                    if (positions.neutralMode === "signal"
                            && Number(positions.neutral) === channelPosition) {
                        compositeOwnerId = String(owner.id || "")
                        compositeOwnerLabel =
                                String(owner.label || compositeOwnerId) + "-N"
                        continue
                    }
                    if (Number(positions.reverse) === channelPosition) {
                        compositeOwnerId = String(owner.id || "")
                        compositeOwnerLabel =
                                String(owner.label || compositeOwnerId) + "-R"
                        continue
                    }
                }
            }
            var ownerId = ""
            var ownerLabel = ""
            var isBound = false
            var liveOwner = liveOwners[channelId]
            if (liveOwner) {
                ownerId = String(liveOwner.ownerId || channelId)
                ownerLabel = String(liveOwner.boundTo
                                    || liveOwner.label || ownerId)
                isBound = true
            } else if (compositeOwnerId && used[compositeOwnerId]) {
                ownerId = compositeOwnerId
                ownerLabel = compositeOwnerLabel
                isBound = true
            } else if (directOwnerId && used[directOwnerId]) {
                ownerId = directOwnerId
                ownerLabel = directOwnerLabel
                isBound = true
            } else if (compositeOwnerId && used[channelId]) {
                ownerId = compositeOwnerId
                ownerLabel = compositeOwnerLabel
                isBound = true
            }
            channelEntries.push({
                id: channelId,
                type: String(channel.kind || ""),
                label: channel.label || channelId,
                bound: isBound,
                boundTo: isBound ? ownerLabel : ""
            })
        }
        return channelEntries
    }

    var miniJoystickCount = 0
    for (var j = 0; j < controls.length; ++j) {
        var countedControl = controls[j] || {}
        if (countedControl.type === "joystick"
                && String(countedControl.id || "").indexOf("miniJoystick_") === 0)
            ++miniJoystickCount
    }

    var miniJoystickIndex = 0
    var entries = []
    for (var k = 0; k < controls.length; ++k) {
        var control = controls[k] || {}
        var id = String(control.id || "")
        var type = String(control.type || "")
        var role = String(control.role || "")
        var statusType = ""
        var label = String(control.label || id)

        if (type === "joystick" && id.indexOf("miniJoystick_") === 0) {
            statusType = "miniJoystick"
            ++miniJoystickIndex
            if (miniJoystickCount > 1 && (!label || label === "迷你摇杆"))
                label = "迷你摇杆 " + miniJoystickIndex
        } else if (type === "button") {
            statusType = "button"
        } else if (type === "axis"
                   && (role === "roller" || role === "potentiometer")) {
            statusType = role
        } else if (type === "fnr") {
            statusType = "fnrSwitch"
        } else if (type === "indicator") {
            statusType = "indicator"
        }

        if (!statusType || !id)
            continue
        entries.push({
            id: id,
            type: statusType,
            label: label,
            bound: used[id] === true,
            boundTo: used[id] === true ? id : ""
        })
    }
    return entries
}

function controlById(config, controlId) {
    var controls = (config || {}).controls || []
    for (var i = 0; i < controls.length; ++i) {
        if (String((controls[i] || {}).id || "") === String(controlId || ""))
            return controls[i]
    }
    return null
}

function signalById(config, signalId) {
    var signals = (config || {}).signals || []
    for (var i = 0; i < signals.length; ++i) {
        if (String((signals[i] || {}).id || "") === String(signalId || ""))
            return signals[i]
    }
    return null
}

function appendUniqueIndex(indexes, value, count) {
    var index = Number(value)
    if (index >= 0 && index < count && indexes.indexOf(index) < 0)
        indexes.push(index)
}

function packedButtonPositionCount(signal) {
    var source = (signal || {}).source || {}
    var bitPositions = source.buttonBitPositions || []
    if (bitPositions.length > 0)
        return bitPositions.length
    var encoding = String(source.encoding || "")
    var bitsPerPosition = encoding === "canopen_1bit" ? 1 : 2
    return Math.floor(Number(source.bitLength || 0) / bitsPerPosition)
}

function fnrEditorState(config, controlId) {
    ensureBindingChannels(config)
    var control = controlById(config, controlId)
    if (!control || control.type !== "fnr")
        return {}

    var signalId = String(control.signalId || "")
    var packedSignal = signalById(config, signalId)
    if (!packedSignal || packedSignal.kind !== "packedButtons")
        return {}

    var source = packedSignal.source || {}
    var count = packedButtonPositionCount(packedSignal)
    var messageId = String(source.messageId || "")
    var positions = control.positions || {}
    var indexes = []
    var claimed = {}
    var controls = config.controls || []
    for (var controlIndex = 0; controlIndex < controls.length; ++controlIndex) {
        var otherFnr = controls[controlIndex] || {}
        if (otherFnr.type !== "fnr"
                || String(otherFnr.id || "") === String(controlId || "")
                || String(otherFnr.signalId || "") !== signalId) {
            continue
        }
        var otherPositions = otherFnr.positions || {}
        claimed[Number(otherPositions.forward)] = true
        claimed[Number(otherPositions.reverse)] = true
        if (otherPositions.neutralMode === "signal")
            claimed[Number(otherPositions.neutral)] = true
    }
    var channels = config.bindingChannels || []
    for (var channelIndex = 0; channelIndex < channels.length; ++channelIndex) {
        var channel = channels[channelIndex] || {}
        if (channel.kind !== "button"
                || String(channel.signalId || "") !== signalId)
            continue
        var channelPosition = Number(channel.position)
        if (!claimed[channelPosition])
            appendUniqueIndex(indexes, channelPosition, count)
    }
    var signals = config.signals || []
    for (var i = 0; i < signals.length; ++i) {
        var signal = signals[i] || {}
        if (signal.kind !== "button")
            continue
        if (String((signal.source || {}).messageId || "") !== messageId)
            continue
        var match = /button(\d+)$/i.exec(String(signal.id || ""))
        if (match)
            appendUniqueIndex(indexes, Number(match[1]), count)
    }
    appendUniqueIndex(indexes, positions.forward, count)
    appendUniqueIndex(indexes, positions.neutral, count)
    appendUniqueIndex(indexes, positions.reverse, count)
    indexes.sort(function(a, b) { return a - b })

    return {
        id: String(control.id || ""),
        source: signalId,
        count: count,
        visibleButtonIndices: indexes,
        forward: Number(positions.forward),
        neutral: positions.neutralMode === "signal" ? Number(positions.neutral) : -1,
        reverse: Number(positions.reverse)
    }
}

function fnrCreationState(config, controlId) {
    config = config || {}
    var controls = config.controls || []
    var signals = config.signals || []
    var channels = ensureBindingChannels(config)
    var buttonCountsBySignal = {}
    for (var i = 0; i < channels.length; ++i) {
        var buttonChannel = channels[i] || {}
        if (buttonChannel.kind !== "button")
            continue
        var buttonSignalId = String(buttonChannel.signalId || "")
        buttonCountsBySignal[buttonSignalId] =
                Number(buttonCountsBySignal[buttonSignalId] || 0) + 1
    }

    var packedSignal = null
    var bestButtonCount = -1
    for (var j = 0; j < signals.length; ++j) {
        var candidate = signals[j] || {}
        if (candidate.kind !== "packedButtons")
            continue
        var candidateCount =
                Number(buttonCountsBySignal[String(candidate.id || "")] || 0)
        if (!packedSignal || candidateCount > bestButtonCount) {
            packedSignal = candidate
            bestButtonCount = candidateCount
        }
    }
    if (!packedSignal)
        return {}

    var signalId = String(packedSignal.id || "")
    var count = packedButtonPositionCount(packedSignal)
    var claimed = {}
    for (var k = 0; k < controls.length; ++k) {
        var fnr = controls[k] || {}
        if (fnr.type !== "fnr"
                || String(fnr.id || "") === String(controlId || "")
                || String(fnr.signalId || "") !== signalId) {
            continue
        }
        var existingPositions = fnr.positions || {}
        claimed[Number(existingPositions.forward)] = true
        claimed[Number(existingPositions.reverse)] = true
        if (existingPositions.neutralMode === "signal")
            claimed[Number(existingPositions.neutral)] = true
    }

    var indexes = []
    for (var m = 0; m < channels.length; ++m) {
        var availableChannel = channels[m] || {}
        if (availableChannel.kind !== "button"
                || String(availableChannel.signalId || "") !== signalId)
            continue
        var position = Number(availableChannel.position)
        if (!claimed[position])
            appendUniqueIndex(indexes, position, count)
    }
    indexes.sort(function(a, b) { return a - b })
    return {
        id: String(controlId || "fnr"),
        source: signalId,
        count: count,
        visibleButtonIndices: indexes,
        forward: -1,
        neutral: -1,
        reverse: -1
    }
}

function buttonControlIdsForPositions(config, signalId, positions) {
    var wanted = {}
    positions = positions || []
    for (var i = 0; i < positions.length; ++i)
        wanted[Number(positions[i])] = true
    var ids = []
    var channels = ensureBindingChannels(config)
    for (var channelIndex = 0; channelIndex < channels.length; ++channelIndex) {
        var channel = channels[channelIndex] || {}
        if (channel.kind === "button"
                && String(channel.signalId || "") === String(signalId || "")
                && wanted[Number(channel.position)]) {
            ids.push(String(channel.id || ""))
        }
    }
    if (ids.length > 0)
        return ids
    var controls = (config || {}).controls || []
    for (var j = 0; j < controls.length; ++j) {
        var control = controls[j] || {}
        if (control.type === "button"
                && String(control.signalId || "") === String(signalId || "")
                && wanted[Number(control.position)]) {
            ids.push(String(control.id || ""))
        }
    }
    return ids
}

function applyFnrPositions(config, controlId, forward, neutral, reverse) {
    ensureBindingChannels(config)
    var control = controlById(config, controlId)
    if (!control) {
        var creationState = fnrCreationState(config, controlId)
        if (!creationState.source)
            return config
        control = {
            id: String(controlId || "fnr"),
            type: "fnr",
            label: "FNR",
            signalId: creationState.source
        }
        var controls = config.controls || []
        controls.push(control)
        config.controls = controls
    }
    if (control.type !== "fnr")
        return config

    var positions = {
        neutralMode: Number(neutral) >= 0 ? "signal" : "inferred",
        forward: Number(forward),
        reverse: Number(reverse)
    }
    if (Number(neutral) >= 0)
        positions.neutral = Number(neutral)
    control.positions = positions
    var claimed = [Number(forward), Number(reverse)]
    if (Number(neutral) >= 0)
        claimed.push(Number(neutral))
    var claimedMap = {}
    for (var i = 0; i < claimed.length; ++i)
        claimedMap[claimed[i]] = true
    var retained = []
    var currentControls = config.controls || []
    for (var j = 0; j < currentControls.length; ++j) {
        var current = currentControls[j] || {}
        if (current.type === "button"
                && String(current.signalId || "") === String(control.signalId || "")
                && claimedMap[Number(current.position)]) {
            continue
        }
        retained.push(current)
    }
    config.controls = retained
    return config
}

function axisControlIdForSignal(config, signalId) {
    var channels = ensureBindingChannels(config)
    for (var channelIndex = 0; channelIndex < channels.length; ++channelIndex) {
        var channel = channels[channelIndex] || {}
        if (channel.kind === "axis"
                && String((channel.axis || {}).signalId || "")
                   === String(signalId || ""))
            return String(channel.id || "")
    }
    var controls = (config || {}).controls || []
    for (var i = 0; i < controls.length; ++i) {
        var control = controls[i] || {}
        var role = String(control.role || "")
        if (control.type === "axis"
                && (role === "roller" || role === "potentiometer")
                && String((control.axis || {}).signalId || "") === String(signalId || ""))
            return String(control.id || "")
    }
    return ""
}

function axisBindingForEditorId(config, bindingId) {
    var channel = bindingChannelById(config, bindingId)
    if (channel && channel.kind === "axis" && (channel.axis || {}).signalId)
        return channel.axis
    var control = controlById(config, bindingId)
    if (control && control.type === "axis" && (control.axis || {}).signalId)
        return control.axis

    var match = /^(.*)\.(xAxis|yAxis)$/.exec(String(bindingId || ""))
    if (!match)
        return null
    var joystickControl = controlById(config, match[1])
    if (!joystickControl || joystickControl.type !== "joystick")
        return null
    var axisBinding = joystickControl[match[2]] || {}
    return axisBinding.signalId ? axisBinding : null
}

function cellBindingErrors(cells) {
    var errors = []
    cells = cells || []
    for (var cellIndex = 0; cellIndex < cells.length; ++cellIndex) {
        var visuals = (cells[cellIndex] || {}).visualComponents || []
        for (var visualIndex = 0; visualIndex < visuals.length; ++visualIndex) {
            var visual = visuals[visualIndex] || {}
            var label = String((visual.config || {}).label || visual.type || ("组件" + (visualIndex + 1)))
            if (visual.type === "MiniJoystick") {
                var xBindingId = String(visual.xBindingId || "")
                var yBindingId = String(visual.yBindingId || "")
                if (!xBindingId || !yBindingId)
                    errors.push(label + " 必须绑定 X、Y 两个通道")
                else if (xBindingId === yBindingId)
                    errors.push(label + " 的 X、Y 不能绑定同一通道")
            } else if (rendererForVisual(visual) && !visual.bindingId) {
                errors.push(label + " 尚未绑定通道")
            }
        }
    }
    return errors
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

function visualFromElement(element, config) {
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
    var visual = {
        type: type,
        x: Number(element.x || 0),
        y: Number(element.y || 0),
        config: properties,
        bindingId: element.controlId || ""
    }
    if (type === "MiniJoystick") {
        var joystickControl = controlById(config, element.controlId)
        if (joystickControl && joystickControl.type === "joystick") {
            visual.xBindingId = axisControlIdForSignal(
                        config, (joystickControl.xAxis || {}).signalId)
            visual.yBindingId = axisControlIdForSignal(
                        config, (joystickControl.yAxis || {}).signalId)
            if (!visual.xBindingId)
                visual.xBindingId = String(element.controlId || "") + ".xAxis"
            if (!visual.yBindingId)
                visual.yBindingId = String(element.controlId || "") + ".yAxis"
            properties._v3MiniControlId = String(element.controlId || "")
            properties._v3MiniXAxis = copyObject(joystickControl.xAxis)
            properties._v3MiniYAxis = copyObject(joystickControl.yAxis)
            var topology = joystickControl.topology || {}
            properties.gateMode = topology.kind === "cross2D"
                    || topology.gate === "cross"
                    ? "cross" : "omnidirectional"
        }
    } else if (type === "VerticalRoller" || type === "HorizontalRoller") {
        var rollerControl = controlById(config, element.controlId)
        var rollerTransform = (((rollerControl || {}).axis || {}).transform) || {}
        properties.invertInput = rollerTransform.invert === true
    }
    return visual
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

    ensureBindingChannels(config)
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
                var visual = visualFromElement(elements[j], config)
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
    delete properties._v3MiniControlId
    delete properties._v3MiniXAxis
    delete properties._v3MiniYAxis
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
    delete properties.gateMode
    delete properties.invertInput
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

function generatedMiniJoystickId(xBindingId, yBindingId) {
    function safePart(value) {
        return String(value || "").replace(/[^A-Za-z0-9_]/g, "_")
    }
    return "miniJoystick_" + safePart(xBindingId) + "_" + safePart(yBindingId)
}

function ensureMiniJoystickControl(config, visual) {
    var xBindingId = String((visual || {}).xBindingId || "")
    var yBindingId = String((visual || {}).yBindingId || "")
    if (!xBindingId || !yBindingId || xBindingId === yBindingId)
        return ""

    var visualConfig = (visual || {}).config || {}
    var xAxis = axisBindingForEditorId(config, xBindingId)
            || visualConfig._v3MiniXAxis
    var yAxis = axisBindingForEditorId(config, yBindingId)
            || visualConfig._v3MiniYAxis
    if (!xAxis || !yAxis || !xAxis.signalId || !yAxis.signalId)
        return ""

    var controlId = String(visualConfig._v3MiniControlId || "")
            || generatedMiniJoystickId(xBindingId, yBindingId)
    var crossGate = String(visualConfig.gateMode || "omnidirectional") === "cross"
    var joystickControl = {
        id: controlId,
        type: "joystick",
        label: visualConfig.label || "迷你摇杆",
        topology: {
            kind: crossGate ? "cross2D" : "xy2D",
            gate: crossGate ? "cross" : "omnidirectional"
        },
        xAxis: copyObject(xAxis),
        yAxis: copyObject(yAxis)
    }

    var controls = config.controls || []
    var replaced = false
    for (var i = 0; i < controls.length; ++i) {
        if (String((controls[i] || {}).id || "") === controlId) {
            controls[i] = joystickControl
            replaced = true
            break
        }
    }
    if (!replaced)
        controls.push(joystickControl)
    config.controls = controls
    return controlId
}

function ensureControlForBindingChannel(config, bindingId, visual) {
    var channel = bindingChannelById(config, bindingId)
    if (!channel)
        return String(bindingId || "")

    var control = null
    if (channel.kind === "button") {
        control = {
            id: String(channel.id || ""),
            type: "button",
            label: channel.label || String(channel.id || ""),
            signalId: String(channel.signalId || ""),
            position: Number(channel.position)
        }
    } else if (channel.kind === "axis") {
        control = {
            id: String(channel.id || ""),
            type: "axis",
            role: channel.role || "roller",
            inputMode: channel.inputMode || "centered",
            label: channel.label || String(channel.id || ""),
            topology: copyObject(channel.topology),
            axis: copyObject(channel.axis)
        }
        var visualConfig = (visual || {}).config || {}
        var visualType = String((visual || {}).type || "")
        if (visualType === "VerticalRoller"
                || visualType === "HorizontalRoller") {
            var axis = copyObject(control.axis)
            var transform = copyObject(axis.transform)
            transform.invert = visualConfig.invertInput === true
            axis.transform = transform
            control.axis = axis
        }
        if (channel.zeroAsNeutral !== undefined)
            control.zeroAsNeutral = channel.zeroAsNeutral
        if (channel.display !== undefined)
            control.display = copyObject(channel.display)
    }
    if (!control || !control.id)
        return ""

    var controls = config.controls || []
    var replaced = false
    for (var i = 0; i < controls.length; ++i) {
        if (String((controls[i] || {}).id || "") === control.id) {
            controls[i] = control
            replaced = true
            break
        }
    }
    if (!replaced)
        controls.push(control)
    config.controls = controls
    return control.id
}

function uniqueElementId(visualConfig, cardId, index, usedIds, reservedIds) {
    var preservedId = String((visualConfig || {})._v3ElementId || "")
    if (preservedId && !usedIds[preservedId]) {
        usedIds[preservedId] = true
        return preservedId
    }

    var serial = index
    var candidate = ""
    do {
        candidate = cardId + "Element" + serial
        ++serial
    } while (usedIds[candidate] || reservedIds[candidate])
    usedIds[candidate] = true
    return candidate
}

function elementFromVisual(visual, cardId, index, config, usedIds, reservedIds) {
    var renderer = rendererForVisual(visual)
    if (!renderer)
        return null
    var controlId = renderer === "miniJoystick"
            ? ensureMiniJoystickControl(config, visual)
            : ensureControlForBindingChannel(
                config, String(visual.bindingId || ""), visual)
    if (!controlId)
        return null
    var visualConfig = visual.config || {}
    return {
        id: uniqueElementId(visualConfig, cardId, index, usedIds, reservedIds),
        controlId: controlId,
        renderer: renderer,
        x: Number(visual.x || 0),
        y: Number(visual.y || 0),
        width: Number(visual.width || visualConfig._v3Width || 1),
        height: Number(visual.height || visualConfig._v3Height || 1),
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

function cardFromCell(cell, index, config) {
    cell = cell || emptyCell(index)
    var id = cell._v3CardId || ("cell" + Math.floor(index / 2) + "_" + (index % 2))
    var grid = gridForCell(cell, index)
    if (cell.cellType === "canvas") {
        var elements = []
        var visuals = cell.visualComponents || []
        var usedIds = {}
        var reservedIds = {}
        for (var reservedIndex = 0; reservedIndex < visuals.length; ++reservedIndex) {
            var reservedConfig = (visuals[reservedIndex] || {}).config || {}
            var reservedId = String(reservedConfig._v3ElementId || "")
            if (reservedId)
                reservedIds[reservedId] = true
        }
        for (var i = 0; i < visuals.length; ++i) {
            var element = elementFromVisual(
                        visuals[i], id, i, config, usedIds, reservedIds)
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

function pruneGeneratedMiniJoystickControls(config) {
    var controls = config.controls || []
    var retained = []
    for (var i = 0; i < controls.length; ++i) {
        var control = controls[i] || {}
        var controlId = String(control.id || "")
        if (control.type === "joystick"
                && controlId.indexOf("miniJoystick_") === 0)
            continue
        retained.push(control)
    }
    config.controls = retained
}

function pruneUnreferencedChannelControls(config, cards) {
    var channelIds = {}
    var channels = config.bindingChannels || []
    for (var channelIndex = 0; channelIndex < channels.length; ++channelIndex)
        channelIds[String((channels[channelIndex] || {}).id || "")] = true
    var referenced = {}
    cards = cards || []
    for (var cardIndex = 0; cardIndex < cards.length; ++cardIndex) {
        var card = cards[cardIndex] || {}
        var cardControlId = String(card.controlId || "")
        if (cardControlId)
            referenced[cardControlId] = true
        var elements = card.elements || []
        for (var elementIndex = 0; elementIndex < elements.length; ++elementIndex) {
            var controlId = String((elements[elementIndex] || {}).controlId || "")
            if (controlId)
                referenced[controlId] = true
        }
    }
    var controls = config.controls || []
    var retained = []
    for (var i = 0; i < controls.length; ++i) {
        var control = controls[i] || {}
        var id = String(control.id || "")
        if (channelIds[id] && !referenced[id])
            continue
        retained.push(control)
    }
    config.controls = retained
}

function applyCellsToConfig(config, cells) {
    if (!config || Number(config.schemaVersion || 0) !== 3)
        return config
    ensureBindingChannels(config)
    pruneGeneratedMiniJoystickControls(config)
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
        cards.push(cardFromCell(cells[j], j, config))
    }
    layout.cards = cards
    pruneUnreferencedChannelControls(config, cards)
    if (layout.grid)
        delete layout.grid.cells
    config.layout = layout
    return config
}
