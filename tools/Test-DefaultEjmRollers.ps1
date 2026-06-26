param(
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Get-Prop {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) {
        return $null
    }

    return $prop.Value
}

function Find-ById {
    param(
        [object[]]$Items,
        [string]$Id
    )

    foreach ($item in @($Items)) {
        if ((Get-Prop $item "id") -eq $Id) {
            return $item
        }
    }
    return $null
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $outerToolRoot = Split-Path -Parent $repoRoot
    $desktopRoot = Split-Path -Parent $outerToolRoot
    $ConfigPath = Join-Path $desktopRoot "CANJoystickDownloadTool\firmware\default\default_V1.json"
}

Assert-True (Test-Path -LiteralPath $ConfigPath) "Default config not found: $ConfigPath"

$config = Get-Content -Raw -LiteralPath $ConfigPath | ConvertFrom-Json
$messages = @((Get-Prop (Get-Prop $config "can") "messages"))
$ejm = Find-ById $messages "ejm"
Assert-True ($null -ne $ejm) "Missing EJM message"

$expectedRollers = @(
    @{ id = "ejm_handleX"; label = "Roller1"; status = "handleXStatus"; position = "handleXPos"; byte = 0 },
    @{ id = "ejm_handleY"; label = "Roller2"; status = "handleYStatus"; position = "handleYPos"; byte = 2 },
    @{ id = "ejm_theta"; label = "Roller3"; status = "thetaStatus"; position = "thetaPos"; byte = 4 },
    @{ id = "ejm_roller4"; label = "Roller4"; status = "roller4Status"; position = "roller4Pos"; byte = 6 }
)

$fields = @((Get-Prop $ejm "fields"))
foreach ($roller in $expectedRollers) {
    $statusField = $fields | Where-Object { (Get-Prop $_ "name") -eq $roller.status } | Select-Object -First 1
    $positionField = $fields | Where-Object { (Get-Prop $_ "name") -eq $roller.position } | Select-Object -First 1

    Assert-True ($null -ne $statusField) "Missing EJM field: $($roller.status)"
    Assert-True ($null -ne $positionField) "Missing EJM field: $($roller.position)"
    Assert-True ((Get-Prop $statusField "startByte") -eq $roller.byte) "Unexpected startByte for $($roller.status)"
    Assert-True ((Get-Prop $statusField "startBit") -eq 0) "Unexpected startBit for $($roller.status)"
    Assert-True ((Get-Prop $statusField "bitLength") -eq 6) "Unexpected bitLength for $($roller.status)"
    Assert-True ((Get-Prop $statusField "type") -eq "status") "Unexpected type for $($roller.status)"
    Assert-True ((Get-Prop $positionField "startByte") -eq $roller.byte) "Unexpected startByte for $($roller.position)"
    Assert-True ((Get-Prop $positionField "startBit") -eq 6) "Unexpected startBit for $($roller.position)"
    Assert-True ((Get-Prop $positionField "bitLength") -eq 10) "Unexpected bitLength for $($roller.position)"
    Assert-True ((Get-Prop $positionField "type") -eq "position") "Unexpected type for $($roller.position)"
}

$components = @((Get-Prop $config "components"))
foreach ($roller in $expectedRollers) {
    $component = Find-ById $components $roller.id
    Assert-True ($null -ne $component) "Missing roller component: $($roller.id)"
    Assert-True ((Get-Prop $component "type") -eq "roller") "Unexpected component type for $($roller.id)"
    Assert-True ((Get-Prop $component "orientation") -eq "vertical") "Roller must default to vertical: $($roller.id)"
    Assert-True ((Get-Prop $component "status") -eq "ejm.$($roller.status)") "Unexpected status ref for $($roller.id)"
    Assert-True ((Get-Prop $component "position") -eq "ejm.$($roller.position)") "Unexpected position ref for $($roller.id)"
}

$cells = @((Get-Prop (Get-Prop (Get-Prop $config "layout") "grid") "cells"))
$rollerCell = $null
foreach ($cell in $cells) {
    $cellComponents = @((Get-Prop $cell "components"))
    if ($cellComponents -contains "ejm_handleX") {
        $rollerCell = $cell
        break
    }
}
Assert-True ($null -ne $rollerCell) "Missing EJM roller canvas cell"

$rollerCellComponents = @((Get-Prop $rollerCell "components"))
$visuals = @((Get-Prop $rollerCell "visualComponents"))
foreach ($roller in $expectedRollers) {
    Assert-True ($rollerCellComponents -contains $roller.id) "Roller cell missing component: $($roller.id)"
    $visual = $visuals | Where-Object { (Get-Prop $_ "bindingId") -eq $roller.id } | Select-Object -First 1
    Assert-True ($null -ne $visual) "Missing roller visual binding: $($roller.id)"
    Assert-True ((Get-Prop $visual "type") -eq "VerticalRoller") "Roller visual must be VerticalRoller: $($roller.id)"
}

$editor = Get-Prop $config "editor"
Assert-True ((Get-Prop $editor "rollerCount") -eq 4) "editor.rollerCount must be 4"

Write-Host "Default EJM roller config OK: $ConfigPath"
