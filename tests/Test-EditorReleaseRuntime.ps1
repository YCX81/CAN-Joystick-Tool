[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$EditorPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$editor = Get-Item -LiteralPath $EditorPath -ErrorAction Stop
$root = $editor.DirectoryName
$requiredFiles = @(
    'Qt6Core.dll'
    'Qt6Gui.dll'
    'Qt6Qml.dll'
    'Qt6QuickControls2.dll'
    'Qt6Sql.dll'
    'Qt6Widgets.dll'
    'libgcc_s_seh-1.dll'
    'libstdc++-6.dll'
    'sqldrivers\qsqlite.dll'
)

$missing = @(
    $requiredFiles |
        Where-Object { -not (Test-Path -LiteralPath (Join-Path $root $_) -PathType Leaf) }
)
if ($missing.Count -gt 0) {
    throw ('Editor runtime deployment is incomplete. Missing: ' + ($missing -join ', '))
}

$requiredQmlDirectories = @(
    'qml\QtQuick\Controls'
    'qml\QtQuick\Layouts'
    'qml\QtQuick\Window'
)
$missingQml = @(
    $requiredQmlDirectories |
        Where-Object { -not (Test-Path -LiteralPath (Join-Path $root $_) -PathType Container) }
)
if ($missingQml.Count -gt 0) {
    throw ('Editor QML deployment is incomplete. Missing: ' + ($missingQml -join ', '))
}

Write-Output ('PASS: editor runtime deployment is complete for ' + $editor.FullName)
