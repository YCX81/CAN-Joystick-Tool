import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import CANJoystickTool

// 主界面 - 展示三张控制卡片
Rectangle {
    id: root
    width: Constants.width
    height: Constants.height
    color: Constants.backgroundColor

    // 三张卡片水平排列
    Row {
        anchors.centerIn: parent
        spacing: 24

        // 摇杆卡片
        XYAxisCard {
            id: joystickCard
        }

        // 滚轮卡片
        RollersCard {
            id: rollersCard
        }

        // 手柄卡片
        HandleCard {
            id: handleCard
        }
    }
}
