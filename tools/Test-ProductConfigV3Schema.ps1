#requires -Version 7.0

param(
    [string]$SchemaPath = (Join-Path $PSScriptRoot '..\schemas\product-config-v3.schema.json'),
    [string]$ExamplesPath = (Join-Path $PSScriptRoot '..\examples\product-config-v3')
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Read-JsonObject {
    param([string]$Path)

    Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -Depth 100
}

function Copy-JsonObject {
    param([object]$Value)

    $Value | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
}

function Assert-SemanticsRejects {
    param(
        [object]$Config,
        [string]$CaseName
    )

    $rejected = $false
    try {
        Assert-Semantics $Config $CaseName
    } catch {
        $rejected = $true
    }
    Assert-True $rejected "Expected semantic failure was not detected: $CaseName"
}

function Assert-ReferenceExists {
    param(
        [hashtable]$KnownIds,
        [string]$Reference,
        [string]$Context
    )

    Assert-True ($KnownIds.ContainsKey($Reference)) "$Context references missing id '$Reference'."
}

function Assert-Semantics {
    param(
        [object]$Config,
        [string]$Path
    )

    $messageIds = @{}
    foreach ($message in @($Config.messages)) {
        Assert-True (-not $messageIds.ContainsKey([string]$message.id)) "$Path has duplicate message id '$($message.id)'."
        $messageIds[[string]$message.id] = $true
    }

    $signalIds = @{}
    foreach ($signal in @($Config.signals)) {
        Assert-True (-not $signalIds.ContainsKey([string]$signal.id)) "$Path has duplicate signal id '$($signal.id)'."
        $signalIds[[string]$signal.id] = $true
        Assert-ReferenceExists $messageIds ([string]$signal.source.messageId) "$Path signal '$($signal.id)'"
    }

    $commandIds = @{}
    foreach ($command in @($Config.commands)) {
        Assert-True (-not $commandIds.ContainsKey([string]$command.id)) "$Path has duplicate command id '$($command.id)'."
        $commandIds[[string]$command.id] = $true

        $payloadBytes = @(([string]$command.frame.data).Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries))
        Assert-True ($payloadBytes.Count -eq [int]$command.frame.dlc) `
            "$Path command '$($command.id)' declares DLC $($command.frame.dlc) but contains $($payloadBytes.Count) data bytes."
    }

    $controlIds = @{}
    foreach ($control in @($Config.controls)) {
        Assert-True (-not $controlIds.ContainsKey([string]$control.id)) "$Path has duplicate control id '$($control.id)'."
        $controlIds[[string]$control.id] = $true

        switch ([string]$control.type) {
            'axis' {
                Assert-ReferenceExists $signalIds ([string]$control.axis.signalId) "$Path control '$($control.id)'"
            }
            'joystick' {
                Assert-ReferenceExists $signalIds ([string]$control.xAxis.signalId) "$Path control '$($control.id)' xAxis"
                Assert-ReferenceExists $signalIds ([string]$control.yAxis.signalId) "$Path control '$($control.id)' yAxis"
            }
            'button' {
                Assert-ReferenceExists $signalIds ([string]$control.signalId) "$Path control '$($control.id)'"
            }
            'fnr' {
                Assert-ReferenceExists $signalIds ([string]$control.signalId) "$Path control '$($control.id)'"
            }
            'numericDisplay' {
                Assert-ReferenceExists $signalIds ([string]$control.signalId) "$Path control '$($control.id)'"
            }
            'indicator' {
                Assert-ReferenceExists $signalIds ([string]$control.signalId) "$Path control '$($control.id)'"
            }
            'binaryOutput' {
                Assert-ReferenceExists $commandIds ([string]$control.onCommandId) "$Path control '$($control.id)' onCommandId"
                Assert-ReferenceExists $commandIds ([string]$control.offCommandId) "$Path control '$($control.id)' offCommandId"
            }
        }
    }

    foreach ($card in @($Config.layout.cards)) {
        if ([string]$card.kind -ne 'controls') {
            continue
        }
        foreach ($element in @($card.elements)) {
            Assert-ReferenceExists $controlIds ([string]$element.controlId) "$Path layout card '$($card.id)'"
        }
    }

    foreach ($test in @($Config.tests)) {
        foreach ($step in @($test.steps) + @($test.cleanup)) {
            if ($step.commandId) {
                Assert-ReferenceExists $commandIds ([string]$step.commandId) "$Path test '$($test.id)'"
            }
            if ($step.controlId) {
                Assert-ReferenceExists $controlIds ([string]$step.controlId) "$Path test '$($test.id)'"
            }
            if ($step.signalId) {
                Assert-ReferenceExists $signalIds ([string]$step.signalId) "$Path test '$($test.id)'"
            }
        }
    }

    if ([string]$Config.operation.firmware.source -eq 'bundled') {
        $expectedProductVersion = "V$($Config.operation.firmware.version)"
        Assert-True ([string]$Config.product.version -eq $expectedProductVersion) `
            "$Path product version '$($Config.product.version)' must match bundled firmware version '$($Config.operation.firmware.version)'."
        $expectedArtifactBaseName = "$($Config.product.code)_$($Config.product.version)"
        $actualArtifactBaseName = [System.IO.Path]::GetFileNameWithoutExtension([string]$Config.operation.firmware.artifact)
        Assert-True ($actualArtifactBaseName -ceq $expectedArtifactBaseName) `
            "$Path bundled firmware artifact '$($Config.operation.firmware.artifact)' must use base name '$expectedArtifactBaseName'."
    }

    if ([string]$Config.product.code -eq 'JC6000-BGA-HM025') {
        $onCommand = @($Config.commands | Where-Object id -eq 'workLightOn')
        $offCommand = @($Config.commands | Where-Object id -eq 'workLightOff')
        Assert-True ($onCommand.Count -eq 1) "$Path must define exactly one workLightOn command."
        Assert-True ($offCommand.Count -eq 1) "$Path must define exactly one workLightOff command."
        Assert-True ([int]$onCommand[0].frame.dlc -eq 3) "$Path workLightOn DLC must be 3."
        Assert-True ([string]$onCommand[0].frame.data -ceq '00 FA 00') "$Path workLightOn data must be '00 FA 00'."
        Assert-True ([int]$offCommand[0].frame.dlc -eq 3) "$Path workLightOff DLC must be 3."
        Assert-True ([string]$offCommand[0].frame.data -ceq '00 00 00') "$Path workLightOff data must be '00 00 00'."
        foreach ($command in @($onCommand[0], $offCommand[0])) {
            Assert-True ([int]$command.frame.priority -eq 6) "$Path $($command.id) priority must be 6."
            Assert-True ([string]$command.frame.pgn -ceq '0x00D000') "$Path $($command.id) PGN must be 0x00D000."
            Assert-True ([string]$command.frame.sourceAddress -ceq '0x03') "$Path $($command.id) source address must be 0x03."
            Assert-True ([string]$command.frame.destinationAddress -ceq '0x33') "$Path $($command.id) destination address must be 0x33."
        }
    }
}

function Repair-NamedInvalidFixture {
    param(
        [object]$Config,
        [string]$FixtureName
    )

    $repaired = Copy-JsonObject $Config
    switch ($FixtureName) {
        'invalid-auto-layout.json' {
            $repaired.layout.mode = 'designed'
        }
        'invalid-decimal-address.json' {
            $repaired.bus.sourceAddress = '0x33'
        }
        'invalid-missing-protocol.json' {
            $repaired | Add-Member -NotePropertyName protocol -NotePropertyValue 'j1939'
        }
        'invalid-missing-topology.json' {
            $repaired.controls[0] | Add-Member -NotePropertyName topology -NotePropertyValue ([pscustomobject]@{
                kind = 'singleAxis'
                orientation = 'horizontal'
            })
        }
        'invalid-operation-pair.json' {
            $repaired.operation.firmware = [pscustomobject]@{
                source = 'external'
            }
        }
        'invalid-canopen-identity-policy.json' {
            $repaired.identityPolicy | Add-Member -NotePropertyName reason -NotePropertyValue '设备身份未固化'
        }
        default {
            throw "No named repair is defined for invalid fixture: $FixtureName"
        }
    }
    return $repaired
}

if (-not (Test-Path -LiteralPath $SchemaPath)) {
    throw "Product Config V3 schema not found: $SchemaPath"
}
if (-not (Test-Path -LiteralPath $ExamplesPath -PathType Container)) {
    throw "Product Config V3 examples directory not found: $ExamplesPath"
}

$validExamples = @(Get-ChildItem -LiteralPath $ExamplesPath -Filter 'valid-*.json' -File | Sort-Object Name)
$invalidExamples = @(Get-ChildItem -LiteralPath $ExamplesPath -Filter 'invalid-*.json' -File | Sort-Object Name)
Assert-True ($validExamples.Count -gt 0) 'No valid Product Config V3 examples found.'
Assert-True ($invalidExamples.Count -gt 0) 'No invalid Product Config V3 examples found.'

$validatedConfigs = @()
foreach ($example in $validExamples) {
    $isValid = Test-Json -LiteralPath $example.FullName -SchemaFile $SchemaPath -ErrorAction SilentlyContinue
    Assert-True $isValid "Expected valid example failed schema validation: $($example.Name)"

    $config = Read-JsonObject $example.FullName
    Assert-Semantics $config $example.Name
    $validatedConfigs += $config
}

foreach ($example in $invalidExamples) {
    $isValid = Test-Json -LiteralPath $example.FullName -SchemaFile $SchemaPath -ErrorAction SilentlyContinue
    Assert-True (-not $isValid) "Expected invalid example unexpectedly passed schema validation: $($example.Name)"

    $invalidConfig = Read-JsonObject $example.FullName
    $repairedConfig = Repair-NamedInvalidFixture $invalidConfig $example.Name
    $repairedJson = $repairedConfig | ConvertTo-Json -Depth 100
    $repairIsValid = Test-Json -Json $repairedJson -SchemaFile $SchemaPath -ErrorAction SilentlyContinue
    Assert-True $repairIsValid `
        "Invalid fixture contains failures beyond its named target: $($example.Name)"
    Assert-Semantics $repairedConfig "repaired-$($example.Name)"
}

$hm025Config = @($validatedConfigs | Where-Object { $_.product.code -eq 'JC6000-BGA-HM025' })[0]
$invalidHm025Dlc = Copy-JsonObject $hm025Config
$invalidHm025Dlc.commands[0].frame.dlc = 8
Assert-SemanticsRejects $invalidHm025Dlc 'semantic-invalid-hm025-dlc'

$bundledConfig = @($validatedConfigs | Where-Object { $_.operation.firmware.source -eq 'bundled' })[0]
$invalidVersionMapping = Copy-JsonObject $bundledConfig
$invalidVersionMapping.product.version = 'V9.9.9'
Assert-SemanticsRejects $invalidVersionMapping 'semantic-invalid-product-firmware-version'

$invalidSignalReference = Copy-JsonObject $validatedConfigs[0]
$invalidSignalReference.signals[0].source.messageId = 'missingMessage'
Assert-SemanticsRejects $invalidSignalReference 'semantic-invalid-signal-reference'

$migrationConfig = @($validatedConfigs | Where-Object { $_.product.code -eq 'V3-CONTROL-COVERAGE' })[0]
Assert-True ($null -ne $migrationConfig) 'Valid examples must cover migration controls and system cards.'
Assert-True (@($migrationConfig.layout.cards | Where-Object kind -eq 'leftRegion').Count -eq 1) `
    'Migration example must preserve an explicit leftRegion card.'
Assert-True (@($migrationConfig.layout.cards | Where-Object kind -eq 'empty').Count -eq 1) `
    'Migration example must preserve an explicit empty grid cell.'
$blankCanvas = @($migrationConfig.layout.cards | Where-Object id -eq 'blankCanvasCard')[0]
Assert-True ($null -ne $blankCanvas -and @($blankCanvas.elements).Count -eq 0) `
    'A controls card with an explicit empty elements array must remain valid.'

$missingContentCanvas = Copy-JsonObject $migrationConfig
$missingContentCanvas.layout.cards[1].PSObject.Properties.Remove('contentCanvas')
$missingContentCanvasJson = $missingContentCanvas | ConvertTo-Json -Depth 100
Assert-True (-not (Test-Json -Json $missingContentCanvasJson -SchemaFile $SchemaPath -ErrorAction SilentlyContinue)) `
    'Controls cards must declare their own contentCanvas.'

$unknownElementProperty = Copy-JsonObject $migrationConfig
$unknownElementProperty.layout.cards[1].elements[0].properties |
    Add-Member -NotePropertyName arbitraryPatch -NotePropertyValue $true
$unknownElementPropertyJson = $unknownElementProperty | ConvertTo-Json -Depth 100
Assert-True (-not (Test-Json -Json $unknownElementPropertyJson -SchemaFile $SchemaPath -ErrorAction SilentlyContinue)) `
    'Layout element properties must reject unknown patch fields.'

$systemCardWithControls = Copy-JsonObject $migrationConfig
$systemCardWithControls.layout.cards[4] |
    Add-Member -NotePropertyName controlIds -NotePropertyValue @('rollerAxis')
$systemCardWithControlsJson = $systemCardWithControls | ConvertTo-Json -Depth 100
Assert-True (-not (Test-Json -Json $systemCardWithControlsJson -SchemaFile $SchemaPath -ErrorAction SilentlyContinue)) `
    'System cards must not accept controlIds.'

$invalidLifecycle = Copy-JsonObject $migrationConfig
$invalidLifecycle.lifecycle.status = 'retired'
$invalidLifecycleJson = $invalidLifecycle | ConvertTo-Json -Depth 100
Assert-True (-not (Test-Json -Json $invalidLifecycleJson -SchemaFile $SchemaPath -ErrorAction SilentlyContinue)) `
    'Lifecycle status must be active or deprecated.'

$branchFirmwareConfig = Copy-JsonObject $bundledConfig
$branchFirmwareConfig.product.version = 'V4'
$branchFirmwareConfig.operation.firmware.version = '4'
$branchFirmwareConfig.operation.firmware.artifact = 'JC6000-AR000003_V4.elf'
$branchFirmwareJson = $branchFirmwareConfig | ConvertTo-Json -Depth 100
Assert-True (Test-Json -Json $branchFirmwareJson -SchemaFile $SchemaPath -ErrorAction SilentlyContinue) `
    'Branch-only bundled firmware version 4 must map to product version V4.'

$unknownEncoding = Copy-JsonObject $migrationConfig
$unknownEncoding.signals[0].source.encoding = 'patched_decoder'
$unknownEncodingJson = $unknownEncoding | ConvertTo-Json -Depth 100
Assert-True (-not (Test-Json -Json $unknownEncodingJson -SchemaFile $SchemaPath -ErrorAction SilentlyContinue)) `
    'Unknown signal encodings must be rejected instead of accepted as patch fields.'

$unknownCalibrationField = Copy-JsonObject $migrationConfig
$unknownCalibrationField.calibration |
    Add-Member -NotePropertyName legacyPatch -NotePropertyValue $true
$unknownCalibrationJson = $unknownCalibrationField | ConvertTo-Json -Depth 100
Assert-True (-not (Test-Json -Json $unknownCalibrationJson -SchemaFile $SchemaPath -ErrorAction SilentlyContinue)) `
    'Calibration must reject unknown patch fields.'

$databaseBindingInJson = Copy-JsonObject $migrationConfig
$databaseBindingInJson |
    Add-Member -NotePropertyName customerBinding -NotePropertyValue 'database-owned'
$databaseBindingJson = $databaseBindingInJson | ConvertTo-Json -Depth 100
Assert-True (-not (Test-Json -Json $databaseBindingJson -SchemaFile $SchemaPath -ErrorAction SilentlyContinue)) `
    'Customer binding is database-owned and must not become an unknown product JSON field.'

$branchVersionConfig = Copy-JsonObject $validatedConfigs[0]
$branchVersionConfig.product.version = 'V2'
$branchVersionJson = $branchVersionConfig | ConvertTo-Json -Depth 100
Assert-True (Test-Json -Json $branchVersionJson -SchemaFile $SchemaPath -ErrorAction SilentlyContinue) `
    'Branch-only product version V2 must remain valid.'

$partialFirmwareVersionConfig = Copy-JsonObject $validatedConfigs[0]
$partialFirmwareVersionConfig.product.version = 'V2.0'
$partialFirmwareVersionJson = $partialFirmwareVersionConfig | ConvertTo-Json -Depth 100
Assert-True (-not (Test-Json -Json $partialFirmwareVersionJson -SchemaFile $SchemaPath -ErrorAction SilentlyContinue)) `
    'Partial firmware product version V2.0 must be rejected; use V2 or a full V2.x.y release.'

$modes = @($validatedConfigs | ForEach-Object { [string]$_.operation.mode } | Sort-Object -Unique)
$topologies = @(
    $validatedConfigs |
        ForEach-Object { @($_.controls) } |
        ForEach-Object { if ($_.topology) { [string]$_.topology.kind } } |
        Sort-Object -Unique
)
Assert-True ($modes -contains 'test_only') 'Valid examples must cover test_only operation.'
Assert-True ($modes -contains 'firmware-backed') 'Valid examples must cover firmware-backed operation.'
Assert-True ($topologies -contains 'singleAxis') 'Valid examples must cover singleAxis topology.'
Assert-True ($topologies -contains 'cross2D') 'Valid examples must cover cross2D topology.'
Assert-True (@($validatedConfigs | Where-Object { $_.product.code -eq 'JC6000-BGA-HM025' }).Count -eq 1) `
    'Valid examples must cover the HM025 work-light command.'

Write-Host "OK: $($validExamples.Count) valid and $($invalidExamples.Count) invalid Product Config V3 examples verified."
