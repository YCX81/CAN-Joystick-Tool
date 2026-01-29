pragma Singleton
import QtQuick 6.5

QtObject {
    readonly property int width: 1920
    readonly property int height: 1080

    property string relativeFontDirectory: "fonts"

    /* Edit this comment to add your custom font */
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

    // 主题颜色 - 浅色Ive风格
    readonly property color backgroundColor: "#f5f5f7"
    readonly property color panelColor: "transparent"  // 使用渐变面板

    // 文字颜色
    readonly property color textPrimary: "#1d1d1f"
    readonly property color textSecondary: "#86868b"
    readonly property color textMuted: "#a1a1a6"

    // 状态颜色
    readonly property color accentColor: "#00e0ff"      // 青色
    readonly property color successColor: "#34c759"     // 绿色
    readonly property color warningColor: "#ff9500"
    readonly property color errorColor: "#ff3b30"

    // 边缘发光色
    readonly property color limitGlow: "#9934c759"  // 绿色边缘光 60%透明度

    // 轴值颜色 - 统一使用深灰
    readonly property color axisFillColor: "#4b5563"    // gray-600
    readonly property color axisThumbColor: "#374151"   // gray-700

    // 铝合金面板颜色
    readonly property color aluminumLight: "#f2f2f2"
    readonly property color aluminumDark: "#dcdcdc"
    readonly property color aluminumShadow: "#b0b0b0"
    readonly property color aluminumHighlight: "#ffffff"

    // 凹槽色
    readonly property color grooveColor: "#e6e6e6"

    // 手柄色
    readonly property color knobLight: "#ffffff"
    readonly property color knobDark: "#e0e0e0"

    // 网格色
    readonly property color gridColor: "#08000000"  // 3%透明度黑色
    readonly property color axisLineColor: "#0F000000"  // 6%黑轴线

    // ========== 统一圆角值 ==========
    readonly property int radiusPanel: 44       // 主面板
    readonly property int radiusRecessed: 36    // 凹槽区域
    readonly property int radiusCard: 12        // 轴卡片
    readonly property int radiusButton: 8       // 按钮

    // ========== 阴影参数 ==========
    readonly property int panelShadowOffset: 30   // 面板阴影偏移
    readonly property int panelShadowBlur: 60     // 面板阴影模糊
    readonly property int insetShadowOffset: 8    // 内凹阴影偏移
    readonly property int insetShadowBlur: 20     // 内凹阴影模糊

    // ========== 阴影颜色 ==========
    readonly property color shadowDark12: "#1F000000"    // 12%黑 - 内凹主阴影
    readonly property color shadowDark05: "#0D000000"    // 5%黑 - 细微阴影
    readonly property color shadowDark15: "#26000000"    // 15%黑 - 手柄阴影
    readonly property color shadowDark30: "#4D000000"    // 30%黑 - 中灯内阴影

    // ========== 高光颜色 ==========
    readonly property color highlightWhite100: "#FFFFFFFF"  // 100%白
    readonly property color highlightWhite80: "#CCFFFFFF"   // 80%白 - 手柄高光
    readonly property color highlightWhite50: "#80FFFFFF"   // 50%白 - 面板内边框
    readonly property color highlightWhite40: "#66FFFFFF"   // 40%白 - 手柄内边框
    readonly property color borderWhite30: "#4DFFFFFF"      // 30%白 - 卡片背景
    readonly property color borderWhite20: "#33FFFFFF"      // 20%白 - 手柄边框

    // ========== 滚轮组件颜色 ==========
    readonly property color rollerHousingColor: "#d4d4d4"
    readonly property color rollerWheelColor: "#222222"
    readonly property color rollerIndicatorColor: "#ff9500"

    // ========== 翘板开关颜色 ==========
    readonly property color rockerHousingColor: "#111111"
    readonly property color rockerGradientStart: "#f59e0b"
    readonly property color rockerGradientEnd: "#fbbf24"
    readonly property color fnrForwardColor: "#22c55e"
    readonly property color fnrNeutralColor: "#10b981"
    readonly property color fnrReverseColor: "#ef4444"

    // ========== 工业按钮颜色 ==========
    readonly property color buttonBezelColor: "#1a1a1a"
    readonly property color buttonRedColor: "#ef4444"
    readonly property color buttonGreyColor: "#9ca3af"
    readonly property color buttonGreenColor: "#00d648"
    readonly property color buttonOrangeColor: "#f59e0b"
    readonly property color buttonBlackColor: "#3f3f46"
    readonly property color buttonBlueColor: "#3b82f6"
}
