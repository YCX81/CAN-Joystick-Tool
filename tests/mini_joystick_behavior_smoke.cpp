#include <QCoreApplication>
#include <QGuiApplication>
#include <QImage>
#include <QObject>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QThread>
#include <QUrl>
#include <QVariantMap>

#include <cmath>
#include <iostream>
#include <memory>

namespace {

void processPendingEvents(int rounds = 4, int maxTimeMs = 50)
{
    for (int i = 0; i < rounds; ++i)
        QCoreApplication::processEvents(QEventLoop::AllEvents, maxTimeMs);
}

bool expect(bool condition, const char *message)
{
    if (!condition)
        std::cerr << message << '\n';
    return condition;
}

bool expectNear(double actual, double expected, double tolerance, const char *message)
{
    if (std::fabs(actual - expected) <= tolerance)
        return true;

    std::cerr << message << ": expected " << expected << ", actual " << actual << '\n';
    return false;
}

bool isDarkJoystickPixel(const QColor &color)
{
    return color.red() < 75
        && color.green() < 78
        && color.blue() < 82
        && color.alpha() > 180;
}

int darkJoystickPixelCount(const QImage &image)
{
    int count = 0;
    for (int y = 0; y < image.height(); ++y) {
        for (int x = 0; x < image.width(); ++x) {
            if (isDarkJoystickPixel(image.pixelColor(x, y)))
                ++count;
        }
    }
    return count;
}

} // namespace

int main(int argc, char *argv[])
{
    if (qEnvironmentVariableIsEmpty("QT_QPA_PLATFORM"))
        qputenv("QT_QPA_PLATFORM", "offscreen");

    QGuiApplication app(argc, argv);
    if (argc < 3) {
        std::cerr << "Usage: mini_joystick_behavior_smoke <source-dir> <build-dir>\n";
        return 1;
    }

    const QString sourceDir = QString::fromLocal8Bit(argv[1]);
    const QString buildDir = QString::fromLocal8Bit(argv[2]);

    QQmlEngine engine;
    engine.addImportPath(buildDir);
    engine.addImportPath(sourceDir + QStringLiteral("/tests/qml_imports"));

    QQmlComponent component(
        &engine,
        QUrl::fromLocalFile(sourceDir + QStringLiteral("/CANJoystickTool/MiniJoystickUnit.qml")));
    if (!component.isReady()) {
        for (const QQmlError &error : component.errors())
            std::cerr << error.toString().toStdString() << '\n';
        return 2;
    }

    QObject *created = component.create();
    if (!created) {
        for (const QQmlError &error : component.errors())
            std::cerr << error.toString().toStdString() << '\n';
        return 3;
    }
    const std::unique_ptr<QObject> guard(created);

    auto *root = qobject_cast<QQuickItem *>(created);
    if (!root) {
        std::cerr << "MiniJoystickUnit root is not a QQuickItem\n";
        return 4;
    }

    QQuickWindow window;
    window.setColor(QColor(QStringLiteral("#f5f5f7")));
    window.resize(440, 420);
    root->setParentItem(window.contentItem());
    root->setWidth(264);
    root->setHeight(328);
    root->setX(88);
    root->setY(40);
    window.show();

    bool ok = true;
    ok &= expect(root->setProperty("animationEnabled", false),
                 "MiniJoystickUnit should expose animationEnabled");
    ok &= expect(root->setProperty("invertX", false),
                 "MiniJoystickUnit should expose invertX");
    ok &= expect(root->setProperty("invertY", false),
                 "MiniJoystickUnit should expose invertY");
    ok &= expect(root->setProperty("gateMode", QStringLiteral("omnidirectional")),
                 "MiniJoystickUnit should expose gateMode");
    ok &= expect(root->setProperty("readOnly", true),
                 "MiniJoystickUnit should expose readOnly");
    ok &= expectNear(root->property("minValue").toDouble(), -1.0, 0.001,
                     "Mini joystick default minimum must match the normalized axis range");
    ok &= expectNear(root->property("maxValue").toDouble(), 1.0, 0.001,
                     "Mini joystick default maximum must match the normalized axis range");
    ok &= expectNear(root->property("designWidth").toDouble(), 244.0, 0.001,
                     "Mini joystick unit width should tightly fit the pad and Y display");
    ok &= expectNear(root->property("designHeight").toDouble(), 240.0, 0.001,
                     "Mini joystick unit height should align with VerticalRoller");

    auto *thumb = root->findChild<QQuickItem *>(QStringLiteral("miniJoystickThumb"));
    ok &= expect(thumb != nullptr, "Mini joystick should expose its visible thumb");
    if (thumb) {
        ok &= expectNear(thumb->width(), 40.0, 0.001,
                         "Mini joystick cap should use the reduced 40-unit diameter");
        ok &= expectNear(thumb->height(), 40.0, 0.001,
                         "Mini joystick cap should remain circular after resizing");
    }
    auto *thumbTop = root->findChild<QQuickItem *>(QStringLiteral("miniJoystickThumbTop"));
    ok &= expect(thumbTop != nullptr, "Mini joystick should expose its visible cap surface");
    auto *joystick = root->findChild<QQuickItem *>(QStringLiteral("miniJoystickControl"));
    ok &= expect(joystick != nullptr, "Mini joystick unit should expose its joystick control");
    if (joystick) {
        ok &= expectNear(joystick->width(), 200.0, 0.001,
                         "Mini joystick pad should match RollerWheel's 200-unit long edge");
        ok &= expectNear(joystick->height(), 200.0, 0.001,
                         "Mini joystick pad should remain square");
        ok &= expectNear(joystick->y(), -2.0, 0.001,
                         "Mini joystick pad top should align with VerticalRoller content");
        ok &= expectNear(joystick->property("shadowOffsetX").toDouble(), 3.0, 0.001,
                         "Mini joystick shadow should follow the shared rightward offset");
        ok &= expectNear(joystick->property("shadowOffsetY").toDouble(), 3.0, 0.001,
                         "Mini joystick shadow should follow the shared downward offset");
        ok &= expect(joystick->property("housingShadowStyle").toString()
                         == QStringLiteral("inset"),
                     "Mini joystick housing should use the roller-style inset shadow");
        ok &= expect(!joystick->property("externalHousingShadowEnabled").toBool(),
                      "Mini joystick housing must not cast an external shadow");
        const QVariant housingFillsBounds = joystick->property("housingFillsBounds");
        ok &= expect(housingFillsBounds.isValid(),
                     "Mini joystick should declare whether its housing fills the item bounds");
        ok &= expect(housingFillsBounds.toBool(),
                     "Mini joystick housing must fill its item bounds without transparent margins");
        ok &= expect(joystick->property("outerHousingStyle").toString()
                          == QStringLiteral("roller-flat"),
                      "Mini joystick should reuse the roller's flat outer housing");
        ok &= expect(!joystick->property("metallicHousingRimEnabled").toBool(),
                     "Mini joystick must not render a metallic gradient rim");
        ok &= expect(joystick->property("housingColor").value<QColor>()
                         == QColor(QStringLiteral("#d4d4d4")),
                     "Mini joystick outer housing color should match RollerWheel");
        ok &= expect(joystick->property("visualStyle").toString()
                         == QStringLiteral("xy-pad-top-view"),
                     "Mini joystick should use the XY-pad top-view visual style");
        const QVariant decorativeTicks = joystick->property("decorativeTicksEnabled");
        ok &= expect(decorativeTicks.isValid(),
                     "Mini joystick should declare whether decorative ticks are enabled");
        ok &= expect(!decorativeTicks.toBool(),
                     "Travel area and thumb cap must not use decorative ticks");
    }
    auto *socket = root->findChild<QQuickItem *>(QStringLiteral("miniJoystickSocket"));
    ok &= expect(socket != nullptr, "Mini joystick should expose its square travel socket");
    if (socket) {
        ok &= expectNear(socket->width(), socket->height(), 0.001,
                         "Mini joystick travel socket should be square");
        ok &= expect(socket->property("radius").toDouble() <= 12.0,
                     "Mini joystick travel socket must not be circular");
    }
    auto *xDisplay = root->findChild<QQuickItem *>(QStringLiteral("miniJoystickXDisplay"));
    auto *yDisplay = root->findChild<QQuickItem *>(QStringLiteral("miniJoystickYDisplay"));
    auto *yDisplaySlot = root->findChild<QQuickItem *>(
        QStringLiteral("miniJoystickYDisplaySlot"));
    ok &= expect(xDisplay != nullptr, "Mini joystick should expose its horizontal X display");
    ok &= expect(yDisplay != nullptr, "Mini joystick should expose its vertical Y display");
    ok &= expect(yDisplaySlot != nullptr,
                 "Mini joystick should expose the Y display layout slot");
    if (joystick && xDisplay && yDisplaySlot) {
        const double xDisplayGap = xDisplay->y() - (joystick->y() + joystick->height());
        const double yDisplayGap = yDisplaySlot->x() - (joystick->x() + joystick->width());
        ok &= expectNear(xDisplayGap, 8.0, 0.001,
                          "X display should use the roller's 8-unit spacing below the joystick body");
        ok &= expectNear(yDisplayGap, 8.0, 0.001,
                          "Y display should use the roller's 8-unit spacing right of the joystick body");
        ok &= expectNear(xDisplayGap, yDisplayGap, 0.001,
                          "X and Y displays must be equally spaced from the joystick body");
        ok &= expectNear(xDisplay->y() + xDisplay->height(), 242.0, 0.001,
                          "Mini joystick readout should preserve the roller-aligned content rhythm");
    }
    if (xDisplay) {
        ok &= expectNear(xDisplay->rotation(), 0.0, 0.001,
                         "X display should remain horizontal");
        ok &= expectNear(xDisplay->property("designWidth").toDouble(), 80.0, 0.001,
                         "X readout should reuse the roller DigitalDisplay");
        ok &= expect(xDisplay->property("label").toString() == QStringLiteral("%"),
                     "X readout should match the roller percentage display exactly");
        ok &= expect(!xDisplay->property("useSegmentGlyphs").isValid(),
                     "X readout must not use a joystick-specific glyph mode");
    }
    if (yDisplay) {
        ok &= expectNear(std::fabs(yDisplay->rotation()), 90.0, 0.001,
                         "Y display should be vertical");
        ok &= expectNear(yDisplay->property("designWidth").toDouble(), 80.0, 0.001,
                         "Y readout should reuse the roller DigitalDisplay");
        ok &= expect(yDisplay->property("label").toString() == QStringLiteral("%"),
                     "Y readout should match the roller percentage display exactly");
        ok &= expect(!yDisplay->property("useSegmentGlyphs").isValid(),
                     "Y readout must not use a joystick-specific glyph mode");
    }
    ok &= expect(root->findChild<QQuickItem *>(
                     QStringLiteral("miniJoystickPerspectiveSide")) == nullptr,
                 "Top-view joystick housing must not expose a 2.5D side face");
    ok &= expect(root->findChild<QQuickItem *>(
                     QStringLiteral("miniJoystickThumbSide")) == nullptr,
                 "Top-view joystick thumb must not expose a 2.5D side face");
    ok &= expect(root->findChild<QQuickItem *>(
                     QStringLiteral("miniJoystickShaft")) == nullptr,
                 "XY-pad joystick must not render a shaft between center and cap");
    ok &= expect(root->findChild<QQuickItem *>(
                     QStringLiteral("miniJoystickXAxis")) != nullptr,
                 "XY-pad joystick should expose a horizontal reference axis");
    ok &= expect(root->findChild<QQuickItem *>(
                     QStringLiteral("miniJoystickYAxis")) != nullptr,
                 "XY-pad joystick should expose a vertical reference axis");
    ok &= expect(root->findChild<QQuickItem *>(
                     QStringLiteral("miniJoystickCenterMark")) != nullptr,
                 "XY-pad joystick should expose its center zero mark");
    if (!ok)
        return 5;

    auto setAxes = [&](double x, double y) {
        bool localOk = root->setProperty("xValue", x);
        localOk &= root->setProperty("yValue", y);
        processPendingEvents();
        return localOk;
    };

    ok &= expect(setAxes(0.0, 0.0), "Failed to set centered axis values");
    const QPointF centered(thumb->x(), thumb->y());

    ok &= expect(setAxes(-1.0, -1.0), "Failed to set minimum axis values");
    const QPointF minimum(thumb->x(), thumb->y());
    ok &= expect(minimum.x() < centered.x() - 12.0,
                 "Negative X should visibly move the thumb left");
    ok &= expect(minimum.y() < centered.y() - 12.0,
                 "Negative Y should visibly move the thumb up");
    if (thumbTop && socket) {
        const QPointF capCenter = thumbTop->mapToItem(
            socket->parentItem(), QPointF(thumbTop->width() / 2.0, thumbTop->height() / 2.0));
        ok &= expectNear(capCenter.x(), socket->x(), 2.0,
                         "Minimum X should move the cap center to the left travel edge");
        ok &= expectNear(capCenter.y(), socket->y(), 2.0,
                         "Minimum Y should move the cap center to the top travel edge");
    }

    ok &= expect(setAxes(1.0, 1.0), "Failed to set maximum axis values");
    const QPointF maximum(thumb->x(), thumb->y());
    ok &= expect(maximum.x() > centered.x() + 12.0,
                 "Positive X should visibly move the thumb right");
    ok &= expect(maximum.y() > centered.y() + 12.0,
                 "Positive Y should visibly move the thumb down");
    if (thumbTop && socket) {
        const QPointF capCenter = thumbTop->mapToItem(
            socket->parentItem(), QPointF(thumbTop->width() / 2.0, thumbTop->height() / 2.0));
        ok &= expectNear(capCenter.x(), socket->x() + socket->width(), 2.0,
                         "Maximum X should move the cap center to the right travel edge");
        ok &= expectNear(capCenter.y(), socket->y() + socket->height(), 2.0,
                         "Maximum Y should move the cap center to the bottom travel edge");
    }

    ok &= expect(setAxes(2.5, -4.0), "Failed to set out-of-range axis values");
    ok &= expectNear(root->property("visualX").toDouble(), 1.0, 0.001,
                     "Visual X should clamp to its positive limit");
    ok &= expectNear(root->property("visualY").toDouble(), -1.0, 0.001,
                     "Visual Y should clamp to its negative limit");

    ok &= expect(setAxes(0.8, -0.3), "Failed to set directional axis values");
    ok &= expect(root->setProperty("invertX", true),
                  "Failed to reverse the mini joystick X output");
    processPendingEvents();
    ok &= expectNear(root->property("visualX").toDouble(), -0.8, 0.001,
                      "Reversed X output should mirror only the X direction");
    ok &= expectNear(root->property("visualY").toDouble(), -0.3, 0.001,
                      "Normal Y output must remain unchanged when only X is reversed");
    ok &= expect(root->setProperty("invertY", true),
                  "Failed to reverse the mini joystick Y output");
    processPendingEvents();
    ok &= expectNear(root->property("visualX").toDouble(), -0.8, 0.001,
                      "Reversing Y must preserve the selected X direction");
    ok &= expectNear(root->property("visualY").toDouble(), 0.3, 0.001,
                      "Reversed Y output should mirror the Y direction");
    ok &= expect(root->setProperty("invertX", false),
                 "Failed to restore normal mini joystick animation");
    ok &= expect(root->setProperty("invertY", false),
                 "Failed to restore normal mini joystick animation");
    ok &= expect(root->setProperty("gateMode", QStringLiteral("cross")),
                 "Failed to select cross mini joystick mode");
    processPendingEvents();
    ok &= expectNear(root->property("visualX").toDouble(), 0.8, 0.001,
                     "Cross mode should retain the dominant X direction");
    ok &= expectNear(root->property("visualY").toDouble(), 0.0, 0.001,
                     "Cross mode should suppress the weaker Y direction");
    ok &= expectNear(root->property("displayXValue").toDouble(), 80.0, 0.001,
                     "Animation settings must not alter the X data readout");
    ok &= expectNear(root->property("displayYValue").toDouble(), -30.0, 0.001,
                     "Animation settings must not alter the Y data readout");
    ok &= expect(root->setProperty("gateMode", QStringLiteral("omnidirectional")),
                 "Failed to restore omnidirectional mini joystick mode");

    ok &= expect(setAxes(0.82, -0.72), "Failed to set preview axis values");
    ok &= expectNear(root->property("displayXValue").toDouble(), 82.0, 0.001,
                     "X readout must show a -100 to 100 percentage");
    ok &= expectNear(root->property("displayYValue").toDouble(), -72.0, 0.001,
                     "Y readout must show a -100 to 100 percentage");
    processPendingEvents(6);
    QThread::msleep(80);
    processPendingEvents(4);

    const QImage image = window.grabWindow();
    ok &= expect(!image.isNull(), "Mini joystick preview should render to an image");
    ok &= expect(darkJoystickPixelCount(image) > 2500,
                 "Rendered preview should contain a substantial black joystick silhouette");
    ok &= expect(image.save(buildDir + QStringLiteral("/mini_joystick_preview.png")),
                 "Failed to save mini joystick preview screenshot");

    QQmlComponent wrapperComponent(
        &engine,
        QUrl::fromLocalFile(sourceDir + QStringLiteral("/CANJoystickTool/DraggableWrapper.qml")));
    ok &= expect(wrapperComponent.isReady(),
                 "DraggableWrapper should load for MiniJoystick binding round-trip");
    if (wrapperComponent.isReady()) {
        const std::unique_ptr<QObject> wrapper(wrapperComponent.create());
        ok &= expect(wrapper != nullptr, "Failed to create DraggableWrapper");
        if (wrapper) {
            wrapper->setProperty("componentType", QStringLiteral("MiniJoystick"));
            wrapper->setProperty("xBindingId", QStringLiteral("ejm_handleX"));
            wrapper->setProperty("yBindingId", QStringLiteral("ejm_handleY"));

            QQmlComponent canvasComponent(
                &engine,
                QUrl::fromLocalFile(sourceDir
                                    + QStringLiteral("/CANJoystickTool/DesignCanvas.qml")));
            ok &= expect(canvasComponent.isReady(),
                         "DesignCanvas should load with MiniJoystick menu settings");
            const std::unique_ptr<QObject> canvas(
                canvasComponent.isReady() ? canvasComponent.create() : nullptr);
            ok &= expect(canvas != nullptr, "Failed to create DesignCanvas");
            if (canvas) {
                ok &= expect(canvas->findChild<QObject *>(
                                 QStringLiteral("miniJoystickXOutputDirectionMenuItem"))
                                 != nullptr,
                             "MiniJoystick context menu must expose X output direction");
                ok &= expect(canvas->findChild<QObject *>(
                                 QStringLiteral("miniJoystickYOutputDirectionMenuItem"))
                                 != nullptr,
                             "MiniJoystick context menu must expose Y output direction");
                ok &= expect(canvas->findChild<QObject *>(
                                 QStringLiteral("miniJoystickGateModeMenuItem"))
                                 != nullptr,
                             "MiniJoystick context menu must expose gate mode");

                const QVariant wrapperArgument = QVariant::fromValue(wrapper.get());
                const bool xReversed = QMetaObject::invokeMethod(
                    canvas.get(), "toggleMiniJoystickXAxisOutputDirection",
                    Q_ARG(QVariant, wrapperArgument));
                const QVariantMap xOnlyConfig =
                    wrapper->property("componentConfig").toMap();
                ok &= expect(xReversed
                                 && xOnlyConfig.value(QStringLiteral("invertX")).toBool()
                                 && !xOnlyConfig.value(QStringLiteral("invertY")).toBool(),
                             "MiniJoystick X menu action must not change Y output direction");
                const bool yReversed = QMetaObject::invokeMethod(
                    canvas.get(), "toggleMiniJoystickYAxisOutputDirection",
                    Q_ARG(QVariant, wrapperArgument));
                const bool gateChanged = QMetaObject::invokeMethod(
                    canvas.get(), "toggleMiniJoystickGateMode",
                    Q_ARG(QVariant, wrapperArgument));
                ok &= expect(yReversed && gateChanged,
                              "MiniJoystick context menu actions should be invokable");

                const std::unique_ptr<QObject> rollerWrapper(
                    wrapperComponent.create());
                ok &= expect(rollerWrapper != nullptr,
                             "Failed to create roller wrapper");
                if (rollerWrapper) {
                    rollerWrapper->setProperty(
                        "componentType", QStringLiteral("VerticalRoller"));
                    ok &= expect(canvas->findChild<QObject *>(
                                     QStringLiteral("rollerOutputDirectionMenuItem"))
                                     != nullptr,
                                 "Roller context menu must expose output direction");
                    const QVariant rollerArgument =
                        QVariant::fromValue(rollerWrapper.get());
                    const bool rollerReversed = QMetaObject::invokeMethod(
                        canvas.get(), "toggleRollerOutputDirection",
                        Q_ARG(QVariant, rollerArgument));
                    ok &= expect(
                        rollerReversed
                            && rollerWrapper->property("componentConfig")
                                   .toMap()
                                   .value(QStringLiteral("invertInput"))
                                   .toBool(),
                        "Roller menu action must persist reversed output");
                }
            } else {
                for (const QQmlError &error : canvasComponent.errors())
                    std::cerr << error.toString().toStdString() << '\n';
            }

            QVariant serialized;
            const bool invoked = QMetaObject::invokeMethod(
                wrapper.get(), "toJSON", Q_RETURN_ARG(QVariant, serialized));
            ok &= expect(invoked, "Failed to serialize MiniJoystick wrapper");
            const QVariantMap serializedMap = serialized.toMap();
            ok &= expect(serializedMap.value(QStringLiteral("xBindingId")).toString()
                             == QStringLiteral("ejm_handleX"),
                         "Serialized MiniJoystick must retain its X binding");
            ok &= expect(serializedMap.value(QStringLiteral("yBindingId")).toString()
                             == QStringLiteral("ejm_handleY"),
                         "Serialized MiniJoystick must retain its Y binding");
            const QVariantMap serializedConfig =
                serializedMap.value(QStringLiteral("config")).toMap();
            ok &= expect(serializedConfig.value(QStringLiteral("invertX")).toBool()
                              && serializedConfig.value(QStringLiteral("invertY")).toBool(),
                          "Serialized MiniJoystick must retain independent reversed axes");
            ok &= expect(serializedConfig.value(QStringLiteral("gateMode")).toString()
                             == QStringLiteral("cross"),
                         "Serialized MiniJoystick must retain its cross gate mode");
        }
    } else {
        for (const QQmlError &error : wrapperComponent.errors())
            std::cerr << error.toString().toStdString() << '\n';
    }

    QQmlComponent verticalRollerComponent(
        &engine,
        QUrl::fromLocalFile(
            sourceDir + QStringLiteral("/CANJoystickTool/VerticalRollerUnit.qml")));
    ok &= expect(verticalRollerComponent.isReady(),
                 "VerticalRollerUnit should load for output inversion");
    if (verticalRollerComponent.isReady()) {
        const std::unique_ptr<QObject> roller(verticalRollerComponent.create());
        ok &= expect(roller != nullptr, "Failed to create VerticalRollerUnit");
        if (roller) {
            ok &= expect(roller->setProperty("value", 0.6),
                         "Failed to set roller input value");
            ok &= expectNear(roller->property("outputValue").toDouble(), 0.6, 0.001,
                             "Normal roller output must preserve its input");
            ok &= expect(roller->setProperty("invertInput", true),
                         "Failed to reverse roller output");
            ok &= expectNear(roller->property("outputValue").toDouble(), -0.6, 0.001,
                             "Reversed roller output must mirror its input");
        }
    } else {
        for (const QQmlError &error : verticalRollerComponent.errors())
            std::cerr << error.toString().toStdString() << '\n';
    }

    return ok ? 0 : 6;
}
