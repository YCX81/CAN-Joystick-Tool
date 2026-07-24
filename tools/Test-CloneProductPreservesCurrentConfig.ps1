param(
    [string]$ProductEditorPath = (Join-Path $PSScriptRoot '..\CANJoystickToolContent\ProductEditor.qml'),
    [string]$LayoutManagerPath = (Join-Path $PSScriptRoot '..\LayoutManager.cpp'),
    [string]$DesignCanvasPath = (Join-Path $PSScriptRoot '..\CANJoystickTool\DesignCanvas.qml')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ProductEditorPath)) {
    throw "ProductEditor.qml not found: $ProductEditorPath"
}
if (-not (Test-Path -LiteralPath $LayoutManagerPath)) {
    throw "LayoutManager.cpp not found: $LayoutManagerPath"
}
if (-not (Test-Path -LiteralPath $DesignCanvasPath)) {
    throw "DesignCanvas.qml not found: $DesignCanvasPath"
}

$content = Get-Content -Raw -LiteralPath $ProductEditorPath
$layoutManagerContent = Get-Content -Raw -LiteralPath $LayoutManagerPath
$designCanvasContent = Get-Content -Raw -LiteralPath $DesignCanvasPath

if ($content -notmatch '(?s)function\s+applyCloneMetadata\s*\([^)]*\).*?function\s+saveCloneProduct\s*\(') {
    throw 'Missing applyCloneMetadata helper before saveCloneProduct().'
}

if ($content -notmatch 'protocol:\s*"j1939"') {
    throw 'defaultProductConfig() must default to J1939.'
}

if ($content -notmatch 'sourceAddress:\s*"0x33"') {
    throw 'defaultProductConfig() must include a J1939 sourceAddress.'
}

if ($content -notmatch 'canFrameFormat:\s*"extended"') {
    throw 'defaultProductConfig() must use extended CAN frame format for J1939.'
}

if ($layoutManagerContent -notmatch 'product\.insert\(QStringLiteral\("protocol"\),\s*QStringLiteral\("j1939"\)\)') {
    throw 'buildStandardProductConfig() must default to J1939.'
}

if ($layoutManagerContent -notmatch 'product\.insert\(QStringLiteral\("sourceAddress"\),\s*QStringLiteral\("0x33"\)\)') {
    throw 'buildStandardProductConfig() must include a J1939 sourceAddress.'
}

if ($layoutManagerContent -notmatch 'product\.insert\(QStringLiteral\("canFrameFormat"\),\s*QStringLiteral\("extended"\)\)') {
    throw 'buildStandardProductConfig() must use extended CAN frame format for J1939.'
}

$match = [regex]::Match($content, '(?s)function\s+buildClonedProductConfig\s*\(\)\s*\{(?<body>.*?)\n\s*function\s+saveCloneProduct\s*\(')
if (-not $match.Success) {
    throw 'Could not locate buildClonedProductConfig() body.'
}

$body = $match.Groups['body'].Value

if ($body -notmatch 'cloneProductUsesBlankTemplate') {
    throw 'buildClonedProductConfig() must distinguish blank products from source-based copies.'
}

if ($body -notmatch 'var\s+config\s*=\s*deepCopyConfig\s*\(\s*productTemplateConfig\s*\(\s*\)\s*\)') {
    throw 'Source-based new products and new versions must deep-copy productTemplateConfig().'
}

if ($body -notmatch 'applyCloneMetadata\s*\(') {
    throw 'Source-based copies do not apply clone metadata through the shared helper.'
}

if ($body -notmatch 'buildStandardProductConfigV3\s*\(') {
    throw 'The explicit blank-product path must create Product Config V3.'
}
if ($body -notmatch 'cloneProductConfigV3\s*\(') {
    throw 'Source-based V3 products must use the semantic deep-clone helper.'
}

if ($body -notmatch 'buttonCount\s*:\s*cloneButtonCountBox\.value') {
    throw 'New products must pass the selected button count to the generic J1939 builder.'
}

if ($body -notmatch 'buttonNumbers\s*:\s*parsedCloneButtonNumbers\(\)\.numbers') {
    throw 'New products must pass the selected physical button numbers to the generic J1939 builder.'
}

if (-not $content.Contains('text.replace(/[，、;；\s]+/g, ",")')) {
    throw 'Physical button-number parsing must accept the Chinese enumeration comma.'
}

if (-not $designCanvasContent.Contains('if (c.type === "joystick" || c.type === "buttonGroup") continue')) {
    throw 'The internal buttonGroup base binding must not appear as a direct visual binding option.'
}

if ($body -notmatch 'rollerCount\s*:\s*cloneRollerCountBox\.value') {
    throw 'New products must pass the selected roller count to the generic J1939 builder.'
}
if ($body -notmatch 'hasWorkLight\s*:\s*cloneHasWorkLightCheck\.checked') {
    throw 'New products must pass the work-light selection to the V3 builder.'
}

$helperMatch = [regex]::Match($content, '(?s)function\s+applyCloneMetadata\s*\([^)]*\)\s*\{(?<body>.*?)\n\s*\}\s*\n\s*function\s+openCloneProductPopup\s*\(')
if (-not $helperMatch.Success) {
    throw 'Could not locate applyCloneMetadata() body.'
}

$helperBody = $helperMatch.Groups['body'].Value
if ($helperBody -match '\.protocol\s*=|protocol\s*:') {
    throw 'applyCloneMetadata() must preserve the source product protocol.'
}
if ($helperBody -match 'calibration\.mode|defaultBaudRate|setProductCustomerBinding') {
    throw 'Source-based copies must not overwrite calibration, CAN baud rate, or customer bindings.'
}
if ($helperBody -match 'clonedConfig\.firmware\s*\|\|\s*\{\}') {
    throw 'Source-based copies must not create a synthetic firmware object.'
}

$versionHelperMatch = [regex]::Match(
    $content,
    '(?s)function\s+setVersionMetadata\s*\([^)]*\)\s*\{(?<body>.*?)\n\s*\}\s*\n\s*function\s+setProductCustomerBinding')
if (-not $versionHelperMatch.Success) {
    throw 'Could not locate setVersionMetadata() body.'
}
if ($versionHelperMatch.Groups['body'].Value -notmatch 'if\s*\(\s*!config\.firmware\s*\)') {
    throw 'Legacy firmware version metadata may only be updated when a firmware block already exists.'
}

$openCloneMatch = [regex]::Match(
    $content,
    '(?s)function\s+openCloneProductPopup\s*\(\)\s*\{(?<body>.*?)\n\s*\}\s*\n\s*function\s+openBlankProductPopup\s*\(')
if (-not $openCloneMatch.Success) {
    throw 'Could not locate source-based new-product popup initialization.'
}
$openCloneBody = $openCloneMatch.Groups['body'].Value
if ($openCloneBody -notmatch 'cloneProductUsesBlankTemplate\s*=\s*false') {
    throw 'Source-based new-product creation must explicitly disable the blank template.'
}
if ($openCloneBody -notmatch 'cloneDescriptionArea\.text\s*=\s*product\.description\s*\|\|\s*""') {
    throw 'Source-based new-product creation must prefill the source description.'
}
if ($openCloneBody -match 'cloneButtonCountBox\.value\s*=|cloneRollerCountBox\.value\s*=|calibrationModeIndex\("centerOnly"\)|selectComboValue\(cloneBaudRateBox,\s*cloneBaudRateModel,\s*250\)') {
    throw 'Source-based new-product creation must not reset source configuration fields.'
}

if ($content -notmatch 'function\s+openBlankProductPopup\s*\(') {
    throw 'Generic blank-product creation must remain available as a separate action.'
}

$saveMatch = [regex]::Match(
    $content,
    '(?s)function\s+saveCloneProduct\s*\(\)\s*\{(?<body>.*?)\n\s*\}\s*\n\s*// Resolve component IDs')
if (-not $saveMatch.Success) {
    throw 'Could not locate saveCloneProduct() body.'
}
$saveBody = $saveMatch.Groups['body'].Value
if ($saveBody -notmatch 'currentConfig\.schemaVersion\s*!==\s*3') {
    throw 'V3 clones must not pass through the legacy layout.grid.cells serializer.'
}

$customerMatch = [regex]::Match(
    $content,
    '(?s)ComboBox\s*\{\s*id:\s*cloneCustomerBox(?<body>.*?)\n\s*\}\s*\n\s*Label\s*\{\s*text:\s*"校准模式"')
if (-not $customerMatch.Success) {
    throw 'Could not locate cloneCustomerBox.'
}
if ($customerMatch.Groups['body'].Value -notmatch 'editable\s*:\s*true') {
    throw 'cloneCustomerBox must allow typing a new customer.'
}

$customerNameMatch = [regex]::Match(
    $content,
    '(?s)function\s+currentCloneCustomerName\s*\(\)\s*\{(?<body>.*?)\n\s*\}\s*\n\s*function\s+currentCloneBaudRate')
if (-not $customerNameMatch.Success -or $customerNameMatch.Groups['body'].Value -notmatch 'cloneCustomerBox\.editText') {
    throw 'currentCloneCustomerName() must return typed customer text.'
}

if ($content -notmatch 'id:\s*cloneButtonCountBox') {
    throw 'The new-product form must expose a button count control.'
}
if ($content -notmatch 'id:\s*cloneButtonNumbersField') {
    throw 'The new-product form must expose an optional physical button-number control.'
}
if ($content -notmatch 'id:\s*cloneRollerCountBox') {
    throw 'The new-product form must expose a roller count control.'
}
if ($content -notmatch 'id:\s*cloneHasWorkLightCheck') {
    throw 'The new-product form must expose a work-light option.'
}

if ($layoutManagerContent -notmatch 'boundedJsonInt\(spec,\s*QStringLiteral\("buttonCount"\),\s*10,\s*0,\s*12\)') {
    throw 'The generic J1939 builder must default to 10 buttons and clamp to 0..12.'
}
if ($layoutManagerContent -notmatch 'boundedJsonInt\(spec,\s*QStringLiteral\("rollerCount"\),\s*4,\s*0,\s*4\)') {
    throw 'The generic J1939 builder must default to 4 rollers and clamp to 0..4.'
}
if ($layoutManagerContent -notmatch 'j1939BjmFields\(decoderButtonCount') {
    throw 'The generic J1939 builder must decode through the highest physical button number.'
}
if ($layoutManagerContent -notmatch 'j1939EjmFields\(rollerCount') {
    throw 'The generic J1939 builder must generate EJM fields from rollerCount.'
}

Write-Host 'OK: source-based copies preserve the complete config and layout; blank products keep the generic J1939 builder.'
