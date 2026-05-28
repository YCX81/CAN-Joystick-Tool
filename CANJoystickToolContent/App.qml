// Copyright (C) 2021 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import QtQuick 6.5
import QtQuick.Window 6.5
import CANJoystickTool

Window {
    id: window
    width: Constants.width
    height: Constants.height
    minimumWidth: resolvedMinimumWidth()
    minimumHeight: resolvedMinimumHeight()

    visible: true
    title: "CANJoystickTool - Product Config Editor"
    color: Constants.backgroundColor

    readonly property real availableScreenWidth: Screen.desktopAvailableWidth > 0
                                               ? Screen.desktopAvailableWidth : Constants.width
    readonly property real availableScreenHeight: Screen.desktopAvailableHeight > 0
                                                ? Screen.desktopAvailableHeight : Constants.height

    function resolvedMinimumWidth() {
        var screenFloor = availableScreenWidth * Constants.minWindowScreenWidthRatio
        return Math.round(Math.min(availableScreenWidth,
                                  Math.max(Constants.minInteractiveWidth, screenFloor)))
    }

    function resolvedMinimumHeight() {
        var screenFloor = availableScreenHeight * Constants.minWindowScreenHeightRatio
        return Math.round(Math.min(availableScreenHeight,
                                  Math.max(Constants.minInteractiveHeight, screenFloor)))
    }

    Component.onCompleted: {
        width = Math.max(width, minimumWidth)
        height = Math.max(height, minimumHeight)
    }

    ProductEditor {
        id: productEditor
        anchors.fill: parent
    }
}
