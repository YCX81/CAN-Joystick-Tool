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
    QStringLiteral("^[1-9][0-9]*(?:\\.[0-9]+\\.[0-9]+)?$"));
const QRegularExpression payloadPattern(
    QStringLiteral("^(?:[0-9A-F]{2})(?: [0-9A-F]{2})*$"));
const QRegularExpression idPattern(
    QStringLiteral("^[A-Za-z][A-Za-z0-9_-]*$"));

class Validator
{
public:
    ProductConfigV3Validator::Result run(const QJsonObject &config)
    {
        rejectUnknownKeys(
            config,
            {QStringLiteral("$schema"),
             QStringLiteral("schemaVersion"),
             QStringLiteral("product"),
             QStringLiteral("lifecycle"),
             QStringLiteral("operation"),
             QStringLiteral("calibration"),
             QStringLiteral("identityPolicy"),
             QStringLiteral("protocol"),
             QStringLiteral("bus"),
              QStringLiteral("messages"),
              QStringLiteral("signals"),
              QStringLiteral("bindingChannels"),
              QStringLiteral("controls"),
             QStringLiteral("commands"),
             QStringLiteral("tests"),
             QStringLiteral("layout")},
            QStringLiteral("top-level config"));
        validateSchemaVersion(config);
        const QString productVersion = validateProduct(config);
        validateLegacyRevision(config);
        validateLifecycle(config);
        validateOperation(config, productVersion);

        const QString protocol = validateProtocol(config);
        validateCalibration(config, protocol);
        validateIdentityPolicy(config, protocol);
        validateBus(config, protocol);

        const QSet<QString> messageIds = validateMessages(config, protocol);
        const QSet<QString> signalIds = validateSignals(config, messageIds);
        const QSet<QString> commandIds = validateCommands(config);
        validateBindingChannels(config, signalIds);
        const QSet<QString> controlIds = validateControls(config, signalIds, commandIds);
        validateBindingChannelCoverage(config);
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

    void rejectUnknownKeys(const QJsonObject &object,
                           const QSet<QString> &allowedKeys,
                           const QString &path)
    {
        for (auto iterator = object.constBegin(); iterator != object.constEnd(); ++iterator) {
            if (!allowedKeys.contains(iterator.key())) {
                addError(QStringLiteral("%1 property '%2' is not allowed")
                             .arg(path, iterator.key()));
            }
        }
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

    int packedBitsPerPosition(const QString &encoding) const
    {
        if (encoding == QStringLiteral("canopen_1bit")) {
            return 1;
        }
        if (encoding == QStringLiteral("j1939_2bit")
            || encoding == QStringLiteral("gessmann_2bit")
            || encoding == QStringLiteral("detent_2bit")) {
            return 2;
        }
        return 0;
    }

    bool validateSignalReference(const QString &signalId,
                                 const QString &path,
                                 const QSet<QString> &signalIds)
    {
        if (signalId.isEmpty()) {
            return false;
        }
        if (!signalIds.contains(signalId)) {
            addError(path + QStringLiteral(" references missing signal"));
            return false;
        }
        return true;
    }

    bool validatePackedPosition(const QString &signalId,
                                int position,
                                const QString &path)
    {
        if (m_signalKinds.value(signalId) != QStringLiteral("packedButtons")) {
            addError(path + QStringLiteral(" requires a packedButtons signal"));
            return false;
        }
        const int bitsPerPosition =
            packedBitsPerPosition(m_signalEncodings.value(signalId));
        const int logicalPositionCount =
            m_signalLogicalPositionCounts.value(signalId);
        if (bitsPerPosition <= 0
            || position < 0
            || position >= logicalPositionCount) {
            addError(path + QStringLiteral(" position is outside the packed signal"));
            return false;
        }
        return true;
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
        rejectUnknownKeys(product,
                          {QStringLiteral("code"),
                           QStringLiteral("version"),
                           QStringLiteral("description"),
                           QStringLiteral("customerBindings"),
                           QStringLiteral("aliases")},
                          QStringLiteral("product"));
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
        if (product.contains(QStringLiteral("customerBindings"))) {
            const QJsonArray bindings =
                requiredArray(product,
                              QStringLiteral("customerBindings"),
                              QStringLiteral("product.customerBindings"),
                              true);
            for (qsizetype index = 0; index < bindings.size(); ++index) {
                const QString path =
                    QStringLiteral("product.customerBindings[%1]").arg(index);
                if (!bindings.at(index).isObject()) {
                    addError(path + QStringLiteral(" must be an object"));
                    continue;
                }
                const QJsonObject binding = bindings.at(index).toObject();
                rejectUnknownKeys(binding,
                                  {QStringLiteral("name"),
                                   QStringLiteral("isDefault"),
                                   QStringLiteral("note")},
                                  path);
                requiredString(binding, QStringLiteral("name"), path + QStringLiteral(".name"));
                if (binding.contains(QStringLiteral("isDefault"))
                    && !binding.value(QStringLiteral("isDefault")).isBool()) {
                    addError(path + QStringLiteral(".isDefault must be a boolean"));
                }
                if (binding.contains(QStringLiteral("note"))
                    && !binding.value(QStringLiteral("note")).isString()) {
                    addError(path + QStringLiteral(".note must be a string"));
                }
            }
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

    void validateLifecycle(const QJsonObject &config)
    {
        const QJsonObject lifecycle =
            requiredObject(config, QStringLiteral("lifecycle"), QStringLiteral("lifecycle"));
        rejectUnknownKeys(lifecycle,
                          {QStringLiteral("status")},
                          QStringLiteral("lifecycle"));
        const QString status =
            requiredString(lifecycle, QStringLiteral("status"),
                           QStringLiteral("lifecycle.status"));
        if (status != QStringLiteral("active")
            && status != QStringLiteral("deprecated")) {
            addError(QStringLiteral(
                "lifecycle.status must be active or deprecated"));
        }
    }

    void validateOperation(const QJsonObject &config, const QString &productVersion)
    {
        const QJsonObject operation =
            requiredObject(config, QStringLiteral("operation"), QStringLiteral("operation"));
        rejectUnknownKeys(operation,
                          {QStringLiteral("mode"), QStringLiteral("firmware")},
                          QStringLiteral("operation"));
        const QString mode =
            requiredString(operation, QStringLiteral("mode"), QStringLiteral("operation.mode"));
        const QJsonObject firmware =
            requiredObject(operation, QStringLiteral("firmware"), QStringLiteral("operation.firmware"));
        rejectUnknownKeys(firmware,
                          {QStringLiteral("source"),
                           QStringLiteral("version"),
                           QStringLiteral("artifact")},
                          QStringLiteral("operation.firmware"));
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
                "operation.firmware.version must use major or major.minor.patch"));
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

    void validateCalibration(const QJsonObject &config, const QString &protocol)
    {
        const QJsonObject calibration =
            requiredObject(config, QStringLiteral("calibration"),
                           QStringLiteral("calibration"));
        const QString mode =
            requiredString(calibration, QStringLiteral("mode"),
                           QStringLiteral("calibration.mode"));
        if (mode == QStringLiteral("disabled")) {
            rejectUnknownKeys(calibration,
                              {QStringLiteral("mode"), QStringLiteral("reason")},
                              QStringLiteral("calibration"));
            requiredString(calibration, QStringLiteral("reason"),
                           QStringLiteral("calibration.reason"));
            return;
        }

        rejectUnknownKeys(calibration,
                          {QStringLiteral("mode"),
                           QStringLiteral("transport"),
                           QStringLiteral("allowedInNormalModeReadOnly")},
                          QStringLiteral("calibration"));
        if (mode != QStringLiteral("centerOnly")
            && mode != QStringLiteral("minCenterMax")) {
            addError(QStringLiteral(
                "calibration.mode must be centerOnly, minCenterMax, or disabled"));
        }
        const QString transport =
            requiredString(calibration, QStringLiteral("transport"),
                           QStringLiteral("calibration.transport"));
        if (transport != QStringLiteral("j1939VendorPgn")
            && transport != QStringLiteral("canopenSdo")) {
            addError(QStringLiteral("calibration.transport is unsupported"));
        }
        if (protocol == QStringLiteral("j1939")
            && transport != QStringLiteral("j1939VendorPgn")) {
            addError(QStringLiteral("J1939 calibration must use j1939VendorPgn"));
        } else if (protocol == QStringLiteral("canopen")
                   && transport != QStringLiteral("canopenSdo")) {
            addError(QStringLiteral("CANopen calibration must use canopenSdo"));
        } else if (protocol == QStringLiteral("raw_can")) {
            addError(QStringLiteral("raw_can calibration must be explicitly disabled"));
        }
        if (!calibration.value(QStringLiteral("allowedInNormalModeReadOnly")).isBool()) {
            addError(QStringLiteral(
                "calibration.allowedInNormalModeReadOnly must be a boolean"));
        }
    }

    void validateIdentityPolicy(const QJsonObject &config, const QString &protocol)
    {
        if (protocol != QStringLiteral("canopen")) {
            if (config.contains(QStringLiteral("identityPolicy"))) {
                addError(QStringLiteral(
                    "identityPolicy is only allowed for CANopen products"));
            }
            return;
        }

        const QJsonObject policy =
            requiredObject(config, QStringLiteral("identityPolicy"),
                           QStringLiteral("identityPolicy"));
        const QString mode =
            requiredString(policy, QStringLiteral("mode"),
                           QStringLiteral("identityPolicy.mode"));
        if (mode == QStringLiteral("disabled")) {
            rejectUnknownKeys(policy,
                              {QStringLiteral("mode"), QStringLiteral("reason")},
                              QStringLiteral("identityPolicy"));
            requiredString(policy, QStringLiteral("reason"),
                           QStringLiteral("identityPolicy.reason"));
            return;
        }

        rejectUnknownKeys(policy,
                          {QStringLiteral("mode"), QStringLiteral("deviceInfo")},
                          QStringLiteral("identityPolicy"));
        if (mode != QStringLiteral("required")) {
            addError(QStringLiteral(
                "identityPolicy.mode must be required or disabled"));
        }
        const QJsonObject deviceInfo =
            requiredObject(policy, QStringLiteral("deviceInfo"),
                           QStringLiteral("identityPolicy.deviceInfo"));
        rejectUnknownKeys(deviceInfo,
                          {QStringLiteral("vendorId"),
                           QStringLiteral("productCode"),
                           QStringLiteral("revisionNumber"),
                           QStringLiteral("serialNumber")},
                          QStringLiteral("identityPolicy.deviceInfo"));
        for (const QString &key : {QStringLiteral("vendorId"),
                                   QStringLiteral("productCode"),
                                   QStringLiteral("revisionNumber")}) {
            isCanonicalHex(deviceInfo.value(key), 8,
                           QStringLiteral("identityPolicy.deviceInfo.%1 hex").arg(key));
        }
        if (deviceInfo.contains(QStringLiteral("serialNumber"))) {
            isCanonicalHex(deviceInfo.value(QStringLiteral("serialNumber")), 8,
                           QStringLiteral("identityPolicy.deviceInfo.serialNumber hex"));
        }
    }

    void validateBus(const QJsonObject &config, const QString &protocol)
    {
        const QJsonObject bus =
            requiredObject(config, QStringLiteral("bus"), QStringLiteral("bus"));
        rejectUnknownKeys(bus,
                          {QStringLiteral("bitrateKbps"),
                           QStringLiteral("frameFormat"),
                           QStringLiteral("sourceAddress"),
                           QStringLiteral("nodeId")},
                          QStringLiteral("bus"));
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
            if (protocol == QStringLiteral("j1939")) {
                rejectUnknownKeys(message,
                                  {QStringLiteral("id"),
                                   QStringLiteral("name"),
                                   QStringLiteral("pgn"),
                                   QStringLiteral("priority"),
                                   QStringLiteral("sourceAddress"),
                                   QStringLiteral("destinationAddress"),
                                   QStringLiteral("dlc"),
                                   QStringLiteral("periodMs")},
                                  path);
            } else {
                rejectUnknownKeys(message,
                                  {QStringLiteral("id"),
                                   QStringLiteral("name"),
                                   QStringLiteral("canId"),
                                   QStringLiteral("dlc"),
                                   QStringLiteral("periodMs")},
                                  path);
            }
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
            rejectUnknownKeys(signal,
                              {QStringLiteral("id"),
                               QStringLiteral("kind"),
                               QStringLiteral("source")},
                              path);
            const QString id = requiredString(signal, QStringLiteral("id"), path + QStringLiteral(".id"));
            if (!id.isEmpty()) {
                if (ids.contains(id)) {
                    addError(path + QStringLiteral(".id is duplicated"));
                }
                ids.insert(id);
            }
            const QString kind =
                requiredString(signal, QStringLiteral("kind"), path + QStringLiteral(".kind"));
            static const QSet<QString> allowedKinds{
                QStringLiteral("position"),
                QStringLiteral("status"),
                QStringLiteral("fnr"),
                QStringLiteral("button"),
                QStringLiteral("packedButtons"),
                QStringLiteral("counter"),
                QStringLiteral("identity"),
                QStringLiteral("numeric"),
                QStringLiteral("crc"),
                QStringLiteral("selfCheck")
            };
            if (!kind.isEmpty() && !allowedKinds.contains(kind)) {
                addError(path + QStringLiteral(".kind is unsupported"));
            }

            const QJsonObject source =
                requiredObject(signal, QStringLiteral("source"), path + QStringLiteral(".source"));
            rejectUnknownKeys(source,
                              {QStringLiteral("messageId"),
                               QStringLiteral("startByte"),
                               QStringLiteral("startBit"),
                               QStringLiteral("bitLength"),
                               QStringLiteral("endian"),
                               QStringLiteral("encoding"),
                               QStringLiteral("buttonBitPositions")},
                               path + QStringLiteral(".source"));
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
            const QString encoding =
                requiredString(source, QStringLiteral("encoding"),
                               path + QStringLiteral(".source.encoding"));
            static const QSet<QString> allowedEncodings{
                QStringLiteral("unsigned"),
                QStringLiteral("signed"),
                QStringLiteral("boolean"),
                QStringLiteral("raw_16bit"),
                QStringLiteral("j1939_axis_status"),
                QStringLiteral("j1939_2bit"),
                QStringLiteral("canopen_1bit"),
                QStringLiteral("gessmann_8bit"),
                QStringLiteral("gessmann_2bit"),
                QStringLiteral("signed_percent"),
                QStringLiteral("crc8_atm"),
                QStringLiteral("detent_2bit"),
                QStringLiteral("counter"),
                QStringLiteral("selfCheck"),
                QStringLiteral("identity")
            };
            if (!encoding.isEmpty() && !allowedEncodings.contains(encoding)) {
                addError(path + QStringLiteral(".source.encoding is unsupported"));
            }
            QJsonArray buttonBitPositions;
            if (source.contains(QStringLiteral("buttonBitPositions"))) {
                const QString positionsPath =
                    path + QStringLiteral(".source.buttonBitPositions");
                const QJsonValue positionsValue =
                    source.value(QStringLiteral("buttonBitPositions"));
                if (!positionsValue.isArray()) {
                    addError(positionsPath + QStringLiteral(" must be an array"));
                } else {
                    buttonBitPositions = positionsValue.toArray();
                    if (buttonBitPositions.isEmpty()) {
                        addError(positionsPath + QStringLiteral(" must not be empty"));
                    }
                    QSet<int> uniquePositions;
                    for (qsizetype positionIndex = 0;
                         positionIndex < buttonBitPositions.size();
                         ++positionIndex) {
                        const QJsonValue positionValue =
                            buttonBitPositions.at(positionIndex);
                        const QString positionPath =
                            QStringLiteral("%1[%2]").arg(positionsPath).arg(positionIndex);
                        if (!positionValue.isDouble()
                            || positionValue.toDouble() != positionValue.toInt()) {
                            addError(positionPath + QStringLiteral(" must be an integer"));
                            continue;
                        }
                        const int position = positionValue.toInt();
                        if (position < 0 || position > 63) {
                            addError(positionPath + QStringLiteral(" must be in range 0..63"));
                            continue;
                        }
                        if (uniquePositions.contains(position)) {
                            addError(positionsPath + QStringLiteral(" values must be unique"));
                            continue;
                        }
                        uniquePositions.insert(position);
                    }
                }
            }
            if (startByte < 0 || startBit < 0 || startBit > 7 || bitLength <= 0) {
                addError(path + QStringLiteral(
                    ".source bit range requires startByte >= 0, startBit 0..7, bitLength > 0"));
                continue;
            }

            if (!id.isEmpty()) {
                m_signalKinds.insert(id, kind);
                m_signalBitLengths.insert(id, bitLength);
                m_signalEncodings.insert(id, encoding);
            }
            if (kind == QStringLiteral("packedButtons")) {
                const int bitsPerPosition = packedBitsPerPosition(encoding);
                if (bitsPerPosition <= 0 || bitLength % bitsPerPosition != 0) {
                    addError(path + QStringLiteral(
                        " packedButtons bitLength must align with its packed encoding"));
                } else {
                    for (qsizetype positionIndex = 0;
                         positionIndex < buttonBitPositions.size();
                         ++positionIndex) {
                        const QJsonValue positionValue =
                            buttonBitPositions.at(positionIndex);
                        if (!positionValue.isDouble()
                            || positionValue.toDouble() != positionValue.toInt()) {
                            continue;
                        }
                        if (positionValue.toInt() + bitsPerPosition > bitLength) {
                            addError(
                                QStringLiteral("%1.source.buttonBitPositions[%2] "
                                               "exceeds bitLength")
                                    .arg(path)
                                    .arg(positionIndex));
                        }
                    }
                    if (!id.isEmpty()) {
                        m_signalLogicalPositionCounts.insert(
                            id,
                            buttonBitPositions.isEmpty()
                                ? bitLength / bitsPerPosition
                                : buttonBitPositions.size());
                    }
                }
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
            rejectUnknownKeys(command,
                              {QStringLiteral("id"),
                               QStringLiteral("label"),
                               QStringLiteral("transport"),
                               QStringLiteral("frame")},
                              path);
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
            if (transport == QStringLiteral("j1939")) {
                rejectUnknownKeys(frame,
                                  {QStringLiteral("priority"),
                                   QStringLiteral("pgn"),
                                   QStringLiteral("sourceAddress"),
                                   QStringLiteral("destinationAddress"),
                                   QStringLiteral("dlc"),
                                   QStringLiteral("data")},
                                  path + QStringLiteral(".frame"));
            } else {
                rejectUnknownKeys(frame,
                                  {QStringLiteral("canId"),
                                   QStringLiteral("dlc"),
                                   QStringLiteral("data")},
                                  path + QStringLiteral(".frame"));
            }
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
        rejectUnknownKeys(binding,
                          {QStringLiteral("signalId"),
                           QStringLiteral("statusSignalId"),
                           QStringLiteral("transform")},
                          path);
        const QString signalId =
            requiredString(binding, QStringLiteral("signalId"), path + QStringLiteral(".signalId"));
        if (!signalId.isEmpty() && !signalIds.contains(signalId)) {
            addError(path + QStringLiteral(".signalId references missing signal"));
        }
        if (binding.contains(QStringLiteral("statusSignalId"))) {
            const QString statusSignalId =
                requiredString(binding,
                               QStringLiteral("statusSignalId"),
                               path + QStringLiteral(".statusSignalId"));
            if (!statusSignalId.isEmpty() && !signalIds.contains(statusSignalId)) {
                addError(path + QStringLiteral(
                    ".statusSignalId references missing signal"));
            } else if (!statusSignalId.isEmpty()
                       && m_signalKinds.value(statusSignalId)
                           != QStringLiteral("status")) {
                addError(path + QStringLiteral(
                    ".statusSignalId must reference a status signal"));
            }
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
        if (rawMinValid && rawCenterValid && rawMaxValid) {
            const bool statusMagnitude =
                binding.contains(QStringLiteral("statusSignalId"))
                && control.value(QStringLiteral("role")).toString()
                       != QStringLiteral("potentiometer")
                && control.value(QStringLiteral("inputMode")).toString()
                       != QStringLiteral("unipolar");
            if (statusMagnitude
                && !(rawMin == rawCenter && rawCenter < rawMax)) {
                addError(path + QStringLiteral(
                    ".transform for status+magnitude input must satisfy "
                    "rawMin == rawCenter < rawMax"));
            } else if (!statusMagnitude
                       && !(rawMin < rawCenter && rawCenter < rawMax)) {
                addError(path + QStringLiteral(
                    ".transform must satisfy rawMin < rawCenter < rawMax"));
            }
        }
        if (deadzoneValid && deadzone < 0.0) {
            addError(path + QStringLiteral(".transform.deadzone must be non-negative"));
        }
    }

    void validateBindingChannels(const QJsonObject &config,
                                 const QSet<QString> &signalIds)
    {
        if (!config.contains(QStringLiteral("bindingChannels")))
            return;
        const QJsonArray channels =
            requiredArray(config,
                          QStringLiteral("bindingChannels"),
                          QStringLiteral("bindingChannels"),
                          true);
        QSet<QString> ids;
        QSet<QString> buttonSources;
        QSet<QString> axisSignals;
        for (qsizetype index = 0; index < channels.size(); ++index) {
            if (!channels.at(index).isObject()) {
                addError(QStringLiteral("bindingChannels[%1] must be an object")
                             .arg(index));
                continue;
            }
            const QJsonObject channel = channels.at(index).toObject();
            const QString path =
                QStringLiteral("bindingChannels[%1]").arg(index);
            const QString id =
                requiredString(channel,
                               QStringLiteral("id"),
                               path + QStringLiteral(".id"));
            if (!id.isEmpty()) {
                if (ids.contains(id))
                    addError(path + QStringLiteral(".id is duplicated"));
                ids.insert(id);
            }
            const QString kind =
                requiredString(channel,
                               QStringLiteral("kind"),
                               path + QStringLiteral(".kind"));
            if (kind == QStringLiteral("button")) {
                rejectUnknownKeys(channel,
                                  {QStringLiteral("id"),
                                   QStringLiteral("kind"),
                                   QStringLiteral("label"),
                                   QStringLiteral("signalId"),
                                   QStringLiteral("position")},
                                  path);
                requiredString(channel,
                               QStringLiteral("label"),
                               path + QStringLiteral(".label"));
                const QString signalId =
                    requiredString(channel,
                                   QStringLiteral("signalId"),
                                   path + QStringLiteral(".signalId"));
                const int position =
                    requiredInteger(channel,
                                    QStringLiteral("position"),
                                    path + QStringLiteral(".position"));
                if (validateSignalReference(signalId,
                                             path + QStringLiteral(".signalId"),
                                             signalIds)
                    && validatePackedPosition(signalId,
                                              position,
                                              path + QStringLiteral(".position"))) {
                    const QString sourceKey =
                        QStringLiteral("%1:%2").arg(signalId).arg(position);
                    if (buttonSources.contains(sourceKey)) {
                        addError(path + QStringLiteral(
                            " duplicates a physical button signal position"));
                    }
                    buttonSources.insert(sourceKey);
                    continue;
                }
            } else if (kind == QStringLiteral("axis")) {
                rejectUnknownKeys(channel,
                                  {QStringLiteral("id"),
                                   QStringLiteral("kind"),
                                    QStringLiteral("role"),
                                    QStringLiteral("inputMode"),
                                    QStringLiteral("zeroAsNeutral"),
                                    QStringLiteral("display"),
                                    QStringLiteral("label"),
                                   QStringLiteral("topology"),
                                   QStringLiteral("axis")},
                                  path);
                const QString role =
                    requiredString(channel,
                                   QStringLiteral("role"),
                                   path + QStringLiteral(".role"));
                if (role != QStringLiteral("roller")
                    && role != QStringLiteral("potentiometer")
                    && role != QStringLiteral("auxiliary")) {
                    addError(path + QStringLiteral(".role is unsupported"));
                }
                const QString inputMode =
                    requiredString(channel,
                                   QStringLiteral("inputMode"),
                                   path + QStringLiteral(".inputMode"));
                if (inputMode != QStringLiteral("centered")
                    && inputMode != QStringLiteral("signed")
                    && inputMode != QStringLiteral("unipolar")) {
                    addError(path + QStringLiteral(".inputMode is unsupported"));
                }
                if (channel.contains(QStringLiteral("zeroAsNeutral"))
                    && !channel.value(QStringLiteral("zeroAsNeutral")).isBool()) {
                    addError(path + QStringLiteral(".zeroAsNeutral must be boolean"));
                }
                if (role == QStringLiteral("potentiometer")
                    || channel.contains(QStringLiteral("display"))) {
                    const QJsonObject display =
                        requiredObject(channel,
                                       QStringLiteral("display"),
                                       path + QStringLiteral(".display"));
                    rejectUnknownKeys(display,
                                      {QStringLiteral("valueMin"),
                                       QStringLiteral("valueMax"),
                                       QStringLiteral("angleMinDegrees"),
                                       QStringLiteral("angleMaxDegrees"),
                                       QStringLiteral("unit")},
                                      path + QStringLiteral(".display"));
                    bool valueMinValid = false;
                    bool valueMaxValid = false;
                    bool angleMinValid = false;
                    bool angleMaxValid = false;
                    const double valueMin =
                        requiredNumber(display,
                                       QStringLiteral("valueMin"),
                                       path + QStringLiteral(".display.valueMin"),
                                       &valueMinValid);
                    const double valueMax =
                        requiredNumber(display,
                                       QStringLiteral("valueMax"),
                                       path + QStringLiteral(".display.valueMax"),
                                       &valueMaxValid);
                    const double angleMin =
                        requiredNumber(display,
                                       QStringLiteral("angleMinDegrees"),
                                       path + QStringLiteral(".display.angleMinDegrees"),
                                       &angleMinValid);
                    const double angleMax =
                        requiredNumber(display,
                                       QStringLiteral("angleMaxDegrees"),
                                       path + QStringLiteral(".display.angleMaxDegrees"),
                                       &angleMaxValid);
                    requiredString(display,
                                   QStringLiteral("unit"),
                                   path + QStringLiteral(".display.unit"));
                    if (valueMinValid && valueMaxValid && !(valueMin < valueMax)) {
                        addError(path + QStringLiteral(
                            ".display must satisfy valueMin < valueMax"));
                    }
                    if (angleMinValid && angleMaxValid && !(angleMin < angleMax)) {
                        addError(path + QStringLiteral(
                            ".display must satisfy angleMinDegrees < angleMaxDegrees"));
                    }
                }
                requiredString(channel,
                               QStringLiteral("label"),
                               path + QStringLiteral(".label"));
                const QJsonObject topology =
                    requiredObject(channel,
                                   QStringLiteral("topology"),
                                   path + QStringLiteral(".topology"));
                rejectUnknownKeys(topology,
                                  {QStringLiteral("kind"),
                                   QStringLiteral("orientation")},
                                  path + QStringLiteral(".topology"));
                if (topology.value(QStringLiteral("kind")).toString()
                    != QStringLiteral("singleAxis")) {
                    addError(path
                             + QStringLiteral(".topology.kind must be singleAxis"));
                }
                const QString orientation =
                    topology.value(QStringLiteral("orientation")).toString();
                if (orientation != QStringLiteral("horizontal")
                    && orientation != QStringLiteral("vertical")) {
                    addError(path
                             + QStringLiteral(
                                 ".topology.orientation must be horizontal or vertical"));
                }
                validateAxisBinding(channel,
                                    QStringLiteral("axis"),
                                    path + QStringLiteral(".axis"),
                                    signalIds);
                const QString axisSignalId =
                    channel.value(QStringLiteral("axis"))
                        .toObject()
                        .value(QStringLiteral("signalId"))
                        .toString();
                if (!axisSignalId.isEmpty()) {
                    if (axisSignals.contains(axisSignalId)) {
                        addError(path + QStringLiteral(
                            " duplicates a physical axis signal"));
                    }
                    axisSignals.insert(axisSignalId);
                }
            } else {
                addError(path + QStringLiteral(".kind must be button or axis"));
            }
        }
    }

    void validateBindingChannelCoverage(const QJsonObject &config)
    {
        if (!config.contains(QStringLiteral("bindingChannels")))
            return;

        QSet<QString> buttonSources;
        QSet<QString> axisSignals;
        const QJsonArray channels =
            config.value(QStringLiteral("bindingChannels")).toArray();
        for (const QJsonValue &value : channels) {
            const QJsonObject channel = value.toObject();
            if (channel.value(QStringLiteral("kind")).toString()
                == QStringLiteral("button")) {
                buttonSources.insert(
                    QStringLiteral("%1:%2")
                        .arg(channel.value(QStringLiteral("signalId")).toString())
                        .arg(channel.value(QStringLiteral("position")).toInt(-1)));
            } else if (channel.value(QStringLiteral("kind")).toString()
                       == QStringLiteral("axis")) {
                axisSignals.insert(
                    channel.value(QStringLiteral("axis"))
                        .toObject()
                        .value(QStringLiteral("signalId"))
                        .toString());
            }
        }

        const auto requireButtonChannel =
            [this, &buttonSources](const QString &signalId,
                                   int position,
                                   const QString &path) {
                const QString sourceKey =
                    QStringLiteral("%1:%2").arg(signalId).arg(position);
                if (!buttonSources.contains(sourceKey)) {
                    addError(path + QStringLiteral(
                        " has no matching physical button channel"));
                }
            };
        const auto requireAxisChannel =
            [this, &axisSignals](const QString &signalId,
                                 const QString &path) {
                if (!signalId.isEmpty() && !axisSignals.contains(signalId)) {
                    addError(path + QStringLiteral(
                        " has no matching physical axis channel"));
                }
            };

        const QJsonArray controls = config.value(QStringLiteral("controls")).toArray();
        for (qsizetype index = 0; index < controls.size(); ++index) {
            const QJsonObject control = controls.at(index).toObject();
            const QString path = QStringLiteral("controls[%1]").arg(index);
            const QString type = control.value(QStringLiteral("type")).toString();
            if (type == QStringLiteral("button")) {
                requireButtonChannel(
                    control.value(QStringLiteral("signalId")).toString(),
                    control.value(QStringLiteral("position")).toInt(-1),
                    path);
            } else if (type == QStringLiteral("fnr")) {
                const QString signalId =
                    control.value(QStringLiteral("signalId")).toString();
                const QJsonObject positions =
                    control.value(QStringLiteral("positions")).toObject();
                requireButtonChannel(signalId,
                                     positions.value(QStringLiteral("forward"))
                                         .toInt(-1),
                                     path + QStringLiteral(".positions.forward"));
                requireButtonChannel(signalId,
                                     positions.value(QStringLiteral("reverse"))
                                         .toInt(-1),
                                     path + QStringLiteral(".positions.reverse"));
                if (positions.value(QStringLiteral("neutralMode")).toString()
                    == QStringLiteral("signal")) {
                    requireButtonChannel(signalId,
                                         positions.value(QStringLiteral("neutral"))
                                             .toInt(-1),
                                         path + QStringLiteral(".positions.neutral"));
                }
            } else if (type == QStringLiteral("axis")) {
                const QString role =
                    control.value(QStringLiteral("role")).toString();
                if (role == QStringLiteral("roller")
                    || role == QStringLiteral("potentiometer")
                    || role == QStringLiteral("auxiliary")) {
                    requireAxisChannel(
                        control.value(QStringLiteral("axis"))
                            .toObject()
                            .value(QStringLiteral("signalId"))
                            .toString(),
                        path + QStringLiteral(".axis"));
                }
            } else if (type == QStringLiteral("joystick")) {
                const QString xSignal =
                    control.value(QStringLiteral("xAxis"))
                        .toObject()
                        .value(QStringLiteral("signalId"))
                        .toString();
                const QString ySignal =
                    control.value(QStringLiteral("yAxis"))
                        .toObject()
                        .value(QStringLiteral("signalId"))
                        .toString();
                if (axisSignals.contains(xSignal) || axisSignals.contains(ySignal)) {
                    requireAxisChannel(xSignal, path + QStringLiteral(".xAxis"));
                    requireAxisChannel(ySignal, path + QStringLiteral(".yAxis"));
                }
            }
        }
    }

    QSet<QString> validateControls(const QJsonObject &config,
                                   const QSet<QString> &signalIds,
                                   const QSet<QString> &commandIds)
    {
        const QJsonArray controls =
            requiredArray(config, QStringLiteral("controls"), QStringLiteral("controls"), false);
        QSet<QString> ids;
        QHash<QString, QHash<int, QString>> packedPositionOwners;
        QHash<QString, QString> analogSignalOwners;
        const auto claimPackedPosition =
            [this, &packedPositionOwners](const QString &signalId,
                                          int position,
                                          const QString &path) {
                const QString previousOwner =
                    packedPositionOwners.value(signalId).value(position);
                if (!previousOwner.isEmpty()) {
                    addError(path
                             + QStringLiteral(
                                 " is assigned more than once; first assigned by %1")
                                   .arg(previousOwner));
                    return;
                }
                packedPositionOwners[signalId].insert(position, path);
            };
        const auto claimAnalogSignal =
            [this, &analogSignalOwners](const QString &signalId,
                                        const QString &path) {
                if (signalId.isEmpty())
                    return;
                const QString previousOwner = analogSignalOwners.value(signalId);
                if (!previousOwner.isEmpty()) {
                    addError(path
                             + QStringLiteral(
                                 " is assigned more than once; first assigned by %1")
                                   .arg(previousOwner));
                    return;
                }
                analogSignalOwners.insert(signalId, path);
            };
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
                rejectUnknownKeys(control,
                                  {QStringLiteral("id"),
                                   QStringLiteral("type"),
                                   QStringLiteral("role"),
                                   QStringLiteral("inputMode"),
                                   QStringLiteral("zeroAsNeutral"),
                                   QStringLiteral("display"),
                                   QStringLiteral("label"),
                                   QStringLiteral("topology"),
                                   QStringLiteral("axis")},
                                  path);
                const QString role =
                    requiredString(control, QStringLiteral("role"), path + QStringLiteral(".role"));
                if (role != QStringLiteral("joystick")
                    && role != QStringLiteral("roller")
                    && role != QStringLiteral("potentiometer")
                    && role != QStringLiteral("auxiliary")) {
                    addError(path + QStringLiteral(".role is unsupported"));
                }
                const QString inputMode =
                    requiredString(control, QStringLiteral("inputMode"),
                                   path + QStringLiteral(".inputMode"));
                if (inputMode != QStringLiteral("centered")
                    && inputMode != QStringLiteral("signed")
                    && inputMode != QStringLiteral("unipolar")) {
                    addError(path + QStringLiteral(".inputMode is unsupported"));
                }
                if (control.contains(QStringLiteral("zeroAsNeutral"))
                    && !control.value(QStringLiteral("zeroAsNeutral")).isBool()) {
                    addError(path + QStringLiteral(".zeroAsNeutral must be boolean"));
                }
                if (role == QStringLiteral("potentiometer")
                    || control.contains(QStringLiteral("display"))) {
                    const QJsonObject display =
                        requiredObject(control, QStringLiteral("display"),
                                       path + QStringLiteral(".display"));
                    rejectUnknownKeys(display,
                                      {QStringLiteral("valueMin"),
                                       QStringLiteral("valueMax"),
                                       QStringLiteral("angleMinDegrees"),
                                       QStringLiteral("angleMaxDegrees"),
                                       QStringLiteral("unit")},
                                      path + QStringLiteral(".display"));
                    bool valueMinValid = false;
                    bool valueMaxValid = false;
                    bool angleMinValid = false;
                    bool angleMaxValid = false;
                    const double valueMin =
                        requiredNumber(display, QStringLiteral("valueMin"),
                                       path + QStringLiteral(".display.valueMin"),
                                       &valueMinValid);
                    const double valueMax =
                        requiredNumber(display, QStringLiteral("valueMax"),
                                       path + QStringLiteral(".display.valueMax"),
                                       &valueMaxValid);
                    const double angleMin =
                        requiredNumber(display, QStringLiteral("angleMinDegrees"),
                                       path + QStringLiteral(".display.angleMinDegrees"),
                                       &angleMinValid);
                    const double angleMax =
                        requiredNumber(display, QStringLiteral("angleMaxDegrees"),
                                       path + QStringLiteral(".display.angleMaxDegrees"),
                                       &angleMaxValid);
                    requiredString(display, QStringLiteral("unit"),
                                   path + QStringLiteral(".display.unit"));
                    if (valueMinValid && valueMaxValid && !(valueMin < valueMax)) {
                        addError(path + QStringLiteral(
                            ".display must satisfy valueMin < valueMax"));
                    }
                    if (angleMinValid && angleMaxValid && !(angleMin < angleMax)) {
                        addError(path + QStringLiteral(
                            ".display must satisfy angleMinDegrees < angleMaxDegrees"));
                    }
                }
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
                const QString axisSignalId =
                    control.value(QStringLiteral("axis"))
                        .toObject()
                        .value(QStringLiteral("signalId"))
                        .toString();
                if (signalIds.contains(axisSignalId)) {
                    claimAnalogSignal(axisSignalId,
                                      path + QStringLiteral(".axis.signalId"));
                }
            } else if (type == QStringLiteral("joystick")) {
                rejectUnknownKeys(control,
                                  {QStringLiteral("id"),
                                   QStringLiteral("type"),
                                   QStringLiteral("label"),
                                   QStringLiteral("testPattern"),
                                   QStringLiteral("cycleCount"),
                                   QStringLiteral("topology"),
                                   QStringLiteral("xAxis"),
                                   QStringLiteral("yAxis")},
                                  path);
                const QJsonObject topology =
                    requiredObject(control, QStringLiteral("topology"),
                                   path + QStringLiteral(".topology"));
                const QString topologyKind =
                    topology.value(QStringLiteral("kind")).toString();
                const QString topologyGate =
                    topology.value(QStringLiteral("gate")).toString();
                if (topologyKind == QStringLiteral("cross2D")) {
                    if (topologyGate != QStringLiteral("cross")) {
                        addError(path + QStringLiteral(
                            ".topology.gate for cross2D must be cross"));
                    }
                } else if (topologyKind == QStringLiteral("xy2D")) {
                    if (topologyGate != QStringLiteral("omnidirectional")) {
                        addError(path + QStringLiteral(
                            ".topology.gate for xy2D must be omnidirectional"));
                    }
                } else {
                    addError(path + QStringLiteral(
                        ".topology.kind must be cross2D or xy2D"));
                }
                if (control.contains(QStringLiteral("testPattern"))) {
                    const QString testPattern =
                        control.value(QStringLiteral("testPattern")).toString();
                    if (testPattern != QStringLiteral("ninePoint")
                        && testPattern != QStringLiteral("cross")) {
                        addError(path
                                 + QStringLiteral(
                                     ".testPattern must be ninePoint or cross"));
                    }
                }
                if (control.contains(QStringLiteral("cycleCount"))) {
                    const int cycleCount =
                        requiredInteger(control,
                                        QStringLiteral("cycleCount"),
                                        path + QStringLiteral(".cycleCount"));
                    if (cycleCount < 1 || cycleCount > 10) {
                        addError(path
                                 + QStringLiteral(
                                     ".cycleCount must be from 1 to 10"));
                    }
                }
                validateAxisBinding(control,
                                    QStringLiteral("xAxis"),
                                    path + QStringLiteral(".xAxis"),
                                    signalIds);
                validateAxisBinding(control,
                                    QStringLiteral("yAxis"),
                                    path + QStringLiteral(".yAxis"),
                                    signalIds);
                const QString xSignalId =
                    control.value(QStringLiteral("xAxis"))
                        .toObject()
                        .value(QStringLiteral("signalId"))
                        .toString();
                const QString ySignalId =
                    control.value(QStringLiteral("yAxis"))
                        .toObject()
                        .value(QStringLiteral("signalId"))
                        .toString();
                if (signalIds.contains(xSignalId)) {
                    claimAnalogSignal(xSignalId,
                                      path + QStringLiteral(".xAxis.signalId"));
                }
                if (signalIds.contains(ySignalId)) {
                    claimAnalogSignal(ySignalId,
                                      path + QStringLiteral(".yAxis.signalId"));
                }
            } else if (type == QStringLiteral("button")) {
                rejectUnknownKeys(control,
                                  {QStringLiteral("id"),
                                   QStringLiteral("type"),
                                   QStringLiteral("label"),
                                   QStringLiteral("signalId"),
                                   QStringLiteral("position")},
                                  path);
                const QString signalId =
                    requiredString(control, QStringLiteral("signalId"),
                                   path + QStringLiteral(".signalId"));
                const int position =
                    requiredInteger(control, QStringLiteral("position"),
                                    path + QStringLiteral(".position"));
                if (validateSignalReference(signalId,
                                            path + QStringLiteral(".signalId"),
                                            signalIds)
                    && validatePackedPosition(signalId,
                                              position,
                                              path + QStringLiteral(".position"))) {
                    claimPackedPosition(signalId,
                                        position,
                                        path + QStringLiteral(".position"));
                }
            } else if (type == QStringLiteral("fnr")) {
                rejectUnknownKeys(control,
                                  {QStringLiteral("id"),
                                   QStringLiteral("type"),
                                   QStringLiteral("label"),
                                   QStringLiteral("signalId"),
                                   QStringLiteral("positions")},
                                  path);
                const QString signalId =
                    requiredString(control, QStringLiteral("signalId"),
                                   path + QStringLiteral(".signalId"));
                const bool hasSignal =
                    validateSignalReference(signalId,
                                            path + QStringLiteral(".signalId"),
                                            signalIds);
                if (hasSignal
                    && m_signalKinds.value(signalId) != QStringLiteral("packedButtons")) {
                    addError(path + QStringLiteral(
                        ".signalId for FNR must reference packedButtons"));
                }
                const QJsonObject positions =
                    requiredObject(control, QStringLiteral("positions"),
                                   path + QStringLiteral(".positions"));
                const QString neutralMode =
                    requiredString(positions, QStringLiteral("neutralMode"),
                                   path + QStringLiteral(".positions.neutralMode"));
                QSet<QString> allowedPositionKeys{
                    QStringLiteral("neutralMode"),
                    QStringLiteral("forward"),
                    QStringLiteral("reverse")
                };
                if (neutralMode == QStringLiteral("signal")) {
                    allowedPositionKeys.insert(QStringLiteral("neutral"));
                } else if (neutralMode != QStringLiteral("inferred")) {
                    addError(path + QStringLiteral(
                        ".positions.neutralMode must be signal or inferred"));
                }
                rejectUnknownKeys(positions,
                                  allowedPositionKeys,
                                  path + QStringLiteral(".positions"));
                const int forward =
                    requiredInteger(positions, QStringLiteral("forward"),
                                    path + QStringLiteral(".positions.forward"));
                const int reverse =
                    requiredInteger(positions, QStringLiteral("reverse"),
                                    path + QStringLiteral(".positions.reverse"));
                int neutral = -1;
                if (neutralMode == QStringLiteral("signal")) {
                    neutral =
                        requiredInteger(positions, QStringLiteral("neutral"),
                                        path + QStringLiteral(".positions.neutral"));
                }
                if (forward == reverse
                    || (neutral >= 0 && (neutral == forward || neutral == reverse))) {
                    addError(path + QStringLiteral(
                        ".positions forward/neutral/reverse must be distinct"));
                }
                if (hasSignal) {
                    if (validatePackedPosition(signalId,
                                               forward,
                                               path + QStringLiteral(".positions.forward"))) {
                        claimPackedPosition(signalId,
                                            forward,
                                            path + QStringLiteral(".positions.forward"));
                    }
                    if (validatePackedPosition(signalId,
                                               reverse,
                                               path + QStringLiteral(".positions.reverse"))) {
                        claimPackedPosition(signalId,
                                            reverse,
                                            path + QStringLiteral(".positions.reverse"));
                    }
                    if (neutral >= 0) {
                        if (validatePackedPosition(signalId,
                                                   neutral,
                                                   path + QStringLiteral(".positions.neutral"))) {
                            claimPackedPosition(signalId,
                                                neutral,
                                                path + QStringLiteral(".positions.neutral"));
                        }
                    }
                }
            } else if (type == QStringLiteral("numericDisplay")) {
                rejectUnknownKeys(control,
                                  {QStringLiteral("id"),
                                   QStringLiteral("type"),
                                   QStringLiteral("label"),
                                   QStringLiteral("signalId"),
                                   QStringLiteral("format")},
                                  path);
                const QString signalId =
                    requiredString(control, QStringLiteral("signalId"),
                                   path + QStringLiteral(".signalId"));
                validateSignalReference(signalId,
                                        path + QStringLiteral(".signalId"),
                                        signalIds);
                const QJsonObject format =
                    requiredObject(control, QStringLiteral("format"),
                                   path + QStringLiteral(".format"));
                rejectUnknownKeys(format,
                                  {QStringLiteral("decimals"),
                                   QStringLiteral("unit"),
                                   QStringLiteral("prefix"),
                                   QStringLiteral("suffix")},
                                  path + QStringLiteral(".format"));
                const int decimals =
                    requiredInteger(format, QStringLiteral("decimals"),
                                    path + QStringLiteral(".format.decimals"));
                if (decimals < 0 || decimals > 6) {
                    addError(path + QStringLiteral(".format.decimals must be 0..6"));
                }
            } else if (type == QStringLiteral("indicator")) {
                rejectUnknownKeys(control,
                                  {QStringLiteral("id"),
                                   QStringLiteral("type"),
                                   QStringLiteral("label"),
                                   QStringLiteral("signalId"),
                                   QStringLiteral("states")},
                                  path);
                const QString signalId =
                    requiredString(control, QStringLiteral("signalId"),
                                   path + QStringLiteral(".signalId"));
                validateSignalReference(signalId,
                                        path + QStringLiteral(".signalId"),
                                        signalIds);
                const QJsonArray states =
                    requiredArray(control, QStringLiteral("states"),
                                  path + QStringLiteral(".states"), false);
                for (qsizetype stateIndex = 0; stateIndex < states.size(); ++stateIndex) {
                    const QString statePath =
                        path + QStringLiteral(".states[%1]").arg(stateIndex);
                    if (!states.at(stateIndex).isObject()) {
                        addError(statePath + QStringLiteral(" must be an object"));
                        continue;
                    }
                    const QJsonObject state = states.at(stateIndex).toObject();
                    rejectUnknownKeys(state,
                                      {QStringLiteral("value"),
                                       QStringLiteral("label"),
                                       QStringLiteral("color")},
                                      statePath);
                    const QJsonValue value = state.value(QStringLiteral("value"));
                    if (!value.isBool() && !value.isDouble() && !value.isString()) {
                        addError(statePath + QStringLiteral(
                            ".value must be boolean, number, or string"));
                    }
                    requiredString(state, QStringLiteral("label"),
                                   statePath + QStringLiteral(".label"));
                    const QString color =
                        requiredString(state, QStringLiteral("color"),
                                       statePath + QStringLiteral(".color"));
                    static const QRegularExpression colorPattern(
                        QStringLiteral("^#[0-9A-F]{6}$"));
                    if (!color.isEmpty() && !colorPattern.match(color).hasMatch()) {
                        addError(statePath + QStringLiteral(
                            ".color must be uppercase #RRGGBB"));
                    }
                }
            } else if (type == QStringLiteral("binaryOutput")) {
                rejectUnknownKeys(control,
                                  {QStringLiteral("id"),
                                   QStringLiteral("type"),
                                   QStringLiteral("label"),
                                   QStringLiteral("onCommandId"),
                                   QStringLiteral("offCommandId"),
                                   QStringLiteral("activeLow")},
                                  path);
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
        rejectUnknownKeys(layout,
                          {QStringLiteral("mode"),
                           QStringLiteral("canvas"),
                           QStringLiteral("grid"),
                           QStringLiteral("cards")},
                          QStringLiteral("layout"));
        if (layout.value(QStringLiteral("mode")).toString() != QStringLiteral("designed")) {
            addError(QStringLiteral("layout.mode must be designed"));
        }
        const QJsonObject canvas =
            requiredObject(layout, QStringLiteral("canvas"), QStringLiteral("layout.canvas"));
        rejectUnknownKeys(canvas,
                          {QStringLiteral("width"), QStringLiteral("height")},
                          QStringLiteral("layout.canvas"));
        const int canvasWidth =
            requiredInteger(canvas, QStringLiteral("width"), QStringLiteral("layout.canvas.width"));
        const int canvasHeight =
            requiredInteger(canvas, QStringLiteral("height"), QStringLiteral("layout.canvas.height"));
        if (canvasWidth <= 0 || canvasHeight <= 0) {
            addError(QStringLiteral("layout.canvas width/height must be positive"));
        }
        const QJsonObject layoutGrid =
            requiredObject(layout, QStringLiteral("grid"), QStringLiteral("layout.grid"));
        rejectUnknownKeys(layoutGrid,
                          {QStringLiteral("rows"), QStringLiteral("columns")},
                          QStringLiteral("layout.grid"));
        const int gridRows =
            requiredInteger(layoutGrid, QStringLiteral("rows"), QStringLiteral("layout.grid.rows"));
        const int gridColumns =
            requiredInteger(layoutGrid, QStringLiteral("columns"),
                            QStringLiteral("layout.grid.columns"));
        if (gridRows <= 0 || gridColumns <= 0) {
            addError(QStringLiteral("layout.grid rows/columns must be positive"));
        }

        const QJsonArray cards =
            requiredArray(layout, QStringLiteral("cards"), QStringLiteral("layout.cards"), false);
        QSet<QString> cardIds;
        QSet<QString> elementIds;
        for (qsizetype index = 0; index < cards.size(); ++index) {
            if (!cards.at(index).isObject()) {
                addError(QStringLiteral("layout.cards[%1] must be an object").arg(index));
                continue;
            }
            const QJsonObject card = cards.at(index).toObject();
            const QString path = QStringLiteral("layout.cards[%1]").arg(index);
            const QString kind =
                requiredString(card, QStringLiteral("kind"), path + QStringLiteral(".kind"));
            if (kind == QStringLiteral("controls")) {
                rejectUnknownKeys(card,
                                  {QStringLiteral("id"),
                                   QStringLiteral("kind"),
                                   QStringLiteral("title"),
                                   QStringLiteral("grid"),
                                   QStringLiteral("contentCanvas"),
                                   QStringLiteral("elements")},
                                  path);
            } else if (kind == QStringLiteral("system")) {
                rejectUnknownKeys(card,
                                  {QStringLiteral("id"),
                                   QStringLiteral("kind"),
                                   QStringLiteral("title"),
                                   QStringLiteral("grid"),
                                   QStringLiteral("systemType"),
                                   QStringLiteral("properties")},
                                  path + QStringLiteral(" system card"));
            } else if (kind == QStringLiteral("empty")) {
                rejectUnknownKeys(card,
                                  {QStringLiteral("id"),
                                   QStringLiteral("kind"),
                                   QStringLiteral("title"),
                                   QStringLiteral("grid")},
                                  path + QStringLiteral(" empty card"));
            } else if (kind == QStringLiteral("leftRegion")) {
                rejectUnknownKeys(card,
                                  {QStringLiteral("id"),
                                   QStringLiteral("kind"),
                                   QStringLiteral("title"),
                                   QStringLiteral("grid"),
                                   QStringLiteral("controlId"),
                                   QStringLiteral("widthRatio")},
                                  path + QStringLiteral(" left-region card"));
            } else {
                addError(path + QStringLiteral(
                    ".kind must be controls, system, empty, or leftRegion"));
            }
            const QString id =
                requiredString(card, QStringLiteral("id"), path + QStringLiteral(".id"));
            if (!id.isEmpty()) {
                if (cardIds.contains(id)) {
                    addError(path + QStringLiteral(".id is duplicated"));
                }
                cardIds.insert(id);
            }
            if (kind == QStringLiteral("controls") || kind == QStringLiteral("system")) {
                requiredString(card, QStringLiteral("title"), path + QStringLiteral(".title"));
            } else if (!card.value(QStringLiteral("title")).isString()) {
                addError(path + QStringLiteral(".title must be a string"));
            }

            const QJsonObject cardGrid =
                requiredObject(card, QStringLiteral("grid"), path + QStringLiteral(".grid"));
            rejectUnknownKeys(cardGrid,
                              {QStringLiteral("row"),
                               QStringLiteral("column"),
                               QStringLiteral("rowSpan"),
                               QStringLiteral("columnSpan")},
                              path + QStringLiteral(".grid"));
            const int row =
                requiredInteger(cardGrid, QStringLiteral("row"),
                                path + QStringLiteral(".grid.row"));
            const int column =
                requiredInteger(cardGrid, QStringLiteral("column"),
                                path + QStringLiteral(".grid.column"));
            const int rowSpan =
                requiredInteger(cardGrid, QStringLiteral("rowSpan"),
                                path + QStringLiteral(".grid.rowSpan"));
            const int columnSpan =
                requiredInteger(cardGrid, QStringLiteral("columnSpan"),
                                path + QStringLiteral(".grid.columnSpan"));
            if (row < 0 || column < 0) {
                addError(path + QStringLiteral(".grid row/column must be non-negative"));
            }
            if (rowSpan <= 0 || columnSpan <= 0) {
                addError(path + QStringLiteral(".grid spans must be positive"));
            }
            if (gridRows > 0 && gridColumns > 0
                && row >= 0 && column >= 0 && rowSpan > 0 && columnSpan > 0
                && (static_cast<qint64>(row) + rowSpan > gridRows
                    || static_cast<qint64>(column) + columnSpan > gridColumns)) {
                addError(path + QStringLiteral(" must remain inside layout.grid"));
            }

            if (kind == QStringLiteral("controls")) {
                const QJsonObject contentCanvas =
                    requiredObject(card, QStringLiteral("contentCanvas"),
                                   path + QStringLiteral(".contentCanvas"));
                rejectUnknownKeys(contentCanvas,
                                  {QStringLiteral("width"),
                                   QStringLiteral("height"),
                                   QStringLiteral("scaleMode")},
                                  path + QStringLiteral(".contentCanvas"));
                const int contentWidth =
                    requiredInteger(contentCanvas, QStringLiteral("width"),
                                    path + QStringLiteral(".contentCanvas.width"));
                const int contentHeight =
                    requiredInteger(contentCanvas, QStringLiteral("height"),
                                    path + QStringLiteral(".contentCanvas.height"));
                const QString scaleMode =
                    requiredString(contentCanvas, QStringLiteral("scaleMode"),
                                   path + QStringLiteral(".contentCanvas.scaleMode"));
                if (contentWidth <= 0 || contentHeight <= 0) {
                    addError(path + QStringLiteral(
                        ".contentCanvas width/height must be positive"));
                }
                if (scaleMode != QStringLiteral("uniform")
                    && scaleMode != QStringLiteral("stretch")
                    && scaleMode != QStringLiteral("none")) {
                    addError(path + QStringLiteral(".contentCanvas.scaleMode is unsupported"));
                }
                const QJsonArray elements =
                    requiredArray(card, QStringLiteral("elements"),
                                  path + QStringLiteral(".elements"), true);
                static const QSet<QString> renderers{
                    QStringLiteral("singleAxisGauge"),
                    QStringLiteral("joystickPad"),
                    QStringLiteral("miniJoystick"),
                    QStringLiteral("button"),
                    QStringLiteral("roller"),
                    QStringLiteral("potentiometer"),
                    QStringLiteral("fnr"),
                    QStringLiteral("numericDisplay"),
                    QStringLiteral("indicator"),
                    QStringLiteral("binaryOutput")
                };
                for (qsizetype elementIndex = 0;
                     elementIndex < elements.size();
                     ++elementIndex) {
                    const QString elementPath =
                        path + QStringLiteral(".elements[%1]").arg(elementIndex);
                    if (!elements.at(elementIndex).isObject()) {
                        addError(elementPath + QStringLiteral(" must be an object"));
                        continue;
                    }
                    const QJsonObject element = elements.at(elementIndex).toObject();
                    rejectUnknownKeys(element,
                                      {QStringLiteral("id"),
                                       QStringLiteral("controlId"),
                                       QStringLiteral("renderer"),
                                       QStringLiteral("x"),
                                       QStringLiteral("y"),
                                       QStringLiteral("width"),
                                       QStringLiteral("height"),
                                       QStringLiteral("properties")},
                                      elementPath);
                    const QString elementId =
                        requiredString(element, QStringLiteral("id"),
                                       elementPath + QStringLiteral(".id"));
                    if (!elementId.isEmpty()) {
                        if (elementIds.contains(elementId)) {
                            addError(elementPath + QStringLiteral(".id is duplicated"));
                        }
                        elementIds.insert(elementId);
                    }
                    const QString controlId =
                        requiredString(element, QStringLiteral("controlId"),
                                       elementPath + QStringLiteral(".controlId"));
                    if (!controlId.isEmpty() && !controlIds.contains(controlId)) {
                        addError(elementPath + QStringLiteral(
                            ".controlId references missing control"));
                    }
                    const QString renderer =
                        requiredString(element, QStringLiteral("renderer"),
                                       elementPath + QStringLiteral(".renderer"));
                    if (!renderer.isEmpty() && !renderers.contains(renderer)) {
                        addError(elementPath + QStringLiteral(".renderer is unsupported"));
                    }
                    const double elementX =
                        requiredNumber(element, QStringLiteral("x"),
                                       elementPath + QStringLiteral(".x"));
                    const double elementY =
                        requiredNumber(element, QStringLiteral("y"),
                                       elementPath + QStringLiteral(".y"));
                    const double elementWidth =
                        requiredNumber(element, QStringLiteral("width"),
                                       elementPath + QStringLiteral(".width"));
                    const double elementHeight =
                        requiredNumber(element, QStringLiteral("height"),
                                       elementPath + QStringLiteral(".height"));
                    if (elementX < 0 || elementY < 0) {
                        addError(elementPath + QStringLiteral(".x/y must be non-negative"));
                    }
                    if (elementWidth <= 0 || elementHeight <= 0) {
                        addError(elementPath + QStringLiteral(
                            ".width/height must be positive"));
                    }
                    if (contentWidth > 0 && contentHeight > 0
                        && elementX >= 0 && elementY >= 0
                        && elementWidth > 0 && elementHeight > 0
                        && (static_cast<qint64>(elementX) + elementWidth > contentWidth
                            || static_cast<qint64>(elementY) + elementHeight > contentHeight)) {
                        addError(elementPath + QStringLiteral(
                            " must remain inside its contentCanvas"));
                    }
                    if (element.contains(QStringLiteral("properties"))) {
                        const QJsonObject properties =
                            requiredObject(element, QStringLiteral("properties"),
                                           elementPath + QStringLiteral(".properties"));
                        rejectUnknownKeys(
                            properties,
                            {QStringLiteral("orientation"),
                             QStringLiteral("showLabel"),
                             QStringLiteral("showValue"),
                             QStringLiteral("compact"),
                             QStringLiteral("invertX"),
                             QStringLiteral("invertY"),
                             QStringLiteral("testPattern"),
                             QStringLiteral("cycleCount"),
                             QStringLiteral("label"),
                             QStringLiteral("buttonVariant"),
                             QStringLiteral("bezelSize"),
                             QStringLiteral("capSize"),
                             QStringLiteral("decimals"),
                             QStringLiteral("unit"),
                             QStringLiteral("columns"),
                             QStringLiteral("rows"),
                             QStringLiteral("activeColor"),
                             QStringLiteral("inactiveColor"),
                             QStringLiteral("labelPosition")},
                            elementPath + QStringLiteral(".properties"));
                        const QSet<QString> buttonPropertyKeys{
                            QStringLiteral("buttonVariant"),
                            QStringLiteral("bezelSize"),
                            QStringLiteral("capSize")
                        };
                        for (const QString &key : buttonPropertyKeys) {
                            if (properties.contains(key)
                                && renderer != QStringLiteral("button")) {
                                addError(elementPath + QStringLiteral(".properties.")
                                         + key
                                         + QStringLiteral(
                                             " is only valid for the button renderer"));
                            }
                        }
                        const QSet<QString> miniJoystickPropertyKeys{
                             QStringLiteral("invertX"),
                             QStringLiteral("invertY"),
                             QStringLiteral("testPattern"),
                             QStringLiteral("cycleCount")
                        };
                        for (const QString &key : miniJoystickPropertyKeys) {
                            if (properties.contains(key)
                                && renderer != QStringLiteral("miniJoystick")) {
                                addError(elementPath + QStringLiteral(".properties.")
                                         + key
                                         + QStringLiteral(
                                             " is only valid for the miniJoystick renderer"));
                            }
                        }
                        for (const QString &key :
                             {QStringLiteral("invertX"), QStringLiteral("invertY")}) {
                            if (properties.contains(key) && !properties.value(key).isBool()) {
                                addError(elementPath + QStringLiteral(".properties.")
                                         + key + QStringLiteral(" must be a boolean"));
                            }
                        }
                        if (properties.contains(QStringLiteral("testPattern"))) {
                            const QString testPattern =
                                properties.value(QStringLiteral("testPattern")).toString();
                            if (testPattern != QStringLiteral("ninePoint")
                                && testPattern != QStringLiteral("cross")) {
                                addError(elementPath
                                         + QStringLiteral(
                                             ".properties.testPattern is unsupported"));
                            }
                        }
                        if (properties.contains(QStringLiteral("cycleCount"))) {
                            const QJsonValue cycleCount =
                                properties.value(QStringLiteral("cycleCount"));
                            if (!cycleCount.isDouble()
                                || cycleCount.toDouble() != cycleCount.toInt()
                                || cycleCount.toInt() < 1
                                || cycleCount.toInt() > 10) {
                                addError(elementPath
                                         + QStringLiteral(
                                             ".properties.cycleCount must be an integer from 1 to 10"));
                            }
                        }
                        if (properties.contains(QStringLiteral("label"))
                            && !properties.value(QStringLiteral("label")).isString()) {
                            addError(elementPath
                                     + QStringLiteral(".properties.label must be a string"));
                        }
                        if (properties.contains(QStringLiteral("buttonVariant"))) {
                            const QString variant =
                                properties.value(QStringLiteral("buttonVariant")).toString();
                            static const QSet<QString> variants{
                                QStringLiteral("red"),
                                QStringLiteral("black"),
                                QStringLiteral("green"),
                                QStringLiteral("orange")
                            };
                            if (!variants.contains(variant)) {
                                addError(elementPath
                                         + QStringLiteral(
                                             ".properties.buttonVariant is unsupported"));
                            }
                        }
                        bool bezelValid = false;
                        bool capValid = false;
                        double bezelSize = 0.0;
                        double capSize = 0.0;
                        if (properties.contains(QStringLiteral("bezelSize"))) {
                            bezelSize =
                                requiredNumber(properties,
                                               QStringLiteral("bezelSize"),
                                               elementPath
                                                   + QStringLiteral(
                                                       ".properties.bezelSize"),
                                               &bezelValid);
                            if (bezelValid && bezelSize <= 0.0) {
                                addError(elementPath
                                         + QStringLiteral(
                                             ".properties.bezelSize must be positive"));
                            }
                        }
                        if (properties.contains(QStringLiteral("capSize"))) {
                            capSize =
                                requiredNumber(properties,
                                               QStringLiteral("capSize"),
                                               elementPath
                                                   + QStringLiteral(
                                                       ".properties.capSize"),
                                               &capValid);
                            if (capValid && capSize <= 0.0) {
                                addError(elementPath
                                         + QStringLiteral(
                                             ".properties.capSize must be positive"));
                            }
                        }
                        if (bezelValid && capValid && capSize > bezelSize) {
                            addError(elementPath
                                     + QStringLiteral(
                                         ".properties.capSize must not exceed bezelSize"));
                        }
                    }
                }
            } else if (kind == QStringLiteral("system")) {
                const QString systemType =
                    requiredString(card, QStringLiteral("systemType"),
                                   path + QStringLiteral(".systemType"));
                if (systemType != QStringLiteral("busStats")
                    && systemType != QStringLiteral("rawFrames")
                    && systemType != QStringLiteral("recordInfo")) {
                    addError(path + QStringLiteral(".systemType is unsupported"));
                }
                if (card.contains(QStringLiteral("properties"))) {
                    const QJsonObject properties =
                        requiredObject(card, QStringLiteral("properties"),
                                       path + QStringLiteral(".properties"));
                    rejectUnknownKeys(
                        properties,
                        {QStringLiteral("refreshMs"),
                         QStringLiteral("maxRows"),
                         QStringLiteral("showTimestamp"),
                         QStringLiteral("showChannel"),
                         QStringLiteral("showDirection"),
                         QStringLiteral("showOperator"),
                         QStringLiteral("showSerialNumber")},
                        path + QStringLiteral(".properties"));
                }
            } else if (kind == QStringLiteral("leftRegion")) {
                const QString controlId =
                    requiredString(card, QStringLiteral("controlId"),
                                   path + QStringLiteral(".controlId"));
                if (!controlId.isEmpty() && !controlIds.contains(controlId)) {
                    addError(path + QStringLiteral(
                        ".controlId references missing control"));
                }
                const double widthRatio =
                    requiredNumber(card, QStringLiteral("widthRatio"),
                                   path + QStringLiteral(".widthRatio"));
                if (widthRatio <= 0.0 || widthRatio >= 1.0) {
                    addError(path + QStringLiteral(".widthRatio must be between 0 and 1"));
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
    QHash<QString, QString> m_signalKinds;
    QHash<QString, int> m_signalBitLengths;
    QHash<QString, QString> m_signalEncodings;
    QHash<QString, int> m_signalLogicalPositionCounts;
};

} // namespace

ProductConfigV3Validator::Result ProductConfigV3Validator::validate(const QJsonObject &config)
{
    return Validator().run(config);
}
