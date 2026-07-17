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

if ($body -notmatch 'cloneProductCreatesVersion') {
    throw 'buildClonedProductConfig() must distinguish new versions from new products.'
}

if ($body -notmatch 'var\s+config\s*=\s*deepCopyConfig\s*\(\s*productTemplateConfig\s*\(\s*\)\s*\)') {
    throw 'New versions must deep-copy productTemplateConfig().'
}

if ($body -notmatch 'applyCloneMetadata\s*\(') {
    throw 'New versions do not apply clone metadata through the shared helper.'
}

if ($body -notmatch 'buildStandardProductConfig\s*\(') {
    throw 'New products must use buildStandardProductConfig().'
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

$helperMatch = [regex]::Match($content, '(?s)function\s+applyCloneMetadata\s*\([^)]*\)\s*\{(?<body>.*?)\n\s*\}\s*\n\s*function\s+openCloneProductPopup\s*\(')
if (-not $helperMatch.Success) {
    throw 'Could not locate applyCloneMetadata() body.'
}

$helperBody = $helperMatch.Groups['body'].Value
if ($helperBody -match '\.protocol\s*=|protocol\s*:') {
    throw 'applyCloneMetadata() must preserve the source product protocol.'
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

Write-Host 'OK: new products use editable customers and configurable generic J1939 parsing; new versions preserve current config.'
