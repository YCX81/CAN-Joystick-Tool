import QtQuick 6.5
import CANJoystickTool

Item {
    id: root

    property string eyebrow: ""
    property string title: ""
    property string subtitle: ""
    property string rightText: ""
    property bool showDivider: false
    property color accentColor: Constants.accent
    property color titleColor: Constants.textPrimary
    property color subtitleColor: Constants.textSecondary
    property color mutedColor: Constants.textMuted

    implicitWidth: 320
    implicitHeight: headerRow.implicitHeight + (showDivider ? 9 : 0)

    Row {
        id: headerRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 10

        Column {
            id: headerColumn
            width: Math.max(0, parent.width - rightLabel.implicitWidth - (rightLabel.visible ? headerRow.spacing : 0))
            spacing: 2

            Text {
                text: root.eyebrow
                visible: text.length > 0
                color: root.accentColor
                font.pixelSize: 10
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                text: root.title
                visible: text.length > 0
                color: root.titleColor
                font.pixelSize: 14
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                text: root.subtitle
                visible: text.length > 0
                color: root.subtitleColor
                font.pixelSize: 11
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        Text {
            id: rightLabel
            text: root.rightText
            visible: text.length > 0
            color: root.mutedColor
            font.pixelSize: 11
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: headerRow.bottom
        anchors.topMargin: 8
        height: 1
        visible: root.showDivider
        color: Constants.borderLight
    }
}
