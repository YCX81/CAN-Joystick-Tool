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
if ($editor -notmatch 'schemaVersion\s*===\s*3[\s\S]*V3EditorAdapter\.fnrEditorState') {
    throw 'Schema v3 FNR controls must expose their packed button positions.'
}
if ($editor -notmatch 'V3EditorAdapter\.applyFnrPositions') {
    throw 'Schema v3 FNR mappings must persist through the v3 adapter.'
}
if ($editor -notmatch 'V3EditorAdapter\.fnrCreationState') {
    throw 'A newly placed schema v3 FNR must be able to claim physical button channels.'
}
if ($editor -notmatch 'V3EditorAdapter\.buttonControlIdsForPositions') {
    throw 'Schema v3 FNR mapping must resolve the exact physical button channel ids.'
}
if ($editor -notmatch 'removeButtonVisualsByBindingIds\s*\(\s*mappedChannelIds\s*,\s*wrapper\s*\)') {
    throw 'Buttons consumed by a schema v3 FNR must be removed from the live canvas.'
}
if ($editor -notmatch 'wrapper\.bindingId\s*=\s*fnrMappingPopup\.targetFnrId') {
    throw 'A newly created schema v3 FNR visual must bind to its logical FNR control.'
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
