#include "ProductConfigV3Validator.h"

#include <QFileInfo>
#include <QHash>
#include <QJsonArray>
#include <QJsonValue>
#include <QRegularExpression>
#include <QSet>

namespace {

const QRegularExpression productVersionPattern(
    QStringLiteral("^V[1-9][0-9]*(?:\\.[0-9]+\\.[0-9]+)?$"));
const QRegularExpression firmwareVersionPattern(
    QStringLiteral("^[0-9]+\\.[0-9]+\\.[0-9]+$"));
const QRegularExpression payloadPattern(
    QStringLiteral("^(?:[0-9A-F]{2})(?: [0-9A-F]{2})*$"));
const QRegularExpression idPattern(
    QStringLiteral("^[A-Za-z][A-Za-z0-9_-]*$"));

class Validator
{
public:
    ProductConfigV3Validator::Result run(const QJsonObject &config)
    {
        validateSchemaVersion(config);
        const QString productVersion = validateProduct(config);
        validateLegacyRevision(config);
        validateOperation(config, productVersion);

        const QString protocol = validateProtocol(config);
        validateBus(config, protocol);

        const QSet<QString> messageIds = validateMessages(config, protocol);
        const QSet<QString> signalIds = validateSignals(config, messageIds);
        const QSet<QString> commandIds = validateCommands(config);
        const QSet<QString> controlIds = validateControls(config, signalIds, commandIds);
        validateLayout(config, controlIds);
        validateTests(config, signalIds, commandIds, controlIds);
        validateHm025Safety(config);

        return {m_errors.isEmpty(), m_errors};
    }

private:
    void addError(const QString &message)
    {
        m_errors.append(message);
    }

    QJsonObject requiredObject(const QJsonObject &parent,
                               const QString &key,
                               const QString &path)
    {
        const QJsonValue value = parent.value(key);
        if (!value.isObject()) {
            addError(QStringLiteral("%1 must be an object").arg(path));
            return {};
        }
        return value.toObject();
    }

    QJsonArray requiredArray(const QJsonObject &parent,
                             const QString &key,
                             const QString &path,
                             bool allowEmpty)
    {
        const QJsonValue value = parent.value(key);
        if (!value.isArray()) {
            addError(QStringLiteral("%1 must be an array").arg(path));
            return {};
        }
        const QJsonArray array = value.toArray();
        if (!allowEmpty && array.isEmpty()) {
            addError(QStringLiteral("%1 must not be empty").arg(path));
        }
        return array;
    }

    QString requiredString(const QJsonObject &parent,
                           const QString &key,
                           const QString &path)
    {
        const QJsonValue value = parent.value(key);
        if (!value.isString() || value.toString().isEmpty()) {
            addError(QStringLiteral("%1 must be a non-empty string").arg(path));
            return {};
        }
        return value.toString();
    }

    int requiredDlc(const QJsonObject &parent, const QString &path)
    {
        const QJsonValue value = parent.value(QStringLiteral("dlc"));
        if (!value.isDouble()) {
            addError(QStringLiteral("%1.DLC must be an integer from 0 to 8").arg(path));
            return -1;
        }
        const double raw = value.toDouble();
        const int dlc = value.toInt(-1);
        if (raw != dlc || dlc < 0 || dlc > 8) {
            addError(QStringLiteral("%1.DLC must be an integer from 0 to 8").arg(path));
            return -1;
        }
        return dlc;
    }

    int requiredInteger(const QJsonObject &parent,
                        const QString &key,
                        const QString &path)
    {
        const QJsonValue value = parent.value(key);
        if (!value.isDouble() || value.toDouble() != value.toInt()) {
            addError(QStringLiteral("%1 must be an integer").arg(path));
            return -1;
        }
        return value.toInt();
    }

    double requiredNumber(const QJsonObject &parent,
                          const QString &key,
                          const QString &path,
                          bool *valid = nullptr)
    {
        const QJsonValue value = parent.value(key);
        const bool isValid = value.isDouble();
        if (valid) {
            *valid = isValid;
        }
        if (!isValid) {
            addError(QStringLiteral("%1 must be a number").arg(path));
            return 0.0;
        }
        return value.toDouble();
    }

    bool isCanonicalHex(const QJsonValue &value, int digits, const QString &path)
    {
        if (!value.isString()) {
            addError(QStringLiteral("%1 must be a canonical uppercase hex string").arg(path));
            return false;
        }
        const QRegularExpression pattern(
            QStringLiteral("^0x[0-9A-F]{%1}$").arg(digits));
        if (!pattern.match(value.toString()).hasMatch()) {
            addError(QStringLiteral("%1 must be a canonical uppercase hex string").arg(path));
            return false;
        }
        return true;
    }

    bool isCanonicalCanId(const QJsonValue &value, const QString &path)
    {
        if (!value.isString()) {
            addError(QStringLiteral("%1 must be a canonical uppercase hex CAN ID").arg(path));
            return false;
        }
        static const QRegularExpression pattern(
            QStringLiteral("^(?:0x[0-9A-F]{3}|0x[0-9A-F]{8})$"));
        if (!pattern.match(value.toString()).hasMatch()) {
            addError(QStringLiteral("%1 must be a canonical uppercase hex CAN ID").arg(path));
            return false;
        }
        return true;
    }

    void validateSchemaVersion(const QJsonObject &config)
    {
        const QJsonValue value = config.value(QStringLiteral("schemaVersion"));
        if (!value.isDouble() || value.toInt(-1) != 3 || value.toDouble() != 3.0) {
            addError(QStringLiteral("schemaVersion must equal 3"));
        }
    }

    QString validateProduct(const QJsonObject &config)
    {
        const QJsonObject product =
            requiredObject(config, QStringLiteral("product"), QStringLiteral("product"));
        requiredString(product, QStringLiteral("code"), QStringLiteral("product.code"));
        const QString version =
            requiredString(product, QStringLiteral("version"), QStringLiteral("product.version"));
        if (!version.isEmpty() && !productVersionPattern.match(version).hasMatch()) {
            addError(QStringLiteral(
                "product.version must use V<major> or V<major>.<minor>.<patch>"));
        }
        if (!product.contains(QStringLiteral("description"))
            || !product.value(QStringLiteral("description")).isString()) {
            addError(QStringLiteral("product.description must be a string"));
        }
        return version;
    }

    void validateLegacyRevision(const QJsonObject &config)
    {
        const QJsonValue legacyConfig = config.value(QStringLiteral("config"));
        if (legacyConfig.isObject()
            && legacyConfig.toObject().contains(QStringLiteral("revision"))) {
            addError(QStringLiteral("legacy config.revision is not allowed in V3"));
        }
    }

    void validateOperation(const QJsonObject &config, const QString &productVersion)
    {
        const QJsonObject operation =
            requiredObject(config, QStringLiteral("operation"), QStringLiteral("operation"));
        const QString mode =
            requiredString(operation, QStringLiteral("mode"), QStringLiteral("operation.mode"));
        const QJsonObject firmware =
            requiredObject(operation, QStringLiteral("firmware"), QStringLiteral("operation.firmware"));
        const QString source =
            requiredString(firmware, QStringLiteral("source"),
                           QStringLiteral("operation.firmware.source"));

        if (mode == QStringLiteral("test_only")) {
            if (source != QStringLiteral("external")) {
                addError(QStringLiteral("test_only firmware source must be external"));
            }
            if (firmware.contains(QStringLiteral("version"))
                || firmware.contains(QStringLiteral("artifact"))) {
                addError(QStringLiteral(
                    "test_only external firmware must not contain version or artifact"));
            }
            return;
        }

        if (mode != QStringLiteral("firmware-backed")) {
            addError(QStringLiteral(
                "operation.mode must be test_only or firmware-backed"));
            return;
        }

        if (source != QStringLiteral("bundled")) {
            addError(QStringLiteral("firmware-backed firmware source must be bundled"));
        }
        const QString firmwareVersion =
            requiredString(firmware, QStringLiteral("version"),
                           QStringLiteral("operation.firmware.version"));
        if (!firmwareVersion.isEmpty()
            && !firmwareVersionPattern.match(firmwareVersion).hasMatch()) {
            addError(QStringLiteral(
                "operation.firmware.version must use major.minor.patch"));
        }

        if (!firmwareVersion.isEmpty()
            && productVersion != QStringLiteral("V") + firmwareVersion) {
            addError(QStringLiteral(
                "product.version must equal V + operation.firmware.version"));
        }

        const QString artifact =
            requiredString(firmware, QStringLiteral("artifact"),
                           QStringLiteral("operation.firmware.artifact"));
        const QJsonObject product = config.value(QStringLiteral("product")).toObject();
        const QString expectedBase =
            product.value(QStringLiteral("code")).toString() + QLatin1Char('_') + productVersion;
        const QFileInfo artifactInfo(artifact);
        const QString suffix = artifactInfo.suffix();
        const bool supportedSuffix = suffix == QStringLiteral("elf")
            || suffix == QStringLiteral("hex")
            || suffix == QStringLiteral("bin");
        if (!artifact.isEmpty()
            && (artifactInfo.fileName() != artifact
                || artifactInfo.completeBaseName() != expectedBase
                || !supportedSuffix)) {
            addError(QStringLiteral(
                "operation.firmware.artifact must match product.code_product.version"
                " and use .elf, .hex, or .bin"));
        }
    }

    QString validateProtocol(const QJsonObject &config)
    {
        const QString protocol =
            requiredString(config, QStringLiteral("protocol"), QStringLiteral("protocol"));
        if (!protocol.isEmpty()
            && protocol != QStringLiteral("j1939")
            && protocol != QStringLiteral("canopen")
            && protocol != QStringLiteral("raw_can")) {
            addError(QStringLiteral("protocol must be j1939, canopen, or raw_can"));
        }
        return protocol;
    }

    void validateBus(const QJsonObject &config, const QString &protocol)
    {
        const QJsonObject bus =
            requiredObject(config, QStringLiteral("bus"), QStringLiteral("bus"));
        const QString frameFormat =
            requiredString(bus, QStringLiteral("frameFormat"), QStringLiteral("bus.frameFormat"));

        if (protocol == QStringLiteral("j1939")) {
            isCanonicalHex(bus.value(QStringLiteral("sourceAddress")),
                           2,
                           QStringLiteral("bus.sourceAddress hex"));
            if (frameFormat != QStringLiteral("extended")) {
                addError(QStringLiteral("J1939 bus.frameFormat must be extended"));
            }
        } else if (protocol == QStringLiteral("canopen")) {
            isCanonicalHex(bus.value(QStringLiteral("nodeId")),
                           2,
                           QStringLiteral("bus.nodeId hex"));
            if (frameFormat != QStringLiteral("standard")) {
                addError(QStringLiteral("CANopen bus.frameFormat must be standard"));
            }
        }
    }

    QSet<QString> validateMessages(const QJsonObject &config, const QString &protocol)
    {
        const QJsonArray messages =
            requiredArray(config, QStringLiteral("messages"), QStringLiteral("messages"), false);
        QSet<QString> ids;
        for (qsizetype index = 0; index < messages.size(); ++index) {
            if (!messages.at(index).isObject()) {
                addError(QStringLiteral("messages[%1] must be an object").arg(index));
                continue;
            }
            const QJsonObject message = messages.at(index).toObject();
            const QString path = QStringLiteral("messages[%1]").arg(index);
            const QString id = requiredString(message, QStringLiteral("id"), path + QStringLiteral(".id"));
            if (!id.isEmpty()) {
                if (!idPattern.match(id).hasMatch()) {
                    addError(path + QStringLiteral(".id is invalid"));
                } else if (ids.contains(id)) {
                    addError(path + QStringLiteral(".id is duplicated"));
                }
                ids.insert(id);
            }
            const int dlc = requiredDlc(message, path);
            if (!id.isEmpty() && dlc >= 0) {
                m_messageDlc.insert(id, dlc);
            }
            if (protocol == QStringLiteral("j1939")) {
                isCanonicalHex(message.value(QStringLiteral("pgn")),
                               6,
                               path + QStringLiteral(".pgn hex"));
                if (message.contains(QStringLiteral("sourceAddress"))) {
                    isCanonicalHex(message.value(QStringLiteral("sourceAddress")),
                                   2,
                                   path + QStringLiteral(".sourceAddress hex"));
                }
                if (message.contains(QStringLiteral("destinationAddress"))) {
                    isCanonicalHex(message.value(QStringLiteral("destinationAddress")),
                                   2,
                                   path + QStringLiteral(".destinationAddress hex"));
                }
            } else {
                isCanonicalCanId(message.value(QStringLiteral("canId")),
                                 path + QStringLiteral(".canId hex"));
            }
        }
        return ids;
    }

    QSet<QString> validateSignals(const QJsonObject &config,
                                  const QSet<QString> &messageIds)
    {
        const QJsonArray signalArray =
            requiredArray(config, QStringLiteral("signals"), QStringLiteral("signals"), false);
        QSet<QString> ids;
        QHash<QString, QList<QPair<int, int>>> occupiedRanges;
        for (qsizetype index = 0; index < signalArray.size(); ++index) {
            if (!signalArray.at(index).isObject()) {
                addError(QStringLiteral("signals[%1] must be an object").arg(index));
                continue;
            }
            const QJsonObject signal = signalArray.at(index).toObject();
            const QString path = QStringLiteral("signals[%1]").arg(index);
            const QString id = requiredString(signal, QStringLiteral("id"), path + QStringLiteral(".id"));
            if (!id.isEmpty()) {
                if (ids.contains(id)) {
                    addError(path + QStringLiteral(".id is duplicated"));
                }
                ids.insert(id);
            }

            const QJsonObject source =
                requiredObject(signal, QStringLiteral("source"), path + QStringLiteral(".source"));
            const QString messageId =
                requiredString(source, QStringLiteral("messageId"),
                               path + QStringLiteral(".source.messageId"));
            if (!messageId.isEmpty() && !messageIds.contains(messageId)) {
                addError(path + QStringLiteral(".source.messageId references missing message"));
            }

            const int startByte =
                requiredInteger(source, QStringLiteral("startByte"),
                                path + QStringLiteral(".source.startByte"));
            const int startBit =
                requiredInteger(source, QStringLiteral("startBit"),
                                path + QStringLiteral(".source.startBit"));
            const int bitLength =
                requiredInteger(source, QStringLiteral("bitLength"),
                                path + QStringLiteral(".source.bitLength"));
            if (startByte < 0 || startBit < 0 || startBit > 7 || bitLength <= 0) {
                addError(path + QStringLiteral(
                    ".source bit range requires startByte >= 0, startBit 0..7, bitLength > 0"));
                continue;
            }

            if (!messageId.isEmpty() && m_messageDlc.contains(messageId)) {
                const int start = startByte * 8 + startBit;
                const int end = start + bitLength;
                if (end > m_messageDlc.value(messageId) * 8) {
                    addError(path + QStringLiteral(
                        ".source bit range exceeds referenced message DLC"));
                    continue;
                }
                for (const QPair<int, int> &range : occupiedRanges.value(messageId)) {
                    if (start < range.second && end > range.first) {
                        addError(path + QStringLiteral(
                            ".source bit range overlaps another signal in the same message"));
                        break;
                    }
                }
                occupiedRanges[messageId].append(qMakePair(start, end));
            }
        }
        return ids;
    }

    QSet<QString> validateCommands(const QJsonObject &config)
    {
        const QJsonArray commands =
            requiredArray(config, QStringLiteral("commands"), QStringLiteral("commands"), true);
        QSet<QString> ids;
        for (qsizetype index = 0; index < commands.size(); ++index) {
            if (!commands.at(index).isObject()) {
                addError(QStringLiteral("commands[%1] must be an object").arg(index));
                continue;
            }
            const QJsonObject command = commands.at(index).toObject();
            const QString path = QStringLiteral("commands[%1]").arg(index);
            const QString id = requiredString(command, QStringLiteral("id"), path + QStringLiteral(".id"));
            if (!id.isEmpty()) {
                if (ids.contains(id)) {
                    addError(path + QStringLiteral(".id is duplicated"));
                }
                ids.insert(id);
            }
            const QString transport =
                requiredString(command, QStringLiteral("transport"),
                               path + QStringLiteral(".transport"));
            const QJsonObject frame =
                requiredObject(command, QStringLiteral("frame"), path + QStringLiteral(".frame"));
            const int dlc = requiredDlc(frame, path + QStringLiteral(".frame"));
            const QJsonValue payloadValue = frame.value(QStringLiteral("data"));
            const QString payload = payloadValue.toString();
            if (!payloadValue.isString()
                || (dlc == 0 ? !payload.isEmpty() : !payloadPattern.match(payload).hasMatch())) {
                addError(path + QStringLiteral(".frame.payload must use uppercase hex bytes"));
            } else if (dlc >= 0) {
                const int payloadBytes =
                    payload.isEmpty() ? 0 : payload.count(QLatin1Char(' ')) + 1;
                if (payloadBytes != dlc) {
                    addError(path + QStringLiteral(".frame DLC does not match payload byte count"));
                }
            }

            if (transport == QStringLiteral("j1939")) {
                isCanonicalHex(frame.value(QStringLiteral("pgn")),
                               6,
                               path + QStringLiteral(".frame.pgn hex"));
                isCanonicalHex(frame.value(QStringLiteral("sourceAddress")),
                               2,
                               path + QStringLiteral(".frame.sourceAddress hex"));
                isCanonicalHex(frame.value(QStringLiteral("destinationAddress")),
                               2,
                               path + QStringLiteral(".frame.destinationAddress hex"));
            } else if (transport == QStringLiteral("can")) {
                isCanonicalCanId(frame.value(QStringLiteral("canId")),
                                 path + QStringLiteral(".frame.canId hex"));
            } else {
                addError(path + QStringLiteral(".transport must be j1939 or can"));
            }
        }
        return ids;
    }

    void validateAxisBinding(const QJsonObject &control,
                             const QString &key,
                             const QString &path,
                             const QSet<QString> &signalIds)
    {
        const QJsonObject binding = requiredObject(control, key, path);
        const QString signalId =
            requiredString(binding, QStringLiteral("signalId"), path + QStringLiteral(".signalId"));
        if (!signalId.isEmpty() && !signalIds.contains(signalId)) {
            addError(path + QStringLiteral(".signalId references missing signal"));
        }

        const QJsonObject transform =
            requiredObject(binding, QStringLiteral("transform"),
                           path + QStringLiteral(".transform"));
        bool rawMinValid = false;
        bool rawCenterValid = false;
        bool rawMaxValid = false;
        bool deadzoneValid = false;
        const double rawMin =
            requiredNumber(transform, QStringLiteral("rawMin"),
                           path + QStringLiteral(".transform.rawMin"), &rawMinValid);
        const double rawCenter =
            requiredNumber(transform, QStringLiteral("rawCenter"),
                           path + QStringLiteral(".transform.rawCenter"), &rawCenterValid);
        const double rawMax =
            requiredNumber(transform, QStringLiteral("rawMax"),
                           path + QStringLiteral(".transform.rawMax"), &rawMaxValid);
        const double deadzone =
            requiredNumber(transform, QStringLiteral("deadzone"),
                           path + QStringLiteral(".transform.deadzone"), &deadzoneValid);
        if (rawMinValid && rawCenterValid && rawMaxValid
            && !(rawMin < rawCenter && rawCenter < rawMax)) {
            addError(path + QStringLiteral(
                ".transform must satisfy rawMin < rawCenter < rawMax"));
        }
        if (deadzoneValid && deadzone < 0.0) {
            addError(path + QStringLiteral(".transform.deadzone must be non-negative"));
        }
    }

    QSet<QString> validateControls(const QJsonObject &config,
                                   const QSet<QString> &signalIds,
                                   const QSet<QString> &commandIds)
    {
        const QJsonArray controls =
            requiredArray(config, QStringLiteral("controls"), QStringLiteral("controls"), false);
        QSet<QString> ids;
        for (qsizetype index = 0; index < controls.size(); ++index) {
            if (!controls.at(index).isObject()) {
                addError(QStringLiteral("controls[%1] must be an object").arg(index));
                continue;
            }
            const QJsonObject control = controls.at(index).toObject();
            const QString path = QStringLiteral("controls[%1]").arg(index);
            const QString id = requiredString(control, QStringLiteral("id"), path + QStringLiteral(".id"));
            if (!id.isEmpty()) {
                if (ids.contains(id)) {
                    addError(path + QStringLiteral(".id is duplicated"));
                }
                ids.insert(id);
            }
            const QString type =
                requiredString(control, QStringLiteral("type"), path + QStringLiteral(".type"));
            if (type == QStringLiteral("axis")) {
                const QJsonObject topology =
                    requiredObject(control, QStringLiteral("topology"),
                                   path + QStringLiteral(".topology"));
                if (topology.value(QStringLiteral("kind")).toString()
                    != QStringLiteral("singleAxis")) {
                    addError(path + QStringLiteral(".topology.kind must be singleAxis"));
                }
                const QString orientation =
                    topology.value(QStringLiteral("orientation")).toString();
                if (orientation != QStringLiteral("horizontal")
                    && orientation != QStringLiteral("vertical")) {
                    addError(path + QStringLiteral(
                        ".topology.orientation must be horizontal or vertical"));
                }
                validateAxisBinding(control,
                                    QStringLiteral("axis"),
                                    path + QStringLiteral(".axis"),
                                    signalIds);
            } else if (type == QStringLiteral("joystick")) {
                const QJsonObject topology =
                    requiredObject(control, QStringLiteral("topology"),
                                   path + QStringLiteral(".topology"));
                if (topology.value(QStringLiteral("kind")).toString()
                    != QStringLiteral("cross2D")) {
                    addError(path + QStringLiteral(".topology.kind must be cross2D"));
                }
                if (topology.value(QStringLiteral("gate")).toString()
                    != QStringLiteral("cross")) {
                    addError(path + QStringLiteral(".topology.gate for cross2D must be cross"));
                }
                validateAxisBinding(control,
                                    QStringLiteral("xAxis"),
                                    path + QStringLiteral(".xAxis"),
                                    signalIds);
                validateAxisBinding(control,
                                    QStringLiteral("yAxis"),
                                    path + QStringLiteral(".yAxis"),
                                    signalIds);
            } else if (type == QStringLiteral("button")) {
                const QString signalId =
                    requiredString(control, QStringLiteral("signalId"),
                                   path + QStringLiteral(".signalId"));
                if (!signalId.isEmpty() && !signalIds.contains(signalId)) {
                    addError(path + QStringLiteral(".signalId references missing signal"));
                }
            } else if (type == QStringLiteral("binaryOutput")) {
                for (const QString &key : {QStringLiteral("onCommandId"),
                                           QStringLiteral("offCommandId")}) {
                    const QString commandId =
                        requiredString(control, key, path + QLatin1Char('.') + key);
                    if (!commandId.isEmpty() && !commandIds.contains(commandId)) {
                        addError(path + QLatin1Char('.') + key
                                 + QStringLiteral(" references missing command"));
                    }
                }
            } else {
                addError(path + QStringLiteral(".type is unsupported"));
            }
        }
        return ids;
    }

    void validateLayout(const QJsonObject &config, const QSet<QString> &controlIds)
    {
        const QJsonObject layout =
            requiredObject(config, QStringLiteral("layout"), QStringLiteral("layout"));
        if (layout.value(QStringLiteral("mode")).toString() != QStringLiteral("designed")) {
            addError(QStringLiteral("layout.mode must be designed"));
        }
        const QJsonObject canvas =
            requiredObject(layout, QStringLiteral("canvas"), QStringLiteral("layout.canvas"));
        const int canvasWidth =
            requiredInteger(canvas, QStringLiteral("width"), QStringLiteral("layout.canvas.width"));
        const int canvasHeight =
            requiredInteger(canvas, QStringLiteral("height"), QStringLiteral("layout.canvas.height"));
        if (canvasWidth <= 0 || canvasHeight <= 0) {
            addError(QStringLiteral("layout.canvas width/height must be positive"));
        }

        const QJsonArray cards =
            requiredArray(layout, QStringLiteral("cards"), QStringLiteral("layout.cards"), false);
        QSet<QString> cardIds;
        for (qsizetype index = 0; index < cards.size(); ++index) {
            if (!cards.at(index).isObject()) {
                addError(QStringLiteral("layout.cards[%1] must be an object").arg(index));
                continue;
            }
            const QJsonObject card = cards.at(index).toObject();
            const QString path = QStringLiteral("layout.cards[%1]").arg(index);
            const QString id =
                requiredString(card, QStringLiteral("id"), path + QStringLiteral(".id"));
            if (!id.isEmpty()) {
                if (cardIds.contains(id)) {
                    addError(path + QStringLiteral(".id is duplicated"));
                }
                cardIds.insert(id);
            }

            const int x = requiredInteger(card, QStringLiteral("x"), path + QStringLiteral(".x"));
            const int y = requiredInteger(card, QStringLiteral("y"), path + QStringLiteral(".y"));
            const int width =
                requiredInteger(card, QStringLiteral("width"), path + QStringLiteral(".width"));
            const int height =
                requiredInteger(card, QStringLiteral("height"), path + QStringLiteral(".height"));
            if (x < 0 || y < 0) {
                addError(path + QStringLiteral(".x/y must be non-negative"));
            }
            if (width <= 0 || height <= 0) {
                addError(path + QStringLiteral(".width/height must be positive"));
            }
            if (canvasWidth > 0 && canvasHeight > 0
                && x >= 0 && y >= 0 && width > 0 && height > 0
                && (static_cast<qint64>(x) + width > canvasWidth
                    || static_cast<qint64>(y) + height > canvasHeight)) {
                addError(path + QStringLiteral(" must remain inside layout.canvas"));
            }

            const QJsonArray references =
                requiredArray(card, QStringLiteral("controlIds"),
                              path + QStringLiteral(".controlIds"), false);
            for (const QJsonValue &reference : references) {
                if (!reference.isString() || !controlIds.contains(reference.toString())) {
                    addError(path + QStringLiteral(".controlIds references missing control"));
                }
            }
        }
    }

    void validateTests(const QJsonObject &config,
                       const QSet<QString> &signalIds,
                       const QSet<QString> &commandIds,
                       const QSet<QString> &controlIds)
    {
        const QJsonArray tests =
            requiredArray(config, QStringLiteral("tests"), QStringLiteral("tests"), true);
        QSet<QString> testIds;
        for (qsizetype testIndex = 0; testIndex < tests.size(); ++testIndex) {
            if (!tests.at(testIndex).isObject()) {
                addError(QStringLiteral("tests[%1] must be an object").arg(testIndex));
                continue;
            }
            const QJsonObject test = tests.at(testIndex).toObject();
            const QString testPath = QStringLiteral("tests[%1]").arg(testIndex);
            const QString id =
                requiredString(test, QStringLiteral("id"), testPath + QStringLiteral(".id"));
            if (!id.isEmpty()) {
                if (testIds.contains(id)) {
                    addError(testPath + QStringLiteral(".id is duplicated"));
                }
                testIds.insert(id);
            }
            for (const QString &arrayName : {QStringLiteral("steps"),
                                             QStringLiteral("cleanup")}) {
                const QJsonArray steps =
                    requiredArray(test, arrayName,
                                  QStringLiteral("tests[%1].%2").arg(testIndex).arg(arrayName),
                                  false);
                for (qsizetype stepIndex = 0; stepIndex < steps.size(); ++stepIndex) {
                    const QJsonObject step = steps.at(stepIndex).toObject();
                    if (step.contains(QStringLiteral("signalId"))
                        && !signalIds.contains(step.value(QStringLiteral("signalId")).toString())) {
                        addError(QStringLiteral("test step references missing signal"));
                    }
                    if (step.contains(QStringLiteral("commandId"))
                        && !commandIds.contains(step.value(QStringLiteral("commandId")).toString())) {
                        addError(QStringLiteral("test step references missing command"));
                    }
                    if (step.contains(QStringLiteral("controlId"))
                        && !controlIds.contains(step.value(QStringLiteral("controlId")).toString())) {
                        addError(QStringLiteral("test step references missing control"));
                    }
                }
            }
        }
    }

    void validateHm025Command(const QJsonObject &command,
                              const QString &commandId,
                              const QString &expectedData)
    {
        if (command.isEmpty()) {
            addError(QStringLiteral("HM025 requires %1 command").arg(commandId));
            return;
        }
        const QJsonObject frame = command.value(QStringLiteral("frame")).toObject();
        if (command.value(QStringLiteral("transport")).toString() != QStringLiteral("j1939")) {
            addError(QStringLiteral("HM025 %1 transport must be j1939").arg(commandId));
        }
        if (frame.value(QStringLiteral("priority")).toInt(-1) != 6) {
            addError(QStringLiteral("HM025 %1 priority must be 6").arg(commandId));
        }
        if (frame.value(QStringLiteral("pgn")).toString() != QStringLiteral("0x00D000")) {
            addError(QStringLiteral("HM025 %1 PGN must be 0x00D000").arg(commandId));
        }
        if (frame.value(QStringLiteral("sourceAddress")).toString() != QStringLiteral("0x03")) {
            addError(QStringLiteral("HM025 %1 sourceAddress must be 0x03").arg(commandId));
        }
        if (frame.value(QStringLiteral("destinationAddress")).toString() != QStringLiteral("0x33")) {
            addError(QStringLiteral("HM025 %1 destinationAddress must be 0x33").arg(commandId));
        }
        if (frame.value(QStringLiteral("dlc")).toInt(-1) != 3) {
            addError(QStringLiteral("HM025 %1 DLC must be 3").arg(commandId));
        }
        if (frame.value(QStringLiteral("data")).toString() != expectedData) {
            addError(QStringLiteral("HM025 %1 data must be %2").arg(commandId, expectedData));
        }
    }

    void validateHm025Safety(const QJsonObject &config)
    {
        if (config.value(QStringLiteral("product")).toObject()
                .value(QStringLiteral("code")).toString()
            != QStringLiteral("JC6000-BGA-HM025")) {
            return;
        }

        QHash<QString, QJsonObject> commandsById;
        for (const QJsonValue &value : config.value(QStringLiteral("commands")).toArray()) {
            const QJsonObject command = value.toObject();
            commandsById.insert(command.value(QStringLiteral("id")).toString(), command);
        }
        validateHm025Command(commandsById.value(QStringLiteral("workLightOn")),
                             QStringLiteral("workLightOn"),
                             QStringLiteral("00 FA 00"));
        validateHm025Command(commandsById.value(QStringLiteral("workLightOff")),
                             QStringLiteral("workLightOff"),
                             QStringLiteral("00 00 00"));

        QJsonObject workLight;
        for (const QJsonValue &value : config.value(QStringLiteral("controls")).toArray()) {
            const QJsonObject control = value.toObject();
            if (control.value(QStringLiteral("id")).toString() == QStringLiteral("workLight")) {
                workLight = control;
                break;
            }
        }
        if (workLight.isEmpty()) {
            addError(QStringLiteral("HM025 requires workLight binaryOutput control"));
        } else {
            if (workLight.value(QStringLiteral("type")).toString()
                != QStringLiteral("binaryOutput")) {
                addError(QStringLiteral("HM025 workLight type must be binaryOutput"));
            }
            if (workLight.value(QStringLiteral("onCommandId")).toString()
                != QStringLiteral("workLightOn")) {
                addError(QStringLiteral("HM025 workLight onCommandId must be workLightOn"));
            }
            if (workLight.value(QStringLiteral("offCommandId")).toString()
                != QStringLiteral("workLightOff")) {
                addError(QStringLiteral("HM025 workLight offCommandId must be workLightOff"));
            }
            if (!workLight.value(QStringLiteral("activeLow")).isBool()
                || !workLight.value(QStringLiteral("activeLow")).toBool()) {
                addError(QStringLiteral("HM025 workLight activeLow must be true"));
            }
        }

        bool safeCleanupFound = false;
        for (const QJsonValue &testValue : config.value(QStringLiteral("tests")).toArray()) {
            const QJsonArray cleanup =
                testValue.toObject().value(QStringLiteral("cleanup")).toArray();
            for (const QJsonValue &stepValue : cleanup) {
                const QJsonObject step = stepValue.toObject();
                if (step.value(QStringLiteral("type")).toString()
                        == QStringLiteral("sendCommand")
                    && step.value(QStringLiteral("commandId")).toString()
                        == QStringLiteral("workLightOff")) {
                    safeCleanupFound = true;
                    break;
                }
            }
            if (safeCleanupFound) {
                break;
            }
        }
        if (!safeCleanupFound) {
            addError(QStringLiteral(
                "HM025 cleanup must send workLightOff on every test exit path"));
        }
    }

    QStringList m_errors;
    QHash<QString, int> m_messageDlc;
};

} // namespace

ProductConfigV3Validator::Result ProductConfigV3Validator::validate(const QJsonObject &config)
{
    return Validator().run(config);
}
