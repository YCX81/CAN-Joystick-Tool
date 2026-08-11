param(
    [string]$ProductEditorPath = (Join-Path $PSScriptRoot '..\CANJoystickToolContent\ProductEditor.qml'),
    [string]$AdapterPath = (Join-Path $PSScriptRoot '..\CANJoystickToolContent\ProductConfigV3EditorAdapter.js'),
    [string]$C0031Path = 'C:\Users\ycx\Desktop\CANJoystickDownloadTool\firmware\JC6000-BGA-C0031\JC6000-BGA-C0031_V1.json'
)

$ErrorActionPreference = 'Stop'

$editor = Get-Content -Raw -LiteralPath $ProductEditorPath
foreach ($removedDraftSymbol in @('ProductDraftPolicy', 'productDraftTimer', 'loadProductDraft', 'saveProductDraft', 'draftRecoveryPopup')) {
    if ($editor -match [regex]::Escape($removedDraftSymbol)) {
        throw "Removed product draft feature is still referenced: $removedDraftSymbol"
    }
}
if ($editor -notmatch 'ProductConfigV3EditorAdapter\.js') {
    throw 'ProductEditor must import the V3 editor layout adapter.'
}
if ($editor -notmatch 'V3EditorAdapter\.cellsFromConfig\s*\(\s*currentConfig\s*\)') {
    throw 'ProductEditor must load V3 layout.cards through the editor adapter.'
}
if ($editor -notmatch 'V3EditorAdapter\.applyCellsToConfig\s*\(') {
    throw 'ProductEditor must save edited cells back to V3 layout.cards.'
}
if ($editor -notmatch 'V3EditorAdapter\.bindingsFromConfig\s*\(\s*currentConfig\s*\)') {
    throw 'ProductEditor must expose V3 controls to the canvas binding editor.'
}
$loadFunction = [regex]::Match(
    $editor,
    'function\s+loadProductVersion\s*\([^)]*\)\s*\{(?<body>[\s\S]*?)\n\s*\}\n\s*\n\s*function\s+openCurrentProductConfig')
if (-not $loadFunction.Success) {
    throw 'Unable to inspect loadProductVersion draft-safety behavior.'
}
$loadBody = $loadFunction.Groups['body'].Value
$loadingGuardIndex = $loadBody.IndexOf('loadingCells = true')
$pathSwitchIndex = $loadBody.IndexOf('currentFilePath = path')
if ($loadingGuardIndex -lt 0 -or $pathSwitchIndex -lt 0 -or $loadingGuardIndex -gt $pathSwitchIndex) {
    throw 'ProductEditor must block draft autosave before switching the product path.'
}
if ($editor -notmatch 'V3EditorAdapter\.cellBindingErrors\s*\(\s*cells\s*\)') {
    throw 'ProductEditor must reject unbound V3 visuals before adapting the layout.'
}
if ($editor -notmatch 'if\s*\(\s*!syncCurrentLayoutFromCells\s*\(\s*\)\s*\)\s*return') {
    throw 'ProductEditor save must stop when canvas binding validation fails.'
}
if ($editor -notmatch 'function\s+handleExternalProductConfigChange\s*\(\s*path\s*\)') {
    throw 'ProductEditor must handle a validated external product-config change.'
}
if ($editor -notmatch 'function\s+onProductConfigExternallyChanged\s*\(\s*path\s*\)\s*\{\s*root\.handleExternalProductConfigChange\s*\(\s*path\s*\)') {
    throw 'ProductEditor must subscribe to LayoutManager external-change notifications.'
}
$externalHandler = [regex]::Match(
    $editor,
    'function\s+handleExternalProductConfigChange\s*\(\s*path\s*\)\s*\{(?<body>[\s\S]*?)\n\s*\}\n\s*\n\s*function\s+openCurrentProductConfig')
if (-not $externalHandler.Success) {
    throw 'Unable to inspect ProductEditor external-change safety behavior.'
}
$externalBody = $externalHandler.Groups['body'].Value
if ($externalBody -notmatch 'hasUnsavedChanges') {
    throw 'An external JSON change must not overwrite unsaved editor state.'
}
if ($externalBody -notmatch 'loadProductVersion\s*\(') {
    throw 'A clean editor must reload the externally changed JSON.'
}

if (-not (Test-Path -LiteralPath $AdapterPath)) {
    throw "V3 editor layout adapter is missing: $AdapterPath"
}
$adapter = Get-Content -Raw -LiteralPath $AdapterPath
foreach ($renderer in @('miniJoystick', 'button', 'roller', 'fnr')) {
    if ($adapter -notmatch [regex]::Escape('"' + $renderer + '"')) {
        throw "V3 editor adapter does not map renderer '$renderer'."
    }
}
foreach ($runtimeOnlyProperty in @('xValue', 'yValue', 'minValue', 'maxValue')) {
    if ($adapter -notmatch [regex]::Escape('delete properties.' + $runtimeOnlyProperty)) {
        throw "V3 editor adapter must not persist runtime-only '$runtimeOnlyProperty'."
    }
}
if ($adapter -notmatch 'function\s+bindingsFromConfig\s*\(') {
    throw 'V3 editor adapter must convert controls into canvas bindings.'
}

$designCanvasPath = Join-Path $PSScriptRoot '..\CANJoystickTool\DesignCanvas.qml'
$designCanvas = Get-Content -Raw -LiteralPath $designCanvasPath
if ($designCanvas -notmatch 'cat\s*===\s*"button"\s*&&\s*comp\.type\s*===\s*"button"') {
    throw 'DesignCanvas must offer direct V3 button controls as button bindings.'
}

$config = Get-Content -Raw -LiteralPath $C0031Path | ConvertFrom-Json -Depth 100
if ($config.schemaVersion -ne 3) {
    throw 'C0031 fixture must be a V3 product.'
}
$controlCards = @($config.layout.cards | Where-Object kind -eq 'controls')
$elements = @($controlCards | ForEach-Object elements)
if ($controlCards.Count -ne 2 -or $elements.Count -ne 7) {
    throw 'C0031 fixture must expose two populated V3 control cards with seven elements.'
}
if (@($elements | Where-Object renderer -eq 'miniJoystick').Count -ne 1) {
    throw 'C0031 fixture must contain one V3 miniJoystick element.'
}

Write-Host 'PASS: ProductEditor loads and saves populated C0031 V3 cards'
