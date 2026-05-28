import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts
import CANJoystickTool

// 右侧组件面板 - compact DownloadTool card style
Item {
    id: root

    property int panelWidth: 210

    // Public style API kept for existing callers.
    property color neuBg: "#e0e0e5"
    property color neuLightShadow: "#ffffff"
    property color neuDarkShadow: "#bebec3"
    property color neuSurface: "#e4e4e9"
    property color neuTextPrimary: "#2a2a2e"
    property color neuTextSecondary: "#76767e"
    property color neuAccent: "#00e0ff"

    signal componentRequested(string componentType)
    signal componentDragStarted(string componentType, real globalX, real globalY)
    signal componentDragMoved(real globalX, real globalY)
    signal componentDragEnded(real globalX, real globalY)

    width: panelWidth

    readonly property color bgPrimary: "#f5f5f7"
    readonly property color bgCard: "#ffffff"
    readonly property color bgInput: "#f0f0f2"
    readonly property color border: "#d2d2d7"
    readonly property color borderLight: "#e5e5ea"
    readonly property color textMuted: "#a1a1a6"
    readonly property color hoverFill: "#f7fbff"
    readonly property color pressedFill: "#eef5ff"
    readonly property color selectedFill: "#e8f0fe"
    property string activeComponentType: ""
    readonly property bool horizontalMode: width > height * 1.35

    function accentAlpha(alpha) {
        return Qt.rgba(neuAccent.r, neuAccent.g, neuAccent.b, alpha)
    }

    Rectangle {
        anchors.fill: parent
        color: bgCard
        radius: 8
        border.width: 1
        border.color: border
    }

    // ========== 面板内容 ==========
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "COMPONENTS"
                color: neuTextPrimary
                font.pixelSize: 12
                font.weight: Font.DemiBold
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                width: 6
                height: 6
                radius: 3
                color: neuAccent
                Layout.alignment: Qt.AlignVCenter
            }
        }

        Item {
            id: libraryArea
            Layout.fillWidth: true
            Layout.fillHeight: true

            Flickable {
                id: horizontalScroll
                anchors.fill: parent
                visible: root.horizontalMode
                contentWidth: horizontalContent.implicitWidth
                contentHeight: height
                flickableDirection: Flickable.HorizontalFlick
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.horizontal: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                Row {
                    id: horizontalContent
                    height: horizontalScroll.height
                    spacing: 16

                    Column {
                        width: buttonRow.implicitWidth
                        height: parent.height
                        spacing: 6

                        PanelSection {
                            sectionName: "BUTTONS"
                            width: buttonRow.implicitWidth
                        }

                        Row {
                            id: buttonRow
                            spacing: 8

                            Repeater {
                                model: ComponentRegistry.getComponentsInCategory("buttons")

                                ComponentTile {
                                    componentType: modelData
                                    componentDef: ComponentRegistry.getDefinition(modelData)
                                    tileWidth: 58
                                    tileHeight: 72
                                    onClicked: {
                                        root.activeComponentType = modelData
                                        root.componentRequested(modelData)
                                    }
                                }
                            }
                        }
                    }

                    Column {
                        width: fnrRow.implicitWidth
                        height: parent.height
                        spacing: 6

                        PanelSection {
                            sectionName: "FNR"
                            width: fnrRow.implicitWidth
                        }

                        Row {
                            id: fnrRow
                            spacing: 8

                            Repeater {
                                model: ComponentRegistry.getComponentsInCategory("fnr")

                                ComponentTile {
                                    componentType: modelData
                                    componentDef: ComponentRegistry.getDefinition(modelData)
                                    tileWidth: modelData === "FNRSwitch" ? 66 : 96
                                    tileHeight: 72
                                    onClicked: {
                                        root.activeComponentType = modelData
                                        root.componentRequested(modelData)
                                    }
                                }
                            }
                        }
                    }

                    Column {
                        width: rollerRow.implicitWidth
                        height: parent.height
                        spacing: 6

                        PanelSection {
                            sectionName: "ROLLERS"
                            width: rollerRow.implicitWidth
                        }

                        Row {
                            id: rollerRow
                            spacing: 8

                            Repeater {
                                model: ComponentRegistry.getComponentsInCategory("rollers")

                                ComponentTile {
                                    componentType: modelData
                                    componentDef: ComponentRegistry.getDefinition(modelData)
                                    tileWidth: modelData === "HorizontalRoller" ? 112 : 66
                                    tileHeight: 72
                                    onClicked: {
                                        root.activeComponentType = modelData
                                        root.componentRequested(modelData)
                                    }
                                }
                            }
                        }
                    }

                }
            }

            Flickable {
                id: scrollArea
                anchors.fill: parent
                visible: !root.horizontalMode
                contentHeight: contentCol.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                ColumnLayout {
                    id: contentCol
                    width: scrollArea.width
                    spacing: 10

                    // ========== Buttons ==========
                    PanelSection {
                        sectionName: "BUTTONS"
                        Layout.fillWidth: true
                    }

                    Grid {
                        Layout.alignment: Qt.AlignHCenter
                        columns: 3
                        rowSpacing: 8
                        columnSpacing: 8

                        Repeater {
                            model: ComponentRegistry.getComponentsInCategory("buttons")

                            ComponentTile {
                                componentType: modelData
                                componentDef: ComponentRegistry.getDefinition(modelData)
                                onClicked: {
                                    root.activeComponentType = modelData
                                    root.componentRequested(modelData)
                                }
                            }
                        }
                    }

                    // ========== FNR ==========
                    PanelSection {
                        sectionName: "FNR"
                        Layout.fillWidth: true
                    }

                    Flow {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        spacing: 8

                        Repeater {
                            model: ComponentRegistry.getComponentsInCategory("fnr")

                            ComponentTile {
                                componentType: modelData
                                componentDef: ComponentRegistry.getDefinition(modelData)
                                tileWidth: modelData === "FNRSwitch" ? 62 : 88
                                tileHeight: modelData === "FNRSwitch" ? 76 : 64
                                onClicked: {
                                    root.activeComponentType = modelData
                                    root.componentRequested(modelData)
                                }
                            }
                        }
                    }

                    // ========== Rollers ==========
                    PanelSection {
                        sectionName: "ROLLERS"
                        Layout.fillWidth: true
                    }

                    Row {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 8

                        Repeater {
                            model: ComponentRegistry.getComponentsInCategory("rollers")

                            ComponentTile {
                                componentType: modelData
                                componentDef: ComponentRegistry.getDefinition(modelData)
                                tileWidth: modelData === "HorizontalRoller" ? 104 : 62
                                tileHeight: modelData === "HorizontalRoller" ? 64 : 76
                                onClicked: {
                                    root.activeComponentType = modelData
                                    root.componentRequested(modelData)
                                }
                            }
                        }
                    }

                    // 弹簧
                    Item { Layout.fillHeight: true }
                }
            }
        }
    }

    // ========== Compact section header ==========
    component PanelSection: Item {
        property string sectionName: ""
        height: 18

        RowLayout {
            anchors.fill: parent
            spacing: 8

            Label {
                text: sectionName
                color: neuTextSecondary
                font.pixelSize: 10
                font.weight: Font.DemiBold
                Layout.alignment: Qt.AlignVCenter
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: borderLight
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    // ========== Component thumbnail tile ==========
    component ComponentTile: Item {
        id: tile
        property string componentType: ""
        property var componentDef: null
        property int tileWidth: 52
        property int tileHeight: 58
        property bool selected: root.activeComponentType === componentType
        readonly property var registryDefaultSize: ComponentRegistry.getDefaultSize(componentType)
        readonly property real registryDefaultWidth: registryDefaultSize && registryDefaultSize.width > 0 ? registryDefaultSize.width : 0
        readonly property real registryDefaultHeight: registryDefaultSize && registryDefaultSize.height > 0 ? registryDefaultSize.height : 0
        readonly property real fallbackThumbnailScale: componentDef ? (componentDef.thumbnailScale || 0.4) : 0.4
        readonly property real thumbnailFitScale: registryDefaultWidth > 0
                                                  && registryDefaultHeight > 0
                                                  && previewSlot.width > 0
                                                  && previewSlot.height > 0
                                                  ? Math.min(previewSlot.width / registryDefaultWidth,
                                                             previewSlot.height / registryDefaultHeight)
                                                  : fallbackThumbnailScale

        signal clicked()

        width: tileWidth
        height: tileHeight
        scale: tileMouse.pressed ? 0.985 : 1.0

        Behavior on scale {
            NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
        }

        // 主体
        Rectangle {
            id: tileMain
            anchors.fill: parent
            radius: 8
            color: tileMouse.dragging ? selectedFill
                  : tileMouse.pressed ? pressedFill
                  : tile.selected ? selectedFill
                  : tileMouse.containsMouse ? hoverFill
                  : bgCard
            border.width: 1
            border.color: tileMouse.dragging || tileMouse.pressed || tile.selected
                          ? root.neuAccent
                          : tileMouse.containsMouse ? root.accentAlpha(0.38) : borderLight

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 3
                radius: 8
                visible: tileMouse.dragging || tile.selected
                color: root.neuAccent
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 1
                color: "#ffffff"
                opacity: tileMouse.pressed ? 0.0 : 0.75
            }
        }

        // 缩略图内容
        Item {
            id: previewSlot
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: nameText.top
            anchors.margins: 4
            enabled: false
            clip: true

            Loader {
                id: thumbLoader
                anchors.centerIn: parent
                width: tile.registryDefaultWidth > 0 ? tile.registryDefaultWidth : 1
                height: tile.registryDefaultHeight > 0 ? tile.registryDefaultHeight : 1
                scale: tile.thumbnailFitScale
                transformOrigin: Item.Center
                source: getThumbSource(componentType)
                onLoaded: applyThumbConfig(item, componentType)
            }
        }

        // 名称
        Text {
            id: nameText
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 3
            anchors.horizontalCenter: parent.horizontalCenter
            text: componentDef ? componentDef.name : ""
            color: tile.selected || tileMouse.dragging ? neuTextPrimary : neuTextSecondary
            font.pixelSize: 8
            font.weight: tile.selected || tileMouse.dragging ? Font.DemiBold : Font.Medium
            elide: Text.ElideRight
            width: parent.width - 6
            horizontalAlignment: Text.AlignHCenter
        }

        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            cursorShape: Qt.PointingHandCursor

            property bool dragging: false
            property real pressX: 0
            property real pressY: 0

            onPressed: function(mouse) {
                pressX = mouse.x
                pressY = mouse.y
                dragging = false
            }

            onPositionChanged: function(mouse) {
                if (!pressed) return
                var dx = mouse.x - pressX
                var dy = mouse.y - pressY
                if (!dragging && (dx * dx + dy * dy) > 100) {
                    dragging = true
                    root.activeComponentType = tile.componentType
                    var gp = tile.mapToGlobal(mouse.x, mouse.y)
                    root.componentDragStarted(tile.componentType, gp.x, gp.y)
                }
                if (dragging) {
                    var gp2 = tile.mapToGlobal(mouse.x, mouse.y)
                    root.componentDragMoved(gp2.x, gp2.y)
                }
            }

            onReleased: function(mouse) {
                if (dragging) {
                    var gp = tile.mapToGlobal(mouse.x, mouse.y)
                    root.componentDragEnded(gp.x, gp.y)
                    dragging = false
                } else {
                    tile.clicked()
                }
            }

            onCanceled: {
                dragging = false
            }
        }

        function getThumbSource(type) {
            if (type.indexOf("Button") === 0) return "IndustrialButton.qml"
            if (type === "FNRSwitch") return "FNRSwitchUnit.qml"
            if (type === "HorizontalFNR") return "HorizontalFNRUnit.qml"
            if (type === "HorizontalFNRRight") return "HorizontalFNRRightUnit.qml"
            if (type === "VerticalRoller") return "VerticalRollerUnit.qml"
            if (type === "HorizontalRoller") return "HorizontalRollerUnit.qml"
            return ""
        }

        function applyThumbConfig(item, type) {
            if (!item) return
            var defaultConfig = ComponentRegistry.getDefaultConfig(type)
            for (var key in defaultConfig) {
                if (item.hasOwnProperty(key)) {
                    item[key] = defaultConfig[key]
                }
            }

            var defaultSize = ComponentRegistry.getDefaultSize(type)
            if (defaultSize.width > 0) item.width = defaultSize.width
            if (defaultSize.height > 0) item.height = defaultSize.height
        }
    }
}
