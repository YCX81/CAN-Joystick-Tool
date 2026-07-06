param(
    [string]$ProductEditorPath = (Join-Path $PSScriptRoot '..\CANJoystickToolContent\ProductEditor.qml'),
    [string]$LayoutManagerPath = (Join-Path $PSScriptRoot '..\LayoutManager.cpp')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ProductEditorPath)) {
    throw "ProductEditor.qml not found: $ProductEditorPath"
}
if (-not (Test-Path -LiteralPath $LayoutManagerPath)) {
    throw "LayoutManager.cpp not found: $LayoutManagerPath"
}

$content = Get-Content -Raw -LiteralPath $ProductEditorPath
$layoutManagerContent = Get-Content -Raw -LiteralPath $LayoutManagerPath

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

if ($body -match 'buildStandardProductConfig') {
    throw 'buildClonedProductConfig() still calls buildStandardProductConfig(); new products must clone the current config.'
}

if ($body -notmatch 'var\s+config\s*=\s*deepCopyConfig\s*\(\s*productTemplateConfig\s*\(\s*\)\s*\)') {
    throw 'New product branch does not deep-copy productTemplateConfig().'
}

if ($body -notmatch 'applyCloneMetadata\s*\(') {
    throw 'buildClonedProductConfig() does not apply clone metadata through the shared helper.'
}

$helperMatch = [regex]::Match($content, '(?s)function\s+applyCloneMetadata\s*\([^)]*\)\s*\{(?<body>.*?)\n\s*\}\s*\n\s*function\s+openCloneProductPopup\s*\(')
if (-not $helperMatch.Success) {
    throw 'Could not locate applyCloneMetadata() body.'
}

$helperBody = $helperMatch.Groups['body'].Value
if ($helperBody -match '\.protocol\s*=|protocol\s*:') {
    throw 'applyCloneMetadata() must preserve the source product protocol.'
}

Write-Host 'OK: blank defaults are J1939 and clone product creation preserves current config.'