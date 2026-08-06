#include <QCoreApplication>
#include <QFile>
#include <QJSEngine>
#include <QJSValue>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>
#include <QTextStream>

namespace {

bool expect(bool condition, const QString &message)
{
    if (!condition) {
        QTextStream(stderr) << "FAIL: " << message << '\n';
    }
    return condition;
}

QJsonObject findBinding(const QJsonArray &bindings, const QString &id)
{
    for (const QJsonValue &value : bindings) {
        const QJsonObject binding = value.toObject();
        if (binding.value(QStringLiteral("id")).toString() == id) {
            return binding;
        }
    }
    return {};
}

QSet<int> buttonPositions(const QJsonArray &controls)
{
    QSet<int> positions;
    for (const QJsonValue &value : controls) {
        const QJsonObject control = value.toObject();
        if (control.value(QStringLiteral("type")).toString()
            == QStringLiteral("button")) {
            positions.insert(control.value(QStringLiteral("position")).toInt());
        }
    }
    return positions;
}

int elementCount(const QJsonArray &cards)
{
    int count = 0;
    for (const QJsonValue &value : cards) {
        count += value.toObject()
                     .value(QStringLiteral("elements"))
                     .toArray()
                     .size();
    }
    return count;
}

} // namespace

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);

    QFile adapter(QStringLiteral(PRODUCT_CONFIG_V3_EDITOR_ADAPTER_SOURCE));
    if (!adapter.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream(stderr) << "FAIL: unable to open V3 editor adapter\n";
        return 1;
    }

    QString source = QString::fromUtf8(adapter.readAll());
    source.remove(QStringLiteral(".pragma library"));

    QJSEngine engine;
    QJSValue evaluation = engine.evaluate(source, adapter.fileName());
    if (evaluation.isError()) {
        QTextStream(stderr) << "FAIL: adapter evaluation failed: "
                            << evaluation.toString() << '\n';
        return 1;
    }

    const QJsonObject config{
        {QStringLiteral("schemaVersion"), 3},
        {QStringLiteral("signals"),
         QJsonArray{
             QJsonObject{
                 {QStringLiteral("id"), QStringLiteral("bjm_button0")},
                 {QStringLiteral("kind"), QStringLiteral("button")},
                 {QStringLiteral("source"),
                  QJsonObject{{QStringLiteral("messageId"), QStringLiteral("bjm")}}}
             },
             QJsonObject{
                 {QStringLiteral("id"), QStringLiteral("bjm_button2")},
                 {QStringLiteral("kind"), QStringLiteral("button")},
                 {QStringLiteral("source"),
                  QJsonObject{{QStringLiteral("messageId"), QStringLiteral("bjm")}}}
             },
             QJsonObject{
                 {QStringLiteral("id"), QStringLiteral("bjm_button4")},
                 {QStringLiteral("kind"), QStringLiteral("button")},
                 {QStringLiteral("source"),
                  QJsonObject{{QStringLiteral("messageId"), QStringLiteral("bjm")}}}
             },
             QJsonObject{
                 {QStringLiteral("id"), QStringLiteral("bjm_fnrButtons")},
                 {QStringLiteral("kind"), QStringLiteral("packedButtons")},
                 {QStringLiteral("source"),
                  QJsonObject{
                      {QStringLiteral("messageId"), QStringLiteral("bjm")},
                      {QStringLiteral("bitLength"), 10}
                  }}
             }
         }},
        {QStringLiteral("controls"),
         QJsonArray{
             QJsonObject{
                 {QStringLiteral("id"), QStringLiteral("joystickXY")},
                 {QStringLiteral("type"), QStringLiteral("joystick")},
                 {QStringLiteral("label"), QStringLiteral("XY轴")}
             },
             QJsonObject{
                 {QStringLiteral("id"), QStringLiteral("button1")},
                 {QStringLiteral("type"), QStringLiteral("button")},
                 {QStringLiteral("label"), QStringLiteral("按钮 1")},
                 {QStringLiteral("signalId"), QStringLiteral("bjm_button0")},
                 {QStringLiteral("position"), 0}
             },
             QJsonObject{
                 {QStringLiteral("id"), QStringLiteral("roller1")},
                 {QStringLiteral("type"), QStringLiteral("axis")},
                 {QStringLiteral("role"), QStringLiteral("roller")},
                 {QStringLiteral("label"), QStringLiteral("滚轮1")},
                 {QStringLiteral("axis"),
                  QJsonObject{{QStringLiteral("signalId"), QStringLiteral("roller1Position")}}}
             },
              QJsonObject{
                  {QStringLiteral("id"), QStringLiteral("roller2")},
                  {QStringLiteral("type"), QStringLiteral("axis")},
                  {QStringLiteral("role"), QStringLiteral("roller")},
                  {QStringLiteral("label"), QStringLiteral("滚轮2")},
                  {QStringLiteral("axis"),
                   QJsonObject{{QStringLiteral("signalId"), QStringLiteral("roller2Position")}}}
              },
              QJsonObject{
                  {QStringLiteral("id"), QStringLiteral("roller3")},
                  {QStringLiteral("type"), QStringLiteral("axis")},
                  {QStringLiteral("role"), QStringLiteral("roller")},
                  {QStringLiteral("label"), QStringLiteral("滚轮3")},
                  {QStringLiteral("axis"),
                   QJsonObject{{QStringLiteral("signalId"), QStringLiteral("roller3Position")}}}
              },
              QJsonObject{
                  {QStringLiteral("id"), QStringLiteral("roller4")},
                  {QStringLiteral("type"), QStringLiteral("axis")},
                  {QStringLiteral("role"), QStringLiteral("roller")},
                  {QStringLiteral("label"), QStringLiteral("滚轮4")},
                  {QStringLiteral("axis"),
                   QJsonObject{{QStringLiteral("signalId"), QStringLiteral("roller4Position")}}}
              },
              QJsonObject{
                  {QStringLiteral("id"), QStringLiteral("miniJoystick_roller1_roller3")},
                  {QStringLiteral("type"), QStringLiteral("joystick")},
                  {QStringLiteral("label"), QStringLiteral("过期迷你摇杆")}
              },
              QJsonObject{
                  {QStringLiteral("id"), QStringLiteral("pot1")},
                  {QStringLiteral("type"), QStringLiteral("axis")},
                  {QStringLiteral("role"), QStringLiteral("potentiometer")},
                  {QStringLiteral("label"), QStringLiteral("旋钮1")},
                  {QStringLiteral("axis"),
                   QJsonObject{{QStringLiteral("signalId"),
                                QStringLiteral("pot1Position")}}}
              },
             QJsonObject{
                 {QStringLiteral("id"), QStringLiteral("fnr")},
                 {QStringLiteral("type"), QStringLiteral("fnr")},
                 {QStringLiteral("label"), QStringLiteral("FNR")},
                 {QStringLiteral("signalId"), QStringLiteral("bjm_fnrButtons")},
                 {QStringLiteral("positions"),
                  QJsonObject{
                      {QStringLiteral("neutralMode"), QStringLiteral("inferred")},
                      {QStringLiteral("forward"), 2},
                      {QStringLiteral("reverse"), 4}
                  }}
             },
             QJsonObject{
                 {QStringLiteral("id"), QStringLiteral("lamp")},
                 {QStringLiteral("type"), QStringLiteral("indicator")},
                 {QStringLiteral("label"), QStringLiteral("工作灯")}
             }
         }}
    };

    QJSValue bindingsFunction = engine.globalObject().property(QStringLiteral("bindingsFromConfig"));
    bool ok = expect(bindingsFunction.isCallable(),
                     QStringLiteral("adapter must expose bindingsFromConfig"));
    if (!bindingsFunction.isCallable()) {
        return 1;
    }

    const QJSValue result = bindingsFunction.call(
        QJSValueList{engine.toScriptValue(config.toVariantMap())});
    const QJsonArray bindings =
        QJsonDocument::fromVariant(result.toVariant()).array();

    ok &= expect(bindings.size() == 10,
                 QStringLiteral(
                     "physical channels plus FNR/indicator controls must remain bindable"));
    ok &= expect(findBinding(bindings, QStringLiteral("button1"))
                     .value(QStringLiteral("type")).toString()
                     == QStringLiteral("button"),
                 QStringLiteral("button control must remain directly bindable"));
    ok &= expect(findBinding(bindings, QStringLiteral("roller1"))
                     .value(QStringLiteral("type")).toString()
                     == QStringLiteral("roller"),
                 QStringLiteral("roller axis must map to a roller binding"));
    ok &= expect(findBinding(bindings, QStringLiteral("button3"))
                         .value(QStringLiteral("type")).toString()
                     == QStringLiteral("button")
                     && findBinding(bindings, QStringLiteral("button5"))
                            .value(QStringLiteral("type")).toString()
                        == QStringLiteral("button"),
                 QStringLiteral(
                     "FNR-owned packed positions must still be exposed as physical button channels"));
    ok &= expect(findBinding(bindings, QStringLiteral("pot1"))
                     .value(QStringLiteral("type")).toString()
                     == QStringLiteral("potentiometer"),
                 QStringLiteral("potentiometer axis must map to a potentiometer binding"));
    ok &= expect(findBinding(bindings, QStringLiteral("fnr"))
                     .value(QStringLiteral("type")).toString()
                     == QStringLiteral("fnrSwitch"),
                 QStringLiteral("FNR control must map to an FNR binding"));
    ok &= expect(findBinding(bindings, QStringLiteral("lamp"))
                      .value(QStringLiteral("type")).toString()
                      == QStringLiteral("indicator"),
                  QStringLiteral("indicator control must remain bindable"));

    QJsonObject emptyInventoryConfig = config;
    emptyInventoryConfig.insert(QStringLiteral("bindingChannels"), QJsonArray{});
    const QJSValue emptyInventoryResult = bindingsFunction.call(
        QJSValueList{
            engine.toScriptValue(emptyInventoryConfig.toVariantMap())
        });
    const QJsonArray recoveredBindings =
        QJsonDocument::fromVariant(emptyInventoryResult.toVariant()).array();
    ok &= expect(recoveredBindings.size() == bindings.size()
                     && !findBinding(recoveredBindings, QStringLiteral("button1")).isEmpty()
                     && !findBinding(recoveredBindings, QStringLiteral("roller1")).isEmpty(),
                 QStringLiteral(
                     "an empty V3 physical inventory must be rebuilt from existing controls"));

    QJSValue fnrStateFunction =
        engine.globalObject().property(QStringLiteral("fnrEditorState"));
    ok &= expect(fnrStateFunction.isCallable(),
                 QStringLiteral("adapter must expose fnrEditorState"));
    if (fnrStateFunction.isCallable()) {
        QJSValue scriptConfig = engine.toScriptValue(config.toVariantMap());
        const QJSValue state = fnrStateFunction.call(
            QJSValueList{scriptConfig, QStringLiteral("fnr")});
        const QVariantList indexes =
            state.property(QStringLiteral("visibleButtonIndices")).toVariant().toList();
        ok &= expect(indexes == QVariantList{0, 2, 4},
                     QStringLiteral("C0009 FNR editor must expose sparse buttons 1, 3 and 5"));
        ok &= expect(state.property(QStringLiteral("count")).toInt() == 5,
                     QStringLiteral("C0009 packed FNR signal must expose five positions"));
        ok &= expect(state.property(QStringLiteral("forward")).toInt() == 2
                         && state.property(QStringLiteral("neutral")).toInt() == -1
                         && state.property(QStringLiteral("reverse")).toInt() == 4,
                     QStringLiteral("C0009 existing inferred-neutral mapping must be loaded"));
    }

    QJSValue applyFnrFunction =
        engine.globalObject().property(QStringLiteral("applyFnrPositions"));
    ok &= expect(applyFnrFunction.isCallable(),
                 QStringLiteral("adapter must expose applyFnrPositions"));
    if (applyFnrFunction.isCallable()) {
        QJSValue scriptConfig = engine.toScriptValue(config.toVariantMap());
        const QJSValue applied = applyFnrFunction.call(
            QJSValueList{scriptConfig, QStringLiteral("fnr"), 0, 2, 4});
        const QJsonObject saved =
            QJsonObject::fromVariantMap(applied.toVariant().toMap());
        const QJsonObject savedFnr =
            findBinding(saved.value(QStringLiteral("controls")).toArray(),
                        QStringLiteral("fnr"));
        const QJsonObject positions =
            savedFnr.value(QStringLiteral("positions")).toObject();
        ok &= expect(positions.value(QStringLiteral("neutralMode")).toString()
                         == QStringLiteral("signal")
                         && positions.value(QStringLiteral("forward")).toInt() == 0
                         && positions.value(QStringLiteral("neutral")).toInt() == 2
                         && positions.value(QStringLiteral("reverse")).toInt() == 4,
                     QStringLiteral("wired V3 FNR selection must persist in controls.positions"));
        ok &= expect(!saved.contains(QStringLiteral("components")),
                     QStringLiteral("editing V3 FNR must not create legacy components"));

        const QJSValue inferred = applyFnrFunction.call(
            QJSValueList{applied, QStringLiteral("fnr"), 2, -1, 4});
        const QJsonObject inferredFnr =
            findBinding(QJsonObject::fromVariantMap(inferred.toVariant().toMap())
                            .value(QStringLiteral("controls")).toArray(),
                        QStringLiteral("fnr"));
        const QJsonObject inferredPositions =
            inferredFnr.value(QStringLiteral("positions")).toObject();
        ok &= expect(inferredPositions.value(QStringLiteral("neutralMode")).toString()
                         == QStringLiteral("inferred")
                          && !inferredPositions.contains(QStringLiteral("neutral")),
                      QStringLiteral("unwired V3 neutral must omit the neutral position"));

        const QJsonObject packedSignal =
            findBinding(config.value(QStringLiteral("signals")).toArray(),
                        QStringLiteral("bjm_fnrButtons"));
        QJsonArray blankButtons;
        QJsonArray blankButtonChannels;
        for (int position = 0; position < 5; ++position) {
            blankButtons.append(QJsonObject{
                {QStringLiteral("id"),
                 QStringLiteral("newButton%1").arg(position + 1)},
                {QStringLiteral("type"), QStringLiteral("button")},
                {QStringLiteral("label"),
                 QStringLiteral("按钮 %1").arg(position + 1)},
                {QStringLiteral("signalId"), QStringLiteral("bjm_fnrButtons")},
                {QStringLiteral("position"), position}
            });
            blankButtonChannels.append(QJsonObject{
                {QStringLiteral("id"),
                 QStringLiteral("newButton%1").arg(position + 1)},
                {QStringLiteral("kind"), QStringLiteral("button")},
                {QStringLiteral("label"),
                 QStringLiteral("按钮 %1").arg(position + 1)},
                {QStringLiteral("signalId"), QStringLiteral("bjm_fnrButtons")},
                {QStringLiteral("position"), position}
            });
        }
        const QJsonObject blankFnrConfig{
            {QStringLiteral("schemaVersion"), 3},
            {QStringLiteral("signals"), QJsonArray{packedSignal}},
            {QStringLiteral("bindingChannels"), blankButtonChannels},
            {QStringLiteral("controls"), blankButtons}
        };
        QJSValue creationStateFunction =
            engine.globalObject().property(QStringLiteral("fnrCreationState"));
        ok &= expect(creationStateFunction.isCallable(),
                     QStringLiteral("adapter must expose fnrCreationState"));
        if (creationStateFunction.isCallable()) {
            const QJSValue creationState = creationStateFunction.call(
                QJSValueList{
                    engine.toScriptValue(blankFnrConfig.toVariantMap()),
                    QStringLiteral("fnr")
                });
            ok &= expect(
                creationState.property(QStringLiteral("visibleButtonIndices"))
                        .toVariant().toList()
                    == QVariantList{0, 1, 2, 3, 4},
                QStringLiteral(
                    "new V3 FNR must offer every unclaimed physical button position"));
        }

        const QJSValue createdFnrValue = applyFnrFunction.call(
            QJSValueList{
                engine.toScriptValue(blankFnrConfig.toVariantMap()),
                QStringLiteral("fnr"),
                0,
                2,
                4
            });
        const QJsonObject createdFnrConfig =
            QJsonObject::fromVariantMap(createdFnrValue.toVariant().toMap());
        const QJsonArray createdControls =
            createdFnrConfig.value(QStringLiteral("controls")).toArray();
        const QJsonObject createdFnr =
            findBinding(createdControls, QStringLiteral("fnr"));
        ok &= expect(createdFnr.value(QStringLiteral("type")).toString()
                         == QStringLiteral("fnr"),
                     QStringLiteral("mapping a new V3 FNR must create one logical FNR control"));
        ok &= expect(buttonPositions(createdControls) == QSet<int>{1, 3},
                     QStringLiteral(
                          "physical button positions claimed by FNR must not remain button controls"));
        ok &= expect(createdFnrConfig.value(QStringLiteral("bindingChannels"))
                             .toArray()
                             .size()
                         == 5,
                     QStringLiteral(
                         "FNR mapping must retain all creation-time physical button channels"));
    }

    const QJsonArray cells{
        QJsonObject{
            {QStringLiteral("cellType"), QStringLiteral("canvas")},
            {QStringLiteral("title"), QStringLiteral("正面")},
            {QStringLiteral("visualComponents"),
              QJsonArray{
                  QJsonObject{
                      {QStringLiteral("type"), QStringLiteral("ButtonBlack")},
                      {QStringLiteral("bindingId"), QStringLiteral("button1")},
                      {QStringLiteral("config"),
                       QJsonObject{
                           {QStringLiteral("_v3ElementId"),
                            QStringLiteral("cell0_0Element2")}
                       }}
                  },
                  QJsonObject{
                      {QStringLiteral("type"), QStringLiteral("ButtonRed")},
                      {QStringLiteral("bindingId"), QStringLiteral("button1")},
                      {QStringLiteral("config"),
                       QJsonObject{
                           {QStringLiteral("_v3ElementId"),
                            QStringLiteral("cell0_0Element3")}
                       }}
                  },
                  QJsonObject{
                      {QStringLiteral("type"), QStringLiteral("MiniJoystick")},
                     {QStringLiteral("x"), 12},
                     {QStringLiteral("y"), 24},
                     {QStringLiteral("width"), 244},
                     {QStringLiteral("height"), 240},
                     {QStringLiteral("xBindingId"), QStringLiteral("roller1")},
                     {QStringLiteral("yBindingId"), QStringLiteral("roller2")},
                     {QStringLiteral("config"),
                      QJsonObject{
                          {QStringLiteral("label"), QStringLiteral("迷你摇杆1")},
                          {QStringLiteral("testPattern"), QStringLiteral("cross")},
                          {QStringLiteral("invertX"), true},
                          {QStringLiteral("invertY"), true},
                          {QStringLiteral("gateMode"), QStringLiteral("cross")}
                       }}
                  },
                  QJsonObject{
                      {QStringLiteral("type"), QStringLiteral("MiniJoystick")},
                      {QStringLiteral("x"), 280},
                      {QStringLiteral("y"), 24},
                      {QStringLiteral("width"), 244},
                      {QStringLiteral("height"), 240},
                      {QStringLiteral("xBindingId"), QStringLiteral("roller3")},
                      {QStringLiteral("yBindingId"), QStringLiteral("roller4")},
                      {QStringLiteral("config"),
                       QJsonObject{{QStringLiteral("label"),
                                    QStringLiteral("迷你摇杆2")}}}
                  }
              }}
        }
    };

    QJSValue bindingErrorsFunction =
        engine.globalObject().property(QStringLiteral("cellBindingErrors"));
    ok &= expect(bindingErrorsFunction.isCallable(),
                 QStringLiteral("adapter must expose cellBindingErrors"));
    if (bindingErrorsFunction.isCallable()) {
        const QJSValue unboundErrors = bindingErrorsFunction.call(
            QJSValueList{engine.toScriptValue(
                QJsonArray{
                    QJsonObject{
                        {QStringLiteral("cellType"), QStringLiteral("canvas")},
                        {QStringLiteral("visualComponents"),
                         QJsonArray{
                             QJsonObject{
                                 {QStringLiteral("type"), QStringLiteral("MiniJoystick")}
                             }
                         }}
                    }
                }.toVariantList())});
        ok &= expect(!unboundErrors.toVariant().toList().isEmpty(),
                     QStringLiteral("unbound MiniJoystick must block saving"));
        const QJSValue boundErrors = bindingErrorsFunction.call(
            QJSValueList{engine.toScriptValue(cells.toVariantList())});
        ok &= expect(boundErrors.toVariant().toList().isEmpty(),
                     QStringLiteral("fully bound MiniJoystick must be saveable"));
    }

    QJSValue applyFunction =
        engine.globalObject().property(QStringLiteral("applyCellsToConfig"));
    ok &= expect(applyFunction.isCallable(),
                 QStringLiteral("adapter must expose applyCellsToConfig"));
    if (applyFunction.isCallable()) {
        QJSValue scriptConfig = engine.toScriptValue(config.toVariantMap());
        const QJSValue applied = applyFunction.call(
            QJSValueList{scriptConfig, engine.toScriptValue(cells.toVariantList())});
        const QJsonObject saved =
            QJsonObject::fromVariantMap(applied.toVariant().toMap());
        const QJsonObject miniControl =
            findBinding(saved.value(QStringLiteral("controls")).toArray(),
                        QStringLiteral("miniJoystick_roller1_roller2"));
        const QJsonObject secondMiniControl =
            findBinding(saved.value(QStringLiteral("controls")).toArray(),
                        QStringLiteral("miniJoystick_roller3_roller4"));
        ok &= expect(miniControl.value(QStringLiteral("type")).toString()
                         == QStringLiteral("joystick"),
                     QStringLiteral("two roller bindings must create a V3 joystick control"));
        ok &= expect(miniControl.value(QStringLiteral("topology")).toObject()
                             .value(QStringLiteral("kind")).toString()
                         == QStringLiteral("cross2D")
                         && miniControl.value(QStringLiteral("topology")).toObject()
                                .value(QStringLiteral("gate")).toString()
                            == QStringLiteral("cross"),
                     QStringLiteral("cross MiniJoystick mode must persist in V3 topology"));
        ok &= expect(miniControl.value(QStringLiteral("xAxis")).toObject()
                             .value(QStringLiteral("signalId")).toString()
                         == QStringLiteral("roller1Position")
                         && miniControl.value(QStringLiteral("yAxis")).toObject()
                                .value(QStringLiteral("signalId")).toString()
                            == QStringLiteral("roller2Position"),
                      QStringLiteral("generated MiniJoystick control must retain both channel signals"));
        ok &= expect(secondMiniControl.value(QStringLiteral("type")).toString()
                         == QStringLiteral("joystick"),
                     QStringLiteral("each bound MiniJoystick must create its own V3 control"));
        ok &= expect(findBinding(saved.value(QStringLiteral("controls")).toArray(),
                                 QStringLiteral("roller1")).isEmpty()
                         && findBinding(saved.value(QStringLiteral("controls")).toArray(),
                                        QStringLiteral("roller2")).isEmpty()
                         && findBinding(saved.value(QStringLiteral("controls")).toArray(),
                                        QStringLiteral("roller3")).isEmpty()
                         && findBinding(saved.value(QStringLiteral("controls")).toArray(),
                                        QStringLiteral("roller4")).isEmpty(),
                     QStringLiteral(
                         "roller controls consumed exclusively by MiniJoysticks must be removed"));
        ok &= expect(findBinding(saved.value(QStringLiteral("controls")).toArray(),
                                  QStringLiteral("miniJoystick_roller1_roller3")).isEmpty(),
                      QStringLiteral("stale generated MiniJoystick controls must be pruned"));
        const QJsonArray savedChannels =
            saved.value(QStringLiteral("bindingChannels")).toArray();
        ok &= expect(!findBinding(savedChannels, QStringLiteral("roller1")).isEmpty()
                         && !findBinding(savedChannels, QStringLiteral("roller2")).isEmpty()
                         && !findBinding(savedChannels, QStringLiteral("roller3")).isEmpty()
                         && !findBinding(savedChannels, QStringLiteral("roller4")).isEmpty(),
                     QStringLiteral(
                         "all four physical roller channels must survive MiniJoystick composition"));

        QJSValue bindingStatusFunction =
            engine.globalObject().property(QStringLiteral("bindingStatusEntries"));
        ok &= expect(bindingStatusFunction.isCallable(),
                     QStringLiteral("adapter must expose bindingStatusEntries"));
        if (bindingStatusFunction.isCallable()) {
            const QJSValue statusResult = bindingStatusFunction.call(
                QJSValueList{
                    engine.toScriptValue(saved.toVariantMap()),
                    engine.toScriptValue(QVariantList{
                        QStringLiteral("button1"),
                        QStringLiteral("miniJoystick_roller1_roller2"),
                        QStringLiteral("miniJoystick_roller3_roller4")
                    })
                });
            const QJsonArray statusEntries =
                QJsonDocument::fromVariant(statusResult.toVariant()).array();
            const QJsonObject roller1Status =
                findBinding(statusEntries, QStringLiteral("roller1"));
            const QJsonObject roller2Status =
                findBinding(statusEntries, QStringLiteral("roller2"));
            const QJsonObject roller3Status =
                findBinding(statusEntries, QStringLiteral("roller3"));
            const QJsonObject roller4Status =
                findBinding(statusEntries, QStringLiteral("roller4"));
            ok &= expect(roller1Status.value(QStringLiteral("bound")).toBool()
                             && roller2Status.value(QStringLiteral("bound")).toBool()
                             && roller3Status.value(QStringLiteral("bound")).toBool()
                             && roller4Status.value(QStringLiteral("bound")).toBool(),
                         QStringLiteral(
                             "all four physical roller channels must be shown as bound"));
            ok &= expect(
                roller1Status.value(QStringLiteral("boundTo")).toString()
                        == QStringLiteral("迷你摇杆1 X")
                    && roller2Status.value(QStringLiteral("boundTo")).toString()
                           == QStringLiteral("迷你摇杆1 Y")
                    && roller3Status.value(QStringLiteral("boundTo")).toString()
                           == QStringLiteral("迷你摇杆2 X")
                    && roller4Status.value(QStringLiteral("boundTo")).toString()
                           == QStringLiteral("迷你摇杆2 Y"),
                QStringLiteral(
                    "roller status must show the logical MiniJoystick axis consuming each channel"));
            ok &= expect(
                findBinding(statusEntries,
                            QStringLiteral("miniJoystick_roller1_roller2")).isEmpty()
                    && findBinding(statusEntries,
                                   QStringLiteral("miniJoystick_roller3_roller4")).isEmpty(),
                QStringLiteral(
                    "binding status must list physical channels, not duplicate composite controls"));
        }

        const QJsonArray savedElements =
            saved.value(QStringLiteral("layout")).toObject()
                .value(QStringLiteral("cards")).toArray().at(0).toObject()
                .value(QStringLiteral("elements")).toArray();
        QSet<QString> savedElementIds;
        for (const QJsonValue &value : savedElements) {
            savedElementIds.insert(value.toObject()
                                       .value(QStringLiteral("id")).toString());
        }
        ok &= expect(savedElementIds.size() == savedElements.size(),
                     QStringLiteral("new visuals must not reuse preserved V3 element ids"));
        const QJsonObject savedMiniProperties =
            savedElements.at(2).toObject().value(QStringLiteral("properties")).toObject();
        ok &= expect(savedMiniProperties.value(QStringLiteral("invertX")).toBool()
                         && savedMiniProperties.value(QStringLiteral("invertY")).toBool(),
                     QStringLiteral("reversed MiniJoystick animation must persist per axis"));
        ok &= expect(!savedMiniProperties.contains(QStringLiteral("gateMode")),
                     QStringLiteral("editor gateMode must be stored in joystick topology"));

        QJSValue cellsFunction =
            engine.globalObject().property(QStringLiteral("cellsFromConfig"));
        const QJSValue roundTrip = cellsFunction.call(QJSValueList{applied});
        const QJsonArray roundTripCells =
            QJsonDocument::fromVariant(roundTrip.toVariant()).array();
        const QJsonArray roundTripVisuals =
            roundTripCells.at(0).toObject()
                .value(QStringLiteral("visualComponents")).toArray();
        ok &= expect(roundTripVisuals.size() == 4
                           && roundTripVisuals.at(2).toObject()
                                  .value(QStringLiteral("xBindingId")).toString()
                              == QStringLiteral("roller1")
                           && roundTripVisuals.at(2).toObject()
                                  .value(QStringLiteral("yBindingId")).toString()
                              == QStringLiteral("roller2"),
                       QStringLiteral("MiniJoystick channel bindings must survive a save/load round trip"));
        const QJsonObject roundTripConfig =
            roundTripVisuals.at(2).toObject().value(QStringLiteral("config")).toObject();
        ok &= expect(roundTripConfig.value(QStringLiteral("gateMode")).toString()
                         == QStringLiteral("cross")
                         && roundTripConfig.value(QStringLiteral("invertX")).toBool()
                         && roundTripConfig.value(QStringLiteral("invertY")).toBool(),
                      QStringLiteral("MiniJoystick menu settings must survive a save/load round trip"));

        const QJsonArray rollerCells{
            QJsonObject{
                {QStringLiteral("cellType"), QStringLiteral("canvas")},
                {QStringLiteral("title"), QStringLiteral("正面")},
                {QStringLiteral("visualComponents"),
                 QJsonArray{
                     QJsonObject{
                         {QStringLiteral("type"), QStringLiteral("VerticalRoller")},
                         {QStringLiteral("bindingId"), QStringLiteral("roller1")},
                         {QStringLiteral("config"),
                          QJsonObject{{QStringLiteral("invertInput"), true}}}
                     }
                 }}
            }
        };
        const QJSValue rollerApplied = applyFunction.call(
            QJSValueList{
                engine.toScriptValue(config.toVariantMap()),
                engine.toScriptValue(rollerCells.toVariantList())
            });
        const QJsonObject rollerSaved =
            QJsonObject::fromVariantMap(rollerApplied.toVariant().toMap());
        const QJsonObject savedRollerControl =
            findBinding(rollerSaved.value(QStringLiteral("controls")).toArray(),
                        QStringLiteral("roller1"));
        ok &= expect(savedRollerControl.value(QStringLiteral("axis")).toObject()
                         .value(QStringLiteral("transform")).toObject()
                         .value(QStringLiteral("invert")).toBool(),
                     QStringLiteral(
                         "roller output reversal must persist in the V3 axis transform"));
        const QJsonObject savedRollerElement =
            rollerSaved.value(QStringLiteral("layout")).toObject()
                .value(QStringLiteral("cards")).toArray().first().toObject()
                .value(QStringLiteral("elements")).toArray().first().toObject();
        ok &= expect(!savedRollerElement.value(QStringLiteral("properties")).toObject()
                           .contains(QStringLiteral("invertInput")),
                     QStringLiteral(
                         "roller inversion must not be duplicated in layout properties"));

        const QJSValue rollerRoundTrip =
            cellsFunction.call(QJSValueList{rollerApplied});
        const QJsonObject rollerRoundTripConfig =
            QJsonDocument::fromVariant(rollerRoundTrip.toVariant()).array()
                .first().toObject()
                .value(QStringLiteral("visualComponents")).toArray()
                .first().toObject()
                .value(QStringLiteral("config")).toObject();
        ok &= expect(rollerRoundTripConfig.value(QStringLiteral("invertInput")).toBool(),
                     QStringLiteral(
                         "roller output reversal must survive a save/load round trip"));

        QJsonObject potentiometerConfig = config;
        QJsonArray potentiometerControls =
            potentiometerConfig.value(QStringLiteral("controls")).toArray();
        for (qsizetype controlIndex = 0;
             controlIndex < potentiometerControls.size();
             ++controlIndex) {
            QJsonObject control = potentiometerControls.at(controlIndex).toObject();
            if (control.value(QStringLiteral("id")).toString()
                != QStringLiteral("pot1")) {
                continue;
            }
            QJsonObject axis = control.value(QStringLiteral("axis")).toObject();
            QJsonObject transform =
                axis.value(QStringLiteral("transform")).toObject();
            transform.insert(QStringLiteral("invert"), true);
            axis.insert(QStringLiteral("transform"), transform);
            control.insert(QStringLiteral("axis"), axis);
            potentiometerControls[controlIndex] = control;
            break;
        }
        potentiometerConfig.insert(QStringLiteral("controls"),
                                   potentiometerControls);
        const QJsonArray potentiometerCells{
            QJsonObject{
                {QStringLiteral("cellType"), QStringLiteral("canvas")},
                {QStringLiteral("visualComponents"),
                 QJsonArray{
                     QJsonObject{
                         {QStringLiteral("type"),
                          QStringLiteral("RotaryPotentiometer")},
                         {QStringLiteral("bindingId"), QStringLiteral("pot1")},
                         {QStringLiteral("config"), QJsonObject{}}
                     }
                 }}
            }
        };
        const QJsonObject potentiometerSaved = QJsonObject::fromVariantMap(
            applyFunction.call(
                QJSValueList{
                    engine.toScriptValue(potentiometerConfig.toVariantMap()),
                    engine.toScriptValue(potentiometerCells.toVariantList())
                }).toVariant().toMap());
        ok &= expect(
            findBinding(potentiometerSaved.value(QStringLiteral("controls"))
                            .toArray(),
                        QStringLiteral("pot1"))
                .value(QStringLiteral("axis")).toObject()
                .value(QStringLiteral("transform")).toObject()
                .value(QStringLiteral("invert")).toBool(),
            QStringLiteral(
                "roller editing must not reset another axis renderer's transform"));

        const QJsonObject compositeOnlyConfig{
            {QStringLiteral("schemaVersion"), 3},
            {QStringLiteral("controls"),
             QJsonArray{
                 QJsonObject{
                     {QStringLiteral("id"),
                      QStringLiteral("miniJoystick_ejm_theta_ejm_roller4")},
                     {QStringLiteral("type"), QStringLiteral("joystick")},
                     {QStringLiteral("label"), QStringLiteral("组合迷你摇杆")},
                     {QStringLiteral("topology"),
                      QJsonObject{
                          {QStringLiteral("kind"), QStringLiteral("xy2D")},
                          {QStringLiteral("gate"), QStringLiteral("omnidirectional")}
                      }},
                     {QStringLiteral("xAxis"),
                      QJsonObject{
                          {QStringLiteral("signalId"), QStringLiteral("ejm_thetaPos")},
                          {QStringLiteral("statusSignalId"),
                           QStringLiteral("ejm_thetaStatus")}
                      }},
                     {QStringLiteral("yAxis"),
                      QJsonObject{
                          {QStringLiteral("signalId"), QStringLiteral("ejm_roller4Pos")},
                          {QStringLiteral("statusSignalId"),
                           QStringLiteral("ejm_roller4Status")}
                      }}
                 }
             }},
            {QStringLiteral("layout"),
             QJsonObject{
                 {QStringLiteral("cards"),
                  QJsonArray{
                      QJsonObject{
                          {QStringLiteral("id"), QStringLiteral("miniCard")},
                          {QStringLiteral("kind"), QStringLiteral("controls")},
                          {QStringLiteral("title"), QStringLiteral("迷你摇杆")},
                          {QStringLiteral("grid"),
                           QJsonObject{
                               {QStringLiteral("row"), 0},
                               {QStringLiteral("column"), 0},
                               {QStringLiteral("rowSpan"), 1},
                               {QStringLiteral("columnSpan"), 1}
                           }},
                          {QStringLiteral("contentCanvas"),
                           QJsonObject{
                               {QStringLiteral("width"), 480},
                               {QStringLiteral("height"), 480},
                               {QStringLiteral("scaleMode"), QStringLiteral("uniform")}
                           }},
                          {QStringLiteral("elements"),
                           QJsonArray{
                               QJsonObject{
                                   {QStringLiteral("id"),
                                    QStringLiteral("miniElement")},
                                   {QStringLiteral("controlId"),
                                    QStringLiteral(
                                        "miniJoystick_ejm_theta_ejm_roller4")},
                                   {QStringLiteral("renderer"),
                                    QStringLiteral("miniJoystick")},
                                   {QStringLiteral("x"), 12},
                                   {QStringLiteral("y"), 24},
                                   {QStringLiteral("width"), 244},
                                   {QStringLiteral("height"), 240}
                               }
                           }}
                      }
                  }}
             }}
        };
        const QJSValue compositeScript =
            engine.toScriptValue(compositeOnlyConfig.toVariantMap());
        const QJSValue compositeCellsValue =
            cellsFunction.call(QJSValueList{compositeScript});
        const QJsonArray compositeCells =
            QJsonDocument::fromVariant(compositeCellsValue.toVariant()).array();
        const QJsonObject compositeVisual =
            compositeCells.at(0).toObject()
                .value(QStringLiteral("visualComponents")).toArray()
                .at(0).toObject();
        ok &= expect(!compositeVisual.value(QStringLiteral("xBindingId")).toString().isEmpty()
                         && !compositeVisual.value(QStringLiteral("yBindingId")).toString().isEmpty(),
                     QStringLiteral(
                         "composite-only MiniJoystick must expose editable X and Y bindings"));

        const QJSValue compositeSavedValue = applyFunction.call(
            QJSValueList{compositeScript, compositeCellsValue});
        const QJsonObject compositeSaved =
            QJsonObject::fromVariantMap(compositeSavedValue.toVariant().toMap());
        const QJsonObject compositeSavedControl =
            findBinding(compositeSaved.value(QStringLiteral("controls")).toArray(),
                        QStringLiteral("miniJoystick_ejm_theta_ejm_roller4"));
        ok &= expect(compositeSavedControl.value(QStringLiteral("xAxis")).toObject()
                             .value(QStringLiteral("signalId")).toString()
                         == QStringLiteral("ejm_thetaPos")
                         && compositeSavedControl.value(QStringLiteral("xAxis")).toObject()
                                .value(QStringLiteral("statusSignalId")).toString()
                            == QStringLiteral("ejm_thetaStatus")
                         && compositeSavedControl.value(QStringLiteral("yAxis")).toObject()
                                .value(QStringLiteral("signalId")).toString()
                            == QStringLiteral("ejm_roller4Pos")
                         && compositeSavedControl.value(QStringLiteral("yAxis")).toObject()
                                .value(QStringLiteral("statusSignalId")).toString()
                            == QStringLiteral("ejm_roller4Status"),
                     QStringLiteral(
                         "composite-only MiniJoystick must preserve both status/magnitude pairs"));
    }

    QJSValue externalCellsFunction =
        engine.globalObject().property(QStringLiteral("cellsFromConfig"));
    QJSValue externalApplyFunction =
        engine.globalObject().property(QStringLiteral("applyCellsToConfig"));
    for (int argumentIndex = 1; argumentIndex < argc; ++argumentIndex) {
        const QString path = QString::fromLocal8Bit(argv[argumentIndex]);
        QFile externalFile(path);
        ok &= expect(externalFile.open(QIODevice::ReadOnly),
                     QStringLiteral("external V3 config must be readable: %1")
                         .arg(path));
        if (!externalFile.isOpen()) {
            continue;
        }

        const QJsonDocument document = QJsonDocument::fromJson(externalFile.readAll());
        ok &= expect(document.isObject(),
                     QStringLiteral("external V3 config must be a JSON object: %1")
                         .arg(path));
        if (!document.isObject()) {
            continue;
        }

        const QJsonObject externalConfig = document.object();
        const QJsonArray originalCards =
            externalConfig.value(QStringLiteral("layout"))
                .toObject()
                .value(QStringLiteral("cards"))
                .toArray();
        const int originalElementCount = elementCount(originalCards);
        const QJSValue scriptConfig =
            engine.toScriptValue(externalConfig.toVariantMap());
        const QJSValue externalCells =
            externalCellsFunction.call(QJSValueList{scriptConfig});
        const QJSValue roundTripValue = externalApplyFunction.call(
            QJSValueList{
                engine.toScriptValue(externalConfig.toVariantMap()),
                externalCells
            });
        const QJsonObject roundTripConfig =
            QJsonObject::fromVariantMap(roundTripValue.toVariant().toMap());
        const QJsonArray roundTripCards =
            roundTripConfig.value(QStringLiteral("layout"))
                .toObject()
                .value(QStringLiteral("cards"))
                .toArray();
        ok &= expect(roundTripCards.size() == originalCards.size(),
                     QStringLiteral(
                         "external V3 editor round trip must retain every card: %1")
                         .arg(path));
        ok &= expect(elementCount(roundTripCards) == originalElementCount,
                     QStringLiteral(
                         "external V3 editor round trip must retain every layout element: %1")
                         .arg(path));
    }

    if (ok) {
        QTextStream(stdout) << "PASS: V3 controls are exposed as editor bindings\n";
    }
    return ok ? 0 : 1;
}
