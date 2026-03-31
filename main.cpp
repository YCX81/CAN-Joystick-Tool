#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QSurfaceFormat>
#include "LayoutManager.h"

int main(int argc, char *argv[])
{
    QSurfaceFormat format;
    format.setSwapInterval(1);  // VSync
    format.setSwapBehavior(QSurfaceFormat::DoubleBuffer);
    QSurfaceFormat::setDefaultFormat(format);

    QApplication app(argc, argv);
    app.setOrganizationName("CANJoystickTool");
    app.setApplicationName("CANJoystickTool");

    QQuickStyle::setStyle("Material");

    QQmlApplicationEngine engine;

    // LayoutManager 已通过 QML_SINGLETON 宏自动注册
    // 无需手动调用 qmlRegisterSingletonType

    const QUrl url(QStringLiteral("qrc:/qt/qml/CANJoystickTool/CANJoystickToolContent/App.qml"));

    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
        &app, []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);

    engine.load(url);

    if (engine.rootObjects().isEmpty())
        return -1;

    return app.exec();
}
