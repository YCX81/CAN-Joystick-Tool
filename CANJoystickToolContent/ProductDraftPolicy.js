.pragma library

function firstText(object, keys) {
    object = object || {}
    for (var i = 0; i < keys.length; ++i) {
        var value = object[keys[i]]
        if (value !== undefined && value !== null
                && String(value).trim().length > 0) {
            return String(value).trim()
        }
    }
    return ""
}

function productIdentity(config) {
    config = config || {}
    var product = config.product || {}
    return firstText(product, ["code", "name", "model"])
            || firstText(config, ["productCode", "name", "model"])
}

function versionIdentity(config) {
    config = config || {}
    var product = config.product || {}
    var firmware = config.firmware || {}
    return firstText(product, ["version"])
            || firstText(firmware, [
                "display_version",
                "displayVersion",
                "version_code",
                "versionCode",
                "variant_code",
                "variantCode",
                "version"
            ])
            || firstText(config, ["version"])
}

function normalized(value) {
    return String(value || "").trim().toUpperCase()
}

function compatibility(officialConfig, draftConfig) {
    officialConfig = officialConfig || {}
    draftConfig = draftConfig || {}

    var officialSchema = Number(officialConfig.schemaVersion || 0)
    var draftSchema = Number(draftConfig.schemaVersion || 0)
    if (officialSchema <= 0 || draftSchema <= 0
            || officialSchema !== draftSchema) {
        return {
            compatible: false,
            reason: "schemaMismatch"
        }
    }

    var officialProduct = normalized(productIdentity(officialConfig))
    var draftProduct = normalized(productIdentity(draftConfig))
    if (!officialProduct || !draftProduct) {
        return {
            compatible: false,
            reason: "missingIdentity"
        }
    }
    if (officialProduct !== draftProduct) {
        return {
            compatible: false,
            reason: "productMismatch"
        }
    }

    var officialVersion = normalized(versionIdentity(officialConfig))
    var draftVersion = normalized(versionIdentity(draftConfig))
    if ((officialVersion || draftVersion)
            && officialVersion !== draftVersion) {
        return {
            compatible: false,
            reason: "versionMismatch"
        }
    }

    return {
        compatible: true,
        reason: "",
        product: officialProduct,
        version: officialVersion,
        schemaVersion: officialSchema
    }
}
