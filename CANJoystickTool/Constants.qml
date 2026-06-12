pragma Singleton
import QtQuick 6.5

QtObject {
    readonly property int width: 1280
    readonly property int height: 800
    readonly property int minInteractiveWidth: 1440
    readonly property int minInteractiveHeight: 860
    readonly property real minWindowScreenWidthRatio: 0.78
    readonly property real minWindowScreenHeightRatio: 0.78

    // ===== Light theme =====
    readonly property color bgPrimary: "#f5f5f7"
    readonly property color bgSecondary: "#ebedef"
    readonly property color bgCard: "#ffffff"
    readonly property color bgInput: "#f0f0f2"

    // ===== Text =====
    readonly property color textPrimary: "#1d1d1f"
    readonly property color textSecondary: "#86868b"
    readonly property color textMuted: "#a1a1a6"

    // ===== Status / Accent =====
    readonly property color accent: "#007aff"
    readonly property color accentDim: "#5ac8fa"
    readonly property color success: "#34c759"
    readonly property color warning: "#ff9500"
    readonly property color error: "#ff3b30"

    // Aliases used by hardware-oriented CANJoystickTool components.
    readonly property color accentColor: "#00e0ff"
    readonly property color successColor: success
    readonly property color warningColor: warning
    readonly property color errorColor: error

    // ===== Border =====
    readonly property color border: "#d2d2d7"
    readonly property color borderLight: "#e5e5ea"

    // ===== Fonts =====
    readonly property string relativeFontDirectory: "fonts"

    readonly property font font: Qt.font({
                                             family: Qt.application.font.family,
                                             pixelSize: Qt.application.font.pixelSize
                                         })
    readonly property font largeFont: Qt.font({
                                                  family: Qt.application.font.family,
                                                  pixelSize: Qt.application.font.pixelSize * 1.6
                                              })
    readonly property font monoFont: Qt.font({
                                                 family: "Consolas",
                                                 pixelSize: 12
                                             })

    // ===== Compatibility aliases =====
    readonly property color backgroundColor: bgPrimary
    readonly property color panelColor: bgCard

    // ===== Aluminum panel =====
    readonly property color aluminumLight: "#f2f2f2"
    readonly property color aluminumDark: "#dcdcdc"
    readonly property color aluminumShadow: "#b0b0b0"
    readonly property color aluminumHighlight: "#ffffff"

    // ===== Groove / Grid =====
    readonly property color grooveColor: "#e6e6e6"
    readonly property color gridColor: "#08000000"
    readonly property color axisLineColor: "#0F000000"

    // ===== Axis =====
    readonly property color axisFillColor: "#4b5563"
    readonly property color axisThumbColor: "#374151"

    // ===== Knob =====
    readonly property color knobLight: "#ffffff"
    readonly property color knobDark: "#e0e0e0"
    readonly property color limitGlow: "#9934c759"

    // ===== Corner radii =====
    readonly property int radiusPanel: 44
    readonly property int radiusRecessed: 36
    readonly property int radiusCard: 12
    readonly property int radiusButton: 8

    // ===== Home card reference =====
    readonly property int homeCardDesignSize: 480

    // ===== DownloadTool test layout contract =====
    readonly property int downloadToolContentMargin: 8
    readonly property int downloadToolCardGap: 8
    readonly property int downloadToolCardMargin: 16
    readonly property int downloadToolCardMarginMin: 12
    readonly property int downloadToolCardHeaderHeight: 20
    readonly property int downloadToolCardHeaderMinHeight: 18
    readonly property int downloadToolCardHeaderGap: 6
    readonly property int downloadToolCardHeaderGapMin: 4
    readonly property int downloadToolCardTitleFontSize: 16
    readonly property int downloadToolCardTitleMinFontSize: 14
    readonly property real downloadToolLeftWidthRatioDefault: 0.52
    readonly property int downloadToolDashboardMinHeight: 320
    readonly property int downloadToolBottomPanelMinHeight: 260
    readonly property int downloadToolBottomPanelMaxHeight: 360
    readonly property real downloadToolBottomPanelHeightRatio: 0.36
    readonly property int downloadToolMonitorRowHeight: 32
    readonly property int downloadToolMonitorHeaderHeight: 22
    readonly property int downloadToolMonitorColumnGap: 5

    // ===== Shadow parameters =====
    readonly property int panelShadowOffset: 30
    readonly property int panelShadowBlur: 60
    readonly property int insetShadowOffset: 8
    readonly property int insetShadowBlur: 20

    // ===== Shadow colors =====
    readonly property color shadowDark12: "#1F000000"
    readonly property color shadowDark05: "#0D000000"
    readonly property color shadowDark15: "#26000000"
    readonly property color shadowDark30: "#4D000000"

    // ===== Highlight colors =====
    readonly property color highlightWhite100: "#FFFFFFFF"
    readonly property color highlightWhite80: "#CCFFFFFF"
    readonly property color highlightWhite50: "#80FFFFFF"
    readonly property color highlightWhite40: "#66FFFFFF"
    readonly property color borderWhite30: "#4DFFFFFF"
    readonly property color borderWhite20: "#33FFFFFF"

    // ===== Roller / Wheel =====
    readonly property color rollerHousingColor: "#d4d4d4"
    readonly property color rollerWheelColor: "#222222"
    readonly property color rollerIndicatorColor: "#ff9500"

    // ===== Rocker switch =====
    readonly property color rockerHousingColor: "#111111"
    readonly property color rockerGradientStart: "#f59e0b"
    readonly property color rockerGradientEnd: "#fbbf24"
    readonly property color fnrForwardColor: "#22c55e"
    readonly property color fnrNeutralColor: "#10b981"
    readonly property color fnrReverseColor: "#ef4444"

    // ===== Industrial button =====
    readonly property color buttonBezelColor: "#1a1a1a"
    readonly property color buttonRedColor: "#ef4444"
    readonly property color buttonGreyColor: "#9ca3af"
    readonly property color buttonGreenColor: "#00d648"
    readonly property color buttonOrangeColor: "#f59e0b"
    readonly property color buttonBlackColor: "#3f3f46"
    readonly property color buttonBlueColor: "#3b82f6"
}
