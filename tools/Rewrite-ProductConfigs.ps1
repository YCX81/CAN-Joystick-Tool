param(
    [string]$ProductsDir = "C:\Users\ycx\Desktop\CANJoystickDownloadTool\products",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Get-Prop($Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $Default
    }
    if ($Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $Default
}

function Set-Prop($Object, [string]$Name, $Value) {
    if ($Object -is [System.Collections.IDictionary]) {
        $Object[$Name] = $Value
        return
    }
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Remove-Prop($Object, [string]$Name) {
    if ($null -eq $Object) { return }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { $Object.Remove($Name) }
        return
    }
    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.PSObject.Properties.Remove($Name)
    }
}

function New-OrderedObject($Pairs) {
    $result = [ordered]@{}
    foreach ($key in $Pairs.Keys) {
        $result[$key] = $Pairs[$key]
    }
    return $result
}

function Parse-ConfigNumber($Value, [int]$Fallback) {
    if ($null -eq $Value -or "$Value".Trim().Length -eq 0) { return $Fallback }
    if ($Value -is [int] -or $Value -is [long]) { return [int]$Value }
    $text = "$Value".Trim()
    try {
        if ($text.StartsWith("0x", [StringComparison]::OrdinalIgnoreCase)) {
            return [Convert]::ToInt32($text.Substring(2), 16)
        }
        return [Convert]::ToInt32($text, 10)
    } catch {
        return $Fallback
    }
}

function Hex-Text([int]$Value, [int]$Width) {
    return "0x$($Value.ToString("X$Width"))"
}

function Compose-J1939BjmCanId([int]$SourceAddress) {
    return Hex-Text (0x0CFDD600 -bor ($SourceAddress -band 0xFF)) 8
}

function New-Field([string]$Name, [int]$StartByte, [int]$StartBit, [int]$BitLength,
                   [string]$Type, [string]$Encoding = "", [string]$Endian = "") {
    $field = [ordered]@{
        name = $Name
        startByte = $StartByte
        startBit = $StartBit
        bitLength = $BitLength
        type = $Type
    }
    if ($Encoding.Length -gt 0) { $field.encoding = $Encoding }
    if ($Endian.Length -gt 0) { $field.endian = $Endian }
    return $field
}

function New-RangeField([string]$Name, [int]$StartByte) {
    $field = New-Field $Name $StartByte 6 10 "position" "unsigned"
    $field.range = @(0, 1000)
    return $field
}

function New-J1939BjmFields([int]$ButtonCount) {
    $fields = @(
        (New-Field "xStatus" 0 0 6 "status" "j1939_axis_status"),
        (New-RangeField "xPos" 0),
        (New-Field "yStatus" 2 0 6 "status" "j1939_axis_status"),
        (New-RangeField "yPos" 2)
    )
    if ($ButtonCount -gt 0) {
        $bits = [int]([math]::Ceiling(($ButtonCount * 2) / 8) * 8)
        $buttons = New-Field "buttons" 5 0 $bits "buttonGroup" "j1939_2bit"
        $buttons.buttonCount = $ButtonCount
        $fields += $buttons
    }
    return @($fields)
}

function New-J1939EjmFields([int]$RollerCount) {
    $fields = @()
    if ($RollerCount -ge 1) {
        $fields += New-Field "handleXStatus" 0 0 6 "status" "j1939_axis_status"
        $fields += New-RangeField "handleXPos" 0
    }
    if ($RollerCount -ge 2) {
        $fields += New-Field "handleYStatus" 2 0 6 "status" "j1939_axis_status"
        $fields += New-RangeField "handleYPos" 2
    }
    if ($RollerCount -ge 3) {
        $fields += New-Field "thetaStatus" 4 0 6 "status" "j1939_axis_status"
        $fields += New-RangeField "thetaPos" 4
    }
    if ($RollerCount -ge 4) {
        $fields += New-Field "roller4Status" 6 0 6 "status" "j1939_axis_status"
        $fields += New-RangeField "roller4Pos" 6
    }
    return @($fields)
}

function New-GeneratedMessages([string]$Protocol, [int]$ButtonCount, [int]$RollerCount, [int]$Address) {
    if ($Protocol -eq "canopen") {
        $nodeId = 0x48
        if ($Address -gt 0) { $nodeId = $Address -band 0x7F }
        $tpdo1Fields = @(
            (New-Field "xValue" 0 0 16 "position" "raw_16bit" "little"),
            (New-Field "yValue" 2 0 16 "position" "raw_16bit" "little")
        )
        if ($ButtonCount -gt 0) {
            $buttons = New-Field "buttons" 4 0 ([Math]::Max(8, $ButtonCount)) "buttonGroup" "canopen_1bit"
            $buttons.buttonCount = $ButtonCount
            $tpdo1Fields += $buttons
        }
        $messages = @(
            [ordered]@{ id = "tpdo1"; name = "TPDO1 - joystick/buttons"; canId = Hex-Text (0x180 + $nodeId) 3; cobIdFormula = "0x180 + nodeId"; dlc = 8; period = 20; fields = @($tpdo1Fields) }
        )
        if ($RollerCount -gt 0) {
            $fields = @()
            for ($i = 0; $i -lt [Math]::Min(3, $RollerCount); $i++) {
                $axis = $i + 3
                $fields += New-Field "axis$($axis)Value" ($i * 2) 0 16 "position" "raw_16bit" "little"
            }
            $messages += [ordered]@{ id = "tpdo2"; name = "TPDO2 - extension axes"; canId = Hex-Text (0x280 + $nodeId) 3; cobIdFormula = "0x280 + nodeId"; dlc = 8; period = 20; fields = @($fields) }
        }
        if ($RollerCount -gt 3) {
            $fields = @()
            for ($i = 0; $i -lt ($RollerCount - 3); $i++) {
                $axis = $i + 6
                $fields += New-Field "axis$($axis)Value" ($i * 2) 0 16 "position" "raw_16bit" "little"
            }
            $messages += [ordered]@{ id = "tpdo3"; name = "TPDO3 - extension axes"; canId = Hex-Text (0x380 + $nodeId) 3; cobIdFormula = "0x380 + nodeId"; dlc = 8; period = 20; fields = @($fields) }
        }
        $messages += [ordered]@{ id = "heartbeat"; name = "CANopen heartbeat"; canId = Hex-Text (0x700 + $nodeId) 3; cobIdFormula = "0x700 + nodeId"; dlc = 1; fields = @((New-Field "state" 0 0 8 "counter")) }
        return @($messages)
    }

    return @(
        [ordered]@{ id = "bjm"; name = "BJM1"; pgn = "0xFDD6"; dlc = 8; period = 20; fields = @(New-J1939BjmFields $ButtonCount) },
        [ordered]@{ id = "ejm"; name = "EJM1"; pgn = "0xFDD7"; dlc = 8; period = 20; fields = @(New-J1939EjmFields $RollerCount) },
        [ordered]@{ id = "addressClaim"; name = "address claim"; pgn = "0x0EEFF"; dlc = 8; fields = @((New-Field "identity" 0 0 21 "identity" "" "little")) }
    ) | Where-Object { @($_.fields).Count -gt 0 -or $_.id -eq "addressClaim" }
}

function New-GeneratedComponents([string]$Protocol, [int]$ButtonCount, [int]$RollerCount, [bool]$FnrEnabled) {
    $joystickLabel = "XY axes (BJM)"
    $xPosition = "bjm.xPos"
    $xStatus = "bjm.xStatus"
    $yPosition = "bjm.yPos"
    $yStatus = "bjm.yStatus"
    $buttonSource = "bjm.buttons"
    if ($Protocol -eq "canopen") {
        $joystickLabel = "XY axes"
        $xPosition = "tpdo1.xValue"
        $xStatus = $null
        $yPosition = "tpdo1.yValue"
        $yStatus = $null
        $buttonSource = "tpdo1.buttons"
    }

    $components = @(
        [ordered]@{
            id = "joystick_xy"
            type = "joystick"
            label = $joystickLabel
            xAxis = [ordered]@{ position = $xPosition; status = $xStatus }
            yAxis = [ordered]@{ position = $yPosition; status = $yStatus }
        }
    )
    if ($ButtonCount -gt 0) {
        $components += [ordered]@{
            id = "buttons"
            type = "buttonGroup"
            label = "buttons"
            source = $buttonSource
            count = $ButtonCount
            layout = [ordered]@{ columns = [Math]::Min(4, [Math]::Max(1, $ButtonCount)); rows = [Math]::Max(1, [Math]::Ceiling($ButtonCount / 4)) }
        }
    }
    for ($i = 0; $i -lt $RollerCount; $i++) {
        if ($Protocol -eq "canopen") {
            $axis = $i + 3
            $message = "tpdo3"
            if ($axis -le 5) { $message = "tpdo2" }
            $components += [ordered]@{ id = "axis$axis"; type = "roller"; label = "axis$axis"; orientation = "horizontal"; position = "$message.axis$($axis)Value"; status = $null }
        } else {
            $ids = @("ejm_handleX", "ejm_handleY", "ejm_theta", "ejm_roller4")
            $labels = @("handleX", "handleY", "theta", "roller4")
            $positions = @("ejm.handleXPos", "ejm.handleYPos", "ejm.thetaPos", "ejm.roller4Pos")
            $statuses = @("ejm.handleXStatus", "ejm.handleYStatus", "ejm.thetaStatus", "ejm.roller4Status")
            $components += [ordered]@{ id = $ids[$i]; type = "roller"; label = $labels[$i]; orientation = "vertical"; position = $positions[$i]; status = $statuses[$i] }
        }
    }
    if ($FnrEnabled -and $ButtonCount -gt 0) {
        $components += [ordered]@{
            id = "fnr"
            type = "fnrSwitch"
            label = "FNR"
            buttonMapping = [ordered]@{
                source = $buttonSource
                forward = [Math]::Max(0, $ButtonCount - 3)
                neutral = [Math]::Max(0, $ButtonCount - 2)
                reverse = [Math]::Max(0, $ButtonCount - 1)
            }
        }
    }
    return @($components)
}

function Get-AllVisuals($Config) {
    $cells = @((Get-Prop (Get-Prop (Get-Prop $Config "layout") "grid") "cells" @()))
    return @($cells | ForEach-Object { @((Get-Prop $_ "visualComponents" @())) })
}

function Infer-ButtonCount($Config) {
    $components = @((Get-Prop $Config "components" @()))
    $buttonComponent = @($components | Where-Object { (Get-Prop $_ "type") -eq "buttonGroup" } | Select-Object -First 1)
    if ($buttonComponent.Count -gt 0) { return [int](Get-Prop $buttonComponent[0] "count" 0) }
    $buttonField = @((Get-Prop (Get-Prop $Config "can") "messages" @()) | ForEach-Object { @((Get-Prop $_ "fields" @())) } | Where-Object { (Get-Prop $_ "type") -eq "buttonGroup" } | Select-Object -First 1)
    if ($buttonField.Count -gt 0) { return [int](Get-Prop $buttonField[0] "buttonCount" 0) }
    if ($components.Count -gt 0) { return 0 }
    return @((Get-AllVisuals $Config) | Where-Object { ([string](Get-Prop $_ "type" "")).StartsWith("Button") }).Count
}

function Infer-RollerCount($Config) {
    $components = @((Get-Prop $Config "components" @()))
    $count = @($components | Where-Object { (Get-Prop $_ "type") -eq "roller" }).Count
    if ($components.Count -gt 0) { return $count }
    return @((Get-AllVisuals $Config) | Where-Object { ([string](Get-Prop $_ "type" "")).Contains("Roller") }).Count
}

function Infer-FnrEnabled($Config) {
    $components = @((Get-Prop $Config "components" @()))
    if (@($components | Where-Object { (Get-Prop $_ "type") -eq "fnrSwitch" }).Count -gt 0) { return $true }
    if ($components.Count -gt 0) { return $false }
    return @((Get-AllVisuals $Config) | Where-Object { ([string](Get-Prop $_ "type" "")).Contains("FNR") }).Count -gt 0
}

function Get-FnrMappedIndexesBySource($Components) {
    $mapped = @{}
    foreach ($component in @($Components)) {
        if ((Get-Prop $component "type") -ne "fnrSwitch") { continue }
        $mapping = Get-Prop $component "buttonMapping"
        $source = Get-Prop $mapping "source" ""
        if ($source.Length -eq 0) { continue }
        if (-not $mapped.ContainsKey($source)) { $mapped[$source] = [System.Collections.Generic.HashSet[int]]::new() }
        foreach ($key in @("forward", "neutral", "reverse")) {
            $value = [int](Get-Prop $mapping $key -1)
            if ($value -ge 0) { [void]$mapped[$source].Add($value) }
        }
    }
    return $mapped
}

function Repair-VisualBindings($Config) {
    $components = @((Get-Prop $Config "components" @()))
    $buttonGroup = @($components | Where-Object { (Get-Prop $_ "type") -eq "buttonGroup" } | Select-Object -First 1)
    $buttonId = ""
    $buttonSource = ""
    $buttonCount = 0
    if ($buttonGroup.Count -gt 0) {
        $buttonId = [string](Get-Prop $buttonGroup[0] "id" "")
        $buttonSource = [string](Get-Prop $buttonGroup[0] "source" "")
        $buttonCount = [int](Get-Prop $buttonGroup[0] "count" 0)
    }
    $rollerIds = @($components | Where-Object { (Get-Prop $_ "type") -eq "roller" } | ForEach-Object { Get-Prop $_ "id" "" })
    $fnrId = @($components | Where-Object { (Get-Prop $_ "type") -eq "fnrSwitch" } | ForEach-Object { Get-Prop $_ "id" "" } | Select-Object -First 1)
    $fnrMapped = Get-FnrMappedIndexesBySource $components
    $reserved = [System.Collections.Generic.HashSet[int]]::new()
    if ($fnrMapped.ContainsKey($buttonSource)) { $reserved = $fnrMapped[$buttonSource] }
    if ($null -eq $reserved) { $reserved = [System.Collections.Generic.HashSet[int]]::new() }
    $visibleButtonVisuals = @((Get-AllVisuals $Config) | Where-Object { ([string](Get-Prop $_ "type" "")).StartsWith("Button") }).Count
    if ($visibleButtonVisuals -ge $buttonCount) {
        $reserved = [System.Collections.Generic.HashSet[int]]::new()
    }
    $used = [System.Collections.Generic.HashSet[int]]::new()

    foreach ($visual in Get-AllVisuals $Config) {
        $binding = Get-Prop $visual "bindingId" ""
        if ($binding -match "^$([regex]::Escape($buttonId))\.(\d+)$") {
            [void]$used.Add([int]$Matches[1])
        }
    }

    $nextButton = 0
    $nextRoller = 0
    $fixed = 0
    $removed = 0
    $cells = @((Get-Prop (Get-Prop (Get-Prop $Config "layout") "grid") "cells" @()))
    foreach ($cell in $cells) {
        $cellComponents = [System.Collections.Generic.List[string]]::new()
        foreach ($existing in @((Get-Prop $cell "components" @()))) {
            if ($existing -and -not $cellComponents.Contains($existing)) { $cellComponents.Add($existing) }
        }
        $visuals = @((Get-Prop $cell "visualComponents" @()))
        $newVisuals = [System.Collections.Generic.List[object]]::new()
        foreach ($visual in $visuals) {
            $type = [string](Get-Prop $visual "type" "")
            $binding = [string](Get-Prop $visual "bindingId" "")
            if ($type.StartsWith("Button") -and $buttonId.Length -gt 0) {
                if ($binding.Length -eq 0) {
                    while (($nextButton -lt $buttonCount) -and ($used.Contains($nextButton) -or $reserved.Contains($nextButton))) { $nextButton++ }
                    if ($nextButton -lt $buttonCount) {
                        $binding = "$buttonId.$nextButton"
                        Set-Prop $visual "bindingId" $binding
                        [void]$used.Add($nextButton)
                        $nextButton++
                        $fixed++
                    }
                }
            } elseif ($type.Contains("Roller") -and $binding.Length -eq 0 -and $nextRoller -lt $rollerIds.Count) {
                $binding = $rollerIds[$nextRoller]
                Set-Prop $visual "bindingId" $binding
                $nextRoller++
                $fixed++
            } elseif ($type.Contains("FNR") -and $binding.Length -eq 0 -and $fnrId.Count -gt 0) {
                $binding = $fnrId[0]
                Set-Prop $visual "bindingId" $binding
                $fixed++
            }

            $isRuntimeVisual = $type.StartsWith("Button") -or $type.Contains("Roller") -or $type.Contains("FNR")
            if ($isRuntimeVisual -and $binding.Length -eq 0) {
                $removed++
                continue
            }
            $newVisuals.Add($visual)

            if ($binding.Length -gt 0) {
                $base = $binding.Split(".")[0]
                if (-not $cellComponents.Contains($base)) { $cellComponents.Add($base) }
            }
        }

        $cellType = Get-Prop $cell "cellType" ""
        $title = Get-Prop $cell "title" ""
        if ($cellType -eq "busStats" -or $title -eq "总线统计") {
            if (-not $cellComponents.Contains("busStats")) { $cellComponents.Add("busStats") }
            Set-Prop $cell "cellType" "busStats"
        }
        if ($cellType -eq "recordInfo" -or $title -eq "记录信息") {
            if (-not $cellComponents.Contains("recordInfo")) { $cellComponents.Add("recordInfo") }
            Set-Prop $cell "cellType" "recordInfo"
        }
        Set-Prop $cell "components" @($cellComponents.ToArray())
        if (@((Get-Prop $cell "visualComponents" @())).Count -gt 0) {
            Set-Prop $cell "visualComponents" @($newVisuals.ToArray())
        }
    }

    return [pscustomobject]@{
        FixedBindings = $fixed
        RemovedOrphans = $removed
    }
}

function Convert-Product($Path) {
    $config = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    $product = Get-Prop $config "product"
    $can = Get-Prop $config "can"
    $layout = Get-Prop $config "layout"
    $grid = Get-Prop $layout "grid"
    $protocol = "$((Get-Prop $product "protocol" "j1939"))".Trim().ToLowerInvariant()
    if ($protocol -ne "canopen") { $protocol = "j1939" }

    $buttonCount = [Math]::Min(12, [Math]::Max(0, (Infer-ButtonCount $config)))
    $rollerLimit = 4
    if ($protocol -eq "canopen") { $rollerLimit = 6 }
    $rollerCount = [Math]::Min($rollerLimit, [Math]::Max(0, (Infer-RollerCount $config)))
    $fnrEnabled = Infer-FnrEnabled $config
    $generatedStructure = $false

    if ($protocol -eq "canopen") {
        $canopen = Get-Prop $can "canopen"
        $nodeId = Parse-ConfigNumber (Get-Prop $product "nodeId" (Get-Prop $canopen "nodeId" 0x48)) 0x48
        if ($nodeId -le 0) { $nodeId = 0x48 }
        Set-Prop $product "nodeId" $nodeId
        Set-Prop $product "canFrameFormat" "standard"
        Set-Prop $product "canAddress" (Hex-Text (0x700 + $nodeId) 3)
        if ($null -eq $canopen) { $canopen = [ordered]@{}; Set-Prop $can "canopen" $canopen }
        Set-Prop $canopen "nodeId" $nodeId
        if ($null -eq (Get-Prop $canopen "heartbeatMs")) { Set-Prop $canopen "heartbeatMs" 1000 }
    } else {
        $sourceAddress = Parse-ConfigNumber (Get-Prop $product "sourceAddress" (Get-Prop $product "canAddress" 0x33)) 0x33
        if ($sourceAddress -gt 0xFF) { $sourceAddress = $sourceAddress -band 0xFF }
        Set-Prop $product "sourceAddress" (Hex-Text $sourceAddress 2)
        Set-Prop $product "canFrameFormat" "extended"
        Set-Prop $product "canAddress" (Compose-J1939BjmCanId $sourceAddress)
    }

    $messages = @((Get-Prop $can "messages" @()))
    $components = @((Get-Prop $config "components" @()))
    if ($messages.Count -eq 0 -or $components.Count -eq 0) {
        $address = Parse-ConfigNumber (Get-Prop $product "sourceAddress" 0x33) 0x33
        if ($protocol -eq "canopen") { $address = Parse-ConfigNumber (Get-Prop $product "nodeId" 0x48) 0x48 }
        Set-Prop $can "messages" @(New-GeneratedMessages $protocol $buttonCount $rollerCount $address)
        Set-Prop $config "components" @(New-GeneratedComponents $protocol $buttonCount $rollerCount $fnrEnabled)
        $generatedStructure = $true
    }

    Set-Prop $config "schemaVersion" 2
    Set-Prop $config "version" "2.0"
    Set-Prop $product "protocol" $protocol
    if ($null -eq (Get-Prop $product "name")) { Set-Prop $product "name" (Get-Prop $product "model" ([IO.Path]::GetFileNameWithoutExtension($Path))) }
    if ($null -eq (Get-Prop $product "model")) { Set-Prop $product "model" (Get-Prop $product "name" ([IO.Path]::GetFileNameWithoutExtension($Path))) }

    $calibration = Get-Prop $config "calibration"
    if ($null -eq $calibration) { $calibration = [ordered]@{}; Set-Prop $config "calibration" $calibration }
    if ($null -eq (Get-Prop $calibration "mode")) { Set-Prop $calibration "mode" "centerOnly" }
    $transport = "j1939VendorPgn"
    if ($protocol -eq "canopen") { $transport = "canopenSdo" }
    Set-Prop $calibration "transport" $transport
    Set-Prop $calibration "allowedInNormalModeReadOnly" $true
    Set-Prop $can "defaultBaudRate" (Parse-ConfigNumber (Get-Prop $can "defaultBaudRate" 250) 250)

    if ($null -ne $grid) {
        if ($null -eq (Get-Prop $grid "columns") -and $null -ne (Get-Prop $grid "cols")) { Set-Prop $grid "columns" (Get-Prop $grid "cols") }
        Remove-Prop $grid "cols"
    }

    $repairResult = Repair-VisualBindings $config
    $editorProfile = "j1939Migrated"
    if ($protocol -eq "canopen") { $editorProfile = "canopenMigrated" }
    $migrationStatus = "preservedMessagesAndComponents"
    if ($generatedStructure) { $migrationStatus = "generatedMissingStructure" }
    Set-Prop $config "editor" ([ordered]@{
        profile = $editorProfile
        buttonCount = $buttonCount
        rollerCount = $rollerCount
        fnrEnabled = $fnrEnabled
        migrationStatus = $migrationStatus
    })

    if (-not $DryRun) {
        $json = $config | ConvertTo-Json -Depth 32
        Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
    }

    return [pscustomobject]@{
        File = [IO.Path]::GetFileName($Path)
        Protocol = $protocol
        Buttons = $buttonCount
        Rollers = $rollerCount
        FNR = $fnrEnabled
        GeneratedStructure = $generatedStructure
        FixedBindings = $repairResult.FixedBindings
        RemovedOrphans = $repairResult.RemovedOrphans
    }
}

if (-not (Test-Path -LiteralPath $ProductsDir)) {
    throw "Products directory not found: $ProductsDir"
}

$results = Get-ChildItem -LiteralPath $ProductsDir -Filter *.json |
    Sort-Object Name |
    ForEach-Object { Convert-Product $_.FullName }

$results | Format-Table -AutoSize
