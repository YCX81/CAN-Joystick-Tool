import QtQuick 6.5
import QtQuick.Controls 6.5
import CANJoystickTool

Button {
    id: root

    property string variant: "secondary"
    property color accentColor: Constants.accent
    property color dangerColor: Constants.error
    property color borderColor: Constants.border
    property color contentColor: variant === "primary" || variant === "danger" ? "#ffffff" : Constants.textPrimary
    property int radius: Constants.radiusButton
    property int minWidth: 72

    icon.width: 14
    icon.height: 14

    leftPadding: 12
    rightPadding: 12
    topPadding: 5
    bottomPadding: 5
    spacing: 6
    implicitWidth: Math.max(minWidth, buttonContent.implicitWidth + leftPadding + rightPadding)
    implicitHeight: 30
    font.pixelSize: 12
    font.weight: Font.Medium

    function baseColor() {
        if (!enabled)
            return Constants.bgInput
        if (variant === "primary")
            return accentColor
        if (variant === "danger")
            return dangerColor
        if (variant === "ghost")
            return "transparent"
        return Constants.bgCard
    }

    function stateColor() {
        var base = baseColor()
        if (!enabled)
            return base
        if (down || checked)
            return variant === "ghost" ? Constants.bgInput : Qt.darker(base, 1.08)
        if (hovered)
            return variant === "ghost" ? Constants.bgInput : Qt.lighter(base, 1.04)
        return base
    }

    function stateBorderColor() {
        if (!enabled)
            return Constants.borderLight
        if (variant === "primary")
            return accentColor
        if (variant === "danger")
            return dangerColor
        if (hovered || checked)
            return accentColor
        return borderColor
    }

    background: Rectangle {
        radius: root.radius
        color: root.stateColor()
        border.width: 1
        border.color: root.stateBorderColor()

        Behavior on color {
            ColorAnimation { duration: 100 }
        }
    }

    contentItem: Item {
        id: buttonContent
        implicitWidth: contentRow.implicitWidth
        implicitHeight: contentRow.implicitHeight
        opacity: root.enabled ? 1 : 0.55

        Row {
            id: contentRow
            spacing: iconImage.visible && label.visible ? root.spacing : 0
            anchors.centerIn: parent

            Image {
                id: iconImage
                source: root.icon.source
                visible: source.toString().length > 0
                width: visible ? root.icon.width : 0
                height: visible ? root.icon.height : 0
                anchors.verticalCenter: parent.verticalCenter
                fillMode: Image.PreserveAspectFit
            }

            Text {
                id: label
                text: root.text
                visible: text.length > 0
                anchors.verticalCenter: parent.verticalCenter
                color: root.enabled ? root.contentColor : Constants.textMuted
                font: root.font
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
    }
}
