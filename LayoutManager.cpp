#include "LayoutManager.h"
#include <QCryptographicHash>
#include <QDebug>
#include <QFileInfo>
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

namespace {

QString compactJsonForDatabase(const QJsonObject &object)
{
    return QString::fromUtf8(QJsonDocument(object).toJson(QJsonDocument::Compact));
}

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
    if (includeFnr) {
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
    default:
        return QStringLiteral("ejm_theta");
    }
}

QString rollerLabel(const QString &protocol, int index)
{
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
    default:
        return QStringLiteral("ejm.thetaPos");
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
    default:
        return QStringLiteral("ejm.thetaStatus");
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
        m_productsDirectory = QDir(desktopPath).filePath(QStringLiteral("CANJoystickDownloadTool/firmware"));
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

    for (const QString &path : paths) {
        const QFileInfo fileInfo(path);
        if (fileInfo.baseName() == QStringLiteral("card_templates")) {
            continue;
        }

        const QJsonDocument productDoc = readJsonFile(fileInfo.absoluteFilePath());
        const QJsonObject root = productDoc.isObject() ? productDoc.object() : QJsonObject();
        const QJsonObject product = root.value(QStringLiteral("product")).toObject();
        const QString productName = product.value(QStringLiteral("name"))
            .toString(product.value(QStringLiteral("model")).toString(fileInfo.completeBaseName()))
            .trimmed();
        if (productName.isEmpty()) {
            continue;
        }

        QJsonObject fileObj;
        fileObj["name"] = fileInfo.baseName();
        fileObj["path"] = fileInfo.absoluteFilePath();
        fileObj["modified"] = fileInfo.lastModified().toString(Qt::ISODate);
        fileObj["size"] = fileInfo.size();
        fileObj["displayName"] = productBaseNameFromVersionedName(productName);
        fileObj["protocol"] = product.value(QStringLiteral("protocol")).toString(QStringLiteral("j1939"));
        fileObj["description"] = product.value(QStringLiteral("description")).toString();
        fileObj["model"] = productBaseNameFromVersionedName(productName);
        files.append(fileObj);
    }

    return files;
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
        } else if (type == QStringLiteral("roller")) {
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

    QJsonObject product;
    product.insert(QStringLiteral("name"), productName);
    product.insert(QStringLiteral("description"), description);
    product.insert(QStringLiteral("protocol"), QStringLiteral("can"));
    product.insert(QStringLiteral("canFrameFormat"), QStringLiteral("standard"));
    product.insert(QStringLiteral("canAddress"), QStringLiteral("0x000"));

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
    calibration.insert(QStringLiteral("transport"), QStringLiteral("manualCanMapping"));
    calibration.insert(QStringLiteral("allowedInNormalModeReadOnly"), true);

    QJsonObject can;
    can.insert(QStringLiteral("defaultBaudRate"), baudRate);
    QJsonArray messages;
    messages.append(QJsonObject{
        {QStringLiteral("id"), QStringLiteral("can_message_1")},
        {QStringLiteral("name"), QStringLiteral("CAN报文1")},
        {QStringLiteral("canId"), QStringLiteral("0x000")},
        {QStringLiteral("frameFormat"), QStringLiteral("standard")},
        {QStringLiteral("dlc"), 8},
        {QStringLiteral("period"), 20},
        {QStringLiteral("fields"), QJsonArray()}
    });
    can.insert(QStringLiteral("messages"), messages);

    QJsonArray cells;
    cells.append(makeGridCell(0, 0, QStringLiteral("CAN映射待填写"), QStringLiteral("empty")));
    cells.append(makeGridCell(0, 1, QStringLiteral("总线统计"), QStringLiteral("busStats"),
                              QJsonArray{QStringLiteral("busStats")}));
    cells.append(makeGridCell(1, 0, QString(), QStringLiteral("empty")));
    cells.append(makeGridCell(1, 1, QStringLiteral("记录信息"), QStringLiteral("recordInfo"), QJsonArray{QStringLiteral("recordInfo")}));

    QJsonObject layout;
    layout.insert(QStringLiteral("left"), QJsonObject{{QStringLiteral("widthRatio"), 0.52}});
    layout.insert(QStringLiteral("grid"), QJsonObject{
        {QStringLiteral("rows"), 2},
        {QStringLiteral("columns"), 2},
        {QStringLiteral("cells"), cells}
    });

    QJsonObject editor;
    editor.insert(QStringLiteral("creationFlow"), QStringLiteral("manualCanMessageMapping"));
    editor.insert(QStringLiteral("manualMappingRequired"), true);
    editor.insert(QStringLiteral("mappingStatus"), QStringLiteral("draft"));
    editor.insert(QStringLiteral("mappingInstructions"), QJsonArray{
        QStringLiteral("填写 can.messages[].canId、frameFormat、fields[]。"),
        QStringLiteral("填写 components[]，所有 source/position/status 使用 message.field。"),
        QStringLiteral("填写 layout.grid.cells[].visualComponents[].bindingId。"),
        QStringLiteral("报文映射完成后把 editor.manualMappingRequired 改为 false，mappingStatus 改为 complete。")
    });

    QJsonObject config;
    config.insert(QStringLiteral("schemaVersion"), 2);
    config.insert(QStringLiteral("version"), QStringLiteral("2.0"));
    config.insert(QStringLiteral("product"), product);
    config.insert(QStringLiteral("calibration"), calibration);
    config.insert(QStringLiteral("can"), can);
    config.insert(QStringLiteral("components"), QJsonArray());
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

    if (!isManualMappingDraft(configJson)) {
        const QJsonObject validation = validateProductConfig(configJson);
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

    const QJsonDocument doc(configJson);
    if (!writeJsonFile(filePath, doc)) {
        return false;
    }

    if (!syncProductConfigToDatabase(configJson, filePath)) {
        return false;
    }

    emit productConfigSaved(filePath);
    return true;
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

    if (!isManualMappingDraft(configJson)) {
        const QJsonObject validation = validateProductConfig(configJson);
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

    const QJsonDocument doc(configJson);
    if (!writeJsonFile(filePath, doc)) {
        return false;
    }

    if (!syncProductConfigToDatabase(configJson, filePath)) {
        return false;
    }

    emit productConfigSaved(filePath);
    return true;
}

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

QString LayoutManager::downloadRecordDirectory() const
{
    QDir projectDir(QDir(m_productsDirectory).absolutePath());
    if (projectDir.cdUp()) {
        return projectDir.filePath(QStringLiteral("downloadrecord"));
    }

    return QDir(QCoreApplication::applicationDirPath()).filePath(QStringLiteral("downloadrecord"));
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

bool LayoutManager::ensureProductDatabaseSchema(QSqlDatabase &db)
{
    const QStringList statements = {
        QStringLiteral("PRAGMA foreign_keys = ON"),
        QStringLiteral("PRAGMA busy_timeout = 3000"),
        QStringLiteral(
            "CREATE TABLE IF NOT EXISTS products ("
            "id INTEGER PRIMARY KEY AUTOINCREMENT,"
            "name TEXT NOT NULL UNIQUE,"
            "protocol TEXT NOT NULL DEFAULT 'j1939',"
            "config_file TEXT NOT NULL DEFAULT '',"
            "status TEXT NOT NULL DEFAULT 'active',"
            "created_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),"
            "updated_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),"
            "description TEXT,"
            "calibration_mode TEXT,"
            "calibration_transport TEXT,"
            "allowed_in_normal_mode_read_only INTEGER,"
            "config_json TEXT"
            ")"),
        QStringLiteral(
            "CREATE TABLE IF NOT EXISTS product_config_versions ("
            "id INTEGER PRIMARY KEY AUTOINCREMENT,"
            "product_id INTEGER NOT NULL,"
            "version_code TEXT NOT NULL DEFAULT '',"
            "config_file TEXT NOT NULL DEFAULT '',"
            "config_sha256 TEXT NOT NULL DEFAULT '',"
            "schema_version INTEGER,"
            "description TEXT NOT NULL DEFAULT '',"
            "status TEXT NOT NULL DEFAULT 'released',"
            "is_default INTEGER NOT NULL DEFAULT 0,"
            "created_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),"
            "released_at TEXT NOT NULL DEFAULT '',"
            "updated_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),"
            "FOREIGN KEY(product_id) REFERENCES products(id),"
            "UNIQUE(product_id, version_code)"
            ")")
    };

    for (const QString &statement : statements) {
        QSqlQuery query(db);
        if (!query.exec(statement)) {
            emit errorOccurred(tr("Failed to prepare product database: %1").arg(query.lastError().text()));
            return false;
        }
    }

    const QList<QPair<QString, QString>> columns = {
        {QStringLiteral("protocol"), QStringLiteral("TEXT NOT NULL DEFAULT 'j1939'")},
        {QStringLiteral("config_file"), QStringLiteral("TEXT NOT NULL DEFAULT ''")},
        {QStringLiteral("status"), QStringLiteral("TEXT NOT NULL DEFAULT 'active'")},
        {QStringLiteral("created_at"), QStringLiteral("TEXT")},
        {QStringLiteral("updated_at"), QStringLiteral("TEXT")},
        {QStringLiteral("description"), QStringLiteral("TEXT")},
        {QStringLiteral("calibration_mode"), QStringLiteral("TEXT")},
        {QStringLiteral("calibration_transport"), QStringLiteral("TEXT")},
        {QStringLiteral("allowed_in_normal_mode_read_only"), QStringLiteral("INTEGER")},
        {QStringLiteral("config_json"), QStringLiteral("TEXT")}
    };

    for (const auto &column : columns) {
        if (databaseTableHasColumn(db, QStringLiteral("products"), column.first)) {
            continue;
        }

        QSqlQuery alter(db);
        const QString statement = QStringLiteral("ALTER TABLE products ADD COLUMN %1 %2")
            .arg(column.first, column.second);
        if (!alter.exec(statement)) {
            emit errorOccurred(tr("Failed to update product database schema: %1").arg(alter.lastError().text()));
            return false;
        }
    }

    const QStringList indexStatements = {
        QStringLiteral("CREATE INDEX IF NOT EXISTS idx_products_protocol ON products(protocol)"),
        QStringLiteral("CREATE INDEX IF NOT EXISTS idx_product_config_versions_product ON product_config_versions(product_id)"),
        QStringLiteral("CREATE INDEX IF NOT EXISTS idx_product_config_versions_status ON product_config_versions(status)")
    };
    for (const QString &statement : indexStatements) {
        QSqlQuery query(db);
        if (!query.exec(statement)) {
            emit errorOccurred(tr("Failed to prepare product database index: %1").arg(query.lastError().text()));
            return false;
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
    const QString databasePath = QDir(downloadRecordDirectory()).filePath(QStringLiteral("production_data.db"));

    if (!ensureDirectoryExists(QFileInfo(databasePath).absolutePath())) {
        emit errorOccurred(tr("Failed to create record database directory: %1").arg(QFileInfo(databasePath).absolutePath()));
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

        if (!ensureProductDatabaseSchema(db)) {
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
            select.prepare(QStringLiteral("SELECT id FROM products WHERE config_file = ? LIMIT 1"));
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
                    "INSERT INTO products (name, model, protocol, config_file, status) "
                    "VALUES (?, ?, ?, ?, 'active')"));
            } else {
                insert.prepare(QStringLiteral(
                    "INSERT INTO products (name, protocol, config_file, status) "
                    "VALUES (?, ?, ?, 'active')"));
            }
            insert.addBindValue(productName);
            if (hasModelColumn) {
                insert.addBindValue(productName);
            }
            insert.addBindValue(protocol);
            insert.addBindValue(databaseConfigPath);
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
                "UPDATE products SET name = ?, model = ?, protocol = ?, config_file = ?, "
                "status = 'active', description = ?, calibration_mode = ?, calibration_transport = ?, "
                "allowed_in_normal_mode_read_only = ?, config_json = ?, "
                "updated_at = datetime('now', 'localtime') WHERE id = ?"));
        } else {
            update.prepare(QStringLiteral(
                "UPDATE products SET name = ?, protocol = ?, config_file = ?, "
                "status = 'active', description = ?, calibration_mode = ?, calibration_transport = ?, "
                "allowed_in_normal_mode_read_only = ?, config_json = ?, "
                "updated_at = datetime('now', 'localtime') WHERE id = ?"));
        }
        update.addBindValue(productName);
        if (hasModelColumn) {
            update.addBindValue(productName);
        }
        update.addBindValue(protocol);
        update.addBindValue(databaseConfigPath);
        update.addBindValue(product.value(QStringLiteral("description")).toString());
        update.addBindValue(calibration.value(QStringLiteral("mode")).toString());
        update.addBindValue(calibration.value(QStringLiteral("transport")).toString());
        update.addBindValue(calibration.value(QStringLiteral("allowedInNormalModeReadOnly")).toBool(true) ? 1 : 0);
        update.addBindValue(compactJsonForDatabase(configJson));
        update.addBindValue(productId);
        if (!update.exec()) {
            db.rollback();
            emit errorOccurred(tr("Failed to update product: %1").arg(update.lastError().text()));
            db.close();
            return false;
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
            "(product_id, version_code, config_file, config_sha256, schema_version, description, status, is_default, released_at) "
            "VALUES (?, ?, ?, ?, ?, ?, 'released', 1, datetime('now', 'localtime'))"));
        insertVersion.addBindValue(productId);
        insertVersion.addBindValue(versionCode);
        insertVersion.addBindValue(databaseConfigPath);
        insertVersion.addBindValue(configSha256);
        insertVersion.addBindValue(configJson.value(QStringLiteral("schemaVersion")).isDouble()
                                       ? configJson.value(QStringLiteral("schemaVersion")).toInt()
                                       : QVariant());
        insertVersion.addBindValue(product.value(QStringLiteral("description")).toString());
        if (!insertVersion.exec()) {
            db.rollback();
            emit errorOccurred(tr("Failed to insert product config version: %1").arg(insertVersion.lastError().text()));
            db.close();
            return false;
        }

        QSqlQuery updateVersion(db);
        updateVersion.prepare(QStringLiteral(
            "UPDATE product_config_versions SET config_file = ?, config_sha256 = ?, "
            "schema_version = ?, description = ?, status = 'released', is_default = 1, "
            "updated_at = datetime('now', 'localtime') "
            "WHERE product_id = ? AND version_code = ?"));
        updateVersion.addBindValue(databaseConfigPath);
        updateVersion.addBindValue(configSha256);
        updateVersion.addBindValue(configJson.value(QStringLiteral("schemaVersion")).isDouble()
                                       ? configJson.value(QStringLiteral("schemaVersion")).toInt()
                                       : QVariant());
        updateVersion.addBindValue(product.value(QStringLiteral("description")).toString());
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
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        emit errorOccurred(tr("Failed to open file for writing: %1").arg(path));
        return false;
    }

    qint64 bytesWritten = file.write(doc.toJson(QJsonDocument::Indented));
    file.close();

    if (bytesWritten < 0) {
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
