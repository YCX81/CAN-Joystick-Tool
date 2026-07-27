#include "LayoutManager.h"

#include <QCoreApplication>
#include <QDebug>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QString>

namespace {

bool expect(bool condition, const QString &message)
{
    if (!condition) {
        qCritical().noquote() << message;
    }
    return condition;
}

QJsonObject loadExample(const QString &fileName)
{
    QFile file(QStringLiteral(PRODUCT_CONFIG_V3_EXAMPLES_DIR) + QLatin1Char('/') + fileName);
    if (!file.open(QIODevice::ReadOnly)) {
        qCritical().noquote() << "Could not open V3 example:" << file.fileName();
        return {};
    }

    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &error);
    if (error.error != QJsonParseError::NoError || !document.isObject()) {
        qCritical().noquote() << "Could not parse V3 example:" << file.fileName()
                              << error.errorString();
        return {};
    }
    return document.object();
}

bool errorContains(const QJsonObject &result, const QString &needle)
{
    for (const QJsonValue &value : result.value(QStringLiteral("errors")).toArray()) {
        if (value.toString().contains(needle, Qt::CaseInsensitive)) {
            return true;
        }
    }
    return false;
}

} // namespace

int main(int argc, char *argv[])
{
    QCoreApplication application(argc, argv);
    LayoutManager manager;
    bool ok = true;

    const QJsonObject validV3 =
        loadExample(QStringLiteral("valid-test-only-single-axis.json"));
    ok &= expect(!validV3.isEmpty(), QStringLiteral("V3 integration fixture is empty"));

    const QJsonObject validResult = manager.validateProductConfig(validV3);
    ok &= expect(validResult.value(QStringLiteral("ok")).toBool(),
                 QStringLiteral("LayoutManager rejected a valid V3 config: %1")
                     .arg(QString::fromUtf8(
                         QJsonDocument(validResult).toJson(QJsonDocument::Compact))));

    QJsonObject invalidV3 = validV3;
    QJsonObject layout = invalidV3.value(QStringLiteral("layout")).toObject();
    layout.insert(QStringLiteral("mode"), QStringLiteral("auto"));
    invalidV3.insert(QStringLiteral("layout"), layout);
    const QJsonObject invalidResult = manager.validateProductConfig(invalidV3);
    ok &= expect(!invalidResult.value(QStringLiteral("ok")).toBool(),
                 QStringLiteral("LayoutManager accepted V3 auto layout"));
    ok &= expect(errorContains(invalidResult, QStringLiteral("layout.mode")),
                 QStringLiteral("LayoutManager did not return the V3 layout.mode error"));

    const QJsonObject legacyV2 = manager.buildStandardProductConfig(QJsonObject{
        {QStringLiteral("model"), QStringLiteral("LEGACY-V2-COMPATIBILITY")},
        {QStringLiteral("buttonCount"), 1},
        {QStringLiteral("rollerCount"), 0}
    });
    ok &= expect(legacyV2.value(QStringLiteral("schemaVersion")).toInt() == 2,
                 QStringLiteral("legacy compatibility fixture is not schemaVersion 2"));
    const QJsonObject legacyResult = manager.validateProductConfig(legacyV2);
    ok &= expect(legacyResult.value(QStringLiteral("ok")).toBool(),
                 QStringLiteral("V3 integration broke V2 validation: %1")
                     .arg(QString::fromUtf8(
                         QJsonDocument(legacyResult).toJson(QJsonDocument::Compact))));

    if (!ok) {
        return 1;
    }
    qInfo() << "LayoutManager V3 validation integration smoke passed";
    return 0;
}
