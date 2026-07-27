param(
    [string]$ProductEditorPath = (Join-Path $PSScriptRoot '..\CANJoystickToolContent\ProductEditor.qml'),
    [string]$AdapterPath = (Join-Path $PSScriptRoot '..\CANJoystickToolContent\ProductConfigV3EditorAdapter.js'),
    [string]$C0031Path = 'C:\Users\ycx\Desktop\CANJoystickDownloadTool\firmware\JC6000-BGA-C0031\JC6000-BGA-C0031_V1.json'
)

$ErrorActionPreference = 'Stop'

$editor = Get-Content -Raw -LiteralPath $ProductEditorPath
if ($editor -notmatch 'ProductConfigV3EditorAdapter\.js') {
    throw 'ProductEditor must import the V3 editor layout adapter.'
}
if ($editor -notmatch 'V3EditorAdapter\.cellsFromConfig\s*\(\s*currentConfig\s*\)') {
    throw 'ProductEditor must load V3 layout.cards through the editor adapter.'
}
if ($editor -notmatch 'V3EditorAdapter\.applyCellsToConfig\s*\(') {
    throw 'ProductEditor must save edited cells back to V3 layout.cards.'
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
