#include <QCoreApplication>
#include <QDebug>
#include <QFile>
#include <QJSValue>
#include <QJSEngine>
#include <QString>

namespace {

bool expect(bool condition, const QString &message)
{
    if (!condition) {
        qCritical().noquote() << message;
    }
    return condition;
}

QJSValue call(QJSEngine &engine, const QString &name, const QJSValueList &arguments)
{
    return engine.globalObject().property(name).call(arguments);
}

} // namespace

int main(int argc, char *argv[])
{
    QCoreApplication application(argc, argv);

    QFile source(QStringLiteral(FNR_MAPPING_SOURCE));
    if (!expect(source.open(QIODevice::ReadOnly | QIODevice::Text),
                QStringLiteral("could not open FnrMapping.js"))) {
        return 1;
    }

    QString script = QString::fromUtf8(source.readAll());
    script.remove(QStringLiteral(".pragma library"));

    QJSEngine engine;
    const QJSValue evaluation = engine.evaluate(script, source.fileName());
    if (!expect(!evaluation.isError(),
                QStringLiteral("FnrMapping.js did not evaluate: %1").arg(evaluation.toString()))) {
        return 1;
    }

    bool ok = true;
    const QJSValue legacyThree = call(engine, QStringLiteral("parseLegacyBinding"),
                                      {QStringLiteral("buttons.fnr:1,2,7")});
    ok &= expect(legacyThree.property(QStringLiteral("sourceId")).toString()
                     == QStringLiteral("buttons"),
                 QStringLiteral("legacy binding source was not parsed"));
    ok &= expect(legacyThree.property(QStringLiteral("forward")).toInt() == 1,
                 QStringLiteral("legacy F index was not parsed"));
    ok &= expect(legacyThree.property(QStringLiteral("neutral")).toInt() == 2,
                 QStringLiteral("legacy N index was not parsed"));
    ok &= expect(legacyThree.property(QStringLiteral("reverse")).toInt() == 7,
                 QStringLiteral("legacy R index was not parsed"));

    const QJSValue legacyTwo = call(engine, QStringLiteral("parseLegacyBinding"),
                                    {QStringLiteral("buttons.fnr:1,7")});
    ok &= expect(legacyTwo.property(QStringLiteral("forward")).toInt() == 1
                     && legacyTwo.property(QStringLiteral("neutral")).isUndefined()
                     && legacyTwo.property(QStringLiteral("reverse")).toInt() == 7,
                 QStringLiteral("two-button legacy F/R binding was not parsed"));

    ok &= expect(call(engine, QStringLiteral("parseLegacyBinding"),
                      {QStringLiteral("buttons.1")}).isNull(),
                 QStringLiteral("ordinary button binding was treated as legacy FNR"));

    QJSValue sparseIndexes = engine.newArray(3);
    sparseIndexes.setProperty(0, 1);
    sparseIndexes.setProperty(1, 2);
    sparseIndexes.setProperty(2, 7);
    const QJSValue options = call(engine, QStringLiteral("buttonOptions"),
                                  {sparseIndexes, 8, true});
    ok &= expect(options.property(QStringLiteral("length")).toInt() == 4,
                 QStringLiteral("optional N choices must include the inferred-neutral option"));
    ok &= expect(options.property(0).property(QStringLiteral("index")).toInt() == -1,
                 QStringLiteral("the first N choice must mean not wired"));
    ok &= expect(options.property(1).property(QStringLiteral("number")).toInt() == 2
                     && options.property(3).property(QStringLiteral("number")).toInt() == 8,
                 QStringLiteral("sparse physical button numbers were not preserved"));

    const QJSValue denseOptions = call(engine, QStringLiteral("buttonOptions"),
                                       {engine.newArray(), 3, false});
    ok &= expect(denseOptions.property(QStringLiteral("length")).toInt() == 3
                     && denseOptions.property(0).property(QStringLiteral("number")).toInt() == 1
                     && denseOptions.property(2).property(QStringLiteral("number")).toInt() == 3,
                 QStringLiteral("legacy dense button groups must expose their complete range"));

    ok &= expect(call(engine, QStringLiteral("validateSelection"), {1, -1, 7}).toString().isEmpty(),
                 QStringLiteral("valid two-button F/R mapping was rejected"));
    ok &= expect(!call(engine, QStringLiteral("validateSelection"), {1, 1, 7}).toString().isEmpty(),
                 QStringLiteral("duplicate F/N mapping was accepted"));
    ok &= expect(!call(engine, QStringLiteral("validateSelection"), {-1, -1, 7}).toString().isEmpty(),
                 QStringLiteral("missing F mapping was accepted"));

    const QJSValue mapping = call(engine, QStringLiteral("buildButtonMapping"),
                                  {QStringLiteral("bjm.buttons"), 1, -1, 7});
    ok &= expect(mapping.property(QStringLiteral("source")).toString()
                     == QStringLiteral("bjm.buttons"),
                 QStringLiteral("button mapping source was not stored"));
    ok &= expect(mapping.property(QStringLiteral("forward")).toInt() == 1
                     && mapping.property(QStringLiteral("neutral")).isUndefined()
                     && mapping.property(QStringLiteral("reverse")).toInt() == 7,
                 QStringLiteral("unwired N must be omitted from JSON mapping"));

    const QJSValue explicitNeutral = call(engine, QStringLiteral("buildButtonMapping"),
                                          {QStringLiteral("bjm.buttons"), 1, 2, 7});
    ok &= expect(explicitNeutral.property(QStringLiteral("neutral")).toInt() == 2,
                 QStringLiteral("wired N must be stored in JSON mapping"));

    return ok ? 0 : 1;
}
