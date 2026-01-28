#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QSurfaceFormat>
#include <QDebug>
#include <QDirIterator>

int main(int argc, char *argv[])
{
    QSurfaceFormat format;
    format.setSwapInterval(1);  // VSync
    format.setSwapBehavior(QSurfaceFormat::DoubleBuffer);
    QSurfaceFormat::setDefaultFormat(format);

    QApplication app(argc, argv);
    QQuickStyle::setStyle("Material");

    // 打印所有 qrc 资源，帮助调试
    qDebug() << "=== QRC Resources ===";
    QDirIterator it(":", QDirIterator::Subdirectories);
    while (it.hasNext()) {
        QString path = it.next();
        if (path.endsWith(".qml"))
            qDebug() << path;
    }
    qDebug() << "=====================";

    QQmlApplicationEngine engine;

    // qt_add_qml_module 默认: qrc:/qt/qml/<URI>/<FILE>
    const QUrl url(QStringLiteral("qrc:/qt/qml/CANJoystickTool/CANJoystickToolContent/App.qml"));

    qDebug() << "Loading:" << url;

    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
        &app, []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);

    engine.load(url);

    if (engine.rootObjects().isEmpty()) {
        qWarning() << "Failed to load QML";
        return -1;
    }

    return app.exec();
}
