// Copyright (C) 2021 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import QtQuick 6.5
import CANJoystickTool

Window {
    id: window
    width: Constants.width
    height: Constants.height

    visible: true
    title: "CANJoystickTool"
    color: Constants.backgroundColor

    // 根据窗口实际大小计算缩放比例
    property real scaleFactor: Math.min(window.width / Constants.width,
                                        window.height / Constants.height)

    Screen01 {
        id: mainScreen
        transformOrigin: Item.Center
        scale: window.scaleFactor
        anchors.centerIn: parent
    }
}

