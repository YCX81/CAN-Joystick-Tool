#include "LayoutManager.h"
#include <QDebug>
#include <QFileInfo>
#include <QDateTime>
#include <QCoreApplication>
#include <QRegularExpression>

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

    // 产品配置目录: CANJoystickDownloadTool/products/
    // 默认在同级目录查找
    QString appDir = QCoreApplication::applicationDirPath();
    m_productsDirectory = appDir + "/../CANJoystickDownloadTool/products";
    // 如果不存在，尝试桌面路径
    if (!QDir(m_productsDirectory).exists()) {
        QString desktopPath = QStandardPaths::writableLocation(QStandardPaths::DesktopLocation);
        m_productsDirectory = desktopPath + "/CANJoystickDownloadTool/products";
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
            fileObj["displayName"] = product.value("name").toString(fileInfo.baseName());
            fileObj["protocol"] = product.value("protocol").toString("j1939");
            fileObj["description"] = product.value("description").toString();
            fileObj["model"] = product.value("model").toString(fileInfo.baseName());
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

    QStringList filters;
    filters << "*.json";
    dir.setNameFilters(filters);
    dir.setSorting(QDir::Name);

    for (const QFileInfo &fileInfo : dir.entryInfoList(QDir::Files)) {
        QJsonObject fileObj;
        fileObj["name"] = fileInfo.baseName();
        fileObj["path"] = fileInfo.absoluteFilePath();
        fileObj["modified"] = fileInfo.lastModified().toString(Qt::ISODate);
        fileObj["size"] = fileInfo.size();
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

bool LayoutManager::saveProductConfig(const QJsonObject &configJson, const QString &filePath)
{
    if (filePath.isEmpty()) {
        emit errorOccurred(tr("No file path specified for product config"));
        return false;
    }

    QJsonDocument doc(configJson);
    if (writeJsonFile(filePath, doc)) {
        emit productConfigSaved(filePath);
        return true;
    }
    return false;
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
    const QString safeModel = sanitizeProductModel(model);
    if (safeModel.isEmpty()) {
        return false;
    }

    const QDir dir(m_productsDirectory);
    return QFileInfo::exists(dir.filePath(safeModel + ".json"));
}

bool LayoutManager::saveProductConfigAs(const QJsonObject &configJson, const QString &model)
{
    const QString safeModel = sanitizeProductModel(model);
    if (safeModel.isEmpty()) {
        emit errorOccurred(tr("Product model cannot be empty"));
        return false;
    }

    if (!ensureDirectoryExists(m_productsDirectory)) {
        emit errorOccurred(tr("Failed to create products directory: %1").arg(m_productsDirectory));
        return false;
    }

    const QDir dir(m_productsDirectory);
    const QString filePath = dir.filePath(safeModel + ".json");
    if (QFileInfo::exists(filePath)) {
        emit errorOccurred(tr("Product config already exists: %1").arg(filePath));
        return false;
    }

    const QJsonDocument doc(configJson);
    if (writeJsonFile(filePath, doc)) {
        emit productConfigSaved(filePath);
        return true;
    }

    return false;
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
