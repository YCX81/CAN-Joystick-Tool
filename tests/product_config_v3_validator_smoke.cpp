#include "ProductConfigV3Validator.h"

#include <QCoreApplication>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
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
    const QString path = QDir(QStringLiteral(PRODUCT_CONFIG_V3_EXAMPLES_DIR)).filePath(fileName);
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qCritical().noquote() << "could not open V3 example:" << path;
        return {};
    }

    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &error);
    if (error.error != QJsonParseError::NoError || !document.isObject()) {
        qCritical().noquote() << "could not parse V3 example:" << path << error.errorString();
        return {};
    }
    return document.object();
}

QString joinedErrors(const ProductConfigV3Validator::Result &result)
{
    return result.errors.join(QStringLiteral(" | "));
}

bool expectValid(const QJsonObject &config, const QString &caseName)
{
    const ProductConfigV3Validator::Result result = ProductConfigV3Validator::validate(config);
    return expect(result.ok,
                  QStringLiteral("%1 should be valid: %2").arg(caseName, joinedErrors(result)));
}

bool expectInvalid(const QJsonObject &config,
                   const QString &caseName,
                   const QString &expectedErrorFragment)
{
    const ProductConfigV3Validator::Result result = ProductConfigV3Validator::validate(config);
    bool ok = expect(!result.ok, QStringLiteral("%1 unexpectedly passed").arg(caseName));
    if (!expectedErrorFragment.isEmpty()) {
        ok &= expect(joinedErrors(result).contains(expectedErrorFragment, Qt::CaseInsensitive),
                     QStringLiteral("%1 did not report '%2': %3")
                         .arg(caseName, expectedErrorFragment, joinedErrors(result)));
    }
    return ok;
}

QJsonObject withProductVersion(QJsonObject config, const QString &version)
{
    QJsonObject product = config.value(QStringLiteral("product")).toObject();
    product.insert(QStringLiteral("version"), version);
    config.insert(QStringLiteral("product"), product);
    return config;
}

QJsonObject withOperation(QJsonObject config, const QJsonObject &operation)
{
    config.insert(QStringLiteral("operation"), operation);
    return config;
}

QJsonObject withFirstMessage(QJsonObject config, const QJsonObject &message)
{
    QJsonArray messages = config.value(QStringLiteral("messages")).toArray();
    messages[0] = message;
    config.insert(QStringLiteral("messages"), messages);
    return config;
}

QJsonObject withFirstSignal(QJsonObject config, const QJsonObject &signal)
{
    QJsonArray signalArray = config.value(QStringLiteral("signals")).toArray();
    signalArray[0] = signal;
    config.insert(QStringLiteral("signals"), signalArray);
    return config;
}

QJsonObject withControl(QJsonObject config, int index, const QJsonObject &control)
{
    QJsonArray controls = config.value(QStringLiteral("controls")).toArray();
    controls[index] = control;
    config.insert(QStringLiteral("controls"), controls);
    return config;
}

QJsonObject withCommand(QJsonObject config, int index, const QJsonObject &command)
{
    QJsonArray commands = config.value(QStringLiteral("commands")).toArray();
    commands[index] = command;
    config.insert(QStringLiteral("commands"), commands);
    return config;
}

bool verifyVersionRules(const QJsonObject &singleAxis, const QJsonObject &firmwareBacked)
{
    bool ok = true;
    QJsonObject wrongSchemaVersion = singleAxis;
    wrongSchemaVersion.insert(QStringLiteral("schemaVersion"), 2);
    ok &= expectInvalid(wrongSchemaVersion,
                        QStringLiteral("schemaVersion 2"),
                        QStringLiteral("schemaVersion"));

    ok &= expectValid(withProductVersion(singleAxis, QStringLiteral("V1")), QStringLiteral("version V1"));
    ok &= expectValid(withProductVersion(singleAxis, QStringLiteral("V2")), QStringLiteral("version V2"));
    ok &= expectValid(firmwareBacked, QStringLiteral("version V2.0.2"));
    ok &= expectInvalid(withProductVersion(singleAxis, QStringLiteral("C1")),
                        QStringLiteral("C1 product version"),
                        QStringLiteral("product.version"));
    ok &= expectInvalid(withProductVersion(singleAxis, QStringLiteral("V2.0")),
                        QStringLiteral("two-part product version"),
                        QStringLiteral("product.version"));

    QJsonObject legacyRevision = singleAxis;
    legacyRevision.insert(QStringLiteral("config"),
                          QJsonObject{{QStringLiteral("revision"), QStringLiteral("C1")}});
    ok &= expectInvalid(legacyRevision,
                        QStringLiteral("legacy config.revision"),
                        QStringLiteral("config.revision"));
    return ok;
}

bool verifyOperationRules(const QJsonObject &singleAxis, const QJsonObject &firmwareBacked)
{
    bool ok = true;

    QJsonObject externalWithVersion = singleAxis;
    QJsonObject operation = externalWithVersion.value(QStringLiteral("operation")).toObject();
    QJsonObject firmware = operation.value(QStringLiteral("firmware")).toObject();
    firmware.insert(QStringLiteral("version"), QStringLiteral("1.0.0"));
    operation.insert(QStringLiteral("firmware"), firmware);
    ok &= expectInvalid(withOperation(externalWithVersion, operation),
                        QStringLiteral("test_only external version"),
                        QStringLiteral("must not"));

    firmware.remove(QStringLiteral("version"));
    firmware.insert(QStringLiteral("artifact"), QStringLiteral("JC6000-BGA-C0009_V1.elf"));
    operation.insert(QStringLiteral("firmware"), firmware);
    ok &= expectInvalid(withOperation(singleAxis, operation),
                        QStringLiteral("test_only external artifact"),
                        QStringLiteral("must not"));

    QJsonObject mismatchedVersion = withProductVersion(firmwareBacked, QStringLiteral("V2.0.1"));
    ok &= expectInvalid(mismatchedVersion,
                        QStringLiteral("firmware version mismatch"),
                        QStringLiteral("must equal"));

    QJsonObject mismatchedArtifact = firmwareBacked;
    operation = mismatchedArtifact.value(QStringLiteral("operation")).toObject();
    firmware = operation.value(QStringLiteral("firmware")).toObject();
    firmware.insert(QStringLiteral("artifact"), QStringLiteral("WRONG_V2.0.2.elf"));
    operation.insert(QStringLiteral("firmware"), firmware);
    ok &= expectInvalid(withOperation(mismatchedArtifact, operation),
                        QStringLiteral("firmware artifact mismatch"),
                        QStringLiteral("artifact"));

    QJsonObject missingArtifact = firmwareBacked;
    operation = missingArtifact.value(QStringLiteral("operation")).toObject();
    firmware = operation.value(QStringLiteral("firmware")).toObject();
    firmware.remove(QStringLiteral("artifact"));
    operation.insert(QStringLiteral("firmware"), firmware);
    ok &= expectInvalid(withOperation(missingArtifact, operation),
                        QStringLiteral("firmware artifact missing"),
                        QStringLiteral("artifact"));

    QJsonObject missingVersion = firmwareBacked;
    operation = missingVersion.value(QStringLiteral("operation")).toObject();
    firmware = operation.value(QStringLiteral("firmware")).toObject();
    firmware.remove(QStringLiteral("version"));
    operation.insert(QStringLiteral("firmware"), firmware);
    ok &= expectInvalid(withOperation(missingVersion, operation),
                        QStringLiteral("firmware version missing"),
                        QStringLiteral("firmware.version"));

    QJsonObject wrongSource = firmwareBacked;
    operation = wrongSource.value(QStringLiteral("operation")).toObject();
    firmware = operation.value(QStringLiteral("firmware")).toObject();
    firmware.insert(QStringLiteral("source"), QStringLiteral("external"));
    operation.insert(QStringLiteral("firmware"), firmware);
    ok &= expectInvalid(withOperation(wrongSource, operation),
                        QStringLiteral("firmware-backed external"),
                        QStringLiteral("bundled"));
    return ok;
}

bool verifyProtocolAndHexRules(const QJsonObject &singleAxis, const QJsonObject &hm025)
{
    bool ok = true;

    QJsonObject missingProtocol = singleAxis;
    missingProtocol.remove(QStringLiteral("protocol"));
    ok &= expectInvalid(missingProtocol,
                        QStringLiteral("missing protocol"),
                        QStringLiteral("protocol"));

    QJsonObject decimalAddress = singleAxis;
    QJsonObject bus = decimalAddress.value(QStringLiteral("bus")).toObject();
    bus.insert(QStringLiteral("sourceAddress"), 51);
    decimalAddress.insert(QStringLiteral("bus"), bus);
    ok &= expectInvalid(decimalAddress,
                        QStringLiteral("decimal address"),
                        QStringLiteral("hex"));

    QJsonObject lowerPgn = singleAxis;
    QJsonObject message = lowerPgn.value(QStringLiteral("messages")).toArray().first().toObject();
    message.insert(QStringLiteral("pgn"), QStringLiteral("0x00fdd6"));
    ok &= expectInvalid(withFirstMessage(lowerPgn, message),
                        QStringLiteral("lower-case PGN"),
                        QStringLiteral("hex"));

    QJsonObject lowerPayload = hm025;
    QJsonObject command = lowerPayload.value(QStringLiteral("commands")).toArray().first().toObject();
    QJsonObject frame = command.value(QStringLiteral("frame")).toObject();
    frame.insert(QStringLiteral("data"), QStringLiteral("00 fa 00"));
    command.insert(QStringLiteral("frame"), frame);
    ok &= expectInvalid(withCommand(lowerPayload, 0, command),
                        QStringLiteral("lower-case payload"),
                        QStringLiteral("payload"));
    return ok;
}

bool verifyLayoutAndPayloadRules(const QJsonObject &singleAxis, const QJsonObject &hm025)
{
    bool ok = true;

    QJsonObject autoLayout = singleAxis;
    QJsonObject layout = autoLayout.value(QStringLiteral("layout")).toObject();
    layout.insert(QStringLiteral("mode"), QStringLiteral("auto"));
    autoLayout.insert(QStringLiteral("layout"), layout);
    ok &= expectInvalid(autoLayout,
                        QStringLiteral("automatic layout"),
                        QStringLiteral("designed"));

    QJsonObject wrongDlc = hm025;
    QJsonObject command = wrongDlc.value(QStringLiteral("commands")).toArray().first().toObject();
    QJsonObject frame = command.value(QStringLiteral("frame")).toObject();
    frame.insert(QStringLiteral("dlc"), 8);
    command.insert(QStringLiteral("frame"), frame);
    ok &= expectInvalid(withCommand(wrongDlc, 0, command),
                        QStringLiteral("DLC payload mismatch"),
                        QStringLiteral("DLC"));
    return ok;
}

bool verifyReferenceRules(const QJsonObject &singleAxis, const QJsonObject &hm025)
{
    bool ok = true;

    QJsonObject badSignalMessage = singleAxis;
    QJsonObject signal = badSignalMessage.value(QStringLiteral("signals")).toArray().first().toObject();
    QJsonObject source = signal.value(QStringLiteral("source")).toObject();
    source.insert(QStringLiteral("messageId"), QStringLiteral("missingMessage"));
    signal.insert(QStringLiteral("source"), source);
    ok &= expectInvalid(withFirstSignal(badSignalMessage, signal),
                        QStringLiteral("signal message reference"),
                        QStringLiteral("message"));

    QJsonObject badControlSignal = singleAxis;
    QJsonObject control = badControlSignal.value(QStringLiteral("controls")).toArray().first().toObject();
    QJsonObject axis = control.value(QStringLiteral("axis")).toObject();
    axis.insert(QStringLiteral("signalId"), QStringLiteral("missingSignal"));
    control.insert(QStringLiteral("axis"), axis);
    ok &= expectInvalid(withControl(badControlSignal, 0, control),
                        QStringLiteral("control signal reference"),
                        QStringLiteral("signal"));

    QJsonObject badControlCommand = hm025;
    control = badControlCommand.value(QStringLiteral("controls")).toArray().at(1).toObject();
    control.insert(QStringLiteral("onCommandId"), QStringLiteral("missingCommand"));
    ok &= expectInvalid(withControl(badControlCommand, 1, control),
                        QStringLiteral("control command reference"),
                        QStringLiteral("command"));

    QJsonObject badLayoutControl = singleAxis;
    QJsonObject layout = badLayoutControl.value(QStringLiteral("layout")).toObject();
    QJsonArray cards = layout.value(QStringLiteral("cards")).toArray();
    QJsonObject card = cards.first().toObject();
    card.insert(QStringLiteral("controlIds"), QJsonArray{QStringLiteral("missingControl")});
    cards[0] = card;
    layout.insert(QStringLiteral("cards"), cards);
    badLayoutControl.insert(QStringLiteral("layout"), layout);
    ok &= expectInvalid(badLayoutControl,
                        QStringLiteral("layout control reference"),
                        QStringLiteral("control"));
    return ok;
}

bool verifyTopologyRules(const QJsonObject &singleAxis, const QJsonObject &cross2d)
{
    bool ok = true;

    QJsonObject missingSingleTopology = singleAxis;
    QJsonObject control = missingSingleTopology.value(QStringLiteral("controls")).toArray().first().toObject();
    control.remove(QStringLiteral("topology"));
    ok &= expectInvalid(withControl(missingSingleTopology, 0, control),
                        QStringLiteral("single-axis topology missing"),
                        QStringLiteral("singleAxis"));

    QJsonObject diagonalGate = cross2d;
    control = diagonalGate.value(QStringLiteral("controls")).toArray().first().toObject();
    QJsonObject topology = control.value(QStringLiteral("topology")).toObject();
    topology.insert(QStringLiteral("gate"), QStringLiteral("square"));
    control.insert(QStringLiteral("topology"), topology);
    ok &= expectInvalid(withControl(diagonalGate, 0, control),
                        QStringLiteral("cross2D non-cross gate"),
                        QStringLiteral("cross"));
    return ok;
}

bool verifySignalBitRules(const QJsonObject &singleAxis)
{
    bool ok = true;

    QJsonObject outOfRange = singleAxis;
    QJsonObject signal = outOfRange.value(QStringLiteral("signals")).toArray().first().toObject();
    QJsonObject source = signal.value(QStringLiteral("source")).toObject();
    source.insert(QStringLiteral("startByte"), 7);
    source.insert(QStringLiteral("startBit"), 7);
    source.insert(QStringLiteral("bitLength"), 2);
    signal.insert(QStringLiteral("source"), source);
    ok &= expectInvalid(withFirstSignal(outOfRange, signal),
                        QStringLiteral("signal beyond DLC"),
                        QStringLiteral("DLC"));

    QJsonObject overlap = singleAxis;
    QJsonArray signalArray = overlap.value(QStringLiteral("signals")).toArray();
    QJsonObject secondSignal = signalArray.at(1).toObject();
    secondSignal.insert(QStringLiteral("source"),
                        signalArray.first().toObject().value(QStringLiteral("source")).toObject());
    signalArray[1] = secondSignal;
    overlap.insert(QStringLiteral("signals"), signalArray);
    ok &= expectInvalid(overlap,
                        QStringLiteral("overlapping signals"),
                        QStringLiteral("overlap"));
    return ok;
}

bool verifyTransformRules(const QJsonObject &singleAxis)
{
    bool ok = true;

    QJsonObject invalidOrder = singleAxis;
    QJsonObject control = invalidOrder.value(QStringLiteral("controls")).toArray().first().toObject();
    QJsonObject axis = control.value(QStringLiteral("axis")).toObject();
    QJsonObject transform = axis.value(QStringLiteral("transform")).toObject();
    transform.insert(QStringLiteral("rawCenter"), 0);
    axis.insert(QStringLiteral("transform"), transform);
    control.insert(QStringLiteral("axis"), axis);
    ok &= expectInvalid(withControl(invalidOrder, 0, control),
                        QStringLiteral("invalid raw transform ordering"),
                        QStringLiteral("rawMin"));

    QJsonObject negativeDeadzone = singleAxis;
    control = negativeDeadzone.value(QStringLiteral("controls")).toArray().first().toObject();
    axis = control.value(QStringLiteral("axis")).toObject();
    transform = axis.value(QStringLiteral("transform")).toObject();
    transform.insert(QStringLiteral("deadzone"), -1);
    axis.insert(QStringLiteral("transform"), transform);
    control.insert(QStringLiteral("axis"), axis);
    ok &= expectInvalid(withControl(negativeDeadzone, 0, control),
                        QStringLiteral("negative transform deadzone"),
                        QStringLiteral("deadzone"));
    return ok;
}

bool verifyLayoutGeometryRules(const QJsonObject &singleAxis)
{
    bool ok = true;

    QJsonObject duplicateCard = singleAxis;
    QJsonObject layout = duplicateCard.value(QStringLiteral("layout")).toObject();
    QJsonArray cards = layout.value(QStringLiteral("cards")).toArray();
    QJsonObject secondCard = cards.at(1).toObject();
    secondCard.insert(QStringLiteral("id"),
                      cards.first().toObject().value(QStringLiteral("id")));
    cards[1] = secondCard;
    layout.insert(QStringLiteral("cards"), cards);
    duplicateCard.insert(QStringLiteral("layout"), layout);
    ok &= expectInvalid(duplicateCard,
                        QStringLiteral("duplicate layout card id"),
                        QStringLiteral("duplicated"));

    QJsonObject negativePosition = singleAxis;
    layout = negativePosition.value(QStringLiteral("layout")).toObject();
    cards = layout.value(QStringLiteral("cards")).toArray();
    QJsonObject card = cards.first().toObject();
    card.insert(QStringLiteral("x"), -1);
    cards[0] = card;
    layout.insert(QStringLiteral("cards"), cards);
    negativePosition.insert(QStringLiteral("layout"), layout);
    ok &= expectInvalid(negativePosition,
                        QStringLiteral("negative layout card position"),
                        QStringLiteral("x/y"));

    QJsonObject zeroSize = singleAxis;
    layout = zeroSize.value(QStringLiteral("layout")).toObject();
    cards = layout.value(QStringLiteral("cards")).toArray();
    card = cards.first().toObject();
    card.insert(QStringLiteral("width"), 0);
    cards[0] = card;
    layout.insert(QStringLiteral("cards"), cards);
    zeroSize.insert(QStringLiteral("layout"), layout);
    ok &= expectInvalid(zeroSize,
                        QStringLiteral("zero layout card size"),
                        QStringLiteral("width/height"));

    QJsonObject outsideCanvas = singleAxis;
    layout = outsideCanvas.value(QStringLiteral("layout")).toObject();
    cards = layout.value(QStringLiteral("cards")).toArray();
    card = cards.first().toObject();
    card.insert(QStringLiteral("x"), 1000);
    cards[0] = card;
    layout.insert(QStringLiteral("cards"), cards);
    outsideCanvas.insert(QStringLiteral("layout"), layout);
    ok &= expectInvalid(outsideCanvas,
                        QStringLiteral("layout card outside canvas"),
                        QStringLiteral("canvas"));
    return ok;
}

bool verifyUniqueIdRules(const QJsonObject &singleAxis, const QJsonObject &hm025)
{
    bool ok = true;

    QJsonObject duplicateMessage = singleAxis;
    QJsonArray messages = duplicateMessage.value(QStringLiteral("messages")).toArray();
    messages.append(messages.first());
    duplicateMessage.insert(QStringLiteral("messages"), messages);
    ok &= expectInvalid(duplicateMessage,
                        QStringLiteral("duplicate message id"),
                        QStringLiteral("duplicated"));

    QJsonObject duplicateSignal = singleAxis;
    QJsonArray signalArray = duplicateSignal.value(QStringLiteral("signals")).toArray();
    QJsonObject signal = signalArray.at(1).toObject();
    signal.insert(QStringLiteral("id"),
                  signalArray.first().toObject().value(QStringLiteral("id")));
    signalArray[1] = signal;
    duplicateSignal.insert(QStringLiteral("signals"), signalArray);
    ok &= expectInvalid(duplicateSignal,
                        QStringLiteral("duplicate signal id"),
                        QStringLiteral("duplicated"));

    QJsonObject duplicateCommand = hm025;
    QJsonArray commands = duplicateCommand.value(QStringLiteral("commands")).toArray();
    QJsonObject command = commands.at(1).toObject();
    command.insert(QStringLiteral("id"),
                   commands.first().toObject().value(QStringLiteral("id")));
    commands[1] = command;
    duplicateCommand.insert(QStringLiteral("commands"), commands);
    ok &= expectInvalid(duplicateCommand,
                        QStringLiteral("duplicate command id"),
                        QStringLiteral("duplicated"));

    QJsonObject duplicateControl = singleAxis;
    QJsonArray controls = duplicateControl.value(QStringLiteral("controls")).toArray();
    QJsonObject control = controls.at(1).toObject();
    control.insert(QStringLiteral("id"),
                   controls.first().toObject().value(QStringLiteral("id")));
    controls[1] = control;
    duplicateControl.insert(QStringLiteral("controls"), controls);
    ok &= expectInvalid(duplicateControl,
                        QStringLiteral("duplicate control id"),
                        QStringLiteral("duplicated"));

    QJsonObject duplicateTest = hm025;
    QJsonArray tests = duplicateTest.value(QStringLiteral("tests")).toArray();
    tests.append(tests.first());
    duplicateTest.insert(QStringLiteral("tests"), tests);
    ok &= expectInvalid(duplicateTest,
                        QStringLiteral("duplicate test id"),
                        QStringLiteral("duplicated"));
    return ok;
}

bool verifyHm025SafetyRules(const QJsonObject &hm025)
{
    bool ok = true;

    QJsonObject wrongOnPayload = hm025;
    QJsonObject command = wrongOnPayload.value(QStringLiteral("commands")).toArray().first().toObject();
    QJsonObject frame = command.value(QStringLiteral("frame")).toObject();
    frame.insert(QStringLiteral("data"), QStringLiteral("01 02 03"));
    command.insert(QStringLiteral("frame"), frame);
    ok &= expectInvalid(withCommand(wrongOnPayload, 0, command),
                        QStringLiteral("HM025 wrong on payload"),
                        QStringLiteral("workLightOn"));

    QJsonObject wrongPriority = hm025;
    command = wrongPriority.value(QStringLiteral("commands")).toArray().first().toObject();
    frame = command.value(QStringLiteral("frame")).toObject();
    frame.insert(QStringLiteral("priority"), 3);
    command.insert(QStringLiteral("frame"), frame);
    ok &= expectInvalid(withCommand(wrongPriority, 0, command),
                        QStringLiteral("HM025 wrong priority"),
                        QStringLiteral("priority"));

    QJsonObject unsafeCleanup = hm025;
    QJsonArray tests = unsafeCleanup.value(QStringLiteral("tests")).toArray();
    QJsonObject test = tests.first().toObject();
    test.insert(QStringLiteral("cleanup"), QJsonArray{
        QJsonObject{
            {QStringLiteral("type"), QStringLiteral("sendCommand")},
            {QStringLiteral("commandId"), QStringLiteral("workLightOn")}
        }
    });
    tests[0] = test;
    unsafeCleanup.insert(QStringLiteral("tests"), tests);
    ok &= expectInvalid(unsafeCleanup,
                        QStringLiteral("HM025 unsafe cleanup"),
                        QStringLiteral("cleanup"));

    QJsonObject wrongPolarity = hm025;
    QJsonArray controls = wrongPolarity.value(QStringLiteral("controls")).toArray();
    QJsonObject workLight = controls.at(1).toObject();
    workLight.insert(QStringLiteral("activeLow"), false);
    controls[1] = workLight;
    wrongPolarity.insert(QStringLiteral("controls"), controls);
    ok &= expectInvalid(wrongPolarity,
                        QStringLiteral("HM025 wrong light polarity"),
                        QStringLiteral("activeLow"));
    return ok;
}

} // namespace

int main(int argc, char *argv[])
{
    QCoreApplication application(argc, argv);

    const QJsonObject singleAxis =
        loadExample(QStringLiteral("valid-test-only-single-axis.json"));
    const QJsonObject cross2d =
        loadExample(QStringLiteral("valid-firmware-backed-cross2d.json"));
    const QJsonObject hm025 =
        loadExample(QStringLiteral("valid-hm025-light.json"));

    bool ok = true;
    ok &= expect(!singleAxis.isEmpty(), QStringLiteral("single-axis example is empty"));
    ok &= expect(!cross2d.isEmpty(), QStringLiteral("cross2D example is empty"));
    ok &= expect(!hm025.isEmpty(), QStringLiteral("HM025 example is empty"));
    if (!ok) {
        return 1;
    }

    ok &= expectValid(singleAxis, QStringLiteral("valid single-axis example"));
    ok &= expectValid(cross2d, QStringLiteral("valid cross2D example"));
    ok &= expectValid(hm025, QStringLiteral("valid HM025 example"));

    ok &= verifyVersionRules(singleAxis, cross2d);
    ok &= verifyOperationRules(singleAxis, cross2d);
    ok &= verifyProtocolAndHexRules(singleAxis, hm025);
    ok &= verifyLayoutAndPayloadRules(singleAxis, hm025);
    ok &= verifyReferenceRules(singleAxis, hm025);
    ok &= verifyTopologyRules(singleAxis, cross2d);
    ok &= verifySignalBitRules(singleAxis);
    ok &= verifyTransformRules(singleAxis);
    ok &= verifyLayoutGeometryRules(singleAxis);
    ok &= verifyUniqueIdRules(singleAxis, hm025);
    ok &= verifyHm025SafetyRules(hm025);

    if (!ok) {
        return 1;
    }
    qInfo() << "Product Config V3 validator smoke passed";
    return 0;
}
