param(
    [string]$ProductEditorPath = (Join-Path $PSScriptRoot '..\CANJoystickToolContent\ProductEditor.qml')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ProductEditorPath)) {
    throw "ProductEditor.qml not found: $ProductEditorPath"
}

$content = Get-Content -Raw -LiteralPath $ProductEditorPath

if ($content -notmatch 'function\s+canvasComponentIdsFromVisualComponents\s*\(\s*visualComponents\s*,\s*fallbackComponents\s*,\s*allowFallback\s*\)') {
    throw 'Canvas binding extraction must let callers disable the legacy component fallback.'
}

if ($content -notmatch 'result\.length\s*>\s*0\s*\|\|\s*allowFallback\s*===\s*false') {
    throw 'An explicitly blank visual layout must produce no component IDs.'
}

if ($content -notmatch 'hasSavedVisualLayout\s*=\s*c\.visualComponents\s*!==\s*undefined\s*&&\s*c\.visualComponents\s*!==\s*null') {
    throw 'The loader must distinguish a missing legacy visual layout from an explicitly empty one.'
}

if ($content -notmatch 'else\s+if\s*\(\s*!hasSavedVisualLayout\s*&&\s*c\.components\s*&&\s*c\.components\.length\s*>\s*0\s*\)') {
    throw 'Only legacy cells without visualComponents may auto-populate from component IDs.'
}

if ($content -notmatch 'canvasComponentIdsFromVisualComponents\s*\(\s*comps\s*,\s*cell\.cellCompIds\s*,\s*false\s*\)') {
    throw 'Saving a blank canvas must clear stale component IDs instead of preserving them.'
}

Write-Host 'OK: explicitly blank canvases stay blank while legacy layouts retain their fallback.'
