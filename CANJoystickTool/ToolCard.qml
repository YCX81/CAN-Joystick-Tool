import QtQuick 6.5
import CANJoystickTool

Rectangle {
    id: root

    default property alias content: contentArea.data

    property string title: ""
    property string subtitle: ""
    property int padding: 12
    property int contentSpacing: 10
    property bool hoverEnabled: false
    property bool clickable: false
    property color backgroundColor: Constants.bgCard
    property color hoverColor: "#fbfbfd"
    property color pressedColor: Constants.bgInput
    property color borderColor: Constants.borderLight
    property color hoverBorderColor: Constants.border
    property color pressedBorderColor: Constants.accent

    readonly property bool hovered: hoverHandler.hovered
    readonly property bool pressed: tapHandler.pressed

    signal clicked()

    implicitWidth: 260
    implicitHeight: Math.max(72, contentColumn.implicitHeight + padding * 2)
    radius: Constants.radiusButton
    color: pressed ? pressedColor : (hovered ? hoverColor : backgroundColor)
    border.width: 1
    border.color: pressed ? pressedBorderColor : (hovered ? hoverBorderColor : borderColor)
    clip: true

    Behavior on color {
        ColorAnimation { duration: 120 }
    }

    Column {
        id: contentColumn
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: root.contentSpacing

        SectionHeader {
            width: parent.width
            title: root.title
            subtitle: root.subtitle
            visible: root.title.length > 0 || root.subtitle.length > 0
        }

        Item {
            id: contentArea
            width: parent.width
            implicitHeight: childrenRect.height
            visible: children.length > 0
        }
    }

    HoverHandler {
        id: hoverHandler
        enabled: root.hoverEnabled || root.clickable
    }

    TapHandler {
        id: tapHandler
        enabled: root.clickable
        onTapped: root.clicked()
    }
}
