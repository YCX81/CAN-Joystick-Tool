param(
    [string]$DesignCanvasPath = (Join-Path $PSScriptRoot '..\CANJoystickTool\DesignCanvas.qml'),
    [string]$ProductEditorPath = (Join-Path $PSScriptRoot '..\CANJoystickToolContent\ProductEditor.qml')
)

$ErrorActionPreference = 'Stop'

$canvas = Get-Content -Raw -LiteralPath $DesignCanvasPath
$editor = Get-Content -Raw -LiteralPath $ProductEditorPath

if ($canvas -notmatch 'signal\s+fnrMappingRequested\s*\(\s*var\s+component\s*\)') {
    throw 'DesignCanvas must expose a dedicated FNR mapping request.'
}
if ($canvas -notmatch 'getBindCategory\s*\([^)]*componentType[^)]*\)\s*===\s*"fnr"[\s\S]*fnrMappingRequested') {
    throw 'Right-click binding for every FNR visual type must open the dedicated mapper.'
}
if ($editor -notmatch 'import\s+"\.\./CANJoystickTool/FnrMapping\.js"\s+as\s+FnrMapping') {
    throw 'ProductEditor must use the tested FNR mapping rules.'
}
if ($editor -notmatch 'function\s+migrateLegacyFnrBindings\s*\(') {
    throw 'Legacy buttons.fnr bindings must be migrated on load.'
}
if ($editor -notmatch 'visual\.bindingId\s*=\s*fnrId') {
    throw 'Legacy migration must change only the binding reference and retain visual layout data.'
}
if ($editor -notmatch 'function\s+openFnrMappingEditor\s*\(\s*wrapper\s*\)') {
    throw 'ProductEditor must open the FNR mapping editor for the selected visual.'
}
if ($editor -notmatch 'function\s+applyFnrMapping\s*\(') {
    throw 'ProductEditor must persist FNR buttonMapping data.'
}
if ($editor -notmatch 'buttonMapping\s*:\s*FnrMapping\.buildButtonMapping') {
    throw 'FNR persistence must use the tested mapping builder.'
}
if ($editor -notmatch 'fnrMappingPopup') {
    throw 'The dedicated FNR mapping popup is missing.'
}
if ($editor -notmatch '未接线（F/R均松开为N）') {
    throw 'The N selector must explain inferred neutral when N is unwired.'
}
if ($editor -notmatch 'onFnrMappingRequested\s*:\s*function\s*\(\s*component\s*\)') {
    throw 'Every canvas must route FNR mapping requests to ProductEditor.'
}

Write-Host 'OK: FNR visuals use dedicated F/N/R mapping and legacy positions are retained.'
