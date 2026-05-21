import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import CANJoystickTool

// 主界面 - 展示三张控制卡片
Rectangle {
    id: root
    implicitWidth: Constants.width
    implicitHeight: Constants.height
    color: Constants.backgroundColor

    readonly property int cardSpacing: 24
    readonly property real cardSize: Math.max(300, Math.min((width - cardSpacing * 2 - 64) / 3,
                                                            height - 120))

    // 三张卡片水平排列
    Row {
        anchors.centerIn: parent
        spacing: root.cardSpacing

        // 摇杆卡片
        XYAxisCard {
            id: joystickCard
            panelWidth: root.cardSize
            panelHeight: root.cardSize
        }

        // 滚轮卡片
        RollersCard {
            id: rollersCard
            panelWidth: root.cardSize
            panelHeight: root.cardSize
        }

        // 手柄卡片
        HandleCard {
            id: handleCard
            panelWidth: root.cardSize
            panelHeight: root.cardSize
        }
    }
}
