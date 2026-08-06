#include <QCoreApplication>
#include <QFile>
#include <QJSEngine>
#include <QJSValue>
#include <QJsonObject>
#include <QTextStream>

namespace {

bool expect(bool condition, const QString &message)
{
    if (!condition) {
        QTextStream(stderr) << "FAIL: " << message << '\n';
    }
    return condition;
}

QJsonObject v3Config(const QString &code, const QString &version)
{
    return {
        {QStringLiteral("schemaVersion"), 3},
        {QStringLiteral("product"),
         QJsonObject{
             {QStringLiteral("code"), code},
             {QStringLiteral("version"), version}
         }}
    };
}

QJsonObject v2Config(const QString &name, const QString &version)
{
    return {
        {QStringLiteral("schemaVersion"), 2},
        {QStringLiteral("version"), version},
        {QStringLiteral("product"),
         QJsonObject{{QStringLiteral("name"), name}}}
    };
}

} // namespace

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);

    QFile policy(QStringLiteral(PRODUCT_DRAFT_POLICY_SOURCE));
    if (!policy.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream(stderr) << "FAIL: unable to open product draft policy\n";
        return 1;
    }

    QString source = QString::fromUtf8(policy.readAll());
    source.remove(QStringLiteral(".pragma library"));

    QJSEngine engine;
    const QJSValue evaluation = engine.evaluate(source, policy.fileName());
    if (evaluation.isError()) {
        QTextStream(stderr) << "FAIL: draft policy evaluation failed: "
                            << evaluation.toString() << '\n';
        return 1;
    }

    const QJSValue compatibility =
        engine.globalObject().property(QStringLiteral("compatibility"));
    bool ok = expect(compatibility.isCallable(),
                     QStringLiteral("draft policy must expose compatibility"));
    if (!compatibility.isCallable()) {
        return 1;
    }

    const auto check = [&engine, &compatibility](const QJsonObject &officialConfig,
                                                 const QJsonObject &draftConfig) {
        return compatibility.call(
            QJSValueList{
                engine.toScriptValue(officialConfig.toVariantMap()),
                engine.toScriptValue(draftConfig.toVariantMap())
            });
    };

    QJSValue result = check(v3Config(QStringLiteral("JC6000-CUS-0043"),
                                    QStringLiteral("V1")),
                            v3Config(QStringLiteral("JC6000-CUS-0043"),
                                    QStringLiteral("V1")));
    ok &= expect(result.property(QStringLiteral("compatible")).toBool(),
                 QStringLiteral("matching V3 draft must remain recoverable"));

    result = check(v3Config(QStringLiteral("JC6000-CUS-0043"),
                            QStringLiteral("V1")),
                   v2Config(QStringLiteral("JC6000-CUS-0043"),
                            QStringLiteral("2.0")));
    ok &= expect(!result.property(QStringLiteral("compatible")).toBool()
                     && result.property(QStringLiteral("reason")).toString()
                            == QStringLiteral("schemaMismatch"),
                 QStringLiteral("V2 draft must never replace a V3 product"));

    result = check(v3Config(QStringLiteral("JC6000-CUS-0043"),
                            QStringLiteral("V1")),
                   v3Config(QStringLiteral("JC6000-BGA-B0003"),
                            QStringLiteral("V1")));
    ok &= expect(!result.property(QStringLiteral("compatible")).toBool()
                     && result.property(QStringLiteral("reason")).toString()
                            == QStringLiteral("productMismatch"),
                 QStringLiteral("another product's draft must never be offered"));

    result = check(v3Config(QStringLiteral("JC6000-CUS-0043"),
                            QStringLiteral("V1")),
                   v3Config(QStringLiteral("JC6000-CUS-0043"),
                            QStringLiteral("V2")));
    ok &= expect(!result.property(QStringLiteral("compatible")).toBool()
                     && result.property(QStringLiteral("reason")).toString()
                            == QStringLiteral("versionMismatch"),
                 QStringLiteral("another product version's draft must never be offered"));

    result = check(v2Config(QStringLiteral("JC6000-0389"),
                            QStringLiteral("2.0")),
                   v2Config(QStringLiteral("JC6000-0389"),
                            QStringLiteral("2.0")));
    ok &= expect(result.property(QStringLiteral("compatible")).toBool(),
                 QStringLiteral("matching legacy drafts must remain recoverable"));

    result = check(v3Config(QStringLiteral("JC6000-CUS-0043"),
                            QStringLiteral("V1")),
                   QJsonObject{{QStringLiteral("schemaVersion"), 3}});
    ok &= expect(!result.property(QStringLiteral("compatible")).toBool()
                     && result.property(QStringLiteral("reason")).toString()
                            == QStringLiteral("missingIdentity"),
                 QStringLiteral("identity-less drafts must be rejected"));

    if (ok) {
        QTextStream(stdout) << "PASS: product draft compatibility is identity-safe\n";
    }
    return ok ? 0 : 1;
}
