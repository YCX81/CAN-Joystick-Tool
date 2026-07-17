import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import QtQuick.Effects
import CANJoystickTool

Item {
    id: root

    property var layoutManager: typeof LayoutManager !== 'undefined' ? LayoutManager : null
    property var currentConfig: ({})
    property string currentFilePath: ""
    property var productEntries: []
    property int currentVersionIndex: -1
    property string currentVersionDisplayText: ""
    property bool currentVersionDeprecated: false
    property bool hasUnsavedChanges: false
    property bool loadingCells: false
    property int activeCellIndex: 0
    property int productMetadataRevision: 0
    property string cloneProductError: ""
    property bool cloneProductCreatesVersion: false
    property string saveProductMessage: ""
    property bool saveProductMessageIsError: false
    readonly property int defaultCanvasWidth: Constants.homeCardDesignSize
    readonly property int defaultCanvasHeight: Constants.homeCardDesignSize
    readonly property real panelWidth: 320
    readonly property var cloneCalibrationModeOptions: [
        { label: "中心点", value: "centerOnly" },
        { label: "五点行程", value: "fivePointTravel" }
    ]

    // DownloadTool colors
    readonly property color dtBg: "#f5f5f7"
    readonly property color dtText: "#1d1d1f"
    readonly property color dtTextSec: "#86868b"
    readonly property color dtTextMuted: "#a1a1a6"
    readonly property color dtAccent: "#007aff"
    readonly property color dtSuccess: "#34c759"
    readonly property color dtWarning: "#ff9500"
    readonly property color dtBorder: "#d2d2d7"

    readonly property var cellTypeOptions: [
        { value: "canvas",     label: "画布" },
        { value: "busStats",   label: "总线统计" },
        { value: "recordInfo", label: "记录" },
        { value: "empty",      label: "空白" }
    ]

    // Reactive canvas mode
    property bool isCanvasMode: false
    function editableCellAt(idx) {
        if (idx < 0 || idx >= 4)
            return null
        var cell = cellRepeater.itemAt(idx)
        return cell !== null && cell.cellType === "canvas" ? cell : null
    }
    function activeCanvasCell() {
        var cell = editableCellAt(activeCellIndex)
        if (cell)
            return cell
        for (var i = 0; i < cellRepeater.count; i++) {
            cell = editableCellAt(i)
            if (cell)
                return cell
        }
        return null
    }
    function refreshCanvasMode() {
        isCanvasMode = activeCanvasCell() !== null
    }
    onActiveCellIndexChanged: refreshCanvasMode()

    function productDescriptionText() {
        productMetadataRevision
        var product = currentConfig && currentConfig.product ? currentConfig.product : {}
        return product.description === undefined || product.description === null
                ? ""
                : String(product.description)
    }

    function setProductDescription(description) {
        if (!currentConfig)
            return
        var value = description === undefined || description === null ? "" : String(description)
        var product = currentConfig.product || {}
        var oldValue = product.description === undefined || product.description === null
                ? ""
                : String(product.description)
        if (oldValue === value)
            return
        product.description = value
        currentConfig.product = product
        productMetadataRevision++
        hasUnsavedChanges = true
    }

    function commitTitleEdits(exceptIndex) {
        for (var i = 0; i < cellRepeater.count; i++) {
            if (i === exceptIndex)
                continue
            var cell = cellRepeater.itemAt(i)
            if (cell && cell.titleEditing && cell.commitTitleEdit)
                cell.commitTitleEdit()
        }
    }

    function commitProductDescriptionEdits(exceptIndex) {
        for (var i = 0; i < cellRepeater.count; i++) {
            if (i === exceptIndex)
                continue
            var cell = cellRepeater.itemAt(i)
            if (cell && cell.productDescriptionEditing && cell.commitProductDescriptionEdit)
                cell.commitProductDescriptionEdit()
        }
    }

    function commitCellEdits(exceptIndex) {
        commitTitleEdits(exceptIndex)
        commitProductDescriptionEdits(exceptIndex)
    }

    function parseConfigNumber(value) {
        if (value === undefined || value === null || value === "")
            return NaN
        if (typeof value === "number")
            return value
        var text = String(value).trim()
        if (text.length === 0)
            return NaN
        if (text.indexOf("0x") === 0 || text.indexOf("0X") === 0)
            return parseInt(text.substring(2), 16)
        return parseInt(text, 10)
    }

    function hexText(value, width) {
        if (isNaN(value))
            return "--"
        var text = Math.floor(value).toString(16).toUpperCase()
        while (text.length < width)
            text = "0" + text
        return "0x" + text
    }

    function composeJ1939Id(priority, pgn, source, destination) {
        var pf = (pgn >> 8) & 0xFF
        var id = (priority & 0x7) << 26
        id |= (pgn & 0x3FF00) << 8
        id |= ((pf < 240) ? (destination & 0xFF) : (pgn & 0xFF)) << 8
        id |= source & 0xFF
        return id
    }

    function j1939SourceAddressFromCanAddress(canAddress) {
        if (isNaN(canAddress))
            return NaN
        return canAddress > 0xFF ? (canAddress & 0xFF) : canAddress
    }

    function j1939DefaultCanAddress(sourceAddress) {
        return composeJ1939Id(6, 0xFDD6, sourceAddress, 0xFF)
    }

    function j1939CanAddressText(value) {
        var parsed = parseConfigNumber(value)
        if (isNaN(parsed))
            parsed = 0x0CFDD633
        return parsed > 0xFF
                ? hexText(parsed, 8)
                : hexText(j1939DefaultCanAddress(parsed), 8)
    }

    function canopenNodeIdFromCanAddress(canAddress) {
        if (isNaN(canAddress))
            return NaN
        return canAddress > 0x7F ? (canAddress & 0x7F) : canAddress
    }

    function canopenDefaultCanAddress(nodeId) {
        return 0x700 + (nodeId & 0x7F)
    }

    function canopenCanAddressText(value) {
        var parsed = parseConfigNumber(value)
        if (isNaN(parsed))
            parsed = 0x748
        return parsed > 0x7F
                ? hexText(parsed, 3)
                : hexText(canopenDefaultCanAddress(parsed), 3)
    }

    function productAddressText() {
        var product = currentConfig.product || {}
        var protocol = String(product.protocol || "j1939").toLowerCase()
        if (protocol === "can")
            return product.canAddress || "---"
        if (protocol === "canopen")
            return canopenCanAddressText(product.canAddress || product.nodeId)
        return j1939CanAddressText(product.canAddress || product.sourceAddress)
    }

    Component.onCompleted: loadProductList()

    function versionStringValue(item, keys) {
        var source = item || {}
        for (var i = 0; i < keys.length; i++) {
            var value = source[keys[i]]
            if (value !== undefined && value !== null) {
                var text = String(value).trim()
                if (text.length > 0)
                    return text
            }
        }
        return ""
    }

    function fileBaseName(path) {
        var text = String(path || "").replace(/\\/g, "/")
        var slashIndex = text.lastIndexOf("/")
        if (slashIndex >= 0)
            text = text.substring(slashIndex + 1)
        if (text.length >= 5 && text.toLowerCase().lastIndexOf(".json") === text.length - 5)
            text = text.substring(0, text.length - 5)
        return text
    }

    function versionCodeFromVersionItem(item) {
        var direct = versionStringValue(item, ["label", "displayVersion", "versionCode", "display_version", "version_code"])
        if (direct.length > 0)
            return direct

        var baseName = fileBaseName(versionStringValue(item, ["name", "path"]))
        var match = baseName.match(/_(V\d+(?:\.\d+)*)$/i)
        if (match && match.length > 1)
            return String(match[1]).toUpperCase()
        return baseName
    }

    function normalizedProductVersion(version) {
        var item = version || {}
        var fallbackLabel = versionCodeFromVersionItem(item)
        var status = versionStringValue(item, ["status"]) || "active"
        var defaultBaudRate = Number(item["defaultBaudRate"] || 250)
        return {
            name: versionStringValue(item, ["name"]) || fallbackLabel,
            path: versionStringValue(item, ["path"]),
            modified: versionStringValue(item, ["modified"]),
            size: item["size"] || 0,
            versionCode: versionStringValue(item, ["versionCode", "version_code"]) || fallbackLabel,
            displayVersion: versionStringValue(item, ["displayVersion", "display_version", "label"]) || fallbackLabel,
            label: fallbackLabel,
            description: versionStringValue(item, ["description"]),
            status: status,
            deprecated: item["deprecated"] === true || status.toLowerCase() === "deprecated",
            customerNames: cloneOptionArray(item["customerNames"]),
            defaultBaudRate: defaultBaudRate > 0 ? defaultBaudRate : 250
        }
    }

    function findVersionIndexByPath(versions, path) {
        var target = String(path || "")
        if (target.length === 0)
            return -1
        for (var i = 0; i < versions.length; i++) {
            if (String(versions[i].path || "") === target)
                return i
        }
        return -1
    }

    function versionLabel(version) {
        var label = versionCodeFromVersionItem(version)
        return label.length > 0 ? label : "JSON"
    }

    function versionDisplayLabel(version) {
        var label = versionLabel(version)
        return (version || {}).deprecated === true ? label + "（弃用）" : label
    }

    function normalizedProductFile(file) {
        var item = file || {}
        var versions = []
        var sourceVersions = item["versions"] || []
        for (var i = 0; i < sourceVersions.length; i++)
            versions.push(normalizedProductVersion(sourceVersions[i]))
        if (versions.length === 0 && String(item["path"] || "").length > 0)
            versions.push(normalizedProductVersion(item))

        var defaultPath = String(item["path"] || (versions.length > 0 ? versions[0].path : ""))
        var defaultVersionIndex = findVersionIndexByPath(versions, defaultPath)
        if (defaultVersionIndex < 0 && versions.length > 0)
            defaultVersionIndex = 0

        var selectedVersion = defaultVersionIndex >= 0 ? versions[defaultVersionIndex] : null
        var fileName = String(item["name"] || (selectedVersion ? selectedVersion.name : ""))
        var productName = String(item["model"] || item["displayName"] || fileName)
        var defaultBaudRate = Number(item["defaultBaudRate"] || (selectedVersion ? selectedVersion.defaultBaudRate : 250) || 250)
        return {
            name: String(item["name"] || productName),
            path: selectedVersion ? selectedVersion.path : defaultPath,
            modified: String(item["modified"] || ""),
            size: item["size"] || 0,
            displayName: String(item["displayName"] || productName || fileName),
            productModelName: productName,
            protocol: String(item["protocol"] || "j1939"),
            description: String(item["description"] || ""),
            versions: versions,
            defaultVersionIndex: defaultVersionIndex,
            customerNames: cloneOptionArray(item["customerNames"]),
            defaultBaudRate: defaultBaudRate > 0 ? defaultBaudRate : 250,
            baudRates: cloneOptionArray(item["baudRates"])
        }
    }

    function loadProductList() {
        if (!layoutManager) return
        var files = layoutManager.getProductFiles()
        var entries = []
        productModel.clear()
        currentVersionModel.clear()
        currentVersionIndex = -1
        refreshCurrentVersionDisplay()
        for (var i = 0; i < files.length; i++) {
            var entry = normalizedProductFile(files[i])
            entries.push(entry)
            productModel.append({
                                    name: entry.name,
                                    path: entry.path,
                                    modified: entry.modified,
                                    size: entry.size,
                                    displayName: entry.displayName,
                                    productModelName: entry.productModelName,
                                    protocol: entry.protocol,
                                    description: entry.description,
                                    versionCount: entry.versions.length
                                })
        }
        productEntries = entries
        rebuildCloneOptionModels()
    }

    function productEntryAt(idx) {
        return idx >= 0 && idx < productEntries.length ? productEntries[idx] : null
    }

    function selectedVersionForEntry(entry, versionIndex) {
        if (!entry)
            return null
        var versions = entry.versions || []
        if (versionIndex >= 0 && versionIndex < versions.length)
            return versions[versionIndex]
        if (entry.defaultVersionIndex >= 0 && entry.defaultVersionIndex < versions.length)
            return versions[entry.defaultVersionIndex]
        return versions.length > 0 ? versions[0] : null
    }

    function refreshVersionModel(entry) {
        currentVersionModel.clear()
        var versions = entry ? (entry.versions || []) : []
        for (var i = 0; i < versions.length; i++) {
            currentVersionModel.append({
                                           label: versionLabel(versions[i]),
                                           path: String(versions[i].path || ""),
                                           description: String(versions[i].description || ""),
                                           status: String(versions[i].status || "active"),
                                           deprecated: versions[i].deprecated === true
                                        })
        }
    }

    function currentVersionOptionAt(index) {
        return index >= 0 && index < currentVersionModel.count
                ? currentVersionModel.get(index)
                : ({})
    }

    function refreshCurrentVersionDisplay() {
        if (currentVersionIndex < 0 || currentVersionIndex >= currentVersionModel.count) {
            currentVersionDisplayText = ""
            currentVersionDeprecated = false
            return
        }

        var option = currentVersionOptionAt(currentVersionIndex)
        currentVersionDisplayText = versionDisplayLabel(option)
        currentVersionDeprecated = option.deprecated === true
    }

    function currentConfigVersionDisplayText() {
        var firmware = currentConfig && currentConfig.firmware ? currentConfig.firmware : {}
        var label = versionStringValue(firmware, ["display_version", "displayVersion", "version_code", "versionCode", "variant_code", "variantCode"])
        if (label.length > 0)
            return label

        var fileLabel = versionCodeFromVersionItem({ path: currentFilePath })
        return fileLabel.length > 0 ? fileLabel : "JSON"
    }

    function versionSelectorDisplayText(controlDisplayText) {
        if (currentVersionDisplayText.length > 0)
            return currentVersionDisplayText
        var comboText = String(controlDisplayText || "").trim()
        if (comboText.length > 0)
            return comboText
        return currentConfigVersionDisplayText()
    }

    function loadProductVersion(productIndex, versionIndex) {
        if (productIndex < 0 || productIndex >= productEntries.length)
            return
        var entry = productEntryAt(productIndex)
        var version = selectedVersionForEntry(entry, versionIndex)
        var resolvedVersionIndex = version ? findVersionIndexByPath(entry.versions || [], version.path) : -1
        if (resolvedVersionIndex < 0 && entry && entry.versions && entry.versions.length > 0)
            resolvedVersionIndex = 0
        var path = String(version ? version.path : entry.path || "")
        if (path.length === 0)
            return

        productList.currentIndex = productIndex
        refreshVersionModel(entry)
        currentVersionIndex = resolvedVersionIndex
        refreshCurrentVersionDisplay()
        currentFilePath = path
        currentConfig = layoutManager.loadProductConfig(currentFilePath)
        saveProductMessage = ""
        saveProductMessageIsError = false
        hasUnsavedChanges = false
        loadCells()
    }

    function openCurrentProductConfig() {
        if (layoutManager && layoutManager.openProductConfigPath && currentFilePath.length > 0)
            layoutManager.openProductConfigPath(currentFilePath)
    }

    function loadProduct(idx) {
        if (idx < 0 || idx >= productModel.count) return
        var entry = productEntryAt(idx)
        loadProductVersion(idx, entry ? entry.defaultVersionIndex : -1)
    }

    function findProductIndexByName(name) {
        var target = String(name || "").toLowerCase()
        for (var i = 0; i < productModel.count; i++) {
            if (String(productModel.get(i).name || "").toLowerCase() === target)
                return i
        }
        return -1
    }

    function deepCopyConfig(config) {
        return JSON.parse(JSON.stringify(config || {}))
    }

    function normalizedProtocol(protocol) {
        var value = String(protocol || "j1939").toLowerCase()
        if (value === "can" || value === "canopen")
            return value
        return "j1939"
    }

    function calibrationModeIndex(mode) {
        var value = String(mode || "centerOnly")
        for (var i = 0; i < cloneCalibrationModeOptions.length; i++) {
            if (cloneCalibrationModeOptions[i].value === value)
                return i
        }
        return 0
    }

    function currentCloneCalibrationMode() {
        var item = cloneCalibrationModeOptions[cloneCalibrationModeBox.currentIndex]
        return item ? item.value : "centerOnly"
    }

    function cloneOptionArray(value) {
        if (value === undefined || value === null)
            return []
        if (Array.isArray(value))
            return value
        return [ value ]
    }

    function appendCloneCustomerOption(options, seen, value) {
        var text = String(value || "").trim()
        if (text.length === 0)
            return
        var key = text.toLowerCase()
        if (seen[key])
            return
        seen[key] = true
        options.push(text)
    }

    function appendCloneCustomerOptionsFromValue(options, seen, value) {
        if (value === undefined || value === null)
            return

        if (typeof value === "string") {
            appendCloneCustomerOption(options, seen, value)
            return
        }

        var entries = cloneOptionArray(value)
        for (var i = 0; i < entries.length; i++) {
            var entry = entries[i]
            if (typeof entry === "string") {
                appendCloneCustomerOption(options, seen, entry)
            } else if (entry && typeof entry === "object") {
                appendCloneCustomerOption(options, seen, entry.customerName || entry.name || entry.displayName)
            }
        }
    }

    function appendCloneCustomerOptionsFromConfig(options, seen, config) {
        if (!config)
            return
        var product = config.product || {}
        appendCloneCustomerOption(options, seen, product.customerName)
        appendCloneCustomerOption(options, seen, product.customer)
        appendCloneCustomerOptionsFromValue(options, seen, product.customerBindings)
        appendCloneCustomerOptionsFromValue(options, seen, product.customers)
        appendCloneCustomerOptionsFromValue(options, seen, config.customerBindings)
        appendCloneCustomerOptionsFromValue(options, seen, config.customers)
    }

    function appendCloneBaudRateOption(options, seen, value) {
        var rate = Number(value)
        if (!isFinite(rate) || rate <= 0)
            return
        rate = Math.round(rate)
        var key = String(rate)
        if (seen[key])
            return
        seen[key] = true
        options.push(rate)
    }

    function appendCloneBaudRateOptionsFromEntry(options, seen, entry) {
        if (!entry)
            return
        appendCloneBaudRateOption(options, seen, entry.defaultBaudRate)
        var rates = cloneOptionArray(entry.baudRates)
        for (var i = 0; i < rates.length; i++)
            appendCloneBaudRateOption(options, seen, rates[i])

        var versions = cloneOptionArray(entry.versions)
        for (var j = 0; j < versions.length; j++)
            appendCloneBaudRateOption(options, seen, versions[j].defaultBaudRate)
    }

    function rebuildCloneOptionModels() {
        var customers = []
        var seenCustomers = ({})
        var rates = []
        var seenRates = ({})

        if (layoutManager && layoutManager.getCustomerOptions)
            appendCloneCustomerOptionsFromValue(customers, seenCustomers, layoutManager.getCustomerOptions())

        for (var i = 0; i < productEntries.length; i++) {
            var entry = productEntries[i]
            appendCloneCustomerOptionsFromValue(customers, seenCustomers, entry.customerNames)
            var versions = cloneOptionArray(entry.versions)
            for (var j = 0; j < versions.length; j++)
                appendCloneCustomerOptionsFromValue(customers, seenCustomers, versions[j].customerNames)
            appendCloneBaudRateOptionsFromEntry(rates, seenRates, entry)
        }
        appendCloneCustomerOptionsFromConfig(customers, seenCustomers, currentConfig)
        var currentCan = currentConfig && currentConfig.can ? currentConfig.can : {}
        appendCloneBaudRateOption(rates, seenRates, currentCan.defaultBaudRate)

        customers.sort(function(left, right) { return left.localeCompare(right) })
        rates.sort(function(left, right) { return left - right })
        if (rates.length === 0)
            rates.push(250)

        cloneCustomerModel.clear()
        for (var customerIndex = 0; customerIndex < customers.length; customerIndex++)
            cloneCustomerModel.append({ label: customers[customerIndex], value: customers[customerIndex] })

        cloneBaudRateModel.clear()
        for (var rateIndex = 0; rateIndex < rates.length; rateIndex++)
            cloneBaudRateModel.append({ label: String(rates[rateIndex]), value: rates[rateIndex] })
    }

    function selectComboValue(comboBox, model, value) {
        var target = String(value || "").trim()
        if (target.length === 0) {
            comboBox.currentIndex = -1
            if (comboBox.editable)
                comboBox.editText = ""
            return
        }

        for (var i = 0; i < model.count; i++) {
            if (String(model.get(i).value || "").trim() === target) {
                comboBox.currentIndex = i
                if (comboBox.editable)
                    comboBox.editText = target
                return
            }
        }
        comboBox.currentIndex = -1
        if (comboBox.editable)
            comboBox.editText = target
    }

    function currentCloneCustomerName() {
        var typedName = String(cloneCustomerBox.editText || "").trim()
        if (typedName.length > 0)
            return typedName
        if (cloneCustomerBox.currentIndex < 0 || cloneCustomerBox.currentIndex >= cloneCustomerModel.count)
            return ""
        return String(cloneCustomerModel.get(cloneCustomerBox.currentIndex).value || "").trim()
    }

    function currentCloneBaudRate() {
        if (cloneBaudRateBox.currentIndex < 0 || cloneBaudRateBox.currentIndex >= cloneBaudRateModel.count)
            return 250
        var value = Number(cloneBaudRateModel.get(cloneBaudRateBox.currentIndex).value)
        return value > 0 ? value : 250
    }

    function firstConfiguredCustomerName() {
        if (!currentConfig)
            return ""

        var product = currentConfig.product || {}
        var sources = [
            product.customerBindings,
            product.customers,
            currentConfig.customerBindings,
            currentConfig.customers
        ]
        for (var i = 0; i < sources.length; i++) {
            var source = sources[i]
            if (!source)
                continue
            var entries = Array.isArray(source) ? source : [ source ]
            for (var j = 0; j < entries.length; j++) {
                var entry = entries[j]
                if (typeof entry === "string" && entry.trim().length > 0)
                    return entry.trim()
                if (entry && typeof entry === "object") {
                    var name = String(entry.customerName || entry.name || "").trim()
                    if (name.length > 0)
                        return name
                }
            }
        }
        return ""
    }

    function sanitizeProductModelFallback(model) {
        var text = String(model || "").trim()
        if (text.length >= 5 && text.toLowerCase().lastIndexOf(".json") === text.length - 5)
            text = text.substring(0, text.length - 5)
        return text.replace(/[<>:"\/\\|?*\x00-\x1f]/g, "_").replace(/[. ]+$/g, "").trim()
    }

    function sanitizeProductModel(model) {
        if (layoutManager && layoutManager.sanitizeProductModel)
            return layoutManager.sanitizeProductModel(model)
        return sanitizeProductModelFallback(model)
    }

    function defaultProductConfig() {
        return {
            product: {
                name: "",
                description: "",
                protocol: "j1939",
                canFrameFormat: "extended",
                canAddress: "0x0CFDD633",
                sourceAddress: "0x33"
            },
            calibration: {
                mode: "centerOnly",
                transport: "manualCanMapping",
                allowedInNormalModeReadOnly: true
            },
            can: {
                defaultBaudRate: 250,
                messages: []
            },
            components: [],
            layout: {
                grid: {
                    rows: 2,
                    columns: 2,
                    cells: []
                }
            }
        }
    }

    function productTemplateConfig() {
        return currentConfig && currentConfig.product ? currentConfig : defaultProductConfig()
    }

    function productBaseNameFromVersionedName(name) {
        var text = String(name || "").trim()
        var match = text.match(/^(.*)_(V\d+(?:\.\d+)*)$/i)
        return match && match.length > 1 ? String(match[1]).trim() : text
    }

    function normalizedCloneVersionCode() {
        var text = String(cloneVersionField.text || "").trim()
        if (text.length === 0)
            return "V1"
        if (text.length >= 5 && text.toLowerCase().lastIndexOf(".json") === text.length - 5)
            text = text.substring(0, text.length - 5)
        if (/^\d/.test(text))
            text = "V" + text
        if (text.charAt(0) === "v")
            text = "V" + text.substring(1)
        text = text.replace(/[<>:"\/\\|?*\x00-\x1f\s]+/g, "_").replace(/[. ]+$/g, "")
        return text.length > 0 ? text : "V1"
    }

    function nextVersionCodeForEntry(entry) {
        var maxMajor = 0
        var versions = entry ? (entry.versions || []) : []
        for (var i = 0; i < versions.length; i++) {
            var label = versionCodeFromVersionItem(versions[i])
            var match = String(label || "").match(/^V(\d+)/i)
            if (match && match.length > 1) {
                var major = Number(match[1])
                if (isFinite(major) && major > maxMajor)
                    maxMajor = major
            }
        }
        return "V" + (maxMajor > 0 ? maxMajor + 1 : 2)
    }

    function setVersionMetadata(config, versionCode) {
        var firmware = config.firmware || {}
        firmware.version_code = versionCode
        firmware.display_version = versionCode
        firmware.variant_code = versionCode
        firmware.status = "active"
        config.firmware = firmware
        return config
    }

    function setProductCustomerBinding(config, customerName) {
        var name = String(customerName || "").trim()
        if (name.length === 0)
            return config
        var product = config.product || {}
        product.customerBindings = [
            { name: name, isDefault: true, note: "SOP configured customer" }
        ]
        config.product = product
        return config
    }

    function applyCloneMetadata(config, model, description, calibrationMode, customerName, baudRate, versionCode) {
        var clonedConfig = deepCopyConfig(config)
        var product = clonedConfig.product || {}
        product.name = model
        product.description = description
        clonedConfig.product = product

        var calibration = clonedConfig.calibration || {}
        calibration.mode = calibrationMode
        clonedConfig.calibration = calibration

        var can = clonedConfig.can || {}
        can.defaultBaudRate = baudRate
        clonedConfig.can = can

        var firmware = clonedConfig.firmware || {}
        firmware.description = description
        clonedConfig.firmware = firmware

        clonedConfig = setProductCustomerBinding(clonedConfig, customerName)
        return setVersionMetadata(clonedConfig, versionCode)
    }

    function openCloneProductPopup() {
        cloneProductCreatesVersion = false
        var templateConfig = productTemplateConfig()
        var product = templateConfig.product || {}
        var model = product.name || ""

        rebuildCloneOptionModels()
        cloneModelField.text = model ? (productBaseNameFromVersionedName(model) + "-NEW") : ""
        cloneVersionField.text = "V1"
        cloneDescriptionArea.text = ""
        selectComboValue(cloneCustomerBox, cloneCustomerModel, "")
        cloneCalibrationModeBox.currentIndex = calibrationModeIndex("centerOnly")
        selectComboValue(cloneBaudRateBox, cloneBaudRateModel, 250)
        if (cloneBaudRateBox.currentIndex < 0 && cloneBaudRateModel.count > 0)
            cloneBaudRateBox.currentIndex = 0
        cloneButtonCountBox.value = 10
        cloneButtonNumbersField.text = ""
        cloneRollerCountBox.value = 4
        cloneProductError = ""
        cloneProductPopup.open()
        cloneModelField.forceActiveFocus()
        cloneModelField.selectAll()
    }

    function openCloneProductVersionPopup() {
        if (productList.currentIndex < 0 || !currentConfig || !currentConfig.product)
            return

        cloneProductCreatesVersion = true
        var entry = productEntryAt(productList.currentIndex)
        var templateConfig = productTemplateConfig()
        var product = templateConfig.product || {}
        var calibration = templateConfig.calibration || {}
        var model = productBaseNameFromVersionedName(entry ? entry.productModelName : product.name)
        var baudRate = Number((templateConfig.can || {}).defaultBaudRate || 250)

        rebuildCloneOptionModels()
        cloneModelField.text = model
        cloneVersionField.text = nextVersionCodeForEntry(entry)
        cloneDescriptionArea.text = product.description || ""
        selectComboValue(cloneCustomerBox, cloneCustomerModel, firstConfiguredCustomerName())
        cloneCalibrationModeBox.currentIndex = calibrationModeIndex(calibration.mode)
        selectComboValue(cloneBaudRateBox, cloneBaudRateModel, baudRate)
        if (cloneBaudRateBox.currentIndex < 0 && cloneBaudRateModel.count > 0)
            cloneBaudRateBox.currentIndex = 0
        cloneProductError = ""
        cloneProductPopup.open()
        cloneVersionField.forceActiveFocus()
        cloneVersionField.selectAll()
    }

    function validateCloneProductForm() {
        var model = sanitizeProductModel(cloneModelField.text)
        var versionCode = normalizedCloneVersionCode()

        if (model.length === 0)
            return "型号不能为空"
        if (versionCode.length === 0)
            return "版本号不能为空"
        if (!cloneProductCreatesVersion && layoutManager && layoutManager.productConfigExists && layoutManager.productConfigExists(model))
            return "型号已存在，请使用创建新版本：" + model
        if (layoutManager && layoutManager.productConfigVersionExists
                && layoutManager.productConfigVersionExists(model, versionCode))
            return "版本文件已存在：" + model + "_" + versionCode + ".json"
        if (currentCloneBaudRate() <= 0)
            return "CAN波特率必须大于0"
        if (!cloneProductCreatesVersion) {
            var buttonNumberResult = parsedCloneButtonNumbers()
            if (!buttonNumberResult.ok)
                return buttonNumberResult.error
            if (buttonNumberResult.numbers.length !== cloneButtonCountBox.value)
                return "按钮编号数量必须与按钮数量一致"
        }
        return ""
    }

    function parsedCloneButtonNumbers() {
        var text = String(cloneButtonNumbersField.text || "").trim()
        var numbers = []
        if (text.length === 0) {
            for (var fallbackNumber = 1; fallbackNumber <= cloneButtonCountBox.value; ++fallbackNumber)
                numbers.push(fallbackNumber)
            return { ok: true, numbers: numbers, error: "" }
        }

        var tokens = text.replace(/[，;；\s]+/g, ",").split(",")
        var seen = {}
        for (var index = 0; index < tokens.length; ++index) {
            if (tokens[index].length === 0)
                continue
            var number = Number(tokens[index])
            if (!Number.isInteger(number) || number < 1 || number > 12)
                return { ok: false, numbers: [], error: "按钮编号必须是1到12的整数" }
            if (seen[number])
                return { ok: false, numbers: [], error: "按钮编号不能重复" }
            seen[number] = true
            numbers.push(number)
        }
        numbers.sort(function(a, b) { return a - b })
        return { ok: true, numbers: numbers, error: "" }
    }

    function buildClonedProductConfig() {
        var model = sanitizeProductModel(cloneModelField.text)
        var versionCode = normalizedCloneVersionCode()
        var calibrationMode = currentCloneCalibrationMode()
        var customerName = currentCloneCustomerName()
        var description = String(cloneDescriptionArea.text || "").trim()

        if (cloneProductCreatesVersion) {
            var config = deepCopyConfig(productTemplateConfig())
            return applyCloneMetadata(config, model, description, calibrationMode, customerName,
                                      currentCloneBaudRate(), versionCode)
        }

        var spec = {
            model: model,
            description: description,
            customerName: customerName,
            calibrationMode: calibrationMode,
            baudRate: currentCloneBaudRate(),
            buttonCount: cloneButtonCountBox.value,
            buttonNumbers: parsedCloneButtonNumbers().numbers,
            rollerCount: cloneRollerCountBox.value
        }
        if (layoutManager && layoutManager.buildStandardProductConfig)
            return setVersionMetadata(layoutManager.buildStandardProductConfig(spec), versionCode)

        return applyCloneMetadata(defaultProductConfig(), model, description, calibrationMode,
                                  customerName, currentCloneBaudRate(), versionCode)
    }

    function saveCloneProduct() {
        cloneProductError = validateCloneProductForm()
        if (cloneProductError.length > 0)
            return

        if (cloneProductCreatesVersion && currentConfig && currentConfig.product)
            syncCurrentLayoutFromCells()
        var model = sanitizeProductModel(cloneModelField.text)
        var versionCode = normalizedCloneVersionCode()
        var config = buildClonedProductConfig()
        if (layoutManager && layoutManager.saveProductConfigVersionAs) {
            if (!layoutManager.saveProductConfigVersionAs(config, model, versionCode))
                return
        } else if (!layoutManager.saveProductConfigAs(config, model)) {
            return
        }

        cloneProductPopup.close()
        loadProductList()
        var idx = findProductIndexByName(model)
        if (idx >= 0) {
            productList.currentIndex = idx
            var targetPath = layoutManager && layoutManager.productConfigVersionPath
                    ? layoutManager.productConfigVersionPath(model, versionCode)
                    : ""
            var entry = productEntryAt(idx)
            var versionIndex = targetPath.length > 0 ? findVersionIndexByPath(entry ? entry.versions : [], targetPath) : -1
            loadProductVersion(idx, versionIndex)
        }
        if (layoutManager && layoutManager.openProductConfigPath && layoutManager.productConfigVersionPath)
            layoutManager.openProductConfigPath(layoutManager.productConfigVersionPath(model, versionCode))
    }

    // Resolve component IDs to their definitions
    function resolveComponents(compIds) {
        var result = []
        var allComps = currentConfig.components || []
        for (var i = 0; i < compIds.length; i++) {
            var id = compIds[i]
            if (isReservedCellComponentId(id)) { result.push({ id: id, type: id }); continue }
            for (var j = 0; j < allComps.length; j++) {
                if (allComps[j].id === id) { result.push(allComps[j]); break }
            }
        }
        return result
    }

    // Guess cell type from component list
    function detectCellType(compIds) {
        if (!compIds || compIds.length === 0) return "empty"
        if (compIds.indexOf("busStats") >= 0) return "busStats"
        if (compIds.indexOf("recordInfo") >= 0) return "recordInfo"
        return "canvas"  // buttons, EJM, FNR all go to canvas
    }

    // Map product component definition to DesignCanvas component type
    function mapToCanvasType(compDef) {
        switch (compDef.type) {
        case "buttonGroup": return { type: "ButtonRed", perItem: true, count: compDef.count || 8, label: "" }
        case "roller":
        case "potentiometer": return {
            type: compDef.type === "potentiometer" || compDef.orientation === "rotary"
                  ? "RotaryPotentiometer"
                  : compDef.orientation === "vertical" ? "VerticalRoller" : "HorizontalRoller",
            perItem: false,
            label: compDef.label || ""
        }
        case "fnrSwitch": return { type: "HorizontalFNR", perItem: false, label: compDef.label || "FNR" }
        case "counter": return null  // skip, shown inside button area
        case "indicator": return null
        default: return null
        }
    }

    // Auto-populate canvas with product components
    function populateCanvas(canvas, compIds) {
        if (!canvas) return
        canvas.clear()
        var resolved = resolveComponents(compIds)
        var x = 10, y = 10, maxRowH = 0
        var canvasW = canvas.canvasWidth - 10

        for (var i = 0; i < resolved.length; i++) {
            var mapping = mapToCanvasType(resolved[i])
            if (!mapping) continue

            if (mapping.perItem) {
                // Buttons follow the original DownloadTool density: 5 on the
                // first row, then wrap.
                var cols = Math.min(5, mapping.count)
                var colSpacing = 8
                var rowSpacing = 2
                var btnSize = ComponentRegistry.getDefaultSize(mapping.type)
                var bw = btnSize.width || 56
                var bh = btnSize.height || 80
                for (var b = 0; b < mapping.count; b++) {
                    var bx = 4 + (b % cols) * (bw + colSpacing)
                    var by = 4 + Math.floor(b / cols) * (bh + rowSpacing)
                    var buttonConfig = ComponentRegistry.getDefaultConfig(mapping.type)
                    buttonConfig.label = (b + 1).toString()
                    var buttonWrapper = canvas.addComponent(mapping.type, bx, by, buttonConfig)
                    if (buttonWrapper)
                        buttonWrapper.bindingId = resolved[i].id + "." + b
                }
                y += Math.ceil(mapping.count / cols) * (bh + rowSpacing) + 10
            } else {
                // Single component
                var size = ComponentRegistry.getDefaultSize(mapping.type)
                var w = size.width || 200
                var h = size.height || 100
                if (x + w > canvasW) { x = 10; y += maxRowH + 8; maxRowH = 0 }
                var config = ComponentRegistry.getDefaultConfig(mapping.type)
                if (mapping.label) config.label = mapping.label
                if (mapping.lampCount) config.lampCount = mapping.lampCount
                var wrapper = canvas.addComponent(mapping.type, x, y, config)
                if (wrapper)
                    wrapper.bindingId = resolved[i].id
                x += w + 8
                maxRowH = Math.max(maxRowH, h)
            }
        }
    }

    function cloneConfig(config) {
        var copy = {}
        config = config || {}
        for (var key in config)
            copy[key] = config[key]
        return copy
    }

    function mergedComponentConfig(type, config) {
        var merged = ComponentRegistry.getDefaultConfig(type)
        config = config || {}
        for (var key in config)
            merged[key] = config[key]
        if (type.indexOf("Button") === 0) {
            var defaults = ComponentRegistry.getDefaultConfig(type)
            merged.bezelSize = defaults.bezelSize
            merged.capSize = defaults.capSize
        }
        return merged
    }

    function sizeForComponentConfig(type, config) {
        var size = ComponentRegistry.getDefaultSize(type)
        config = config || {}
        if (type.indexOf("Button") === 0) {
            var defaults = ComponentRegistry.getDefaultConfig(type)
            config.bezelSize = defaults.bezelSize
            config.capSize = defaults.capSize
        }
        return size
    }

    function clampComponentPosition(canvas, type, x, y, config) {
        var size = sizeForComponentConfig(type, config)
        var targetWidth = canvas.canvasWidth || root.defaultCanvasWidth
        var targetHeight = canvas.canvasHeight || root.defaultCanvasHeight
        var maxX = Math.max(0, targetWidth - size.width)
        var maxY = Math.max(0, targetHeight - size.height)
        return {
            x: Math.max(0, Math.min(x || 0, maxX)),
            y: Math.max(0, Math.min(y || 0, maxY))
        }
    }

    function addVisualComponent(canvas, visual, canvasMeta) {
        var type = visual.type || ""
        var config = mergedComponentConfig(type, visual.config || {})
        var targetWidth = canvas.canvasWidth || root.defaultCanvasWidth
        var targetHeight = canvas.canvasHeight || root.defaultCanvasHeight
        var sourceWidth = canvasMeta && canvasMeta.width ? canvasMeta.width : targetWidth
        var sourceHeight = canvasMeta && canvasMeta.height ? canvasMeta.height : targetHeight
        var sx = sourceWidth > 0 ? targetWidth / sourceWidth : 1
        var sy = sourceHeight > 0 ? targetHeight / sourceHeight : 1
        var pos = clampComponentPosition(canvas, type, (visual.x || 0) * sx, (visual.y || 0) * sy, config)
        var wrapper = canvas.addComponent(type, pos.x, pos.y, config)
        if (wrapper && visual.bindingId)
            wrapper.bindingId = visual.bindingId
        return wrapper
    }

    function labelForCellType(value) {
        for (var i = 0; i < cellTypeOptions.length; i++) {
            if (cellTypeOptions[i].value === value)
                return cellTypeOptions[i].label
        }
        return "空白"
    }

    function canvasDefaultTitle(index) {
        return Math.floor(index / 2) === 0 ? "正面" : "背面"
    }

    function defaultCellTitle(index, cellType) {
        if (cellType === "canvas") return canvasDefaultTitle(index)
        if (cellType === "busStats") return "总线统计"
        if (cellType === "recordInfo") return "记录信息"
        return ""
    }

    function isLegacyCanvasTitle(title) {
        var value = title === undefined || title === null ? "" : String(title).trim()
        return value === "" || value === "按钮" || value === "EJM 轴" || value === "EJM轴"
                || value === "扩展轴" || value === "EJM 轴 / FNR"
    }

    function normalizedCellTitle(index, cellType, title) {
        var value = title === undefined || title === null ? "" : String(title).trim()
        return value.length > 0 ? value : defaultCellTitle(index, cellType)
    }

    function loadedCellTitle(index, cellType, title) {
        return cellType === "canvas" && isLegacyCanvasTitle(title)
                ? defaultCellTitle(index, cellType)
                : normalizedCellTitle(index, cellType, title)
    }

    function componentsForCellType(cellType, currentComponents) {
        if (cellType === "busStats")
            return ["busStats"]
        if (cellType === "recordInfo")
            return ["recordInfo"]
        if (cellType === "empty")
            return []
        if (cellType === "canvas")
            return sanitizedCanvasComponentIds(currentComponents || [])
        return currentComponents || []
    }

    function isReservedCellComponentId(id) {
        return id === "busStats" || id === "recordInfo"
    }

    function bindingComponentId(bindingId) {
        if (bindingId === undefined || bindingId === null)
            return ""
        var value = String(bindingId).trim()
        if (value.length === 0)
            return ""
        var dot = value.indexOf(".")
        return dot > 0 ? value.substring(0, dot) : value
    }

    function appendCanvasComponentId(result, id) {
        if (!id || isReservedCellComponentId(id))
            return
        if (result.indexOf(id) < 0)
            result.push(id)
    }

    function sanitizedCanvasComponentIds(componentIds) {
        var result = []
        var ids = componentIds || []
        for (var i = 0; i < ids.length; i++)
            appendCanvasComponentId(result, ids[i])
        return result
    }

    function canvasComponentIdsFromVisualComponents(visualComponents, fallbackComponents) {
        var result = []
        var visuals = visualComponents || []
        for (var i = 0; i < visuals.length; i++)
            appendCanvasComponentId(result, bindingComponentId(visuals[i].bindingId))
        if (result.length > 0)
            return result
        return sanitizedCanvasComponentIds(fallbackComponents || [])
    }

    function setCellTitle(cell, title) {
        if (!cell)
            return
        var value = title === undefined || title === null ? "" : String(title)
        if (cell.cellTitle === value)
            return
        cell.cellTitle = value
        if (!loadingCells)
            hasUnsavedChanges = true
    }

    function setCellType(cell, value) {
        if (!cell || cell.cellType === value)
            return
        var previousType = cell.cellType
        cell.cellType = value
        cell.cellCompIds = componentsForCellType(value, previousType === "canvas" ? cell.cellCompIds : [])
        if (value === "canvas" && cell.cellTitle.trim().length === 0)
            cell.cellTitle = defaultCellTitle(cell.cellIndex, value)
        else if (value !== "canvas")
            cell.cellTitle = defaultCellTitle(cell.cellIndex, value)
        if (value !== "canvas" && cell.canvasItem)
            cell.canvasItem.clear()
        hasUnsavedChanges = true
        refreshCanvasMode()
    }

    function normalizedCanvasMeta(canvasMeta) {
        return {
            width: defaultCanvasWidth,
            height: defaultCanvasHeight,
            scaleMode: canvasMeta && canvasMeta.scaleMode ? canvasMeta.scaleMode : "uniform"
        }
    }

    function sourceCanvasMeta(canvasMeta) {
        var width = canvasMeta && canvasMeta.width ? canvasMeta.width : defaultCanvasWidth
        var height = canvasMeta && canvasMeta.height ? canvasMeta.height : defaultCanvasHeight
        if (width <= 0 || height <= 0) {
            width = defaultCanvasWidth
            height = defaultCanvasHeight
        }
        return { width: width, height: height }
    }

    function loadCells() {
        if (!currentConfig || !currentConfig.layout) return
        var cells = (currentConfig.layout.grid || {}).cells || []

        // Use timer to ensure canvas items are created
        cellLoadTimer.cellData = cells
        cellLoadTimer.start()
    }

    Timer {
        id: cellLoadTimer
        interval: 100; repeat: false
        property var cellData: []
        onTriggered: doLoadCells(cellData)
    }

    function doLoadCells(cells) {
        loadingCells = true
        for (var i = 0; i < cellRepeater.count && i < cells.length; i++) {
            var cell = cellRepeater.itemAt(i)
            if (!cell) continue
            var c = cells[i]
            // Map old types to new unified types
            var oldType = c.cellType || detectCellType(c.components)
            if (oldType === "buttons" || oldType === "ejm") oldType = "canvas"
            var visualComponents = c.visualComponents || []
            cell.cellTitle = loadedCellTitle(i, oldType, c.title)
            cell.cellType = oldType
            cell.cellCompIds = oldType === "canvas"
                    ? canvasComponentIdsFromVisualComponents(visualComponents, c.components || [])
                    : componentsForCellType(oldType, c.components || [])
            var canvasMeta = normalizedCanvasMeta(c.canvas)
            var savedCanvasMeta = sourceCanvasMeta(c.canvas)
            cell.canvasDesignWidth = canvasMeta.width
            cell.canvasDesignHeight = canvasMeta.height
            cell.canvasScaleMode = canvasMeta.scaleMode

            if (cell.canvasItem)
                cell.canvasItem.clear()

            // For canvas cells: populate with visual components or auto-generate from component IDs
            if (cell.cellType === "canvas" && cell.canvasItem) {
                var vis = visualComponents
                if (vis.length > 0) {
                    // Load saved visual layout with bindingIds
                    for (var j = 0; j < vis.length; j++) {
                        addVisualComponent(cell.canvasItem, vis[j], savedCanvasMeta)
                    }
                } else if (c.components && c.components.length > 0) {
                    // Auto-populate from component definitions
                    populateCanvas(cell.canvasItem, c.components)
                }
            }
        }
        for (var k = cells.length; k < cellRepeater.count; k++) {
            var ec = cellRepeater.itemAt(k)
            if (ec) {
                ec.cellTitle = ""
                ec.cellType = "empty"
                ec.cellCompIds = []
                if (ec.canvasItem)
                    ec.canvasItem.clear()
            }
        }
        refreshCanvasMode()
        refreshBindingStatus()
        hasUnsavedChanges = false
        loadingCells = false
    }

    function syncCurrentLayoutFromCells() {
        if (!currentConfig) return
        commitCellEdits(-1)
        var layout = currentConfig.layout || {}
        var grid = layout.grid || {}
        var cells = []
        for (var i = 0; i < cellRepeater.count; i++) {
            var cell = cellRepeater.itemAt(i)
            if (!cell) continue
            var cd = {
                row: Math.floor(i/2),
                col: i%2,
                title: normalizedCellTitle(i, cell.cellType, cell.cellTitle),
                cellType: cell.cellType,
                components: componentsForCellType(cell.cellType, cell.cellCompIds)
            }
            if (cell.cellType === "canvas" && cell.canvasItem) {
                var canvasData = cell.canvasItem.toJSON()
                cd.canvas = {
                    width: canvasData.canvas.width,
                    height: canvasData.canvas.height,
                    scaleMode: canvasData.canvas.scaleMode || "uniform"
                }
                cd.visualComponents = []
                var comps = canvasData.components || []
                cd.components = canvasComponentIdsFromVisualComponents(comps, cell.cellCompIds)
                for (var j = 0; j < comps.length; j++)
                    cd.visualComponents.push({ type: comps[j].type, x: comps[j].x, y: comps[j].y, config: comps[j].config, bindingId: comps[j].bindingId || "" })
            }
            cells.push(cd)
        }
        grid.cells = cells; layout.grid = grid; currentConfig.layout = layout
    }

    function saveProduct() {
        if (!currentFilePath || !currentConfig) {
            saveProductMessage = "未选择可保存的产品配置。"
            saveProductMessageIsError = true
            return
        }
        syncCurrentLayoutFromCells()
        if (layoutManager.saveProductConfig(currentConfig, currentFilePath)) {
            hasUnsavedChanges = false
            saveProductMessage = "已保存：" + currentFilePath
            saveProductMessageIsError = false
        }
    }

    ListModel { id: productModel }
    ListModel { id: currentVersionModel }
    ListModel { id: bindingStatusModel }
    ListModel { id: cloneCustomerModel }
    ListModel { id: cloneBaudRateModel }

    Connections {
        target: layoutManager
        function onErrorOccurred(error) {
            if (cloneProductPopup.opened)
                cloneProductError = error
            else {
                saveProductMessage = error
                saveProductMessageIsError = true
            }
        }
        function onProductConfigSaved(path) {
            if (!cloneProductPopup.opened) {
                saveProductMessage = "已保存：" + path
                saveProductMessageIsError = false
            }
        }
    }

    // Collect all bindings from all canvas cells and compare with product components
    function refreshBindingStatus() {
        bindingStatusModel.clear()
        var allComps = currentConfig.components || []
        var usedBindings = []

        // Collect all bindingIds from all canvas cells
        for (var i = 0; i < cellRepeater.count; i++) {
            var cell = cellRepeater.itemAt(i)
            if (!cell || cell.cellType !== "canvas" || !cell.canvasItem) continue
            var used = cell.canvasItem.getUsedBindings()
            for (var j = 0; j < used.length; j++) usedBindings.push(used[j])
        }

        for (var k = 0; k < allComps.length; k++) {
            var comp = allComps[k]
            if (comp.type === "joystick") continue // fixed, skip

            if (comp.type === "buttonGroup") {
                // Expand buttons
                var count = comp.count || 8
                for (var b = 0; b < count; b++) {
                    var btnId = comp.id + "." + b
                    var btnBound = usedBindings.indexOf(btnId) >= 0
                    bindingStatusModel.append({ compId: "BTN" + (b+1), bound: btnBound, boundTo: btnBound ? btnId : "" })
                }
            } else {
                // Single component
                var isBound = usedBindings.indexOf(comp.id) >= 0
                // Also check fnr composite bindings
                if (!isBound) {
                    for (var m = 0; m < usedBindings.length; m++) {
                        if (usedBindings[m].indexOf(comp.id) >= 0) { isBound = true; break }
                    }
                }
                var typeLabel = comp.type === "roller" ? "轴" : (comp.type === "fnrSwitch" ? "FNR" : comp.type)
                bindingStatusModel.append({ compId: comp.label || comp.id, bound: isBound, boundTo: isBound ? comp.id : "" })
            }
        }
    }

    Rectangle { anchors.fill: parent; color: dtBg }

    // ===== Top Bar =====
    Rectangle {
        id: topBar; anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
        height: 60; color: "white"
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: dtBorder }
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 10
            Label { text: "产品配置编辑器"; font.pixelSize: 14; font.bold: true; color: dtText }
            Rectangle {
                visible: !!currentConfig.product; width: pL.width+10; height: 18; radius: 3
                color: currentConfig.product && currentConfig.product.protocol==="canopen" ? dtWarning : dtSuccess
                Label { id: pL; anchors.centerIn: parent; text: currentConfig.product ? currentConfig.product.name||"" : ""; font.pixelSize: 8; font.bold: true; color: "white" }
            }
            Label { visible: !!currentConfig.product; text: root.productDescriptionText(); font.pixelSize: 10; color: dtTextSec; elide: Text.ElideRight; Layout.fillWidth: true }
            Label {
                visible: saveProductMessage.length > 0
                text: saveProductMessage
                font.pixelSize: 10
                color: saveProductMessageIsError ? "#d70015" : dtSuccess
                elide: Text.ElideRight
                Layout.maximumWidth: 360
            }
            Item { Layout.fillWidth: true }
            ComboBox {
                id: versionSelector
                visible: root.currentFilePath !== "" && currentVersionModel.count > 0
                enabled: currentVersionModel.count > 1
                model: currentVersionModel
                textRole: "label"
                currentIndex: root.currentVersionIndex
                displayText: root.versionSelectorDisplayText(versionSelector.currentText)
                font.pixelSize: 10
                Layout.preferredWidth: 108
                Layout.preferredHeight: 30
                ToolTip.visible: hovered
                ToolTip.text: "选择产品 JSON 版本"
                delegate: ItemDelegate {
                    id: versionSelectorDelegate
                    width: versionSelector.width
                    highlighted: versionSelector.highlightedIndex === index
                    property var versionOption: root.currentVersionOptionAt(index)
                    contentItem: Label {
                        leftPadding: 12
                        rightPadding: 12
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        clip: true
                        text: root.versionDisplayLabel(versionSelectorDelegate.versionOption)
                        color: versionSelectorDelegate.versionOption.deprecated === true ? root.dtTextMuted : root.dtText
                        font.pixelSize: 10
                    }
                }
                onActivated: function(index) {
                    if (productList.currentIndex >= 0 && index !== root.currentVersionIndex) {
                        root.commitCellEdits(-1)
                        loadProductVersion(productList.currentIndex, index)
                    }
                }
            }
            Button {
                text: "打开 JSON"
                enabled: root.currentFilePath !== ""
                font.pixelSize: 11
                focusPolicy: Qt.NoFocus
                ToolTip.visible: hovered
                ToolTip.text: "用默认编辑器打开当前版本 JSON"
                onClicked: openCurrentProductConfig()
            }
            Button {
                text: "创建新产品"
                enabled: true
                font.pixelSize: 11
                onClicked: openCloneProductPopup()
            }
            Button {
                text: "创建新版本"
                enabled: currentFilePath !== "" && !!currentConfig.product
                font.pixelSize: 11
                ToolTip.visible: hovered
                ToolTip.text: "复制当前 JSON 并保存为该产品的新版本"
                onClicked: openCloneProductVersionPopup()
            }
            Button {
                text: hasUnsavedChanges ? "保存 *" : "保存"
                enabled: currentFilePath !== ""
                font.pixelSize: 11
                palette.button: hasUnsavedChanges ? dtAccent : "#e5e5ea"
                palette.buttonText: hasUnsavedChanges ? "white" : dtTextMuted
                onClicked: saveProduct()
            }
        }
    }

    // ===== Main =====
    RowLayout {
        anchors.top: topBar.bottom; anchors.topMargin: 8
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.leftMargin: 10; anchors.rightMargin: 10; anchors.bottomMargin: 10; spacing: 10

        Item {
            id: leftSidebar
            Layout.preferredWidth: root.panelWidth
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignTop

            readonly property real gap: Constants.downloadToolCardGap
            readonly property real functionPanelHeight: Math.min(Constants.downloadToolBottomPanelMaxHeight,
                                                                 Math.max(Constants.downloadToolBottomPanelMinHeight,
                                                                          height * Constants.downloadToolBottomPanelHeightRatio))
            readonly property real dashboardHeight: Math.max(Constants.downloadToolDashboardMinHeight,
                                                             height - functionPanelHeight - gap)

            Rectangle {
                id: productListCard
                x: 0
                y: 0
                width: parent.width
                height: Math.min(parent.height, leftSidebar.dashboardHeight)
                color: "white"; radius: 8; border.width: 1; border.color: dtBorder

                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 14; spacing: 8
                    Label { text: "产品列表"; font.pixelSize: 12; font.bold: true; color: dtText }
                    Rectangle { Layout.fillWidth: true; height: 1; color: dtBorder }
                    ListView {
                        id: productList; Layout.fillWidth: true; Layout.fillHeight: true
                        model: productModel; clip: true; spacing: 1; currentIndex: -1
                        delegate: Rectangle {
                            width: productList.width; height: 46; radius: 4
                            readonly property var productEntry: productModel.get(index)
                            readonly property string productNameText: String(productEntry.displayName || productEntry.productModelName || productEntry.name || "")
                            color: productList.currentIndex === index ? "#e8f0fe" : (rowHover.hovered ? dtBg : "transparent")
                            HoverHandler { id: rowHover }
                            RowLayout {
                                z: 2
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                spacing: 6
                                Rectangle {
                                    width: 5
                                    height: 28
                                    radius: 2.5
                                    color: productList.currentIndex === index ? dtAccent : dtTextMuted
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Label {
                                        Layout.fillWidth: true
                                        text: productNameText
                                        font.pixelSize: 11
                                        font.bold: productList.currentIndex === index
                                        color: dtText
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                            MouseArea {
                                id: pha
                                z: 1
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.commitCellEdits(-1)
                                    productList.currentIndex = index
                                    loadProduct(index)
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: bindingStatusCard
                x: 0
                y: productListCard.height + leftSidebar.gap
                width: parent.width
                height: Math.max(0, parent.height - y)
                color: "white"; radius: 8; border.width: 1; border.color: dtBorder
                visible: height > 0

                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 12; spacing: 6

                    Label { text: "绑定状态"; font.pixelSize: 12; font.bold: true; color: dtText }
                    Rectangle { Layout.fillWidth: true; height: 1; color: dtBorder }

                    ListView {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        clip: true; spacing: 2
                        model: bindingStatusModel

                        delegate: Row {
                            width: parent ? parent.width : 0; spacing: 4; height: 18

                            Rectangle {
                                width: 8; height: 8; radius: 4; anchors.verticalCenter: parent.verticalCenter
                                color: model.bound ? dtSuccess : "#ff3b30"
                            }
                            Text {
                                text: model.compId; font.pixelSize: 9; font.bold: true
                                color: model.bound ? dtText : dtTextMuted
                                anchors.verticalCenter: parent.verticalCenter; width: 96; elide: Text.ElideRight
                            }
                            Text {
                                text: model.bound ? model.boundTo : "未绑定"
                                font.pixelSize: 8; color: model.bound ? dtAccent : "#ff3b30"
                                anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                                width: Math.max(60, parent.width - 116)
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: previewPane
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 520

            Rectangle {
                anchors.fill: parent
                color: dtBg
                radius: 8
            }

            Item {
                id: dtViewport
                anchors.top: parent.top; anchors.topMargin: Constants.downloadToolContentVerticalMargin
                anchors.left: parent.left; anchors.leftMargin: Constants.downloadToolContentMargin
                anchors.right: parent.right; anchors.rightMargin: Constants.downloadToolContentMargin
                anchors.bottom: parent.bottom; anchors.bottomMargin: Constants.downloadToolContentVerticalMargin

                readonly property real gap: Constants.downloadToolCardGap
                readonly property real functionPanelHeight: Math.min(Constants.downloadToolBottomPanelMaxHeight,
                                                                     Math.max(Constants.downloadToolBottomPanelMinHeight,
                                                                              height * Constants.downloadToolBottomPanelHeightRatio))
                readonly property real dashboardHeight: Math.max(Constants.downloadToolDashboardMinHeight,
                                                                 height - functionPanelHeight - gap)
                readonly property var editorLayout: currentConfig && currentConfig.layout ? currentConfig.layout : ({})
                readonly property var leftLayout: editorLayout.left ? editorLayout.left : ({})
                readonly property real leftWidthRatio: leftLayout.widthRatio ? leftLayout.widthRatio
                                                                             : Constants.downloadToolLeftWidthRatioDefault
                readonly property real joySlotW: Math.max(0, Math.min(width - gap, width * leftWidthRatio))
                readonly property real joyCardWidth: Math.max(0, joySlotW)
                readonly property real joyCardHeight: Math.max(0, dashboardHeight)
                readonly property real gridW: Math.max(0, width - joySlotW - gap)
                readonly property real gridH: dashboardHeight
                readonly property real cellSize: Math.max(0, Math.min((gridW - gap) / 2, (dashboardHeight - gap) / 2))
                readonly property real gridContentW: cellSize * 2 + gap
                readonly property real gridContentH: cellSize * 2 + gap
                readonly property real gridOffsetX: Math.max(0, (gridW - gridContentW) / 2)
                readonly property real gridOffsetY: Math.max(0, (dashboardHeight - gridContentH) / 2)
                readonly property real cardScale: cellSize / Constants.homeCardDesignSize
                readonly property real joyCardScale: Math.min(joyCardWidth, joyCardHeight) / Constants.homeCardDesignSize
                readonly property real cardMargin: Math.max(Constants.downloadToolCardMarginMin,
                                                            Constants.downloadToolCardMargin * cardScale)
                readonly property real joyCardMargin: Math.max(Constants.downloadToolCardMarginMin,
                                                               Constants.downloadToolCardMargin * joyCardScale)
                readonly property real cardHeaderHeight: Math.max(Constants.downloadToolCardHeaderMinHeight,
                                                                  Constants.downloadToolCardHeaderHeight * cardScale)
                readonly property real joyCardHeaderHeight: Math.max(Constants.downloadToolCardHeaderMinHeight,
                                                                     Constants.downloadToolCardHeaderHeight * joyCardScale)
                readonly property real cardHeaderGap: Math.max(Constants.downloadToolCardHeaderGapMin,
                                                               Constants.downloadToolCardHeaderGap * cardScale)
                readonly property real cardTitleFont: Math.max(Constants.downloadToolCardTitleMinFontSize,
                                                               Constants.downloadToolCardTitleFontSize * cardScale)
                readonly property real cardControlFont: Math.max(12, 13 * cardScale)
                readonly property real cardBodyFont: Math.max(13, 15 * cardScale)
                readonly property real cardValueFont: Math.max(14, 16 * cardScale)
                readonly property real cardMetaFont: Math.max(11, 12 * cardScale)

                AluminumPanel {
                    id: joyPrev
                    x: 0
                    y: 0
                    panelWidth: dtViewport.joyCardWidth
                    panelHeight: dtViewport.joyCardHeight
                    borderRadius: 32
                    contentMargins: dtViewport.joyCardMargin

                    Item {
                        anchors.fill: parent

                        Text {
                            id: joyHeader
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: dtViewport.joyCardHeaderHeight
                            text: "XY 轴 (BJM)"
                            color: dtTextSec
                            font.pixelSize: Math.max(12, 14 * dtViewport.joyCardScale)
                            font.weight: Font.Bold
                            font.letterSpacing: 0
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }

                        Item {
                            id: joystickArea
                            anchors.top: joyHeader.bottom
                            anchors.topMargin: 8 * dtViewport.joyCardScale
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom

                            property real gap: 8 * dtViewport.joyCardScale
                            property real sideW: 50 * dtViewport.joyCardScale
                            property real axisH: 20 * dtViewport.joyCardScale
                            property real botH: axisH + gap
                            property real joySize: Math.max(1, Math.min(width - sideW - gap,
                                                                        height - botH - gap))

                            JoystickPad {
                                id: joystick
                                anchors.top: parent.top
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.horizontalCenterOffset: -parent.sideW / 2
                                padSize: parent.joySize
                                width: padSize
                                height: padSize
                                xValue: 0
                                yValue: 0
                                enabled: false
                            }

                            ColumnLayout {
                                anchors.top: joystick.top
                                anchors.bottom: joystick.bottom
                                anchors.left: joystick.right
                                anchors.leftMargin: parent.gap
                                width: parent.sideW
                                spacing: 4 * dtViewport.joyCardScale

                                AxisValueBar {
                                    Layout.fillHeight: true
                                    Layout.alignment: Qt.AlignHCenter
                                    width: 12 * dtViewport.joyCardScale
                                    orientation: "vertical"
                                    value: 0
                                    active: false
                                    label: "Y"
                                }
                            }

                            RowLayout {
                                anchors.top: joystick.bottom
                                anchors.topMargin: parent.gap
                                anchors.left: joystick.left
                                anchors.right: joystick.right
                                height: parent.axisH
                                spacing: 8 * dtViewport.joyCardScale

                                AxisValueBar {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    height: 12 * dtViewport.joyCardScale
                                    orientation: "horizontal"
                                    value: 0
                                    active: false
                                    label: "X"
                                }
                            }
                        }
                    }
                }

                Item {
                    id: gridArea
                    x: dtViewport.joySlotW + dtViewport.gap
                    y: 0
                    width: dtViewport.gridW
                    height: dtViewport.gridH

                    property real cellSize: dtViewport.cellSize

                    Repeater {
                        id: cellRepeater; model: 4

                        AluminumPanel {
                            id: cellCard
                            x: dtViewport.gridOffsetX + (index % 2) * (gridArea.cellSize + dtViewport.gap)
                            y: dtViewport.gridOffsetY + Math.floor(index / 2) * (gridArea.cellSize + dtViewport.gap)
                            panelWidth: gridArea.cellSize
                            panelHeight: gridArea.cellSize
                            borderRadius: Math.max(8, Constants.radiusPanel * dtViewport.cardScale)
                            contentMargins: 0
                            z: activeCellIndex === index ? 10 : 0

                            property string cellTitle: ""
                            property string cellType: "empty"
                            property var cellCompIds: []
                            property int canvasDesignWidth: root.defaultCanvasWidth
                            property int canvasDesignHeight: root.defaultCanvasHeight
                            property string canvasScaleMode: "uniform"
                            property int cellIndex: index
                            property bool titleEditing: false
                            property bool productDescriptionEditing: false
                            property string productDescriptionDraft: ""
                            property string productDescriptionOriginal: ""
                            property alias canvasItem: cvLoader.item

                            onCellTitleChanged: {
                                if (!titleEditing)
                                    syncTitleEditor()
                            }
                            onCellTypeChanged: {
                                if (!titleEditing)
                                    syncTitleEditor()
                            }

                            function syncTitleEditor() {
                                titleEditor.text = root.normalizedCellTitle(cellIndex, cellType, cellTitle)
                            }

                            function beginTitleEdit() {
                                root.commitCellEdits(cellIndex)
                                commitProductDescriptionEdit()
                                activeCellIndex = cellIndex
                                syncTitleEditor()
                                titleEditing = true
                                titleEditor.forceActiveFocus()
                                titleEditor.selectAll()
                            }

                            function commitTitleEdit() {
                                if (titleEditing)
                                    titleEditor.commitTitle()
                            }

                            function cancelTitleEdit() {
                                titleEditing = false
                                syncTitleEditor()
                                titleEditor.focus = false
                            }

                            function beginProductDescriptionEdit() {
                                root.commitCellEdits(cellIndex)
                                commitTitleEdit()
                                activeCellIndex = cellIndex
                                productDescriptionOriginal = root.productDescriptionText()
                                productDescriptionDraft = productDescriptionOriginal
                                productDescriptionEditing = true
                            }

                            function commitProductDescriptionEdit() {
                                if (!productDescriptionEditing)
                                    return
                                root.setProductDescription(productDescriptionDraft)
                                productDescriptionEditing = false
                            }

                            function cancelProductDescriptionEdit() {
                                productDescriptionDraft = productDescriptionOriginal
                                productDescriptionEditing = false
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: cellCard.borderRadius
                                color: "transparent"
                                border.width: activeCellIndex === index ? 2 : 0
                                border.color: dtAccent
                                z: 30
                            }

                            MouseArea {
                                anchors.fill: parent
                                z: -1
                                onClicked: {
                                    root.commitCellEdits(-1)
                                    activeCellIndex = index
                                }
                            }

                            Item {
                                id: cellContent
                                anchors.fill: parent
                                anchors.margins: cellCard.cellType === "canvas" ? 0 : dtViewport.cardMargin

                                Row {
                                    id: hdr
                                    anchors.top: parent.top
                                    anchors.topMargin: cellCard.cellType === "canvas" ? dtViewport.cardMargin : 0
                                    anchors.left: parent.left
                                    anchors.leftMargin: cellCard.cellType === "canvas" ? dtViewport.cardMargin : 0
                                    anchors.right: parent.right
                                    anchors.rightMargin: cellCard.cellType === "canvas" ? dtViewport.cardMargin : 0
                                    height: dtViewport.cardHeaderHeight; spacing: 4 * dtViewport.cardScale
                                    z: 20

                                    Item {
                                        id: titleSlot
                                        width: Math.max(1, parent.width - typeSelector.width - 6)
                                        height: parent.height
                                        clip: true
                                        anchors.verticalCenter: parent.verticalCenter

                                        Item {
                                            id: titleLabelGroup
                                            visible: !cellCard.titleEditing
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: Math.min(parent.width, titleLabel.implicitWidth + 10)
                                            height: parent.height
                                            clip: true

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 4
                                                visible: cellCard.cellType === "canvas"
                                                color: "#eaeaec"
                                                opacity: 0.95
                                            }

                                            Text {
                                                id: titleLabel
                                                anchors.left: parent.left
                                                anchors.leftMargin: cellCard.cellType === "canvas" ? 5 : 0
                                                anchors.right: parent.right
                                                anchors.rightMargin: cellCard.cellType === "canvas" ? 5 : 0
                                                anchors.verticalCenter: parent.verticalCenter
                                                height: parent.height
                                                text: root.normalizedCellTitle(cellCard.cellIndex, cellCard.cellType, cellCard.cellTitle)
                                                color: dtTextSec
                                                font.pixelSize: dtViewport.cardTitleFont
                                                font.weight: Font.Bold
                                                font.letterSpacing: 0
                                                elide: Text.ElideRight
                                                verticalAlignment: Text.AlignVCenter
                                                clip: true
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.IBeamCursor
                                                onClicked: cellCard.beginTitleEdit()
                                            }
                                        }

                                        Rectangle {
                                            id: titleEditFrame
                                            anchors.fill: parent
                                            visible: cellCard.titleEditing
                                            color: "white"
                                            radius: 5
                                            border.width: titleEditor.activeFocus ? 1 : 0
                                            border.color: dtAccent
                                        }

                                        TextInput {
                                            id: titleEditor
                                            anchors.fill: titleEditFrame
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 6
                                            anchors.topMargin: 1
                                            anchors.bottomMargin: 1
                                            visible: cellCard.titleEditing
                                            clip: true
                                            color: dtTextSec
                                            selectionColor: dtAccent
                                            selectedTextColor: "white"
                                            font.pixelSize: dtViewport.cardTitleFont
                                            font.weight: Font.Bold
                                            font.letterSpacing: 0
                                            horizontalAlignment: TextInput.AlignLeft
                                            verticalAlignment: TextInput.AlignVCenter
                                            selectByMouse: true

                                            function commitTitle() {
                                                root.setCellTitle(cellCard, root.normalizedCellTitle(cellCard.cellIndex, cellCard.cellType, text))
                                                cellCard.titleEditing = false
                                                cellCard.syncTitleEditor()
                                                focus = false
                                            }

                                            onAccepted: commitTitle()
                                            onEditingFinished: {
                                                if (cellCard.titleEditing)
                                                    commitTitle()
                                            }
                                            onActiveFocusChanged: {
                                                if (!activeFocus && cellCard.titleEditing)
                                                    commitTitle()
                                            }
                                            Keys.onEscapePressed: function(event) {
                                                cellCard.cancelTitleEdit()
                                                event.accepted = true
                                            }
                                            Component.onCompleted: cellCard.syncTitleEditor()
                                        }
                                    }

                                    Rectangle {
                                        id: typeSelector
                                        width: Math.max(88, 96 * dtViewport.cardScale)
                                        height: Math.max(30, 32 * dtViewport.cardScale)
                                        radius: 4
                                        color: "#f5f5f7"
                                        border.width: 1
                                        border.color: typeMouse.containsMouse ? dtAccent : "#8e8e93"
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            anchors.left: parent.left
                                            anchors.leftMargin: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: root.labelForCellType(cellCard.cellType)
                                            color: dtText
                                            font.pixelSize: dtViewport.cardControlFont
                                            font.bold: true
                                            width: parent.width - 34
                                            elide: Text.ElideRight
                                        }

                                        Canvas {
                                            width: 12; height: 8
                                            anchors.right: parent.right
                                            anchors.rightMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            onPaint: {
                                                var ctx = getContext("2d")
                                                ctx.clearRect(0, 0, width, height)
                                                ctx.fillStyle = dtText
                                                ctx.beginPath()
                                                ctx.moveTo(0, 0)
                                                ctx.lineTo(width, 0)
                                                ctx.lineTo(width / 2, height)
                                                ctx.closePath()
                                                ctx.fill()
                                            }
                                        }

                                        MouseArea {
                                            id: typeMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.commitCellEdits(index)
                                                cellCard.commitTitleEdit()
                                                cellCard.commitProductDescriptionEdit()
                                                activeCellIndex = index
                                                cellTypePopup.openFor(cellCard, typeSelector)
                                            }
                                        }
                                    }
                                }

                                Item {
                                    id: body
                                    anchors.top: cellCard.cellType === "canvas" ? parent.top : hdr.bottom
                                    anchors.topMargin: cellCard.cellType === "canvas" ? 0 : dtViewport.cardHeaderGap
                                    anchors.left: parent.left; anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    z: cellCard.cellType === "canvas" ? 0 : 1

                                    ColumnLayout {
                                        id: busStatsPanel
                                        visible: cellCard.cellType === "busStats"
                                        anchors.fill: parent
                                        spacing: Math.max(7, 9 * dtViewport.cardScale)
                                        clip: true

                                        readonly property int messageCount: ((currentConfig.can || {}).messages || []).length

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            Text {
                                                text: "总线统计"
                                                color: dtText
                                                font.pixelSize: Math.max(18, 21 * dtViewport.cardScale)
                                                font.weight: Font.Bold
                                                font.letterSpacing: 0
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                text: "--%"
                                                color: dtTextSec
                                                font.pixelSize: Math.max(15, 18 * dtViewport.cardScale)
                                                font.weight: Font.Bold
                                                font.family: "Consolas"
                                                font.letterSpacing: 0
                                                Layout.alignment: Qt.AlignVCenter
                                            }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 1
                                            color: dtBorder
                                            opacity: 0.75
                                        }

                                        Repeater {
                                            model: [
                                                { label: "总线负载", value: "--%" },
                                                { label: "Rx FPS", value: "-- fps" },
                                                { label: "Count", value: "0" },
                                                { label: "匹配报文", value: "0/" + busStatsPanel.messageCount },
                                                { label: "平均间隔", value: "--" },
                                                { label: "最小/最大", value: "-- / --" }
                                            ]

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 8

                                                Text {
                                                    text: modelData.label
                                                    color: dtTextSec
                                                    font.pixelSize: Math.max(11, 12 * dtViewport.cardScale)
                                                    font.weight: Font.DemiBold
                                                    font.letterSpacing: 0
                                                    width: Math.max(70, 78 * dtViewport.cardScale)
                                                    elide: Text.ElideRight
                                                    Layout.alignment: Qt.AlignVCenter
                                                }

                                                Text {
                                                    text: modelData.value
                                                    color: dtTextMuted
                                                    font.pixelSize: Math.max(11, 12 * dtViewport.cardScale)
                                                    font.weight: Font.DemiBold
                                                    font.family: "Consolas"
                                                    font.letterSpacing: 0
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                            }
                                        }
                                    }

                                    Column {
                                        id: recordInfoPanel
                                        visible: cellCard.cellType === "recordInfo"
                                        anchors.fill: parent
                                        z: cellCard.productDescriptionEditing ? 30 : 0
                                        spacing: Math.max(6, 8 * dtViewport.cardScale)
                                        clip: true

                                        readonly property var rows: [
                                            { label: "产品型号", val: currentConfig.product ? currentConfig.product.name || currentConfig.product.model || "---" : "---" },
                                            { label: "通信协议", val: currentConfig.product ? String(currentConfig.product.protocol || "j1939").toUpperCase() : "---" },
                                            { label: "CAN地址", val: root.productAddressText() },
                                            { label: "产品描述", val: "", multiline: true, editableDescription: true }
                                        ]
                                        readonly property real gapHeight: spacing * Math.max(0, rows.length - 1)
                                        readonly property real rowUnitHeight: Math.max(12, (height - gapHeight) / rowUnits())

                                        function rowUnits() {
                                            var total = 0
                                            for (var i = 0; i < rows.length; i++)
                                                total += rows[i].multiline ? 2 : 1
                                            return Math.max(1, total)
                                        }

                                        Repeater {
                                            model: recordInfoPanel.rows
                                            Row {
                                                width: parent ? parent.width : 0
                                                height: recordInfoPanel.rowUnitHeight * (modelData.multiline ? 2 : 1)
                                                spacing: Math.max(8, 10 * dtViewport.cardScale)
                                                Text {
                                                    id: recordInfoLabel
                                                    text: modelData.label + "："
                                                    color: dtTextSec
                                                    font.pixelSize: dtViewport.cardBodyFont
                                                    fontSizeMode: Text.HorizontalFit
                                                    minimumPixelSize: Math.max(8, dtViewport.cardMetaFont)
                                                    width: Math.max(76, 82 * dtViewport.cardScale)
                                                    horizontalAlignment: Text.AlignRight
                                                    height: parent.height
                                                    verticalAlignment: Text.AlignVCenter
                                                }
                                                Item {
                                                    id: recordInfoValueSlot
                                                    width: Math.max(1, parent.width - recordInfoLabel.width - parent.spacing)
                                                    height: parent.height
                                                    clip: true

                                                    Text {
                                                        id: recordInfoValue
                                                        anchors.fill: parent
                                                        visible: !modelData.editableDescription
                                                        text: modelData.val
                                                        color: dtAccent
                                                        font.pixelSize: dtViewport.cardValueFont
                                                        fontSizeMode: Text.Fit
                                                        minimumPixelSize: Math.max(8, dtViewport.cardMetaFont)
                                                        font.bold: true
                                                        elide: Text.ElideNone
                                                        wrapMode: Text.WrapAnywhere
                                                        verticalAlignment: Text.AlignVCenter
                                                    }

                                                    Text {
                                                        id: productDescriptionLabel
                                                        anchors.fill: parent
                                                        visible: modelData.editableDescription === true && !cellCard.productDescriptionEditing
                                                        text: root.productDescriptionText() !== "" ? root.productDescriptionText() : "---"
                                                        color: dtAccent
                                                        font.pixelSize: dtViewport.cardValueFont
                                                        fontSizeMode: Text.Fit
                                                        minimumPixelSize: Math.max(8, dtViewport.cardMetaFont)
                                                        font.bold: true
                                                        elide: Text.ElideNone
                                                        wrapMode: Text.WrapAnywhere
                                                        verticalAlignment: Text.AlignVCenter

                                                        MouseArea {
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.IBeamCursor
                                                            onClicked: {
                                                                cellCard.beginProductDescriptionEdit()
                                                            }
                                                        }
                                                    }

                                                    Rectangle {
                                                        id: descriptionEditFrame
                                                        anchors.fill: parent
                                                        visible: modelData.editableDescription === true && cellCard.productDescriptionEditing
                                                        z: 10
                                                        radius: 4
                                                        color: "white"
                                                        border.width: descriptionEdit.activeFocus ? 1 : 0
                                                        border.color: dtAccent
                                                        clip: true

                                                        TextEdit {
                                                            id: descriptionEdit
                                                            anchors.fill: parent
                                                            anchors.margins: 5
                                                            clip: true
                                                            wrapMode: TextEdit.WrapAnywhere
                                                            selectByMouse: true
                                                            color: dtAccent
                                                            font.pixelSize: Math.max(10, dtViewport.cardValueFont - 1)
                                                            font.bold: true
                                                            textFormat: TextEdit.PlainText
                                                            text: cellCard.productDescriptionDraft

                                                            onVisibleChanged: {
                                                                if (visible) {
                                                                    forceActiveFocus()
                                                                    selectAll()
                                                                } else {
                                                                    focus = false
                                                                }
                                                            }
                                                            onTextChanged: {
                                                                if (descriptionEditFrame.visible)
                                                                    cellCard.productDescriptionDraft = text
                                                            }
                                                            onActiveFocusChanged: {
                                                                if (!activeFocus && cellCard.productDescriptionEditing)
                                                                    cellCard.commitProductDescriptionEdit()
                                                            }
                                                            Keys.onEscapePressed: function(event) {
                                                                cellCard.cancelProductDescriptionEdit()
                                                                event.accepted = true
                                                            }
                                                            Keys.onPressed: function(event) {
                                                                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                                                    cellCard.commitProductDescriptionEdit()
                                                                    event.accepted = true
                                                                }
                                                            }
                                                        }

                                                        Text {
                                                            anchors.left: descriptionEdit.left
                                                            anchors.right: descriptionEdit.right
                                                            anchors.top: descriptionEdit.top
                                                            visible: descriptionEdit.text.length === 0
                                                            text: "请输入产品描述"
                                                            color: dtTextMuted
                                                            font.pixelSize: descriptionEdit.font.pixelSize
                                                            font.bold: true
                                                            elide: Text.ElideRight
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        z: 20
                                        visible: cellCard.productDescriptionEditing
                                        enabled: visible
                                        onClicked: cellCard.commitProductDescriptionEdit()
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        z: 50
                                        visible: cellCard.titleEditing
                                        enabled: visible
                                        onClicked: cellCard.commitTitleEdit()
                                    }

                                    Item {
                                        id: canvasViewport
                                        anchors.fill: parent
                                        visible: cellCard.cellType === "canvas"
                                        clip: true

                                        readonly property real displayCanvasWidth: Math.max(1, width)
                                        readonly property real displayCanvasHeight: Math.max(1, height)

                                        Loader {
                                            id: cvLoader
                                            active: true
                                            anchors.fill: parent
                                            sourceComponent: DesignCanvas {
                                                panelWidth: canvasViewport.displayCanvasWidth
                                                panelHeight: canvasViewport.displayCanvasHeight
                                                borderRadius: Constants.radiusPanel
                                                panelChromeVisible: false
                                                canvasWidth: cellCard.canvasDesignWidth
                                                canvasHeight: cellCard.canvasDesignHeight
                                                scaleMode: cellCard.canvasScaleMode
                                                productBindings: currentConfig.components || []
                                                onCanvasPressed: {
                                                    root.activeCellIndex = index
                                                }
                                                onLayoutModified: {
                                                    if (!root.loadingCells)
                                                        hasUnsavedChanges = true
                                                    root.refreshBindingStatus()
                                                }
                                            }
                                        }
                                    }

                                    Text { visible: cellCard.cellType === "empty"; anchors.centerIn: parent; text: "空白"; color: dtTextMuted; font.pixelSize: 10 }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: componentDock
                    x: 0
                    y: dtViewport.dashboardHeight + dtViewport.gap
                    width: parent.width
                    height: Math.max(120, parent.height - y)
                    radius: 24
                    color: "#eaeaec"
                    border.width: 1
                    border.color: dtBorder
                    clip: true

                    ComponentPanel {
                        id: componentPanel
                        anchors.fill: parent
                        anchors.margins: Math.max(10, 16 * dtViewport.cardScale)
                        panelWidth: width
                        visible: root.isCanvasMode
                        neuBg: dtBg
                        neuLightShadow: "#ffffff"
                        neuDarkShadow: dtBorder
                        neuSurface: "white"
                        neuTextPrimary: dtText
                        neuTextSecondary: dtTextSec
                        neuAccent: dtAccent

                        onComponentRequested: function(ct) {
                            var cell = root.activeCanvasCell()
                            if (!cell || !cell.canvasItem) return
                            var size = ComponentRegistry.getDefaultSize(ct)
                            var cfg = ComponentRegistry.getDefaultConfig(ct)
                            cell.canvasItem.addComponent(ct,
                                                         (cell.canvasItem.canvasWidth - size.width) / 2,
                                                         (cell.canvasItem.canvasHeight - size.height) / 2,
                                                         cfg)
                            hasUnsavedChanges = true
                            refreshBindingStatus()
                        }

                        onComponentDragStarted: function(ct,gx,gy) {
                            dp.componentType = ct
                            dp.visible = true
                            var p = root.mapFromGlobal(gx, gy)
                            dp.x = p.x - dp.width / 2
                            dp.y = p.y - dp.height / 2
                        }

                        onComponentDragMoved: function(gx,gy) {
                            var p = root.mapFromGlobal(gx, gy)
                            dp.x = p.x - dp.width / 2
                            dp.y = p.y - dp.height / 2
                        }

                        onComponentDragEnded: function(gx,gy) {
                            dp.visible = false
                            for (var i = 0; i < cellRepeater.count; i++) {
                                var cell = cellRepeater.itemAt(i)
                                if (!cell || cell.cellType !== "canvas" || !cell.canvasItem) continue
                                var displayPos = cell.canvasItem.mapFromGlobal(gx, gy)
                                if (displayPos.x >= 0 && displayPos.x <= cell.canvasItem.width
                                        && displayPos.y >= 0 && displayPos.y <= cell.canvasItem.height) {
                                    activeCellIndex = i
                                    var pos = cell.canvasItem.displayToCanvasPoint(displayPos.x, displayPos.y)
                                    var size = ComponentRegistry.getDefaultSize(dp.componentType)
                                    var cfg = ComponentRegistry.getDefaultConfig(dp.componentType)
                                    cell.canvasItem.addComponent(dp.componentType,
                                                                 pos.x - size.width / 2,
                                                                 pos.y - size.height / 2,
                                                                 cfg)
                                    hasUnsavedChanges = true
                                    refreshBindingStatus()
                                    return
                                }
                            }
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 8
                        width: Math.min(parent.width - 32, 320)
                        visible: !root.isCanvasMode

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "组件面板"
                            font.pixelSize: 13
                            font.bold: true
                            color: dtText
                        }
                        Rectangle { width: parent.width; height: 1; color: dtBorder }
                        Label {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                            text: "选择「画布」类型的卡片后可拖放组件"
                            font.pixelSize: 10
                            color: dtTextSec
                            lineHeight: 1.4
                        }
                    }
                }
            }
        }

    }

    Popup {
        id: cloneProductPopup
        parent: root
        width: Math.min(520, root.width - 32)
        height: Math.min(root.height - 32, cloneProductContent.implicitHeight + 32)
        x: Math.max(16, (root.width - width) / 2)
        y: Math.max(16, (root.height - height) / 2)
        padding: 16
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        z: 10000

        background: Rectangle {
            radius: 8
            color: "white"
            border.width: 1
            border.color: dtBorder
        }

        contentItem: ColumnLayout {
            id: cloneProductContent
            spacing: 10

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 10
                rowSpacing: 8

                Label { text: "型号"; color: dtText; font.pixelSize: 11 }
                TextField {
                    id: cloneModelField
                    Layout.fillWidth: true
                    readOnly: cloneProductCreatesVersion
                    selectByMouse: true
                    font.pixelSize: 11
                    onTextChanged: cloneProductError = ""
                }

                Label { text: "版本"; color: dtText; font.pixelSize: 11 }
                TextField {
                    id: cloneVersionField
                    Layout.fillWidth: true
                    selectByMouse: true
                    font.pixelSize: 11
                    onTextChanged: cloneProductError = ""
                }

                Label { text: "描述"; color: dtText; font.pixelSize: 11 }
                TextArea {
                    id: cloneDescriptionArea
                    Layout.fillWidth: true
                    Layout.preferredHeight: 58
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    font.pixelSize: 11
                }

                Label { text: "客户"; color: dtText; font.pixelSize: 11 }
                ComboBox {
                    id: cloneCustomerBox
                    Layout.fillWidth: true
                    model: cloneCustomerModel
                    textRole: "label"
                    valueRole: "value"
                    editable: true
                    currentIndex: -1
                    font.pixelSize: 11
                    onActivated: root.cloneProductError = ""
                    onEditTextChanged: root.cloneProductError = ""
                }

                Label {
                    text: "按钮数量"
                    color: dtText
                    font.pixelSize: 11
                    visible: !cloneProductCreatesVersion
                }
                SpinBox {
                    id: cloneButtonCountBox
                    Layout.fillWidth: true
                    from: 0
                    to: 12
                    value: 10
                    editable: true
                    visible: !cloneProductCreatesVersion
                    font.pixelSize: 11
                    onValueChanged: root.cloneProductError = ""
                }

                Label {
                    text: "按钮编号"
                    color: dtText
                    font.pixelSize: 11
                    visible: !cloneProductCreatesVersion
                }
                TextField {
                    id: cloneButtonNumbersField
                    Layout.fillWidth: true
                    placeholderText: "留空为1到按钮数量；例如 2,3,8"
                    visible: !cloneProductCreatesVersion
                    font.pixelSize: 11
                    onTextChanged: root.cloneProductError = ""
                }

                Label {
                    text: "滚轮数量"
                    color: dtText
                    font.pixelSize: 11
                    visible: !cloneProductCreatesVersion
                }
                SpinBox {
                    id: cloneRollerCountBox
                    Layout.fillWidth: true
                    from: 0
                    to: 4
                    value: 4
                    editable: true
                    visible: !cloneProductCreatesVersion
                    font.pixelSize: 11
                    onValueChanged: root.cloneProductError = ""
                }

                Label { text: "校准模式"; color: dtText; font.pixelSize: 11 }
                ComboBox {
                    id: cloneCalibrationModeBox
                    Layout.fillWidth: true
                    model: cloneCalibrationModeOptions
                    textRole: "label"
                    valueRole: "value"
                    font.pixelSize: 11
                }

                Label { text: "CAN波特率"; color: root.dtText; font.pixelSize: 11 }
                ComboBox {
                    id: cloneBaudRateBox
                    Layout.fillWidth: true
                    model: cloneBaudRateModel
                    textRole: "label"
                    valueRole: "value"
                    font.pixelSize: 11
                    onActivated: root.cloneProductError = ""
                }

                Label {
                    Layout.columnSpan: 2
                    Layout.fillWidth: true
                    text: cloneProductCreatesVersion
                          ? "新版本会完整保留当前产品的报文解析、组件和布局。"
                          : "默认生成 J1939 通用解析：BJM 轴/按钮、EJM 滚轮和地址声明；非通用报文保存后直接修改 JSON。"
                    color: root.dtTextSec
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }

            }

            Label {
                Layout.fillWidth: true
                visible: cloneProductError.length > 0
                text: cloneProductError
                color: "#d70015"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button {
                    text: "取消"
                    font.pixelSize: 11
                    onClicked: cloneProductPopup.close()
                }
                Button {
                    text: cloneProductCreatesVersion ? "保存新版本" : "保存新产品"
                    font.pixelSize: 11
                    palette.button: dtAccent
                    palette.buttonText: "white"
                    onClicked: saveCloneProduct()
                }
            }
        }
    }

    Popup {
        id: cellTypePopup
        parent: root
        width: 124
        height: typePopupContent.implicitHeight + 8
        padding: 4
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        z: 10000

        property var targetCell: null

        background: Rectangle {
            radius: 6
            color: "white"
            border.width: 1
            border.color: dtBorder
        }

        contentItem: Column {
            id: typePopupContent
            spacing: 2
            Repeater {
                model: cellTypeOptions
                delegate: Rectangle {
                    width: cellTypePopup.width - 8
                    height: 32
                    radius: 4
                    color: typeChoiceMouse.containsMouse ? "#e8f0fe" : "transparent"

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        color: dtText
                        font.pixelSize: dtViewport.cardControlFont
                        font.bold: cellTypePopup.targetCell && cellTypePopup.targetCell.cellType === modelData.value
                    }

                    MouseArea {
                        id: typeChoiceMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.commitCellEdits(-1)
                            root.setCellType(cellTypePopup.targetCell, modelData.value)
                            cellTypePopup.close()
                        }
                    }
                }
            }
        }

        function openFor(cell, anchorItem) {
            targetCell = cell
            var pos = anchorItem.mapToItem(root, 0, anchorItem.height + 4)
            x = Math.max(8, Math.min(pos.x, root.width - width - 8))
            y = Math.max(8, Math.min(pos.y, root.height - height - 8))
            open()
        }
    }

    // Drag proxy
    Item {
        id: dp
        visible: false
        z: 9999
        opacity: 0.88

        property string componentType: ""
        property real thumbScale: 0.55

        width: dpThumbLoader.item ? dpThumbLoader.item.width * thumbScale + 12 : 60
        height: dpThumbLoader.item ? dpThumbLoader.item.height * thumbScale + 12 : 60

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: "#f8f8fa"
            border.width: 1
            border.color: dtAccent

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#26000000"
                shadowBlur: 0.35
                shadowVerticalOffset: 4
            }
        }

        Item {
            anchors.centerIn: parent
            width: dpThumbLoader.item ? dpThumbLoader.item.width : 0
            height: dpThumbLoader.item ? dpThumbLoader.item.height : 0
            scale: dp.thumbScale
            enabled: false

            Loader {
                id: dpThumbLoader
                active: dp.visible
                sourceComponent: {
                    var t = dp.componentType
                    if (t.indexOf("Button") === 0) return dpButtonComp
                    if (t === "FNRSwitch") return dpFNRComp
                    if (t === "VerticalRoller") return dpVRollerComp
                    if (t === "HorizontalRoller") return dpHRollerComp
                    if (t === "RotaryPotentiometer") return dpPotentiometerComp
                    if (t === "HorizontalFNR") return dpHFNRComp
                    if (t === "HorizontalFNRRight") return dpHFNRRightComp
                    return null
                }
                onLoaded: root.applyDragThumbConfig(item, dp.componentType)
            }
        }
    }

    Component { id: dpButtonComp; IndustrialButton {} }
    Component { id: dpFNRComp; FNRSwitchUnit {} }
    Component { id: dpVRollerComp; VerticalRollerUnit {} }
    Component { id: dpHRollerComp; HorizontalRollerUnit {} }
    Component { id: dpPotentiometerComp; RotaryPotentiometerUnit {} }
    Component { id: dpHFNRComp; HorizontalFNRUnit {} }
    Component { id: dpHFNRRightComp; HorizontalFNRRightUnit {} }

    function applyDragThumbConfig(item, type) {
        if (!item)
            return
        var defaultConfig = ComponentRegistry.getDefaultConfig(type)
        for (var key in defaultConfig) {
            if (item.hasOwnProperty(key))
                item[key] = defaultConfig[key]
        }

        var defaultSize = ComponentRegistry.getDefaultSize(type)
        if (defaultSize.width > 0)
            item.width = defaultSize.width
        if (defaultSize.height > 0)
            item.height = defaultSize.height
    }

    Shortcut { sequence: "Ctrl+S"; onActivated: saveProduct() }
}
