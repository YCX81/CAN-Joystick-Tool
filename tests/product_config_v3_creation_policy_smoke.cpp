#include "LayoutManager.h"

#include <QCoreApplication>
#include <QJsonArray>
#include <QJsonObject>

#include <cstdio>

namespace {

bool expect(bool condition, const char *message)
{
    if (!condition)
        std::fprintf(stderr, "%s\n", message);
    return condition;
}

QJsonObject findControl(const QJsonObject &config, const QString &id)
{
    for (const QJsonValue &entry : config.value(QStringLiteral("controls")).toArray()) {
        const QJsonObject control = entry.toObject();
        if (control.value(QStringLiteral("id")).toString() == id)
            return control;
    }
    return {};
}

} // namespace

int main(int argc, char *argv[])
{
    QCoreApplication application(argc, argv);
    LayoutManager manager;
    const QJsonObject spec{
        {QStringLiteral("code"), QStringLiteral("CONFIRM-V3")},
        {QStringLiteral("version"), QStringLiteral("V2")},
        {QStringLiteral("customerName"), QStringLiteral("确认客户")},
        {QStringLiteral("calibrationMode"), QStringLiteral("minCenterMax")},
        {QStringLiteral("baudRate"), 250},
        {QStringLiteral("joystickTopology"), QStringLiteral("singleAxisY")},
        {QStringLiteral("buttonCount"), 3},
        {QStringLiteral("buttonNumbers"), QJsonArray{2, 3, 8}},
        {QStringLiteral("rollerCount"), 2},
        {QStringLiteral("hasWorkLight"), true}
    };

    bool ok = true;
    ok &= expect(manager.validateStandardProductSpecV3(spec)
                     .value(QStringLiteral("ok")).toBool(),
                 "valid creation spec was rejected");
    const QJsonObject config = manager.buildStandardProductConfigV3(spec);
    const QJsonObject summary = manager.summarizeProductConfigV3(config);
    ok &= expect(summary.value(QStringLiteral("ok")).toBool()
                     && summary.value(QStringLiteral("productCode")).toString()
                         == QStringLiteral("CONFIRM-V3")
                     && summary.value(QStringLiteral("joystickTopology")).toString()
                         == QStringLiteral("singleAxisY")
                     && summary.value(QStringLiteral("buttonNumbers")).toArray()
                         == QJsonArray{2, 3, 8}
                     && summary.value(QStringLiteral("rollerCount")).toInt() == 2
                     && summary.value(QStringLiteral("hasWorkLight")).toBool(),
                 "confirmation summary differs from generated config");

    QJsonObject invalid = spec;
    invalid.insert(QStringLiteral("buttonCount"), 13);
    ok &= expect(!manager.validateStandardProductSpecV3(invalid)
                      .value(QStringLiteral("ok")).toBool()
                     && manager.buildStandardProductConfigV3(invalid).isEmpty(),
                 "invalid creation counts were silently normalized");
    invalid = spec;
    invalid.insert(QStringLiteral("buttonNumbers"), QJsonArray{2, 2, 8});
    ok &= expect(!manager.validateStandardProductSpecV3(invalid)
                      .value(QStringLiteral("ok")).toBool(),
                 "duplicate physical button numbers were accepted");

    const QJsonObject inversion = manager.setPrimaryJoystickAxisInvertedV3(
        config, QStringLiteral("y"), true);
    const QJsonObject joystick = findControl(
        inversion.value(QStringLiteral("config")).toObject(), QStringLiteral("joystickY"));
    ok &= expect(inversion.value(QStringLiteral("ok")).toBool()
                     && joystick.value(QStringLiteral("axis")).toObject()
                            .value(QStringLiteral("transform")).toObject()
                            .value(QStringLiteral("invert")).toBool()
                     && !manager.setPrimaryJoystickAxisInvertedV3(
                            config, QStringLiteral("x"), true)
                            .value(QStringLiteral("ok")).toBool(),
                 "single-axis Y inversion was not applied canonically");
    return ok ? 0 : 1;
}
