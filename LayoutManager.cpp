#include "LayoutManager.h"
#include <QCryptographicHash>
#include <QDebug>
#include <QFileInfo>
#include <QSaveFile>
#include <QDateTime>
#include <QCoreApplication>
#include <QDesktopServices>
#include <QDirIterator>
#include <QRegularExpression>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>
#include <QUrl>
#include <QMap>
#include <QSet>
#include <QStringList>
#include <QUuid>
#include <QVector>

#include <algorithm>

namespace {

constexpr int kSupportedProductionDatabaseVersion = 1;

QJsonDocument readJsonFileQuiet(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return QJsonDocument();
    }

    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &error);
    return error.error == QJsonParseError::NoError ? document : QJsonDocument();
}

QString fileSha256Hex(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return QString();
    }

    QCryptographicHash hash(QCryptographicHash::Sha256);
    while (!file.atEnd()) {
        hash.addData(file.read(1024 * 1024));
    }
    return QString::fromLatin1(hash.result().toHex());
}

QString versionCodeFromNameSuffix(const QString &name)
{
    static const QRegularExpression versionSuffix(
        QStringLiteral("^(.*)_(V\\d+(?:\\.\\d+)*)$"),
        QRegularExpression::CaseInsensitiveOption);
    const QRegularExpressionMatch suffixMatch = versionSuffix.match(name.trimmed());
    return suffixMatch.hasMatch() ? suffixMatch.captured(2).trimmed().toUpper() : QString();
}

QString normalizedVersionCode(QString versionCode)
{
    versionCode = versionCode.trimmed();
    if (versionCode.endsWith(QStringLiteral(".json"), Qt::CaseInsensitive)) {
        versionCode.chop(5);
    }
    if (versionCode.isEmpty()) {
        return QStringLiteral("V1");
    }

    if (versionCode.at(0).isDigit()) {
        versionCode.prepend(QLatin1Char('V'));
    }
    if (versionCode.startsWith(QLatin1Char('v'))) {
        versionCode[0] = QLatin1Char('V');
    }
    versionCode.replace(QRegularExpression(QStringLiteral("[<>:\"/\\\\|?*\\x00-\\x1F\\s]+")), QStringLiteral("_"));
    while (!versionCode.isEmpty() && (versionCode.endsWith('.') || versionCode.endsWith(' '))) {
        versionCode.chop(1);
    }
    return versionCode.isEmpty() ? QStringLiteral("V1") : versionCode;
}

QString productBaseNameFromVersionedName(const QString &name)
{
    static const QRegularExpression versionSuffix(
        QStringLiteral("^(.*)_(V\\d+(?:\\.\\d+)*)$"),
        QRegularExpression::CaseInsensitiveOption);
    const QRegularExpressionMatch suffixMatch = versionSuffix.match(name.trimmed());
    return suffixMatch.hasMatch() ? suffixMatch.captured(1).trimmed() : name.trimmed();
}

QString versionCodeFromProductConfig(const QJsonObject &configJson, const QFileInfo &fileInfo)
{
    const QJsonObject firmware = configJson.value(QStringLiteral("firmware")).toObject();
    QString versionCode = firmware.value(QStringLiteral("version_code")).toString().trimmed();
    if (versionCode.isEmpty()) {
        versionCode = firmware.value(QStringLiteral("versionCode")).toString().trimmed();
    }
    if (versionCode.isEmpty()) {
        versionCode = versionCodeFromNameSuffix(fileInfo.completeBaseName());
    }
    return versionCode.isEmpty() ? QStringLiteral("V1") : versionCode.toUpper();
}

QString displayVersionFromProductConfig(const QJsonObject &configJson, const QFileInfo &fileInfo)
{
    const QJsonObject firmware = configJson.value(QStringLiteral("firmware")).toObject();
    QString displayVersion = firmware.value(QStringLiteral("display_version")).toString().trimmed();
    if (displayVersion.isEmpty()) {
        displayVersion = firmware.value(QStringLiteral("displayVersion")).toString().trimmed();
    }
    return displayVersion.isEmpty() ? versionCodeFromProductConfig(configJson, fileInfo) : displayVersion;
}

QJsonObject configWithDefaultVersionMetadata(const QJsonObject &configJson, const QFileInfo &fileInfo)
{
    QJsonObject normalized = configJson;
    const QJsonObject product = normalized.value(QStringLiteral("product")).toObject();
    QJsonObject firmware = normalized.value(QStringLiteral("firmware")).toObject();

    QString versionCode = firmware.value(QStringLiteral("version_code")).toString().trimmed();
    if (versionCode.isEmpty()) {
        versionCode = firmware.value(QStringLiteral("versionCode")).toString().trimmed();
    }
    if (versionCode.isEmpty()) {
        versionCode = versionCodeFromNameSuffix(fileInfo.completeBaseName());
    }
    versionCode = normalizedVersionCode(versionCode);

    if (firmware.value(QStringLiteral("version_code")).toString().trimmed().isEmpty()) {
        firmware.insert(QStringLiteral("version_code"), versionCode);
    }
    if (firmware.value(QStringLiteral("display_version")).toString().trimmed().isEmpty()) {
        firmware.insert(QStringLiteral("display_version"), versionCode);
    }
    if (firmware.value(QStringLiteral("variant_code")).toString().trimmed().isEmpty()) {
        firmware.insert(QStringLiteral("variant_code"), versionCode);
    }
    if (firmware.value(QStringLiteral("status")).toString().trimmed().isEmpty()) {
        firmware.insert(QStringLiteral("status"), QStringLiteral("active"));
    }
    if (firmware.value(QStringLiteral("description")).toString().trimmed().isEmpty()) {
        const QString description = product.value(QStringLiteral("description")).toString().trimmed();
        if (!description.isEmpty()) {
            firmware.insert(QStringLiteral("description"), description);
        }
    }

    normalized.insert(QStringLiteral("firmware"), firmware);
    return normalized;
}

QString normalizedProductVersionStatus(const QString &status)
{
    const QString value = status.trimmed().toLower();
    if (value.isEmpty()
        || value == QStringLiteral("active")
        || value == QStringLiteral("current")
        || value == QStringLiteral("released")
        || value == QStringLiteral("stable")
        || value == QStringLiteral("使用中")
        || value == QStringLiteral("启用")) {
        return QStringLiteral("active");
    }

    if (value == QStringLiteral("deprecated")
        || value == QStringLiteral("obsolete")
        || value == QStringLiteral("retired")
        || value == QStringLiteral("inactive")
        || value == QStringLiteral("disabled")
        || value == QStringLiteral("弃用")
        || value == QStringLiteral("废弃")
        || value == QStringLiteral("停用")) {
        return QStringLiteral("deprecated");
    }

    return value;
}

QString statusFromProductConfig(const QJsonObject &configJson)
{
    const QJsonObject firmware = configJson.value(QStringLiteral("firmware")).toObject();
    QString status = firmware.value(QStringLiteral("status")).toString().trimmed();
    if (status.isEmpty()) {
        status = firmware.value(QStringLiteral("lifecycle")).toString().trimmed();
    }
    if (status.isEmpty()) {
        status = configJson.value(QStringLiteral("status")).toString().trimmed();
    }
    if (status.isEmpty()) {
        status = configJson.value(QStringLiteral("lifecycle")).toString().trimmed();
    }
    return normalizedProductVersionStatus(status);
}

QVector<int> numericVersionParts(const QString &versionCode)
{
    QString text = versionCode.trimmed();
    if (text.startsWith(QLatin1Char('V'), Qt::CaseInsensitive)) {
        text.remove(0, 1);
    }

    QVector<int> result;
    for (const QString &part : text.split(QLatin1Char('.'), Qt::SkipEmptyParts)) {
        bool ok = false;
        const int value = part.toInt(&ok);
        if (!ok) {
            return {};
        }
        result.append(value);
    }
    return result;
}

int compareVersionCodes(const QString &left, const QString &right)
{
    const QVector<int> leftParts = numericVersionParts(left);
    const QVector<int> rightParts = numericVersionParts(right);
    if (!leftParts.isEmpty() && !rightParts.isEmpty()) {
        const int partCount = std::max(leftParts.size(), rightParts.size());
        for (int i = 0; i < partCount; ++i) {
            const int leftPart = i < leftParts.size() ? leftParts.at(i) : 0;
            const int rightPart = i < rightParts.size() ? rightParts.at(i) : 0;
            if (leftPart != rightPart) {
                return leftPart < rightPart ? -1 : 1;
            }
        }
        return 0;
    }

    return QString::compare(left, right, Qt::CaseInsensitive);
}

bool productVersionLessThan(const QJsonObject &left, const QJsonObject &right)
{
    const int leftStatusRank = left.value(QStringLiteral("deprecated")).toBool() ? 1 : 0;
    const int rightStatusRank = right.value(QStringLiteral("deprecated")).toBool() ? 1 : 0;
    if (leftStatusRank != rightStatusRank) {
        return leftStatusRank < rightStatusRank;
    }

    const int versionCompare = compareVersionCodes(
        left.value(QStringLiteral("versionCode")).toString(),
        right.value(QStringLiteral("versionCode")).toString());
    if (versionCompare != 0) {
        return versionCompare > 0;
    }

    return QString::compare(
               left.value(QStringLiteral("name")).toString(),
               right.value(QStringLiteral("name")).toString(),
               Qt::CaseInsensitive) < 0;
}

struct ProductFileGroup
{
    QString displayName;
    QString model;
    QString protocol;
    QString description;
    QMap<QString, QString> customerNames;
    QSet<int> baudRates;
    QVector<QJsonObject> versions;
};

struct CustomerBindingSpec
{
    QString name;
    bool isDefault = false;
};

QString assetRootNameForDirectory(const QString &directory)
{
    const QString rootName = QFileInfo(QDir(directory).absolutePath()).fileName();
    return rootName.compare(QStringLiteral("firmware"), Qt::CaseInsensitive) == 0
        ? QStringLiteral("firmware")
        : QStringLiteral("products");
}

QString normalizedProductEditorProtocol(const QString &protocol)
{
    const QString value = protocol.trimmed().toLower();
    if (value == QStringLiteral("can") || value == QStringLiteral("canopen")) {
        return value;
    }
    return QStringLiteral("j1939");
}

bool isManualMappingDraft(const QJsonObject &configJson)
{
    const QJsonObject editor = configJson.value(QStringLiteral("editor")).toObject();
    return editor.value(QStringLiteral("creationFlow")).toString() == QStringLiteral("manualCanMessageMapping")
        && editor.value(QStringLiteral("manualMappingRequired")).toBool(false);
}

bool databaseTableHasColumn(QSqlDatabase &db, const QString &tableName, const QString &columnName)
{
    QSqlQuery query(db);
    if (!query.exec(QStringLiteral("PRAGMA table_info(%1)").arg(tableName))) {
        return false;
    }

    while (query.next()) {
        if (query.value(QStringLiteral("name")).toString().compare(columnName, Qt::CaseInsensitive) == 0) {
            return true;
        }
    }

    return false;
}

bool isCanonicalProductionDatabaseFile(const QString &path);

void appendMessage(QJsonArray &messages, const QString &message)
{
    messages.append(message);
}

int boundedJsonInt(const QJsonObject &object, const QString &key, int fallback, int minValue, int maxValue)
{
    int value = fallback;
    const QJsonValue rawValue = object.value(key);
    if (rawValue.isDouble()) {
        value = rawValue.toInt(fallback);
    } else if (rawValue.isString()) {
        bool ok = false;
        const int parsed = rawValue.toString().trimmed().toInt(&ok, 0);
        if (ok) {
            value = parsed;
        }
    }
    return qBound(minValue, value, maxValue);
}

void collectCustomerName(QMap<QString, QString> &names, const QString &name)
{
    const QString trimmed = name.trimmed();
    if (trimmed.isEmpty()) {
        return;
    }

    const QString key = trimmed.toCaseFolded();
    if (!names.contains(key)) {
        names.insert(key, trimmed);
    }
}

void collectCustomerNamesFromValue(QMap<QString, QString> &names, const QJsonValue &value)
{
    if (value.isString()) {
        collectCustomerName(names, value.toString());
        return;
    }

    if (value.isArray()) {
        const QJsonArray entries = value.toArray();
        for (const QJsonValue &entry : entries) {
            collectCustomerNamesFromValue(names, entry);
        }
        return;
    }

    if (!value.isObject()) {
        return;
    }

    const QJsonObject object = value.toObject();
    QString name = object.value(QStringLiteral("customerName")).toString().trimmed();
    if (name.isEmpty()) {
        name = object.value(QStringLiteral("name")).toString().trimmed();
    }
    if (name.isEmpty()) {
        name = object.value(QStringLiteral("displayName")).toString().trimmed();
    }
    collectCustomerName(names, name);
}

QMap<QString, QString> customerNamesFromProductConfig(const QJsonObject &configJson)
{
    QMap<QString, QString> names;
    const QJsonObject product = configJson.value(QStringLiteral("product")).toObject();

    collectCustomerName(names, product.value(QStringLiteral("customerName")).toString());
    collectCustomerName(names, product.value(QStringLiteral("customer")).toString());
    collectCustomerNamesFromValue(names, product.value(QStringLiteral("customerBindings")));
    collectCustomerNamesFromValue(names, product.value(QStringLiteral("customers")));
    collectCustomerNamesFromValue(names, configJson.value(QStringLiteral("customerBindings")));
    collectCustomerNamesFromValue(names, configJson.value(QStringLiteral("customers")));

    return names;
}

void appendCustomerBindingSpecs(QVector<CustomerBindingSpec> &bindings, const QJsonValue &value)
{
    if (value.isArray()) {
        const QJsonArray entries = value.toArray();
        for (const QJsonValue &entry : entries) {
            appendCustomerBindingSpecs(bindings, entry);
        }
        return;
    }

    CustomerBindingSpec binding;
    if (value.isString()) {
        binding.name = value.toString().trimmed();
    } else if (value.isObject()) {
        const QJsonObject object = value.toObject();
        binding.name = object.value(QStringLiteral("customerName"))
            .toString(object.value(QStringLiteral("name")).toString())
            .trimmed();
        binding.isDefault = object.value(QStringLiteral("isDefault")).toBool(false);
    }

    if (!binding.name.isEmpty()) {
        bindings.append(binding);
    }
}

QVector<CustomerBindingSpec> customerBindingSpecsFromProductConfig(const QJsonObject &configJson)
{
    QVector<CustomerBindingSpec> bindings;
    const QJsonObject product = configJson.value(QStringLiteral("product")).toObject();

    appendCustomerBindingSpecs(bindings, product.value(QStringLiteral("customerBindings")));
    appendCustomerBindingSpecs(bindings, product.value(QStringLiteral("customers")));
    appendCustomerBindingSpecs(bindings, configJson.value(QStringLiteral("customerBindings")));
    appendCustomerBindingSpecs(bindings, configJson.value(QStringLiteral("customers")));

    return bindings;
}

QJsonArray customerNamesToJsonArray(const QMap<QString, QString> &names)
{
    QJsonArray result;
    for (auto it = names.cbegin(); it != names.cend(); ++it) {
        result.append(it.value());
    }
    return result;
}

QJsonArray baudRatesToJsonArray(const QSet<int> &baudRates)
{
    QList<int> values = baudRates.values();
    std::sort(values.begin(), values.end());

    QJsonArray result;
    for (int value : values) {
        result.append(value);
    }
    return result;
}

int defaultBaudRateFromProductConfig(const QJsonObject &configJson)
{
    const QJsonObject can = configJson.value(QStringLiteral("can")).toObject();
    return boundedJsonInt(can, QStringLiteral("defaultBaudRate"), 250, 10, 1000);
}

bool jsonBool(const QJsonObject &object, const QString &key, bool fallback = false)
{
    const QJsonValue value = object.value(key);
    if (value.isBool()) {
        return value.toBool();
    }
    if (value.isDouble()) {
        return value.toInt() != 0;
    }
    if (value.isString()) {
        const QString text = value.toString().trimmed().toLower();
        if (text == QStringLiteral("true") || text == QStringLiteral("1") || text == QStringLiteral("yes")) {
            return true;
        }
        if (text == QStringLiteral("false") || text == QStringLiteral("0") || text == QStringLiteral("no")) {
            return false;
        }
    }
    return fallback;
}

QString hexText(quint32 value, int width)
{
    return QStringLiteral("0x%1")
        .arg(value, width, 16, QLatin1Char('0'))
        .toUpper();
}

quint32 composeJ1939Id(quint32 priority, quint32 pgn, quint32 source, quint32 destination)
{
    const quint32 pf = (pgn >> 8) & 0xFFU;
    quint32 id = (priority & 0x7U) << 26;
    id |= (pgn & 0x3FF00U) << 8;
    id |= ((pf < 240U) ? (destination & 0xFFU) : (pgn & 0xFFU)) << 8;
    id |= source & 0xFFU;
    return id;
}

quint32 parseUnsignedConfigValue(const QJsonValue &value, quint32 fallback)
{
    if (value.isDouble()) {
        return static_cast<quint32>(value.toInt(static_cast<int>(fallback)));
    }

    bool ok = false;
    const QString text = value.toString().trimmed();
    if (text.isEmpty()) {
        return fallback;
    }
    const quint32 parsed = text.toUInt(&ok, 0);
    return ok ? parsed : fallback;
}

QJsonObject makeField(const QString &name, int startByte, int startBit, int bitLength,
                      const QString &type, const QString &encoding = QString(),
                      const QString &endian = QString())
{
    QJsonObject field;
    field.insert(QStringLiteral("name"), name);
    field.insert(QStringLiteral("startByte"), startByte);
    field.insert(QStringLiteral("startBit"), startBit);
    field.insert(QStringLiteral("bitLength"), bitLength);
    field.insert(QStringLiteral("type"), type);
    if (!encoding.isEmpty()) {
        field.insert(QStringLiteral("encoding"), encoding);
    }
    if (!endian.isEmpty()) {
        field.insert(QStringLiteral("endian"), endian);
    }
    return field;
}

QJsonObject makeRangePositionField(const QString &name, int startByte)
{
    QJsonObject field = makeField(name, startByte, 6, 10, QStringLiteral("position"), QStringLiteral("unsigned"));
    field.insert(QStringLiteral("range"), QJsonArray{0, 1000});
    return field;
}

QJsonObject makeMessage(const QString &id, const QString &name, const QString &periodKey,
                        const QJsonValue &addressValue, const QJsonArray &fields)
{
    QJsonObject message;
    message.insert(QStringLiteral("id"), id);
    message.insert(QStringLiteral("name"), name);
    message.insert(QStringLiteral("dlc"), 8);
    if (!periodKey.isEmpty()) {
        message.insert(QStringLiteral("period"), 20);
    }
    message.insert(periodKey.isEmpty() ? QStringLiteral("pgn") : periodKey, addressValue);
    message.insert(QStringLiteral("fields"), fields);
    return message;
}

QJsonArray j1939BjmFields(int buttonCount, bool includeFnr = false)
{
    QJsonArray fields;
    fields.append(makeField(QStringLiteral("xStatus"), 0, 0, 6, QStringLiteral("status"), QStringLiteral("j1939_axis_status")));
    fields.append(makeRangePositionField(QStringLiteral("xPos"), 0));
    fields.append(makeField(QStringLiteral("yStatus"), 2, 0, 6, QStringLiteral("status"), QStringLiteral("j1939_axis_status")));
    fields.append(makeRangePositionField(QStringLiteral("yPos"), 2));
    if (includeFnr) {
        fields.append(makeField(QStringLiteral("fnr"), 4, 0, 2, QStringLiteral("fnr"), QStringLiteral("unsigned")));
    }
    if (buttonCount > 0) {
        QJsonObject buttons = makeField(QStringLiteral("buttons"), 5, 0,
                                        ((buttonCount * 2 + 7) / 8) * 8,
                                        QStringLiteral("buttonGroup"),
                                        QStringLiteral("j1939_2bit"));
        buttons.insert(QStringLiteral("buttonCount"), buttonCount);
        fields.append(buttons);
    }
    return fields;
}

QJsonArray j1939EjmFields(int rollerCount, bool includeFnr = false)
{
    QJsonArray fields;
    if (rollerCount >= 1) {
        fields.append(makeField(QStringLiteral("handleXStatus"), 0, 0, 6, QStringLiteral("status"), QStringLiteral("j1939_axis_status")));
        fields.append(makeRangePositionField(QStringLiteral("handleXPos"), 0));
    }
    if (rollerCount >= 2) {
        fields.append(makeField(QStringLiteral("handleYStatus"), 2, 0, 6, QStringLiteral("status"), QStringLiteral("j1939_axis_status")));
        fields.append(makeRangePositionField(QStringLiteral("handleYPos"), 2));
    }
    if (rollerCount >= 3) {
        fields.append(makeField(QStringLiteral("thetaStatus"), 4, 0, 6, QStringLiteral("status"), QStringLiteral("j1939_axis_status")));
        fields.append(makeRangePositionField(QStringLiteral("thetaPos"), 4));
    }
    if (rollerCount >= 4) {
        fields.append(makeField(QStringLiteral("roller4Status"), 6, 0, 6, QStringLiteral("status"), QStringLiteral("j1939_axis_status")));
        fields.append(makeRangePositionField(QStringLiteral("roller4Pos"), 6));
    }
    if (includeFnr && rollerCount < 4) {
        fields.append(makeField(QStringLiteral("fnr"), 6, 0, 2, QStringLiteral("fnr"), QStringLiteral("unsigned")));
    }
    return fields;
}

QJsonArray canopenTpdo1Fields(int buttonCount, bool includeFnr = false)
{
    QJsonArray fields;
    fields.append(makeField(QStringLiteral("xValue"), 0, 0, 16, QStringLiteral("position"), QStringLiteral("raw_16bit"), QStringLiteral("little")));
    fields.append(makeField(QStringLiteral("yValue"), 2, 0, 16, QStringLiteral("position"), QStringLiteral("raw_16bit"), QStringLiteral("little")));
    if (buttonCount > 0) {
        QJsonObject buttons = makeField(QStringLiteral("buttons"), 4, 0, qMax(8, buttonCount),
                                        QStringLiteral("buttonGroup"),
                                        QStringLiteral("canopen_1bit"));
        buttons.insert(QStringLiteral("buttonCount"), buttonCount);
        fields.append(buttons);
    }
    if (includeFnr) {
        fields.append(makeField(QStringLiteral("fnr"), 6, 0, 2, QStringLiteral("fnr"), QStringLiteral("unsigned")));
    }
    return fields;
}

QJsonArray canopenAxisFields(int firstAxis, int axisCount, bool includeFnr = false)
{
    QJsonArray fields;
    for (int i = 0; i < axisCount; ++i) {
        const int axis = firstAxis + i;
        fields.append(makeField(QStringLiteral("axis%1Value").arg(axis), i * 2, 0, 16,
                                QStringLiteral("position"), QStringLiteral("raw_16bit"), QStringLiteral("little")));
    }
    if (includeFnr) {
        fields.append(makeField(QStringLiteral("fnr"), 6, 0, 2, QStringLiteral("fnr"), QStringLiteral("unsigned")));
    }
    return fields;
}

QString rollerComponentId(const QString &protocol, int index)
{
    if (protocol == QStringLiteral("canopen")) {
        return QStringLiteral("axis%1").arg(index + 3);
    }

    switch (index) {
    case 0:
        return QStringLiteral("ejm_handleX");
    case 1:
        return QStringLiteral("ejm_handleY");
    case 2:
        return QStringLiteral("ejm_theta");
    case 3:
        return QStringLiteral("ejm_roller4");
    default:
        return QStringLiteral("ejm_roller%1").arg(index + 1);
    }
}

QString rollerLabel(const QString &protocol, int index)
{
    if (protocol != QStringLiteral("canopen") && index == 3) {
        return QStringLiteral("Roller4");
    }
    if (protocol != QStringLiteral("canopen") && index > 3) {
        return QStringLiteral("Roller%1").arg(index + 1);
    }

    if (protocol == QStringLiteral("canopen")) {
        return QStringLiteral("轴%1").arg(index + 3);
    }

    switch (index) {
    case 0:
        return QStringLiteral("手柄X");
    case 1:
        return QStringLiteral("手柄Y");
    default:
        return QStringLiteral("旋转");
    }
}

QString rollerPositionRef(const QString &protocol, int index)
{
    if (protocol == QStringLiteral("canopen")) {
        const int axis = index + 3;
        const QString messageId = axis <= 5 ? QStringLiteral("tpdo2") : QStringLiteral("tpdo3");
        return QStringLiteral("%1.axis%2Value").arg(messageId).arg(axis);
    }

    switch (index) {
    case 0:
        return QStringLiteral("ejm.handleXPos");
    case 1:
        return QStringLiteral("ejm.handleYPos");
    case 2:
        return QStringLiteral("ejm.thetaPos");
    case 3:
        return QStringLiteral("ejm.roller4Pos");
    default:
        return QStringLiteral("ejm.roller%1Pos").arg(index + 1);
    }
}

QJsonValue rollerStatusRef(const QString &protocol, int index)
{
    if (protocol == QStringLiteral("canopen")) {
        return QJsonValue::Null;
    }

    switch (index) {
    case 0:
        return QStringLiteral("ejm.handleXStatus");
    case 1:
        return QStringLiteral("ejm.handleYStatus");
    case 2:
        return QStringLiteral("ejm.thetaStatus");
    case 3:
        return QStringLiteral("ejm.roller4Status");
    default:
        return QStringLiteral("ejm.roller%1Status").arg(index + 1);
    }
}

QJsonObject makeButtonComponent(int buttonCount, const QString &source)
{
    QJsonObject component;
    component.insert(QStringLiteral("id"), QStringLiteral("buttons"));
    component.insert(QStringLiteral("type"), QStringLiteral("buttonGroup"));
    component.insert(QStringLiteral("label"), QStringLiteral("按钮"));
    component.insert(QStringLiteral("source"), source);
    component.insert(QStringLiteral("count"), buttonCount);
    component.insert(QStringLiteral("layout"), QJsonObject{
        {QStringLiteral("columns"), qMin(4, qMax(1, buttonCount))},
        {QStringLiteral("rows"), qMax(1, (buttonCount + 3) / 4)}
    });
    return component;
}

QJsonObject makeVisualComponent(const QString &type, const QString &bindingId,
                                int x, int y, const QJsonObject &config)
{
    QJsonObject visual;
    visual.insert(QStringLiteral("type"), type);
    visual.insert(QStringLiteral("bindingId"), bindingId);
    visual.insert(QStringLiteral("x"), x);
    visual.insert(QStringLiteral("y"), y);
    visual.insert(QStringLiteral("config"), config);
    return visual;
}

QJsonArray makeButtonVisuals(int buttonCount)
{
    QJsonArray visuals;
    constexpr int buttonWidth = 56;
    constexpr int xGap = 8;
    constexpr int yGap = 2;
    const int columns = qMin(5, qMax(1, buttonCount));
    for (int i = 0; i < buttonCount; ++i) {
        visuals.append(makeVisualComponent(
            QStringLiteral("ButtonRed"),
            QStringLiteral("buttons.%1").arg(i),
            4 + (i % columns) * (buttonWidth + xGap),
            4 + (i / columns) * (88 + yGap),
            QJsonObject{
                {QStringLiteral("variant"), QStringLiteral("red")},
                {QStringLiteral("bezelSize"), 56},
                {QStringLiteral("capSize"), 40},
                {QStringLiteral("label"), QString::number(i + 1)}
            }));
    }
    return visuals;
}

QJsonObject makeGridCell(int row, int col, const QString &title, const QString &cellType,
                         const QJsonArray &components = QJsonArray(),
                         const QJsonArray &visualComponents = QJsonArray())
{
    QJsonObject cell;
    cell.insert(QStringLiteral("row"), row);
    cell.insert(QStringLiteral("col"), col);
    cell.insert(QStringLiteral("title"), title);
    cell.insert(QStringLiteral("cellType"), cellType);
    cell.insert(QStringLiteral("components"), components);
    if (cellType == QStringLiteral("canvas")) {
        cell.insert(QStringLiteral("canvas"), QJsonObject{
            {QStringLiteral("width"), 480},
            {QStringLiteral("height"), 480},
            {QStringLiteral("scaleMode"), QStringLiteral("uniform")}
        });
        cell.insert(QStringLiteral("visualComponents"), visualComponents);
    }
    return cell;
}

bool isRuntimeVisualType(const QString &type)
{
    return type.startsWith(QStringLiteral("Button"))
        || type.contains(QStringLiteral("Roller"))
        || type.contains(QStringLiteral("Potentiometer"))
        || type.contains(QStringLiteral("FNR"));
}

QString bindingBaseId(const QString &bindingId)
{
    const int dot = bindingId.indexOf(QLatin1Char('.'));
    return dot >= 0 ? bindingId.left(dot) : bindingId;
}

QString fieldRefTarget(const QJsonObject &component, const QString &key)
{
    const QJsonValue value = component.value(key);
    return value.isString() ? value.toString().trimmed() : QString();
}

} // namespace

LayoutManager::LayoutManager(QObject *parent)
    : QObject(parent)
{
    initDefaultDirectories();
}

LayoutManager *LayoutManager::create(QQmlEngine *qmlEngine, QJSEngine *jsEngine)
{
    Q_UNUSED(qmlEngine)
    Q_UNUSED(jsEngine)

    static LayoutManager instance;
    return &instance;
}

void LayoutManager::initDefaultDirectories()
{
    // 使用应用程序数据目录
    QString appDataPath = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);

    m_layoutsDirectory = appDataPath + "/layouts";
    m_templatesDirectory = appDataPath + "/templates";

    // 产品配置目录优先使用 DownloadTool 当前的 firmware 资产根；保留 products 作为旧版本回退。
    const QString appDir = QCoreApplication::applicationDirPath();
    const QString desktopPath = QStandardPaths::writableLocation(QStandardPaths::DesktopLocation);
    const QStringList assetCandidates = {
        QDir(appDir).filePath(QStringLiteral("firmware")),
        QDir(appDir).filePath(QStringLiteral("products")),
        QDir(appDir).filePath(QStringLiteral("../CANJoystickDownloadTool/firmware")),
        QDir(desktopPath).filePath(QStringLiteral("CANJoystickDownloadTool/firmware")),
        QDir(appDir).filePath(QStringLiteral("../CANJoystickDownloadTool/products")),
        QDir(desktopPath).filePath(QStringLiteral("CANJoystickDownloadTool/products"))
    };
    for (const QString &candidate : assetCandidates) {
        if (QDir(candidate).exists()) {
            m_productsDirectory = QDir::cleanPath(candidate);
            break;
        }
    }
    if (m_productsDirectory.isEmpty()) {
        m_productsDirectory = QDir(appDir).filePath(QStringLiteral("firmware"));
    }

    // 确保目录存在
    ensureDirectoryExists(m_layoutsDirectory);
    ensureDirectoryExists(m_templatesDirectory);
}

void LayoutManager::setLayoutsDirectory(const QString &path)
{
    if (m_layoutsDirectory != path) {
        m_layoutsDirectory = path;
        ensureDirectoryExists(path);
        emit layoutsDirectoryChanged();
    }
}

void LayoutManager::setTemplatesDirectory(const QString &path)
{
    if (m_templatesDirectory != path) {
        m_templatesDirectory = path;
        ensureDirectoryExists(path);
        emit templatesDirectoryChanged();
    }
}

void LayoutManager::setProductsDirectory(const QString &path)
{
    if (m_productsDirectory != path) {
        m_productsDirectory = path;
        emit productsDirectoryChanged();
    }
}

void LayoutManager::setHasUnsavedChanges(bool value)
{
    if (m_hasUnsavedChanges != value) {
        m_hasUnsavedChanges = value;
        emit hasUnsavedChangesChanged();
    }
}

// ========== 布局操作 ==========

bool LayoutManager::saveLayout(const QJsonObject &layoutJson, const QString &filePath)
{
    QString path = filePath.isEmpty() ? m_currentLayoutPath : filePath;

    if (path.isEmpty()) {
        emit errorOccurred(tr("No file path specified"));
        return false;
    }

    QJsonDocument doc(layoutJson);
    if (writeJsonFile(path, doc)) {
        m_currentLayoutPath = path;
        emit currentLayoutPathChanged();
        setHasUnsavedChanges(false);
        emit layoutSaved(path);
        return true;
    }

    return false;
}

QJsonObject LayoutManager::loadLayout(const QString &filePath)
{
    QJsonDocument doc = readJsonFile(filePath);
    if (doc.isNull() || !doc.isObject()) {
        emit errorOccurred(tr("Failed to load layout from: %1").arg(filePath));
        return QJsonObject();
    }

    m_currentLayoutPath = filePath;
    emit currentLayoutPathChanged();
    setHasUnsavedChanges(false);
    emit layoutLoaded(filePath);

    return doc.object();
}

QString LayoutManager::saveLayoutAs(const QJsonObject &layoutJson, const QString &suggestedName)
{
    QString fileName = suggestedName.isEmpty() ? "layout" : suggestedName;
    if (!fileName.endsWith(".json")) {
        fileName += ".json";
    }

    QString path = m_layoutsDirectory + "/" + fileName;

    // 如果文件已存在，添加数字后缀
    int counter = 1;
    while (QFile::exists(path)) {
        QString baseName = suggestedName.isEmpty() ? "layout" : suggestedName;
        path = m_layoutsDirectory + "/" + baseName + "_" + QString::number(counter) + ".json";
        counter++;
    }

    if (saveLayout(layoutJson, path)) {
        return path;
    }

    return QString();
}

QJsonArray LayoutManager::getLayoutFiles()
{
    QJsonArray files;
    QDir dir(m_layoutsDirectory);

    if (!dir.exists()) {
        return files;
    }

    QStringList filters;
    filters << "*.json";
    dir.setNameFilters(filters);
    dir.setSorting(QDir::Time | QDir::Reversed);

    for (const QFileInfo &fileInfo : dir.entryInfoList(QDir::Files)) {
        QJsonObject fileObj;
        fileObj["name"] = fileInfo.baseName();
        fileObj["path"] = fileInfo.absoluteFilePath();
        fileObj["modified"] = fileInfo.lastModified().toString(Qt::ISODate);
        fileObj["size"] = fileInfo.size();

        QJsonDocument productDoc = readJsonFile(fileInfo.absoluteFilePath());
        if (productDoc.isObject()) {
            QJsonObject product = productDoc.object().value("product").toObject();
            const QString productName = product.value("name").toString(product.value("model").toString(fileInfo.baseName()));
            fileObj["displayName"] = productName;
            fileObj["protocol"] = product.value("protocol").toString("j1939");
            fileObj["description"] = product.value("description").toString();
            fileObj["model"] = productName;
        }

        files.append(fileObj);
    }

    return files;
}

// ========== 卡片模板操作 ==========

bool LayoutManager::saveCardTemplates(const QJsonArray &templatesJson)
{
    QJsonObject wrapper;
    wrapper["version"] = "1.0";
    wrapper["templates"] = templatesJson;

    QString path = m_templatesDirectory + "/card_templates.json";
    QJsonDocument doc(wrapper);

    if (writeJsonFile(path, doc)) {
        emit templatesSaved();
        return true;
    }

    return false;
}

QJsonArray LayoutManager::loadCardTemplates()
{
    QString path = m_templatesDirectory + "/card_templates.json";
    QJsonDocument doc = readJsonFile(path);

    if (doc.isNull()) {
        // 文件不存在，返回空数组
        return QJsonArray();
    }

    if (doc.isObject()) {
        QJsonObject obj = doc.object();
        if (obj.contains("templates") && obj["templates"].isArray()) {
            emit templatesLoaded();
            return obj["templates"].toArray();
        }
    }

    return QJsonArray();
}

bool LayoutManager::saveCardTemplate(const QJsonObject &templateJson, const QString &fileName)
{
    QString safeName = fileName;
    safeName.replace(QRegularExpression("[^a-zA-Z0-9_-]"), "_");

    if (!safeName.endsWith(".json")) {
        safeName += ".json";
    }

    QString path = m_templatesDirectory + "/" + safeName;
    QJsonDocument doc(templateJson);

    return writeJsonFile(path, doc);
}

bool LayoutManager::deleteCardTemplate(const QString &fileName)
{
    QString path = m_templatesDirectory + "/" + fileName;
    if (!path.endsWith(".json")) {
        path += ".json";
    }

    QFile file(path);
    if (file.exists()) {
        return file.remove();
    }

    return false;
}

QJsonArray LayoutManager::getTemplateFiles()
{
    QJsonArray files;
    QDir dir(m_templatesDirectory);

    if (!dir.exists()) {
        return files;
    }

    QStringList filters;
    filters << "*.json";
    dir.setNameFilters(filters);

    for (const QFileInfo &fileInfo : dir.entryInfoList(QDir::Files)) {
        // 跳过主模板文件
        if (fileInfo.baseName() == "card_templates") {
            continue;
        }

        QJsonObject fileObj;
        fileObj["name"] = fileInfo.baseName();
        fileObj["path"] = fileInfo.absoluteFilePath();
        fileObj["modified"] = fileInfo.lastModified().toString(Qt::ISODate);
        files.append(fileObj);
    }

    return files;
}

// ========== 产品配置操作 ==========

QJsonArray LayoutManager::getProductFiles()
{
    QJsonArray files;
    QDir dir(m_productsDirectory);
    if (!dir.exists()) {
        return files;
    }

    QStringList paths;
    QDirIterator it(dir.absolutePath(),
                    QStringList{QStringLiteral("*.json")},
                    QDir::Files,
                    QDirIterator::Subdirectories);
    while (it.hasNext()) {
        paths.append(it.next());
    }
    paths.sort(Qt::CaseInsensitive);

    QMap<QString, ProductFileGroup> groupedFiles;
    for (const QString &path : paths) {
        const QFileInfo fileInfo(path);
        if (fileInfo.baseName() == QStringLiteral("card_templates")) {
            continue;
        }

        const QJsonDocument productDoc = readJsonFile(fileInfo.absoluteFilePath());
        const QJsonObject root = productDoc.isObject() ? productDoc.object() : QJsonObject();
        const QJsonObject product = root.value(QStringLiteral("product")).toObject();
        const QMap<QString, QString> customerNames = customerNamesFromProductConfig(root);
        const int defaultBaudRate = defaultBaudRateFromProductConfig(root);
        const QString productName = product.value(QStringLiteral("name"))
            .toString(product.value(QStringLiteral("model")).toString(fileInfo.completeBaseName()))
            .trimmed();
        if (productName.isEmpty()) {
            continue;
        }

        const QString baseProductName = productBaseNameFromVersionedName(productName);
        if (baseProductName.isEmpty()) {
            continue;
        }

        ProductFileGroup &group = groupedFiles[baseProductName.toCaseFolded()];
        if (group.model.isEmpty()) {
            group.displayName = baseProductName;
            group.model = baseProductName;
            group.protocol = product.value(QStringLiteral("protocol")).toString(QStringLiteral("j1939"));
            group.description = product.value(QStringLiteral("description")).toString();
        } else if (group.description.isEmpty()) {
            group.description = product.value(QStringLiteral("description")).toString();
        }
        for (auto customerIt = customerNames.cbegin(); customerIt != customerNames.cend(); ++customerIt) {
            collectCustomerName(group.customerNames, customerIt.value());
        }
        group.baudRates.insert(defaultBaudRate);

        const QJsonObject firmware = root.value(QStringLiteral("firmware")).toObject();
        const QString versionStatus = statusFromProductConfig(root);
        const QString versionCode = versionCodeFromProductConfig(root, fileInfo);
        const QString displayVersion = displayVersionFromProductConfig(root, fileInfo);
        QJsonObject versionObj;
        versionObj["name"] = fileInfo.baseName();
        versionObj["path"] = fileInfo.absoluteFilePath();
        versionObj["modified"] = fileInfo.lastModified().toString(Qt::ISODate);
        versionObj["size"] = fileInfo.size();
        versionObj["versionCode"] = versionCode;
        versionObj["displayVersion"] = displayVersion;
        versionObj["label"] = displayVersion.isEmpty() ? versionCode : displayVersion;
        versionObj["status"] = versionStatus;
        versionObj["deprecated"] = versionStatus == QStringLiteral("deprecated");
        versionObj["customerNames"] = customerNamesToJsonArray(customerNames);
        versionObj["defaultBaudRate"] = defaultBaudRate;
        versionObj["description"] = firmware.value(QStringLiteral("description"))
            .toString(product.value(QStringLiteral("description")).toString());
        group.versions.append(versionObj);
    }

    for (auto it = groupedFiles.cbegin(); it != groupedFiles.cend(); ++it) {
        ProductFileGroup group = it.value();
        if (group.versions.isEmpty()) {
            continue;
        }

        std::sort(group.versions.begin(), group.versions.end(), productVersionLessThan);

        QJsonArray versions;
        for (const QJsonObject &version : group.versions) {
            versions.append(version);
        }

        const QJsonObject defaultVersion = group.versions.constFirst();
        QJsonObject fileObj;
        fileObj["name"] = group.model;
        fileObj["path"] = defaultVersion.value(QStringLiteral("path")).toString();
        fileObj["modified"] = defaultVersion.value(QStringLiteral("modified")).toString();
        fileObj["size"] = defaultVersion.value(QStringLiteral("size")).toVariant().toLongLong();
        fileObj["displayName"] = group.displayName;
        fileObj["protocol"] = group.protocol;
        fileObj["description"] = group.description;
        fileObj["model"] = group.model;
        fileObj["versionCode"] = defaultVersion.value(QStringLiteral("versionCode")).toString();
        fileObj["displayVersion"] = defaultVersion.value(QStringLiteral("displayVersion")).toString();
        fileObj["label"] = defaultVersion.value(QStringLiteral("label")).toString();
        fileObj["status"] = defaultVersion.value(QStringLiteral("status")).toString();
        fileObj["deprecated"] = defaultVersion.value(QStringLiteral("deprecated")).toBool();
        fileObj["customerNames"] = customerNamesToJsonArray(group.customerNames);
        fileObj["defaultBaudRate"] = defaultVersion.value(QStringLiteral("defaultBaudRate")).toInt(250);
        fileObj["baudRates"] = baudRatesToJsonArray(group.baudRates);
        fileObj["versions"] = versions;
        files.append(fileObj);
    }

    return files;
}

QJsonArray LayoutManager::getCustomerOptions() const
{
    QJsonArray customers;
    const QString databasePath = customerDatabasePath();
    if (databasePath.isEmpty() || !isCanonicalProductionDatabaseFile(databasePath)) {
        return customers;
    }

    const QString connectionName = QStringLiteral("product_editor_customers_%1")
        .arg(QUuid::createUuid().toString(QUuid::WithoutBraces));

    {
        QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connectionName);
        db.setDatabaseName(databasePath);
        db.setConnectOptions(QStringLiteral("QSQLITE_OPEN_READONLY"));
        if (!db.open()) {
            qWarning() << "Failed to open customer database" << databasePath << db.lastError().text();
        } else if (databaseTableHasColumn(db, QStringLiteral("customers"), QStringLiteral("name"))) {
            const bool hasStatusColumn = databaseTableHasColumn(db, QStringLiteral("customers"), QStringLiteral("status"));
            QSqlQuery query(db);
            const QString statement = hasStatusColumn
                ? QStringLiteral(
                    "SELECT name FROM customers "
                    "WHERE name IS NOT NULL AND TRIM(name) <> '' "
                    "AND LOWER(COALESCE(status, 'active')) NOT IN ('deleted', 'removed') "
                    "ORDER BY name COLLATE NOCASE")
                : QStringLiteral(
                    "SELECT name FROM customers "
                    "WHERE name IS NOT NULL AND TRIM(name) <> '' "
                    "ORDER BY name COLLATE NOCASE");
            if (!query.exec(statement)) {
                qWarning() << "Failed to query customer database" << databasePath << query.lastError().text();
            } else {
                QMap<QString, QString> names;
                while (query.next()) {
                    collectCustomerName(names, query.value(0).toString());
                }
                customers = customerNamesToJsonArray(names);
            }
            db.close();
        } else {
            qWarning() << "Customer database has no customers.name table" << databasePath;
            db.close();
        }
    }

    QSqlDatabase::removeDatabase(connectionName);
    return customers;
}

QJsonObject LayoutManager::loadProductConfig(const QString &filePath)
{
    QJsonDocument doc = readJsonFile(filePath);
    if (doc.isNull() || !doc.isObject()) {
        emit errorOccurred(tr("Failed to load product config: %1").arg(filePath));
        return QJsonObject();
    }

    emit productConfigLoaded(filePath);
    return doc.object();
}

QJsonObject LayoutManager::validateProductConfig(const QJsonObject &configJson) const
{
    QJsonArray errors;
    QJsonArray warnings;

    const QJsonObject product = configJson.value(QStringLiteral("product")).toObject();
    const QString productName = product.value(QStringLiteral("name")).toString().trimmed();
    const QString protocol = normalizedProductEditorProtocol(product.value(QStringLiteral("protocol")).toString(QStringLiteral("j1939")));
    if (productName.isEmpty()) {
        appendMessage(errors, tr("Product name is required"));
    }
    if (!configJson.contains(QStringLiteral("schemaVersion"))) {
        appendMessage(warnings, tr("schemaVersion is missing; new products should use schemaVersion 3"));
    }

    if (protocol == QStringLiteral("can")) {
        // Generic CAN mapping uses can.messages[].canId and does not require protocol-specific address metadata.
    } else if (protocol == QStringLiteral("j1939")) {
        if (product.value(QStringLiteral("sourceAddress")).toString().trimmed().isEmpty()) {
            appendMessage(errors, tr("J1939 product requires sourceAddress"));
        }
    } else {
        if (!product.contains(QStringLiteral("nodeId"))) {
            appendMessage(errors, tr("CANopen product requires nodeId"));
        }
        const QJsonObject canopen = configJson.value(QStringLiteral("can")).toObject().value(QStringLiteral("canopen")).toObject();
        if (!canopen.contains(QStringLiteral("nodeId"))) {
            appendMessage(errors, tr("CANopen product requires can.canopen.nodeId"));
        }
    }

    const QJsonArray messages = configJson.value(QStringLiteral("can")).toObject().value(QStringLiteral("messages")).toArray();
    const QJsonArray components = configJson.value(QStringLiteral("components")).toArray();
    if (messages.isEmpty()) {
        appendMessage(errors, tr("can.messages must not be empty"));
    }
    if (components.isEmpty()) {
        appendMessage(errors, tr("components must not be empty"));
    }

    QSet<QString> fieldRefs;
    QMap<QString, QString> fieldTypes;
    QMap<QString, int> buttonFieldCounts;
    for (const QJsonValue &messageValue : messages) {
        const QJsonObject message = messageValue.toObject();
        const QString messageId = message.value(QStringLiteral("id")).toString().trimmed();
        if (messageId.isEmpty()) {
            appendMessage(errors, tr("Every CAN message requires an id"));
            continue;
        }

        if (protocol == QStringLiteral("j1939")) {
            if (message.value(QStringLiteral("pgn")).toString().trimmed().isEmpty()) {
                appendMessage(errors, tr("J1939 message %1 requires pgn").arg(messageId));
            }
        } else if (message.value(QStringLiteral("canId")).toString().trimmed().isEmpty()) {
            appendMessage(errors, tr("CANopen message %1 requires canId").arg(messageId));
        }

        const QJsonArray fields = message.value(QStringLiteral("fields")).toArray();
        if (fields.isEmpty()) {
            appendMessage(warnings, tr("Message %1 has no fields").arg(messageId));
        }
        for (const QJsonValue &fieldValue : fields) {
            const QJsonObject field = fieldValue.toObject();
            const QString fieldName = field.value(QStringLiteral("name")).toString().trimmed();
            const QString type = field.value(QStringLiteral("type")).toString().trimmed();
            if (fieldName.isEmpty()) {
                appendMessage(errors, tr("Message %1 has a field without name").arg(messageId));
                continue;
            }
            const QString ref = messageId + QLatin1Char('.') + fieldName;
            fieldRefs.insert(ref);
            fieldTypes.insert(ref, type);
            if (type == QStringLiteral("buttonGroup")) {
                buttonFieldCounts.insert(ref, field.value(QStringLiteral("buttonCount")).toInt());
            }
        }
    }

    QSet<QString> componentIds;
    QMap<QString, QString> componentTypes;
    QMap<QString, int> buttonComponentCounts;
    QMap<QString, QString> buttonComponentBySource;
    QMap<QString, QSet<int>> fnrButtonMappingsBySource;
    const auto validateRef = [&](const QString &ref, const QString &context, bool required) {
        if (ref.isEmpty()) {
            if (required) {
                appendMessage(errors, tr("%1 requires a field reference").arg(context));
            }
            return;
        }
        if (!fieldRefs.contains(ref)) {
            appendMessage(errors, tr("%1 references missing field %2").arg(context, ref));
        }
    };

    for (const QJsonValue &componentValue : components) {
        const QJsonObject component = componentValue.toObject();
        const QString id = component.value(QStringLiteral("id")).toString().trimmed();
        const QString type = component.value(QStringLiteral("type")).toString().trimmed();
        if (id.isEmpty()) {
            appendMessage(errors, tr("Every component requires an id"));
            continue;
        }
        if (componentIds.contains(id)) {
            appendMessage(errors, tr("Duplicate component id: %1").arg(id));
        }
        componentIds.insert(id);
        componentTypes.insert(id, type);

        if (type == QStringLiteral("joystick")) {
            const QJsonObject xAxis = component.value(QStringLiteral("xAxis")).toObject();
            const QJsonObject yAxis = component.value(QStringLiteral("yAxis")).toObject();
            validateRef(xAxis.value(QStringLiteral("position")).toString(), tr("Joystick %1 xAxis").arg(id), true);
            validateRef(xAxis.value(QStringLiteral("status")).toString(), tr("Joystick %1 xAxis status").arg(id), false);
            validateRef(yAxis.value(QStringLiteral("position")).toString(), tr("Joystick %1 yAxis").arg(id), true);
            validateRef(yAxis.value(QStringLiteral("status")).toString(), tr("Joystick %1 yAxis status").arg(id), false);
        } else if (type == QStringLiteral("buttonGroup")) {
            const QString source = fieldRefTarget(component, QStringLiteral("source"));
            validateRef(source, tr("Button group %1").arg(id), true);
            const int componentCount = component.value(QStringLiteral("count")).toInt();
            if (componentCount <= 0) {
                appendMessage(errors, tr("Button group %1 requires count > 0").arg(id));
            }
            buttonComponentCounts.insert(id, componentCount);
            buttonComponentBySource.insert(source, id);
            if (buttonFieldCounts.contains(source) && buttonFieldCounts.value(source) != componentCount) {
                appendMessage(errors, tr("Button group %1 count does not match %2 buttonCount").arg(id, source));
            }
        } else if (type == QStringLiteral("roller")
                   || type == QStringLiteral("potentiometer")) {
            validateRef(fieldRefTarget(component, QStringLiteral("position")), tr("Roller %1").arg(id), true);
            validateRef(fieldRefTarget(component, QStringLiteral("status")), tr("Roller %1 status").arg(id), false);
        } else if (type == QStringLiteral("counter") || type == QStringLiteral("indicator")) {
            validateRef(fieldRefTarget(component, QStringLiteral("source")), tr("Component %1").arg(id), true);
        } else if (type == QStringLiteral("fnrSwitch")) {
            const QJsonObject buttonMapping = component.value(QStringLiteral("buttonMapping")).toObject();
            if (!buttonMapping.isEmpty()) {
                const QString source = buttonMapping.value(QStringLiteral("source")).toString().trimmed();
                validateRef(source, tr("FNR %1 buttonMapping").arg(id), true);
                const QStringList mappingKeys{
                    QStringLiteral("forward"),
                    QStringLiteral("neutral"),
                    QStringLiteral("reverse")
                };
                for (const QString &key : mappingKeys) {
                    const int index = buttonMapping.value(key).toInt(-1);
                    if (index >= 0) {
                        fnrButtonMappingsBySource[source].insert(index);
                    }
                }
            } else {
                validateRef(fieldRefTarget(component, QStringLiteral("source")), tr("FNR %1").arg(id), true);
            }
        }
    }

    QMap<QString, QSet<int>> buttonBindings;
    for (auto it = fnrButtonMappingsBySource.cbegin(); it != fnrButtonMappingsBySource.cend(); ++it) {
        const QString componentId = buttonComponentBySource.value(it.key());
        if (componentId.isEmpty()) {
            continue;
        }
        for (int index : it.value()) {
            if (index < 0 || index >= buttonComponentCounts.value(componentId)) {
                appendMessage(errors, tr("FNR button mapping %1 is outside button group %2 range").arg(index).arg(componentId));
            } else {
                buttonBindings[componentId].insert(index);
            }
        }
    }

    const QJsonArray cells = configJson.value(QStringLiteral("layout")).toObject()
        .value(QStringLiteral("grid")).toObject()
        .value(QStringLiteral("cells")).toArray();
    for (const QJsonValue &cellValue : cells) {
        const QJsonArray visuals = cellValue.toObject().value(QStringLiteral("visualComponents")).toArray();
        for (const QJsonValue &visualValue : visuals) {
            const QJsonObject visual = visualValue.toObject();
            const QString visualType = visual.value(QStringLiteral("type")).toString();
            const QString bindingId = visual.value(QStringLiteral("bindingId")).toString().trimmed();
            if (!isRuntimeVisualType(visualType)) {
                continue;
            }
            if (bindingId.isEmpty()) {
                appendMessage(errors, tr("Runtime visual component %1 has no bindingId").arg(visualType));
                continue;
            }

            const QString baseId = bindingBaseId(bindingId);
            if (!componentIds.contains(baseId)) {
                appendMessage(errors, tr("bindingId %1 references missing component %2").arg(bindingId, baseId));
                continue;
            }

            if (componentTypes.value(baseId) == QStringLiteral("buttonGroup")) {
                const int dot = bindingId.indexOf(QLatin1Char('.'));
                bool ok = false;
                const int buttonIndex = dot >= 0 ? bindingId.mid(dot + 1).toInt(&ok) : -1;
                if (!ok || buttonIndex < 0 || buttonIndex >= buttonComponentCounts.value(baseId)) {
                    appendMessage(errors, tr("Button binding %1 is outside button group range").arg(bindingId));
                } else {
                    buttonBindings[baseId].insert(buttonIndex);
                }
            }
        }
    }

    for (auto it = buttonComponentCounts.cbegin(); it != buttonComponentCounts.cend(); ++it) {
        const int boundCount = buttonBindings.value(it.key()).size();
        if (boundCount != it.value()) {
            appendMessage(warnings, tr("Button group %1 has %2 visual bindings, expected %3")
                .arg(it.key())
                .arg(boundCount)
                .arg(it.value()));
        }
    }

    return QJsonObject{
        {QStringLiteral("ok"), errors.isEmpty()},
        {QStringLiteral("errors"), errors},
        {QStringLiteral("warnings"), warnings}
    };
}

QJsonObject LayoutManager::buildStandardProductConfig(const QJsonObject &spec) const
{
    const QString productName = sanitizeProductModel(spec.value(QStringLiteral("model")).toString());
    const QString description = spec.value(QStringLiteral("description")).toString().trimmed();
    const QString customerName = spec.value(QStringLiteral("customerName")).toString().trimmed();
    const QString calibrationMode = spec.value(QStringLiteral("calibrationMode")).toString(QStringLiteral("centerOnly")).trimmed();
    const int baudRate = boundedJsonInt(spec, QStringLiteral("baudRate"), 250, 10, 1000);
    const int buttonCount = boundedJsonInt(spec, QStringLiteral("buttonCount"), 10, 0, 12);
    const int rollerCount = boundedJsonInt(spec, QStringLiteral("rollerCount"), 4, 0, 4);

    QJsonObject product;
    product.insert(QStringLiteral("name"), productName);
    product.insert(QStringLiteral("description"), description);
    product.insert(QStringLiteral("protocol"), QStringLiteral("j1939"));
    product.insert(QStringLiteral("canFrameFormat"), QStringLiteral("extended"));
    product.insert(QStringLiteral("canAddress"), QStringLiteral("0x0CFDD633"));
    product.insert(QStringLiteral("sourceAddress"), QStringLiteral("0x33"));

    if (!customerName.isEmpty()) {
        product.insert(QStringLiteral("customerBindings"), QJsonArray{
            QJsonObject{
                {QStringLiteral("name"), customerName},
                {QStringLiteral("isDefault"), true},
                {QStringLiteral("note"), QStringLiteral("SOP configured customer")}
            }
        });
    }

    QJsonObject calibration;
    calibration.insert(QStringLiteral("mode"), calibrationMode.isEmpty() ? QStringLiteral("centerOnly") : calibrationMode);
    calibration.insert(QStringLiteral("transport"), QStringLiteral("j1939VendorPgn"));
    calibration.insert(QStringLiteral("allowedInNormalModeReadOnly"), true);

    QJsonObject can;
    can.insert(QStringLiteral("defaultBaudRate"), baudRate);
    QJsonArray messages;
    messages.append(makeMessage(
        QStringLiteral("bjm"),
        QStringLiteral("基本摇杆报文 BJM1"),
        QStringLiteral("pgn"),
        QStringLiteral("0xFDD6"),
        j1939BjmFields(buttonCount)));
    if (rollerCount > 0) {
        messages.append(makeMessage(
            QStringLiteral("ejm"),
            QStringLiteral("扩展摇杆报文 EJM1"),
            QStringLiteral("pgn"),
            QStringLiteral("0xFDD7"),
            j1939EjmFields(rollerCount)));
    }
    messages.append(makeMessage(
        QStringLiteral("addressClaim"),
        QStringLiteral("地址声明"),
        QString(),
        QStringLiteral("0x0EEFF"),
        QJsonArray{makeField(QStringLiteral("identity"), 0, 0, 21,
                             QStringLiteral("identity"), QString(), QStringLiteral("little"))}));
    can.insert(QStringLiteral("messages"), messages);

    QJsonArray components;
    QJsonObject joystick;
    joystick.insert(QStringLiteral("id"), QStringLiteral("joystick_xy"));
    joystick.insert(QStringLiteral("type"), QStringLiteral("joystick"));
    joystick.insert(QStringLiteral("label"), QStringLiteral("XY 轴 (BJM)"));
    joystick.insert(QStringLiteral("xAxis"), QJsonObject{
        {QStringLiteral("position"), QStringLiteral("bjm.xPos")},
        {QStringLiteral("status"), QStringLiteral("bjm.xStatus")}
    });
    joystick.insert(QStringLiteral("yAxis"), QJsonObject{
        {QStringLiteral("position"), QStringLiteral("bjm.yPos")},
        {QStringLiteral("status"), QStringLiteral("bjm.yStatus")}
    });
    components.append(joystick);

    QJsonArray buttonCellComponents;
    if (buttonCount > 0) {
        components.append(makeButtonComponent(buttonCount, QStringLiteral("bjm.buttons")));
        buttonCellComponents.append(QStringLiteral("buttons"));
    }

    QJsonArray rollerCellComponents;
    QJsonArray rollerVisuals;
    for (int index = 0; index < rollerCount; ++index) {
        const QString componentId = rollerComponentId(QStringLiteral("j1939"), index);
        const QString label = QStringLiteral("滚轮%1").arg(index + 1);

        QJsonObject roller;
        roller.insert(QStringLiteral("id"), componentId);
        roller.insert(QStringLiteral("type"), QStringLiteral("roller"));
        roller.insert(QStringLiteral("label"), label);
        roller.insert(QStringLiteral("orientation"), QStringLiteral("vertical"));
        roller.insert(QStringLiteral("position"), rollerPositionRef(QStringLiteral("j1939"), index));
        roller.insert(QStringLiteral("status"), rollerStatusRef(QStringLiteral("j1939"), index));
        components.append(roller);
        rollerCellComponents.append(componentId);

        rollerVisuals.append(makeVisualComponent(
            QStringLiteral("VerticalRoller"),
            componentId,
            37 + index * 100,
            120,
            QJsonObject{
                {QStringLiteral("label"), label},
                {QStringLiteral("value"), 0}
            }));
    }

    QJsonArray cells;
    cells.append(makeGridCell(0, 0, QStringLiteral("正面"), QStringLiteral("canvas"),
                              buttonCellComponents, makeButtonVisuals(buttonCount)));
    cells.append(makeGridCell(0, 1, QStringLiteral("总线统计"), QStringLiteral("busStats"),
                              QJsonArray{QStringLiteral("busStats")}));
    cells.append(makeGridCell(1, 0, QStringLiteral("背面"), QStringLiteral("canvas"),
                              rollerCellComponents, rollerVisuals));
    cells.append(makeGridCell(1, 1, QStringLiteral("记录信息"), QStringLiteral("recordInfo"), QJsonArray{QStringLiteral("recordInfo")}));

    QJsonObject layout;
    layout.insert(QStringLiteral("left"), QJsonObject{
        {QStringLiteral("component"), QStringLiteral("joystick_xy")},
        {QStringLiteral("widthRatio"), 0.52}
    });
    layout.insert(QStringLiteral("grid"), QJsonObject{
        {QStringLiteral("rows"), 2},
        {QStringLiteral("columns"), 2},
        {QStringLiteral("cells"), cells}
    });

    QJsonObject editor;
    editor.insert(QStringLiteral("profile"), QStringLiteral("j1939Generic"));
    editor.insert(QStringLiteral("creationFlow"), QStringLiteral("genericJ1939"));
    editor.insert(QStringLiteral("manualMappingRequired"), false);
    editor.insert(QStringLiteral("mappingStatus"), QStringLiteral("complete"));
    editor.insert(QStringLiteral("buttonCount"), buttonCount);
    editor.insert(QStringLiteral("rollerCount"), rollerCount);
    editor.insert(QStringLiteral("fnrEnabled"), false);

    QJsonObject config;
    config.insert(QStringLiteral("schemaVersion"), 2);
    config.insert(QStringLiteral("version"), QStringLiteral("2.0"));
    config.insert(QStringLiteral("product"), product);
    config.insert(QStringLiteral("calibration"), calibration);
    config.insert(QStringLiteral("can"), can);
    config.insert(QStringLiteral("components"), components);
    config.insert(QStringLiteral("layout"), layout);
    config.insert(QStringLiteral("editor"), editor);
    return config;
}

bool LayoutManager::saveProductConfig(const QJsonObject &configJson, const QString &filePath)
{
    if (filePath.isEmpty()) {
        emit errorOccurred(tr("No file path specified for product config"));
        return false;
    }

    const QFileInfo targetFileInfo(filePath);
    const QJsonObject normalizedConfig = configWithDefaultVersionMetadata(configJson, targetFileInfo);

    if (!isManualMappingDraft(normalizedConfig)) {
        const QJsonObject validation = validateProductConfig(normalizedConfig);
        if (!validation.value(QStringLiteral("ok")).toBool()) {
        const QJsonArray errors = validation.value(QStringLiteral("errors")).toArray();
        QStringList errorText;
        for (const QJsonValue &error : errors) {
            errorText.append(error.toString());
        }
        emit errorOccurred(tr("Product config validation failed: %1").arg(errorText.join(QStringLiteral("; "))));
        return false;
        }
    }

    return persistProductConfig(normalizedConfig, filePath);
}

QString LayoutManager::sanitizeProductModel(const QString &model) const
{
    QString safeModel = model.trimmed();
    if (safeModel.endsWith(".json", Qt::CaseInsensitive)) {
        safeModel.chop(5);
    }

    safeModel.replace(QRegularExpression(QStringLiteral("[<>:\"/\\\\|?*\\x00-\\x1F]")), QStringLiteral("_"));

    while (!safeModel.isEmpty() && (safeModel.endsWith('.') || safeModel.endsWith(' '))) {
        safeModel.chop(1);
    }

    return safeModel.trimmed();
}

bool LayoutManager::productConfigExists(const QString &model) const
{
    const QString path = productConfigPath(model);
    return !path.isEmpty() && QFileInfo::exists(path);
}

QString LayoutManager::productConfigVersionPath(const QString &model, const QString &versionCode) const
{
    const QString safeModel = sanitizeProductModel(model);
    const QString baseModel = productBaseNameFromVersionedName(safeModel);
    const QString safeVersionCode = normalizedVersionCode(versionCode);
    if (baseModel.isEmpty() || safeVersionCode.isEmpty()) {
        return QString();
    }

    const QDir dir(m_productsDirectory);
    const QString fileName = QStringLiteral("%1_%2.json").arg(baseModel, safeVersionCode);
    return QDir(dir.filePath(baseModel)).filePath(fileName);
}

bool LayoutManager::productConfigVersionExists(const QString &model, const QString &versionCode) const
{
    const QString path = productConfigVersionPath(model, versionCode);
    return !path.isEmpty() && QFileInfo::exists(path);
}

QString LayoutManager::productConfigPath(const QString &model) const
{
    const QString safeModel = sanitizeProductModel(model);
    const QString baseModel = productBaseNameFromVersionedName(safeModel);
    if (safeModel.isEmpty()) {
        return QString();
    }

    const QDir dir(m_productsDirectory);
    if (dir.exists()) {
        QStringList paths;
        QDirIterator it(dir.absolutePath(),
                        QStringList{QStringLiteral("*.json")},
                        QDir::Files,
                        QDirIterator::Subdirectories);
        while (it.hasNext()) {
            paths.append(it.next());
        }
        paths.sort(Qt::CaseInsensitive);

        for (const QString &path : paths) {
            const QFileInfo fileInfo(path);
            const QString fileBaseName = fileInfo.completeBaseName();
            if (fileBaseName.compare(safeModel, Qt::CaseInsensitive) == 0
                || fileBaseName.compare(baseModel, Qt::CaseInsensitive) == 0
                || fileBaseName.startsWith(baseModel + QStringLiteral("_V"), Qt::CaseInsensitive)) {
                return fileInfo.absoluteFilePath();
            }

            const QJsonDocument doc = readJsonFileQuiet(fileInfo.absoluteFilePath());
            const QString productName = doc.object()
                                            .value(QStringLiteral("product"))
                                            .toObject()
                                            .value(QStringLiteral("name"))
                                            .toString()
                                            .trimmed();
            if (productBaseNameFromVersionedName(productName).compare(baseModel, Qt::CaseInsensitive) == 0) {
                return fileInfo.absoluteFilePath();
            }
        }
    }

    return QDir(dir.filePath(baseModel)).filePath(baseModel + QStringLiteral("_V1.json"));
}

bool LayoutManager::openProductConfigFile(const QString &model) const
{
    const QString filePath = productConfigPath(model);
    if (filePath.isEmpty() || !QFileInfo::exists(filePath)) {
        return false;
    }
    return QDesktopServices::openUrl(QUrl::fromLocalFile(filePath));
}

bool LayoutManager::openProductConfigPath(const QString &filePath)
{
    const QString cleanPath = QDir::cleanPath(filePath);
    if (cleanPath.isEmpty() || !QFileInfo::exists(cleanPath)) {
        emit errorOccurred(tr("Product config file not found: %1").arg(filePath));
        return false;
    }
    return QDesktopServices::openUrl(QUrl::fromLocalFile(cleanPath));
}

bool LayoutManager::saveProductConfigAs(const QJsonObject &configJson, const QString &model)
{
    const QString safeModel = sanitizeProductModel(model);
    if (safeModel.isEmpty()) {
        emit errorOccurred(tr("Product name cannot be empty"));
        return false;
    }

    const QString filePath = productConfigPath(safeModel);
    const QString targetDirectory = QFileInfo(filePath).absolutePath();
    if (!ensureDirectoryExists(targetDirectory)) {
        emit errorOccurred(tr("Failed to create products directory: %1").arg(targetDirectory));
        return false;
    }
    if (QFileInfo::exists(filePath)) {
        emit errorOccurred(tr("Product config already exists: %1").arg(filePath));
        return false;
    }

    const QFileInfo targetFileInfo(filePath);
    const QJsonObject normalizedConfig = configWithDefaultVersionMetadata(configJson, targetFileInfo);

    if (!isManualMappingDraft(normalizedConfig)) {
        const QJsonObject validation = validateProductConfig(normalizedConfig);
        if (!validation.value(QStringLiteral("ok")).toBool()) {
        const QJsonArray errors = validation.value(QStringLiteral("errors")).toArray();
        QStringList errorText;
        for (const QJsonValue &error : errors) {
            errorText.append(error.toString());
        }
        emit errorOccurred(tr("Product config validation failed: %1").arg(errorText.join(QStringLiteral("; "))));
        return false;
        }
    }

    return persistProductConfig(normalizedConfig, filePath);
}

bool LayoutManager::saveProductConfigVersionAs(const QJsonObject &configJson,
                                               const QString &model,
                                               const QString &versionCode)
{
    const QString safeModel = sanitizeProductModel(model);
    if (safeModel.isEmpty()) {
        emit errorOccurred(tr("Product name cannot be empty"));
        return false;
    }

    const QString filePath = productConfigVersionPath(safeModel, versionCode);
    const QString targetDirectory = QFileInfo(filePath).absolutePath();
    if (!ensureDirectoryExists(targetDirectory)) {
        emit errorOccurred(tr("Failed to create products directory: %1").arg(targetDirectory));
        return false;
    }
    if (QFileInfo::exists(filePath)) {
        emit errorOccurred(tr("Product config already exists: %1").arg(filePath));
        return false;
    }

    const QFileInfo fileInfo(filePath);
    const QJsonObject normalizedConfig = configWithDefaultVersionMetadata(configJson, fileInfo);

    if (!isManualMappingDraft(normalizedConfig)) {
        const QJsonObject validation = validateProductConfig(normalizedConfig);
        if (!validation.value(QStringLiteral("ok")).toBool()) {
        const QJsonArray errors = validation.value(QStringLiteral("errors")).toArray();
        QStringList errorText;
        for (const QJsonValue &error : errors) {
            errorText.append(error.toString());
        }
        emit errorOccurred(tr("Product config validation failed: %1").arg(errorText.join(QStringLiteral("; "))));
        return false;
        }
    }

    return persistProductConfig(normalizedConfig, filePath);
}

bool LayoutManager::persistProductConfig(const QJsonObject &configJson, const QString &filePath)
{
    const QFileInfo existingInfo(filePath);
    const bool existed = existingInfo.exists();
    QByteArray previousContents;
    if (existed) {
        QFile existing(filePath);
        if (!existing.open(QIODevice::ReadOnly)) {
            emit errorOccurred(tr("Failed to read existing product config before saving: %1")
                                   .arg(filePath));
            return false;
        }
        previousContents = existing.readAll();
    }

    if (isManualMappingDraft(configJson) && existed) {
        const QJsonDocument previousDocument = QJsonDocument::fromJson(previousContents);
        if (!previousDocument.isObject() || !isManualMappingDraft(previousDocument.object())) {
            emit errorOccurred(tr("A manual mapping draft cannot overwrite a released product config: %1")
                                   .arg(filePath));
            return false;
        }
    }

    if (!writeJsonFile(filePath, QJsonDocument(configJson)))
        return false;

    if (isManualMappingDraft(configJson)) {
        emit productConfigSaved(filePath);
        return true;
    }

    if (syncProductConfigToDatabase(configJson, filePath)) {
        emit productConfigSaved(filePath);
        return true;
    }

    bool restored = false;
    if (existed) {
        QSaveFile restore(filePath);
        restored = restore.open(QIODevice::WriteOnly)
            && restore.write(previousContents) == previousContents.size()
            && restore.commit();
    } else {
        restored = !QFileInfo::exists(filePath) || QFile::remove(filePath);
    }
    if (!restored) {
        emit errorOccurred(tr("Database sync failed and the previous product config could not be restored: %1")
                               .arg(filePath));
    }
    return false;
}

namespace {

bool isCanonicalProductionDatabaseFile(const QString &path)
{
    if (!QFileInfo(path).isFile())
        return false;

    const QString connectionName = QStringLiteral("product_database_probe_%1")
        .arg(QUuid::createUuid().toString(QUuid::WithoutBraces));
    bool canonical = false;
    {
        QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connectionName);
        db.setConnectOptions(QStringLiteral("QSQLITE_OPEN_READONLY"));
        db.setDatabaseName(path);
        if (db.open()) {
            QSqlQuery version(db);
            QSqlQuery ledger(db);
            canonical = version.exec(QStringLiteral("PRAGMA user_version"))
                && version.next()
                && version.value(0).toInt() == kSupportedProductionDatabaseVersion
                && ledger.exec(QStringLiteral(
                    "SELECT 1 FROM sqlite_master WHERE type = 'table' "
                    "AND name = 'schema_migrations' LIMIT 1"))
                && ledger.next();
            db.close();
        }
    }
    QSqlDatabase::removeDatabase(connectionName);
    return canonical;
}

} // namespace

// ========== 工具方法 ==========

QString LayoutManager::toJsonString(const QJsonObject &obj, bool compact)
{
    QJsonDocument doc(obj);
    return QString::fromUtf8(doc.toJson(compact ? QJsonDocument::Compact : QJsonDocument::Indented));
}

QJsonObject LayoutManager::fromJsonString(const QString &jsonStr)
{
    QJsonParseError error;
    QJsonDocument doc = QJsonDocument::fromJson(jsonStr.toUtf8(), &error);

    if (error.error != QJsonParseError::NoError) {
        emit errorOccurred(tr("JSON parse error: %1").arg(error.errorString()));
        return QJsonObject();
    }

    if (!doc.isObject()) {
        emit errorOccurred(tr("JSON is not an object"));
        return QJsonObject();
    }

    return doc.object();
}

bool LayoutManager::ensureDirectoryExists(const QString &path)
{
    QDir dir(path);
    if (!dir.exists()) {
        return dir.mkpath(".");
    }
    return true;
}

QString LayoutManager::productionDatabasePath() const
{
    const QString envDatabasePath = qEnvironmentVariable("CANJOYSTICK_DATABASE_PATH").trimmed();
    if (!envDatabasePath.isEmpty())
        return QDir::fromNativeSeparators(QFileInfo(envDatabasePath).absoluteFilePath());

    const QString envDataDir = qEnvironmentVariable("CANJOYSTICK_DATA_DIR").trimmed();
    if (!envDataDir.isEmpty())
        return QDir::fromNativeSeparators(
            QDir::cleanPath(QDir(envDataDir).filePath(QStringLiteral("production_data.db"))));

    QStringList candidates;

    const QString appDir = QCoreApplication::applicationDirPath();
    candidates.append(QDir(appDir).filePath(QStringLiteral("data/production_data.db")));

    QDir projectDir(QDir(m_productsDirectory).absolutePath());
    if (projectDir.cdUp()) {
        candidates.append(projectDir.filePath(QStringLiteral("data/production_data.db")));
    }

    candidates.append(QDir(appDir).filePath(QStringLiteral("../CANJoystickDownloadTool/data/production_data.db")));

    const QString desktopPath = QStandardPaths::writableLocation(QStandardPaths::DesktopLocation);
    candidates.append(QDir(desktopPath).filePath(QStringLiteral("CANJoystickDownloadTool/data/production_data.db")));

    for (const QString &candidate : candidates) {
        const QString cleanPath = QDir::cleanPath(candidate);
        if (isCanonicalProductionDatabaseFile(cleanPath)) {
            return QDir::fromNativeSeparators(cleanPath);
        }
    }

    return candidates.isEmpty()
        ? QString()
        : QDir::fromNativeSeparators(QDir::cleanPath(candidates.constFirst()));
}

QString LayoutManager::customerDatabasePath() const
{
    return productionDatabasePath();
}

QString LayoutManager::productConfigPathForDatabase(const QString &filePath) const
{
    const QFileInfo fileInfo(filePath);
    const QDir assetDir(m_productsDirectory);
    const QString relativePath = assetDir.relativeFilePath(fileInfo.absoluteFilePath());
    const bool isInsideAssetDirectory = !relativePath.startsWith(QStringLiteral("../"))
        && !relativePath.startsWith(QStringLiteral("..\\"))
        && !QDir::isAbsolutePath(relativePath);
    const QString assetRootName = assetRootNameForDirectory(m_productsDirectory);

    const QString databasePath = isInsideAssetDirectory
        ? QDir(assetRootName).filePath(relativePath)
        : QDir(assetRootName).filePath(fileInfo.fileName());
    return QDir::fromNativeSeparators(QDir::cleanPath(databasePath));
}

bool LayoutManager::validateProductionDatabaseSchema(QSqlDatabase &db)
{
    QSqlQuery query(db);
    if (!query.exec(QStringLiteral("PRAGMA foreign_keys = ON"))
        || !query.exec(QStringLiteral("PRAGMA busy_timeout = 3000"))
        || !query.exec(QStringLiteral("PRAGMA user_version"))
        || !query.next()) {
        emit errorOccurred(tr("Failed to inspect production database: %1")
                               .arg(query.lastError().text()));
        return false;
    }
    const int databaseVersion = query.value(0).toInt();
    if (databaseVersion != kSupportedProductionDatabaseVersion) {
        emit errorOccurred(tr("Unsupported production database version %1; expected %2. Open it with the matching DownloadTool first.")
                               .arg(databaseVersion)
                               .arg(kSupportedProductionDatabaseVersion));
        return false;
    }

    const QMap<QString, QStringList> requiredColumns = {
        {QStringLiteral("schema_migrations"),
         {QStringLiteral("version"), QStringLiteral("migration_name")}},
        {QStringLiteral("products"),
         {QStringLiteral("id"), QStringLiteral("name"), QStringLiteral("protocol"),
          QStringLiteral("status"), QStringLiteral("description"),
          QStringLiteral("calibration_mode"), QStringLiteral("calibration_transport"),
          QStringLiteral("allowed_in_normal_mode_read_only"), QStringLiteral("updated_at")}},
        {QStringLiteral("product_config_versions"),
         {QStringLiteral("id"), QStringLiteral("product_id"), QStringLiteral("version_code"),
          QStringLiteral("config_file"), QStringLiteral("config_sha256"),
          QStringLiteral("is_default"), QStringLiteral("updated_at")}},
        {QStringLiteral("customers"),
         {QStringLiteral("id"), QStringLiteral("name"), QStringLiteral("type"),
          QStringLiteral("status")}},
        {QStringLiteral("product_customer_bindings"),
         {QStringLiteral("product_id"), QStringLiteral("customer_id"),
          QStringLiteral("is_default"), QStringLiteral("updated_at")}}
    };
    for (auto table = requiredColumns.cbegin(); table != requiredColumns.cend(); ++table) {
        for (const QString &column : table.value()) {
            if (!databaseTableHasColumn(db, table.key(), column)) {
                emit errorOccurred(tr("Production database is missing required field %1.%2. Open it with DownloadTool to repair it.")
                                       .arg(table.key(), column));
                return false;
            }
        }
    }

    return true;
}

bool LayoutManager::syncProductConfigToDatabase(const QJsonObject &configJson, const QString &filePath)
{
    const QFileInfo fileInfo(filePath);
    const QJsonObject product = configJson.value(QStringLiteral("product")).toObject();
    const QJsonObject calibration = configJson.value(QStringLiteral("calibration")).toObject();

    QString productName = product.value(QStringLiteral("name")).toString().trimmed();
    if (productName.isEmpty()) {
        productName = fileInfo.completeBaseName().trimmed();
    }
    productName = productBaseNameFromVersionedName(productName);
    if (productName.isEmpty()) {
        emit errorOccurred(tr("Product name cannot be empty"));
        return false;
    }

    const QString protocol = normalizedProductEditorProtocol(product.value(QStringLiteral("protocol")).toString(QStringLiteral("j1939")));
    const QString databaseConfigPath = productConfigPathForDatabase(filePath);
    const QString versionCode = versionCodeFromProductConfig(configJson, fileInfo);
    const QString configSha256 = fileSha256Hex(filePath);
    const QString databasePath = productionDatabasePath();

    if (databasePath.isEmpty() || !QFileInfo(databasePath).isFile()) {
        emit errorOccurred(tr("Production database not found: %1. Initialize it with DownloadTool first.")
                               .arg(databasePath));
        return false;
    }

    const QString connectionName = QStringLiteral("product_editor_%1")
        .arg(QUuid::createUuid().toString(QUuid::WithoutBraces));

    const auto runSync = [&]() -> bool {
        QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connectionName);
        db.setDatabaseName(databasePath);
        if (!db.open()) {
            emit errorOccurred(tr("Failed to open product database: %1").arg(db.lastError().text()));
            return false;
        }

        if (!validateProductionDatabaseSchema(db)) {
            db.close();
            return false;
        }
        const bool hasModelColumn = databaseTableHasColumn(db, QStringLiteral("products"), QStringLiteral("model"));

        if (!db.transaction()) {
            emit errorOccurred(tr("Failed to start product database transaction: %1").arg(db.lastError().text()));
            db.close();
            return false;
        }

        qint64 productId = 0;
        {
            QSqlQuery select(db);
            select.prepare(QStringLiteral(
                "SELECT product_id FROM product_config_versions WHERE config_file = ? LIMIT 1"));
            select.addBindValue(databaseConfigPath);
            if (!select.exec()) {
                db.rollback();
                emit errorOccurred(tr("Failed to query product by config path: %1").arg(select.lastError().text()));
                db.close();
                return false;
            }
            if (select.next()) {
                productId = select.value(0).toLongLong();
            }
        }

        if (productId <= 0) {
            QSqlQuery select(db);
            select.prepare(QStringLiteral("SELECT id FROM products WHERE name = ? LIMIT 1"));
            select.addBindValue(productName);
            if (!select.exec()) {
                db.rollback();
                emit errorOccurred(tr("Failed to query product by name: %1").arg(select.lastError().text()));
                db.close();
                return false;
            }
            if (select.next()) {
                productId = select.value(0).toLongLong();
            }
        }

        if (productId <= 0) {
            QSqlQuery insert(db);
            if (hasModelColumn) {
                insert.prepare(QStringLiteral(
                    "INSERT INTO products (name, model, protocol, status) "
                    "VALUES (?, ?, ?, 'active')"));
            } else {
                insert.prepare(QStringLiteral(
                    "INSERT INTO products (name, protocol, status) "
                    "VALUES (?, ?, 'active')"));
            }
            insert.addBindValue(productName);
            if (hasModelColumn) {
                insert.addBindValue(productName);
            }
            insert.addBindValue(protocol);
            if (!insert.exec()) {
                db.rollback();
                emit errorOccurred(tr("Failed to insert product: %1").arg(insert.lastError().text()));
                db.close();
                return false;
            }
            productId = insert.lastInsertId().toLongLong();
        }

        QSqlQuery update(db);
        if (hasModelColumn) {
            update.prepare(QStringLiteral(
                "UPDATE products SET name = ?, model = ?, protocol = ?, "
                "status = 'active', description = ?, calibration_mode = ?, calibration_transport = ?, "
                "allowed_in_normal_mode_read_only = ?, "
                "updated_at = datetime('now', 'localtime') WHERE id = ?"));
        } else {
            update.prepare(QStringLiteral(
                "UPDATE products SET name = ?, protocol = ?, "
                "status = 'active', description = ?, calibration_mode = ?, calibration_transport = ?, "
                "allowed_in_normal_mode_read_only = ?, "
                "updated_at = datetime('now', 'localtime') WHERE id = ?"));
        }
        update.addBindValue(productName);
        if (hasModelColumn) {
            update.addBindValue(productName);
        }
        update.addBindValue(protocol);
        update.addBindValue(product.value(QStringLiteral("description")).toString());
        update.addBindValue(calibration.value(QStringLiteral("mode")).toString());
        update.addBindValue(calibration.value(QStringLiteral("transport")).toString());
        update.addBindValue(calibration.value(QStringLiteral("allowedInNormalModeReadOnly")).toBool(true) ? 1 : 0);
        update.addBindValue(productId);
        if (!update.exec()) {
            db.rollback();
            emit errorOccurred(tr("Failed to update product: %1").arg(update.lastError().text()));
            db.close();
            return false;
        }

        const QVector<CustomerBindingSpec> customerBindings = customerBindingSpecsFromProductConfig(configJson);
        QSqlQuery clearBindings(db);
        clearBindings.prepare(QStringLiteral("DELETE FROM product_customer_bindings WHERE product_id = ?"));
        clearBindings.addBindValue(productId);
        if (!clearBindings.exec()) {
            db.rollback();
            emit errorOccurred(tr("Failed to clear product/customer bindings: %1").arg(clearBindings.lastError().text()));
            db.close();
            return false;
        }

        QSet<QString> importedCustomerNames;
        for (const CustomerBindingSpec &binding : customerBindings) {
            const QString customerName = binding.name.trimmed();
            const QString customerKey = customerName.toCaseFolded();
            if (customerName.isEmpty() || importedCustomerNames.contains(customerKey)) {
                continue;
            }
            importedCustomerNames.insert(customerKey);

            qint64 customerId = 0;
            QSqlQuery selectCustomer(db);
            selectCustomer.prepare(QStringLiteral("SELECT id FROM customers WHERE name = ? LIMIT 1"));
            selectCustomer.addBindValue(customerName);
            if (!selectCustomer.exec()) {
                db.rollback();
                emit errorOccurred(tr("Failed to query customer: %1").arg(selectCustomer.lastError().text()));
                db.close();
                return false;
            }
            if (selectCustomer.next()) {
                customerId = selectCustomer.value(0).toLongLong();
            }

            if (customerId <= 0) {
                const bool hasCustomerTypeColumn = databaseTableHasColumn(db, QStringLiteral("customers"), QStringLiteral("type"));
                const bool hasCustomerStatusColumn = databaseTableHasColumn(db, QStringLiteral("customers"), QStringLiteral("status"));
                QSqlQuery insertCustomer(db);
                if (hasCustomerTypeColumn && hasCustomerStatusColumn) {
                    insertCustomer.prepare(QStringLiteral(
                        "INSERT INTO customers (name, type, status) VALUES (?, 'real', 'active')"));
                } else {
                    insertCustomer.prepare(QStringLiteral("INSERT INTO customers (name) VALUES (?)"));
                }
                insertCustomer.addBindValue(customerName);
                if (!insertCustomer.exec()) {
                    db.rollback();
                    emit errorOccurred(tr("Failed to insert customer: %1").arg(insertCustomer.lastError().text()));
                    db.close();
                    return false;
                }
                customerId = insertCustomer.lastInsertId().toLongLong();
            }

            QSqlQuery insertBinding(db);
            insertBinding.prepare(QStringLiteral(
                "INSERT OR IGNORE INTO product_customer_bindings "
                "(product_id, customer_id, is_default) VALUES (?, ?, ?)"));
            insertBinding.addBindValue(productId);
            insertBinding.addBindValue(customerId);
            insertBinding.addBindValue(binding.isDefault ? 1 : 0);
            if (!insertBinding.exec()) {
                db.rollback();
                emit errorOccurred(tr("Failed to insert product/customer binding: %1").arg(insertBinding.lastError().text()));
                db.close();
                return false;
            }

            QSqlQuery updateBinding(db);
            updateBinding.prepare(QStringLiteral(
                "UPDATE product_customer_bindings SET "
                "is_default = CASE WHEN ? = 1 THEN 1 ELSE is_default END, "
                "updated_at = datetime('now', 'localtime') "
                "WHERE product_id = ? AND customer_id = ?"));
            updateBinding.addBindValue(binding.isDefault ? 1 : 0);
            updateBinding.addBindValue(productId);
            updateBinding.addBindValue(customerId);
            if (!updateBinding.exec()) {
                db.rollback();
                emit errorOccurred(tr("Failed to update product/customer binding: %1").arg(updateBinding.lastError().text()));
                db.close();
                return false;
            }
        }

        QSqlQuery clearDefaultVersion(db);
        clearDefaultVersion.prepare(QStringLiteral(
            "UPDATE product_config_versions SET is_default = 0, updated_at = datetime('now', 'localtime') "
            "WHERE product_id = ?"));
        clearDefaultVersion.addBindValue(productId);
        if (!clearDefaultVersion.exec()) {
            db.rollback();
            emit errorOccurred(tr("Failed to update product config version default: %1").arg(clearDefaultVersion.lastError().text()));
            db.close();
            return false;
        }

        QSqlQuery insertVersion(db);
        insertVersion.prepare(QStringLiteral(
            "INSERT OR IGNORE INTO product_config_versions "
            "(product_id, version_code, config_file, config_sha256, is_default) "
            "VALUES (?, ?, ?, ?, 1)"));
        insertVersion.addBindValue(productId);
        insertVersion.addBindValue(versionCode);
        insertVersion.addBindValue(databaseConfigPath);
        insertVersion.addBindValue(configSha256);
        if (!insertVersion.exec()) {
            db.rollback();
            emit errorOccurred(tr("Failed to insert product config version: %1").arg(insertVersion.lastError().text()));
            db.close();
            return false;
        }

        QSqlQuery updateVersion(db);
        updateVersion.prepare(QStringLiteral(
            "UPDATE product_config_versions SET config_file = ?, config_sha256 = ?, is_default = 1, "
            "updated_at = datetime('now', 'localtime') "
            "WHERE product_id = ? AND version_code = ?"));
        updateVersion.addBindValue(databaseConfigPath);
        updateVersion.addBindValue(configSha256);
        updateVersion.addBindValue(productId);
        updateVersion.addBindValue(versionCode);
        if (!updateVersion.exec()) {
            db.rollback();
            emit errorOccurred(tr("Failed to update product config version: %1").arg(updateVersion.lastError().text()));
            db.close();
            return false;
        }

        if (!db.commit()) {
            emit errorOccurred(tr("Failed to commit product database update: %1").arg(db.lastError().text()));
            db.close();
            return false;
        }

        db.close();
        return true;
    };

    const bool success = runSync();
    QSqlDatabase::removeDatabase(connectionName);
    return success;
}

// ========== 私有方法 ==========

bool LayoutManager::writeJsonFile(const QString &path, const QJsonDocument &doc)
{
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        emit errorOccurred(tr("Failed to open file for writing: %1").arg(path));
        return false;
    }

    const qint64 bytesWritten = file.write(doc.toJson(QJsonDocument::Indented));

    if (bytesWritten < 0 || !file.commit()) {
        emit errorOccurred(tr("Failed to write to file: %1").arg(path));
        return false;
    }

    return true;
}

QJsonDocument LayoutManager::readJsonFile(const QString &path)
{
    QFile file(path);
    if (!file.exists()) {
        return QJsonDocument();
    }

    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        emit errorOccurred(tr("Failed to open file for reading: %1").arg(path));
        return QJsonDocument();
    }

    QByteArray data = file.readAll();
    file.close();

    QJsonParseError error;
    QJsonDocument doc = QJsonDocument::fromJson(data, &error);

    if (error.error != QJsonParseError::NoError) {
        emit errorOccurred(tr("JSON parse error in %1: %2").arg(path, error.errorString()));
        return QJsonDocument();
    }

    return doc;
}
