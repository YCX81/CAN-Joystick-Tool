import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts
import QtQuick.Effects
import CANJoystickTool

// 右侧组件面板 - Light Neumorphism 风格
Item {
    id: root

    property int panelWidth: 210

    // Neumorphism 配色 (从父级传入)
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

    // ========== 面板背景 ==========
    Rectangle {
        anchors.fill: parent
        color: neuBg
    }

    // 左侧边缘凹槽分隔线
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: neuDarkShadow
    }
    Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: 1
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: neuLightShadow
    }

    // ========== 面板内容 ==========
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        anchors.topMargin: 28
        spacing: 20

        // 标题
        Text {
            text: "COMPONENTS"
            color: neuTextSecondary
            font.pixelSize: 10
            font.weight: Font.Bold
            font.letterSpacing: 3
            Layout.alignment: Qt.AlignHCenter
        }

        // 滚动区域
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: contentCol.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: contentCol
                width: parent.width
                spacing: 24

                // ========== Buttons ==========
                NeuSection {
                    sectionName: "BUTTONS"
                    Layout.fillWidth: true
                }

                // 按钮网格 - 3x2
                Grid {
                    Layout.alignment: Qt.AlignHCenter
                    columns: 3
                    rowSpacing: 10
                    columnSpacing: 10

                    Repeater {
                        model: ComponentRegistry.getComponentsInCategory("buttons")

                        NeuComponentTile {
                            componentType: modelData
                            componentDef: ComponentRegistry.getDefinition(modelData)
                            neuBg: root.neuBg
                            neuLight: root.neuLightShadow
                            neuDark: root.neuDarkShadow
                            onClicked: root.componentRequested(modelData)
                        }
                    }
                }

                // ========== FNR ==========
                NeuSection {
                    sectionName: "FNR"
                    Layout.fillWidth: true
                }

                Flow {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    Layout.leftMargin: 10; Layout.rightMargin: 10
                    spacing: 10

                    Repeater {
                        model: ComponentRegistry.getComponentsInCategory("fnr")

                        NeuComponentTile {
                            componentType: modelData
                            componentDef: ComponentRegistry.getDefinition(modelData)
                            tileWidth: modelData === "FNRSwitch" ? 60 : 72
                            tileHeight: modelData === "FNRSwitch" ? 72 : 60
                            neuBg: root.neuBg
                            neuLight: root.neuLightShadow
                            neuDark: root.neuDarkShadow
                            onClicked: root.componentRequested(modelData)
                        }
                    }
                }

                // ========== Rollers ==========
                NeuSection {
                    sectionName: "ROLLERS"
                    Layout.fillWidth: true
                }

                Row {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 10

                    Repeater {
                        model: ComponentRegistry.getComponentsInCategory("rollers")

                        NeuComponentTile {
                            componentType: modelData
                            componentDef: ComponentRegistry.getDefinition(modelData)
                            tileWidth: 60
                            tileHeight: 72
                            neuBg: root.neuBg
                            neuLight: root.neuLightShadow
                            neuDark: root.neuDarkShadow
                            onClicked: root.componentRequested(modelData)
                        }
                    }
                }

                // 弹簧
                Item { Layout.fillHeight: true }
            }
        }
    }

    // ========== Neumorphic 分组标题 ==========
    component NeuSection: Item {
        property string sectionName: ""
        height: 16

        Row {
            anchors.centerIn: parent
            spacing: 10

            // 左线
            Rectangle {
                width: 24
                height: 1
                anchors.verticalCenter: parent.verticalCenter
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: neuTextSecondary }
                }
            }

            Text {
                text: sectionName
                color: neuTextSecondary
                font.pixelSize: 9
                font.weight: Font.Medium
                font.letterSpacing: 2
            }

            // 右线
            Rectangle {
                width: 24
                height: 1
                anchors.verticalCenter: parent.verticalCenter
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: neuTextSecondary }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
        }
    }

    // ========== Neumorphic 组件缩略图 ==========
    component NeuComponentTile: Item {
        id: tile
        property string componentType: ""
        property var componentDef: null
        property int tileWidth: 50
        property int tileHeight: 60
        property color neuBg: "#e0e0e5"
        property color neuLight: "#ffffff"
        property color neuDark: "#bebec3"

        signal clicked()

        width: tileWidth
        height: tileHeight

        // ---- 凸起状态 (未按下) ----

        // 亮阴影 (左上)
        Rectangle {
            visible: !tileMouse.pressed
            anchors.fill: tileMain
            anchors.margins: -1
            anchors.leftMargin: -4
            anchors.topMargin: -4
            anchors.rightMargin: 4
            anchors.bottomMargin: 4
            radius: tileMain.radius + 1
            color: tile.neuLight
            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 0.5
                blurMax: 10
            }
        }

        // 暗阴影 (右下)
        Rectangle {
            visible: !tileMouse.pressed
            anchors.fill: tileMain
            anchors.margins: -1
            anchors.leftMargin: 4
            anchors.topMargin: 4
            anchors.rightMargin: -4
            anchors.bottomMargin: -4
            radius: tileMain.radius + 1
            color: tile.neuDark
            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 0.5
                blurMax: 10
            }
        }

        // 主体
        Rectangle {
            id: tileMain
            anchors.fill: parent
            radius: 10
            color: tile.neuBg

            // 按下时凹陷效果 - 顶部暗
            Rectangle {
                visible: tileMouse.pressed
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#35000000" }
                    GradientStop { position: 0.35; color: "transparent" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // 按下时凹陷效果 - 底部亮
            Rectangle {
                visible: tileMouse.pressed
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.65; color: "transparent" }
                    GradientStop { position: 1.0; color: "#15FFFFFF" }
                }
            }

            // 未按下 - 微妙顶部高光
            Rectangle {
                visible: !tileMouse.pressed
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#30FFFFFF" }
                    GradientStop { position: 0.25; color: "transparent" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // Hover 高亮边框
            Rectangle {
                visible: tileMouse.containsMouse && !tileMouse.pressed
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 1
                border.color: "#20" + neuAccent.toString().substring(1)
            }
        }

        // 缩略图内容
        Loader {
            id: thumbLoader
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 4
            scale: componentDef ? (componentDef.thumbnailScale || 0.4) : 0.4
            transformOrigin: Item.Top
            source: getThumbSource(componentType)
            onLoaded: applyThumbConfig(item, componentType)
        }

        // 名称
        Text {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 3
            anchors.horizontalCenter: parent.horizontalCenter
            text: componentDef ? componentDef.name : ""
            color: neuTextSecondary
            font.pixelSize: 8
            font.weight: Font.Medium
            elide: Text.ElideRight
            width: parent.width - 6
            horizontalAlignment: Text.AlignHCenter
        }

        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
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
        }

        function getThumbSource(type) {
            if (type.indexOf("Button") === 0) return "IndustrialButton.qml"
            if (type === "FNRSwitch") return "RockerSwitch.qml"
            if (type === "HorizontalFNR") return "HorizontalFNRUnit.qml"
            if (type === "HorizontalFNRRight") return "HorizontalFNRRightUnit.qml"
            if (type === "VerticalRoller") return "RollerWheel.qml"
            if (type === "HorizontalRoller") return "RollerWheel.qml"
            return ""
        }

        function applyThumbConfig(item, type) {
            if (!item) return
            if (type === "ButtonRed" && item.hasOwnProperty("variant")) item.variant = "red"
            else if (type === "ButtonGreen" && item.hasOwnProperty("variant")) item.variant = "green"
            else if (type === "ButtonOrange" && item.hasOwnProperty("variant")) item.variant = "orange"
            else if (type === "ButtonBlue" && item.hasOwnProperty("variant")) item.variant = "blue"
            else if (type === "ButtonBlack" && item.hasOwnProperty("variant")) item.variant = "black"
            else if (type === "ButtonGrey" && item.hasOwnProperty("variant")) item.variant = "grey"
            else if (type === "HorizontalRoller" && item.hasOwnProperty("orientation")) item.orientation = "horizontal"
        }
    }
}
