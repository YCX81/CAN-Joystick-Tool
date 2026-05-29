#include "LayoutManager.h"
#include <QDebug>
#include <QFileInfo>
#include <QDateTime>
#include <QCoreApplication>
#include <QRegularExpression>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>
#include <QUuid>

namespace {

QString compactJsonForDatabase(const QJsonObject &object)
{
    return QString::fromUtf8(QJsonDocument(object).toJson(QJsonDocument::Compact));
}

QString normalizedProductEditorProtocol(const QString &protocol)
{
    const QString value = protocol.trimmed().toLower();
    if (value == QStringLiteral("canopen")) {
        return value;
    }
    return QStringLiteral("j1939");
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
    const QDir productsDir(m_productsDirectory);
    const QString relativePath = productsDir.relativeFilePath(fileInfo.absoluteFilePath());
    const bool isInsideProductsDirectory = !relativePath.startsWith(QStringLiteral("../"))
        && !relativePath.startsWith(QStringLiteral("..\\"))
        && !QDir::isAbsolutePath(relativePath);

    const QString databasePath = isInsideProductsDirectory
        ? QDir(QStringLiteral("products")).filePath(relativePath)
        : QDir(QStringLiteral("products")).filePath(fileInfo.fileName());
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
            "model TEXT NOT NULL DEFAULT '',"
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
        QStringLiteral("CREATE INDEX IF NOT EXISTS idx_products_model ON products(model)"),
        QStringLiteral("CREATE INDEX IF NOT EXISTS idx_products_protocol ON products(protocol)")
    };

    for (const QString &statement : statements) {
        QSqlQuery query(db);
        if (!query.exec(statement)) {
            emit errorOccurred(tr("Failed to prepare product database: %1").arg(query.lastError().text()));
            return false;
        }
    }

    const QList<QPair<QString, QString>> columns = {
        {QStringLiteral("model"), QStringLiteral("TEXT NOT NULL DEFAULT ''")},
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

    return true;
}

bool LayoutManager::syncProductConfigToDatabase(const QJsonObject &configJson, const QString &filePath)
{
    const QFileInfo fileInfo(filePath);
    const QJsonObject product = configJson.value(QStringLiteral("product")).toObject();
    const QJsonObject calibration = configJson.value(QStringLiteral("calibration")).toObject();

    QString model = product.value(QStringLiteral("model")).toString(fileInfo.completeBaseName()).trimmed();
    if (model.isEmpty()) {
        model = fileInfo.completeBaseName().trimmed();
    }
    if (model.isEmpty()) {
        emit errorOccurred(tr("Product model cannot be empty"));
        return false;
    }

    const QString protocol = normalizedProductEditorProtocol(product.value(QStringLiteral("protocol")).toString(QStringLiteral("j1939")));
    const QString databaseConfigPath = productConfigPathForDatabase(filePath);
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
            select.addBindValue(model);
            if (!select.exec()) {
                db.rollback();
                emit errorOccurred(tr("Failed to query product by model: %1").arg(select.lastError().text()));
                db.close();
                return false;
            }
            if (select.next()) {
                productId = select.value(0).toLongLong();
            }
        }

        if (productId <= 0) {
            QSqlQuery insert(db);
            insert.prepare(QStringLiteral(
                "INSERT INTO products (name, model, protocol, config_file, status) "
                "VALUES (?, ?, ?, ?, 'active')"));
            insert.addBindValue(model);
            insert.addBindValue(model);
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
        update.prepare(QStringLiteral(
            "UPDATE products SET name = ?, model = ?, protocol = ?, config_file = ?, "
            "status = 'active', description = ?, calibration_mode = ?, calibration_transport = ?, "
            "allowed_in_normal_mode_read_only = ?, config_json = ?, "
            "updated_at = datetime('now', 'localtime') WHERE id = ?"));
        update.addBindValue(model);
        update.addBindValue(model);
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
