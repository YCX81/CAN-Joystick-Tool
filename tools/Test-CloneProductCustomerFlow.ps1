param(
    [string]$ProductEditorPath = (Join-Path $PSScriptRoot '..\CANJoystickToolContent\ProductEditor.qml')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ProductEditorPath)) {
    throw "ProductEditor.qml not found: $ProductEditorPath"
}

$content = Get-Content -Raw -LiteralPath $ProductEditorPath

$customerMatch = [regex]::Match(
    $content,
    '(?s)ComboBox\s*\{\s*id:\s*cloneCustomerBox(?<body>.*?)\n\s*\}\s*\n\s*Label\s*\{\s*text:\s*"校准模式"')
if (-not $customerMatch.Success) {
    throw 'Could not locate cloneCustomerBox.'
}
$customerBody = $customerMatch.Groups['body'].Value
if ($customerBody -notmatch 'visible\s*:\s*!cloneProductCreatesVersion') {
    throw 'Customer selection must be visible for both blank and source-based new products.'
}

$validationMatch = [regex]::Match(
    $content,
    '(?s)function\s+validateCloneProductForm\s*\(\)\s*\{(?<body>.*?)\n\s*\}\s*\n\s*function\s+parsedCloneButtonNumbers')
if ((-not $validationMatch.Success) -or
    ($validationMatch.Groups['body'].Value -notmatch '!cloneProductCreatesVersion\s*&&\s*currentCloneCustomerName\(\)\.length\s*===\s*0')) {
    throw 'Every new product must require a customer before saving.'
}

$saveMatch = [regex]::Match(
    $content,
    '(?s)function\s+saveCloneProduct\s*\(\)\s*\{(?<body>.*?)\n\s*\}\s*\n\s*// Resolve component IDs')
if (-not $saveMatch.Success) {
    throw 'Could not locate saveCloneProduct().'
}
$saveBody = $saveMatch.Groups['body'].Value
if (($saveBody -notmatch '!cloneProductCreatesVersion\s*&&\s*layoutManager') -or
    ($saveBody -notmatch 'saveProductConfigVersionWithCustomerAs\s*\(') -or
    ($saveBody -notmatch 'currentCloneCustomerName\(\)')) {
    throw 'All new-product paths must persist the selected customer through the customer-aware save API.'
}
if (($saveBody -notmatch 'cloneProductConfigVersionWithCustomerAs\s*\(') -or
    ($saveBody -notmatch 'deepCopyConfig\s*\(\s*productTemplateConfig\s*\(\s*\)\s*\)')) {
    throw 'Source-based V3 products must use the atomic firmware-copy clone API.'
}
if ($content -notmatch '自动复制原固件，按新型号和版本重命名') {
    throw 'The clone dialog must explain automatic firmware copying and renaming.'
}

Write-Host 'OK: source-based and blank new products both require and persist the selected customer.'
