param(
    [string]$ProductEditorPath =
        (Join-Path $PSScriptRoot '..\CANJoystickToolContent\ProductEditor.qml')
)

$ErrorActionPreference = 'Stop'

$editor = Get-Content -Raw -LiteralPath $ProductEditorPath

if ($editor -notmatch 'function\s+setProductAddress\s*\(') {
    throw 'ProductEditor must expose a CAN address update function.'
}
if ($editor -notmatch 'schemaVersion\s*===\s*3[\s\S]*?bus\.sourceAddress\s*=') {
    throw 'V3 J1939 address edits must write bus.sourceAddress.'
}
if ($editor -notmatch 'schemaVersion\s*===\s*3[\s\S]*?bus\.nodeId\s*=') {
    throw 'V3 CANopen address edits must write bus.nodeId.'
}
if ($editor -notmatch 'editableAddress\s*:\s*root\.productAddressEditable\s*\(\s*\)') {
    throw 'The record card CAN address row must be editable.'
}
if (($editor -notmatch 'function\s+productAddressLabel\s*\(') -or
        ($editor -notmatch '"CANopen节点ID"') -or
        ($editor -notmatch '"J1939源地址"')) {
    throw 'The record card must distinguish J1939 addresses from CANopen node IDs.'
}
if ($editor -notmatch 'J1939 源地址请输入 0x00～0xFF') {
    throw 'J1939 inline editing must accept one-byte source addresses only.'
}
if (($editor -notmatch 'function\s+beginProductAddressEdit\s*\(') -or
        ($editor -notmatch 'function\s+commitProductAddressEdit\s*\(') -or
        ($editor -notmatch 'function\s+cancelProductAddressEdit\s*\(')) {
    throw 'The CAN address row must support begin, commit, and cancel editing.'
}
if ($editor -notmatch 'id\s*:\s*productAddressEdit[\s\S]*?Keys\.onEscapePressed') {
    throw 'The CAN address editor must support keyboard commit and cancel behavior.'
}
$addressEditor = [regex]::Match(
    $editor,
    'id\s*:\s*productAddressEdit(?<body>[\s\S]*?)Keys\.onEscapePressed')
if ((-not $addressEditor.Success) -or
        ($addressEditor.Groups['body'].Value -notmatch
            'onAccepted\s*:\s*\{[\s\S]*?commitProductAddressEdit\s*\(\s*text\s*\)')) {
    throw 'Enter must commit the CAN address text currently visible in the editor.'
}
if ($addressEditor.Groups['body'].Value -match
        'text\s*:\s*cellCard\.addressDraft') {
    throw 'The CAN address editor must not keep a binding that can restore stale draft text.'
}
if ($editor -notmatch 'cell\.addressEditing') {
    throw 'Draft autosave must defer while the CAN address editor is active.'
}

Write-Host 'PASS: record card supports protected inline CAN address editing'
