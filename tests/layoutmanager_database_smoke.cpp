#include "LayoutManager.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDir>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QTemporaryDir>
#include <QThread>
#include <QDebug>
#include <cstdio>
#include <functional>

namespace {

bool writeBytes(const QString &path, const QByteArray &bytes)
{
    QFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(bytes) == bytes.size();
}

bool writeBytesAtomically(const QString &path, const QByteArray &bytes)
{
    QSaveFile file(path);
    return file.open(QIODevice::WriteOnly)
        && file.write(bytes) == bytes.size()
        && file.commit();
}

bool waitUntil(const std::function<bool()> &condition, int timeoutMs = 3000)
{
    QElapsedTimer elapsed;
    elapsed.start();
    while (elapsed.elapsed() < timeoutMs) {
        QCoreApplication::processEvents(QEventLoop::AllEvents, 50);
        if (condition())
            return true;
        QThread::msleep(10);
    }
    QCoreApplication::processEvents(QEventLoop::AllEvents, 50);
    return condition();
}

void processEventsFor(int durationMs)
{
    QElapsedTimer elapsed;
    elapsed.start();
    while (elapsed.elapsed() < durationMs) {
        QCoreApplication::processEvents(QEventLoop::AllEvents, 50);
        QThread::msleep(10);
    }
}

bool databaseHasColumn(const QString &databasePath, const QString &table, const QString &column)
{
    const QString connectionName = QStringLiteral("layoutmanager_smoke_inspect");
    bool found = false;
    {
        QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connectionName);
        db.setDatabaseName(databasePath);
        if (db.open()) {
            QSqlQuery query(db);
            if (query.exec(QStringLiteral("PRAGMA table_info(%1)").arg(table))) {
                while (query.next()) {
                    if (query.value(QStringLiteral("name")).toString() == column) {
                        found = true;
                        break;
                    }
                }
            }
            db.close();
        }
    }
    QSqlDatabase::removeDatabase(connectionName);
    return found;
}

QVariant scalar(const QString &databasePath, const QString &sql)
{
    const QString connectionName = QStringLiteral("layoutmanager_smoke_scalar");
    QVariant value;
    {
        QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connectionName);
        db.setDatabaseName(databasePath);
        if (db.open()) {
            QSqlQuery query(db);
            if (query.exec(sql) && query.next())
                value = query.value(0);
            db.close();
        }
    }
    QSqlDatabase::removeDatabase(connectionName);
    return value;
}

bool createCanonicalDatabase(const QString &databasePath)
{
    const QString connectionName = QStringLiteral("layoutmanager_smoke_create");
    bool success = false;
    {
        QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connectionName);
        db.setDatabaseName(databasePath);
        if (db.open()) {
            const QStringList schema = {
                QStringLiteral(
                    "CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, migration_name TEXT NOT NULL, "
                    "application_version TEXT NOT NULL DEFAULT '', applied_at TEXT)"),
                QStringLiteral(
                    "CREATE TABLE products (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, "
                    "protocol TEXT NOT NULL DEFAULT 'j1939', status TEXT NOT NULL DEFAULT 'active', "
                    "created_at TEXT, updated_at TEXT)"),
                QStringLiteral(
                    "CREATE TABLE product_config_versions (id INTEGER PRIMARY KEY AUTOINCREMENT, "
                    "product_id INTEGER NOT NULL, version_code TEXT NOT NULL DEFAULT '', "
                    "config_file TEXT NOT NULL DEFAULT '', config_sha256 TEXT NOT NULL DEFAULT '', "
                    "schema_version INTEGER NOT NULL DEFAULT 2, "
                    "operation_mode TEXT NOT NULL DEFAULT 'legacy', "
                    "firmware_source TEXT NOT NULL DEFAULT '', "
                    "description TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'active', "
                    "is_default INTEGER NOT NULL DEFAULT 0, created_at TEXT, updated_at TEXT, "
                    "UNIQUE(product_id, version_code))"),
                QStringLiteral(
                    "CREATE TABLE firmwares (id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER, "
                    "customer_id INTEGER, version TEXT NOT NULL DEFAULT '', version_code TEXT NOT NULL DEFAULT '', "
                    "description TEXT NOT NULL DEFAULT '', file_name TEXT NOT NULL, file_path TEXT NOT NULL UNIQUE, "
                    "sha256 TEXT NOT NULL DEFAULT '', file_size INTEGER NOT NULL DEFAULT 0, "
                    "file_mtime TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'active', "
                    "created_at TEXT, updated_at TEXT)"),
                QStringLiteral(
                    "CREATE TABLE product_version_firmwares (id INTEGER PRIMARY KEY AUTOINCREMENT, "
                    "product_version_id INTEGER NOT NULL, firmware_id INTEGER NOT NULL, "
                    "compatibility_level TEXT NOT NULL DEFAULT 'exact', is_default INTEGER NOT NULL DEFAULT 0, "
                    "created_at TEXT, updated_at TEXT, UNIQUE(product_version_id, firmware_id))"),
                QStringLiteral(
                    "CREATE TABLE customers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, "
                    "code TEXT UNIQUE, type TEXT NOT NULL DEFAULT 'real', "
                    "status TEXT NOT NULL DEFAULT 'active', created_at TEXT, updated_at TEXT)"),
                QStringLiteral(
                    "CREATE TABLE product_customer_bindings (id INTEGER PRIMARY KEY AUTOINCREMENT, "
                    "product_id INTEGER NOT NULL, customer_id INTEGER NOT NULL, "
                    "is_default INTEGER NOT NULL DEFAULT 0, updated_at TEXT, UNIQUE(product_id, customer_id))"),
                QStringLiteral("INSERT INTO schema_migrations (version, migration_name) VALUES (1, 'core-event-schema-v1')"),
                QStringLiteral("INSERT INTO schema_migrations (version, migration_name) VALUES (2, 'functional-device-bindings-v2')"),
                QStringLiteral("INSERT INTO schema_migrations (version, migration_name) VALUES (3, 'product-config-v3')"),
                QStringLiteral("PRAGMA user_version = 3")
            };
            success = true;
            for (const QString &statement : schema) {
                QSqlQuery query(db);
                if (!query.exec(statement)) {
                    success = false;
                    break;
                }
            }
            db.close();
        }
    }
    QSqlDatabase::removeDatabase(connectionName);
    return success;
}

QJsonObject draftConfig()
{
    QJsonObject product{{QStringLiteral("name"), QStringLiteral("DRAFT-PRODUCT")},
                        {QStringLiteral("protocol"), QStringLiteral("j1939")}};
    QJsonObject editor{{QStringLiteral("creationFlow"), QStringLiteral("manualCanMessageMapping")},
                       {QStringLiteral("manualMappingRequired"), true}};
    return QJsonObject{{QStringLiteral("schemaVersion"), 2},
                       {QStringLiteral("product"), product},
                       {QStringLiteral("editor"), editor}};
}

QJsonObject releasedConfig()
{
    const QJsonObject field{{QStringLiteral("name"), QStringLiteral("value")},
                            {QStringLiteral("type"), QStringLiteral("uint8")}};
    const QJsonObject message{{QStringLiteral("id"), QStringLiteral("message_1")},
                              {QStringLiteral("canId"), QStringLiteral("0x100")},
                              {QStringLiteral("fields"), QJsonArray{field}}};
    const QJsonObject component{{QStringLiteral("id"), QStringLiteral("counter_1")},
                                {QStringLiteral("type"), QStringLiteral("counter")},
                                {QStringLiteral("source"), QStringLiteral("message_1.value")}};
    return QJsonObject{
        {QStringLiteral("schemaVersion"), 2},
        {QStringLiteral("product"),
         QJsonObject{{QStringLiteral("name"), QStringLiteral("RELEASED-PRODUCT")},
                     {QStringLiteral("protocol"), QStringLiteral("can")}}},
        {QStringLiteral("can"), QJsonObject{{QStringLiteral("messages"), QJsonArray{message}}}},
        {QStringLiteral("components"), QJsonArray{component}},
        {QStringLiteral("layout"), QJsonObject{}},
        {QStringLiteral("editor"), QJsonObject{{QStringLiteral("manualMappingRequired"), false}}}
    };
}

QJsonObject testOnlyV3Config(LayoutManager &manager,
                             const QString &code,
                             const QString &description = QStringLiteral("无固件纯测试产品"))
{
    return manager.buildStandardProductConfigV3(
        QJsonObject{{QStringLiteral("code"), code},
                    {QStringLiteral("description"), description},
                    {QStringLiteral("version"), QStringLiteral("V1")},
                    {QStringLiteral("buttonCount"), 4},
                    {QStringLiteral("hasWorkLight"), true}});
}

QJsonObject firmwareBackedV3Config(LayoutManager &manager,
                                   const QString &code,
                                   const QString &version,
                                   const QString &artifact)
{
    QJsonObject config = testOnlyV3Config(manager, code, QStringLiteral("有固件产品"));
    QJsonObject product = config.value(QStringLiteral("product")).toObject();
    product.insert(QStringLiteral("version"), version);
    config.insert(QStringLiteral("product"), product);
    config.insert(
        QStringLiteral("operation"),
        QJsonObject{
            {QStringLiteral("mode"), QStringLiteral("firmware-backed")},
            {QStringLiteral("firmware"),
             QJsonObject{{QStringLiteral("source"), QStringLiteral("bundled")},
                         {QStringLiteral("version"), version.mid(1)},
                         {QStringLiteral("artifact"), artifact}}}});
    return config;
}

} // namespace

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    if (app.arguments().size() > 1) {
        const QString databasePath = QFileInfo(app.arguments().at(1)).absoluteFilePath();
        QTemporaryDir products;
        if (!products.isValid())
            return 20;
        qputenv("CANJOYSTICK_DATABASE_PATH", databasePath.toUtf8());
        LayoutManager manager;
        manager.setProductsDirectory(products.path());
        const QString configPath = QDir(products.path()).filePath(QStringLiteral("RELEASED-PRODUCT_V2.json"));
        if (!manager.saveProductConfig(releasedConfig(), configPath))
            return 21;
        return databaseHasColumn(databasePath, QStringLiteral("products"), QStringLiteral("config_file"))
            ? 22
            : 0;
    }

    QTemporaryDir root;
    if (!root.isValid())
        return 1;

    const QString productsDir = QDir(root.path()).filePath(QStringLiteral("products"));
    if (!QDir().mkpath(productsDir))
        return 2;

    LayoutManager manager;
    manager.setProductsDirectory(productsDir);
    manager.setProductCatalogRoot(QDir(root.path()).filePath(QStringLiteral("catalog")));
    QStringList reportedErrors;
    QObject::connect(&manager, &LayoutManager::errorOccurred, [&reportedErrors](const QString &message) {
        reportedErrors.append(message);
        std::fprintf(stderr, "%s\n", qPrintable(message));
    });
    int externalChangeCount = 0;
    QString lastExternalChangePath;
    QObject::connect(&manager,
                     &LayoutManager::productConfigExternallyChanged,
                     [&externalChangeCount, &lastExternalChangePath](const QString &path) {
                         ++externalChangeCount;
                         lastExternalChangePath = path;
                     });

    const QString unusableDatabasePath = QDir(root.path()).filePath(QStringLiteral("database-directory"));
    if (!QDir().mkpath(unusableDatabasePath))
        return 3;
    qputenv("CANJOYSTICK_DATABASE_PATH", unusableDatabasePath.toUtf8());

    const QString draftPath = QDir(productsDir).filePath(QStringLiteral("DRAFT-PRODUCT_V1.json"));
    if (!manager.saveProductConfig(draftConfig(), draftPath))
        return 4;

    const QByteArray original("{\"original\":true}\n");
    const QString releasedPath = QDir(productsDir).filePath(QStringLiteral("RELEASED-PRODUCT_V1.json"));
    if (!writeBytes(releasedPath, original))
        return 5;

    const QJsonObject released = releasedConfig();
    if (!manager.validateProductConfig(released).value(QStringLiteral("ok")).toBool())
        return 8;
    if (manager.saveProductConfig(released, releasedPath))
        return 6;
    QFile restored(releasedPath);
    if (!restored.open(QIODevice::ReadOnly) || restored.readAll() != original)
        return 7;
    restored.close();
    if (manager.saveProductConfig(draftConfig(), releasedPath))
        return 18;
    QFile protectedReleased(releasedPath);
    if (!protectedReleased.open(QIODevice::ReadOnly) || protectedReleased.readAll() != original)
        return 19;

    const QString newReleasedPath =
        QDir(productsDir).filePath(QStringLiteral("RELEASED-PRODUCT_V9.json"));
    if (manager.saveProductConfig(released, newReleasedPath)
        || QFileInfo::exists(newReleasedPath)) {
        return 17;
    }

    const QString databasePath = QDir(root.path()).filePath(QStringLiteral("production_data.db"));
    if (!createCanonicalDatabase(databasePath))
        return 9;
    qputenv("CANJOYSTICK_DATABASE_PATH", databasePath.toUtf8());

    const QString cloneSourceCode = QStringLiteral("SOURCE-FIRMWARE");
    const QString cloneSourceArtifactName = QStringLiteral("SOURCE-FIRMWARE_V1.elf");
    const QString cloneSourceDirectory = QDir(productsDir).filePath(cloneSourceCode);
    if (!QDir().mkpath(cloneSourceDirectory))
        return 70;
    const QByteArray cloneSourceBytes = QByteArrayLiteral("source-firmware-bytes");
    if (!writeBytes(QDir(cloneSourceDirectory).filePath(cloneSourceArtifactName),
                    cloneSourceBytes)) {
        return 71;
    }
    const QJsonObject cloneSourceConfig =
        firmwareBackedV3Config(manager,
                               cloneSourceCode,
                               QStringLiteral("V1"),
                               cloneSourceArtifactName);
    const QString cloneTargetCode = QStringLiteral("TARGET-FIRMWARE");
    if (!manager.cloneProductConfigVersionWithCustomerAs(
            cloneSourceConfig,
            cloneTargetCode,
            QStringLiteral("V3"),
            QStringLiteral("复制固件产品"),
            QStringLiteral("测试客户"))) {
        return 72;
    }
    const QString cloneTargetConfigPath =
        manager.productConfigVersionPath(cloneTargetCode, QStringLiteral("V3"));
    const QString cloneTargetArtifactPath =
        QDir(QFileInfo(cloneTargetConfigPath).absolutePath())
            .filePath(QStringLiteral("TARGET-FIRMWARE_V3.elf"));
    QFile cloneTargetArtifact(cloneTargetArtifactPath);
    QFile cloneTargetConfigFile(cloneTargetConfigPath);
    if (!cloneTargetArtifact.open(QIODevice::ReadOnly)
        || cloneTargetArtifact.readAll() != cloneSourceBytes
        || !cloneTargetConfigFile.open(QIODevice::ReadOnly)) {
        return 73;
    }
    const QJsonObject clonedFirmwareConfig =
        QJsonDocument::fromJson(cloneTargetConfigFile.readAll()).object();
    if (clonedFirmwareConfig.value(QStringLiteral("operation")).toObject()
            .value(QStringLiteral("firmware")).toObject()
            .value(QStringLiteral("artifact")).toString()
        != QStringLiteral("TARGET-FIRMWARE_V3.elf")) {
        return 74;
    }

    const QString conflictCode = QStringLiteral("CONFLICT-FIRMWARE");
    const QString conflictDirectory = QDir(productsDir).filePath(conflictCode);
    if (!QDir().mkpath(conflictDirectory))
        return 75;
    const QString conflictArtifactPath =
        QDir(conflictDirectory).filePath(QStringLiteral("CONFLICT-FIRMWARE_V3.elf"));
    const QByteArray conflictBytes = QByteArrayLiteral("do-not-overwrite");
    if (!writeBytes(conflictArtifactPath, conflictBytes)
        || manager.cloneProductConfigVersionWithCustomerAs(
            cloneSourceConfig,
            conflictCode,
            QStringLiteral("V3"),
            QStringLiteral("冲突产品"),
            QStringLiteral("测试客户"))) {
        return 76;
    }
    QFile conflictArtifact(conflictArtifactPath);
    if (!conflictArtifact.open(QIODevice::ReadOnly)
        || conflictArtifact.readAll() != conflictBytes) {
        return 77;
    }

    qputenv("CANJOYSTICK_DATABASE_PATH", unusableDatabasePath.toUtf8());
    const QString failedCloneCode = QStringLiteral("FAILED-FIRMWARE");
    const QString failedCloneConfigPath =
        manager.productConfigVersionPath(failedCloneCode, QStringLiteral("V3"));
    const QString failedCloneDirectory = QFileInfo(failedCloneConfigPath).absolutePath();
    const QString failedCloneArtifactPath =
        QDir(failedCloneDirectory).filePath(QStringLiteral("FAILED-FIRMWARE_V3.elf"));
    if (manager.cloneProductConfigVersionWithCustomerAs(
            cloneSourceConfig,
            failedCloneCode,
            QStringLiteral("V3"),
            QStringLiteral("数据库失败产品"),
            QStringLiteral("测试客户"))
        || QFileInfo::exists(failedCloneConfigPath)
        || QFileInfo::exists(failedCloneArtifactPath)
        || QDir(failedCloneDirectory).exists()) {
        return 78;
    }
    qputenv("CANJOYSTICK_DATABASE_PATH", databasePath.toUtf8());

    const QString syncedPath = QDir(productsDir).filePath(QStringLiteral("RELEASED-PRODUCT_V2.json"));
    if (!manager.saveProductConfig(released, syncedPath))
        return 10;
    if (databaseHasColumn(databasePath, QStringLiteral("products"), QStringLiteral("config_file"))
        || databaseHasColumn(databasePath, QStringLiteral("products"), QStringLiteral("config_json"))
        || !databaseHasColumn(databasePath, QStringLiteral("product_config_versions"), QStringLiteral("status"))
        || !databaseHasColumn(databasePath, QStringLiteral("product_config_versions"), QStringLiteral("schema_version"))) {
        return 11;
    }

    const QString testOnlyCode = QStringLiteral("JC6000-BGA-C0009");
    const QJsonObject testOnlyConfig = testOnlyV3Config(manager, testOnlyCode);
    const QString testOnlyPath =
        manager.productConfigVersionPath(testOnlyCode, QStringLiteral("V1"));
    if (!manager.saveProductDraft(testOnlyConfig, testOnlyPath)
        || !QFileInfo::exists(manager.productDraftPath(testOnlyPath))) {
        return 35;
    }
    if (!manager.saveProductConfigVersionWithCustomerAs(
            testOnlyConfig, testOnlyCode, QStringLiteral("V1"), QStringLiteral("安徽好运来叉车"))) {
        return 23;
    }
    if (QFileInfo::exists(manager.productDraftPath(testOnlyPath))) {
        return 36;
    }
    QFile persistedTestOnlyFile(testOnlyPath);
    if (!persistedTestOnlyFile.open(QIODevice::ReadOnly)) {
        return 37;
    }
    const QJsonObject persistedTestOnlyConfig =
        QJsonDocument::fromJson(persistedTestOnlyFile.readAll()).object();
    persistedTestOnlyFile.close();
    const QJsonArray persistedCustomerBindings =
        persistedTestOnlyConfig.value(QStringLiteral("product"))
            .toObject()
            .value(QStringLiteral("customerBindings"))
            .toArray();
    if (persistedCustomerBindings.size() != 1
        || persistedCustomerBindings.first()
                   .toObject()
                   .value(QStringLiteral("name"))
                   .toString()
            != QStringLiteral("安徽好运来叉车")
        || !persistedCustomerBindings.first()
                .toObject()
                .value(QStringLiteral("isDefault"))
                .toBool()) {
        return 38;
    }

    QJsonObject reboundConfig = persistedTestOnlyConfig;
    QJsonObject reboundProduct = reboundConfig.value(QStringLiteral("product")).toObject();
    reboundProduct.insert(
        QStringLiteral("customerBindings"),
        QJsonArray{QJsonObject{{QStringLiteral("name"), QStringLiteral("重新绑定客户")},
                               {QStringLiteral("isDefault"), true}}});
    reboundConfig.insert(QStringLiteral("product"), reboundProduct);
    if (!manager.saveProductConfig(reboundConfig, testOnlyPath)) {
        return 81;
    }
    if (scalar(databasePath,
               QStringLiteral(
                   "SELECT COUNT(*) FROM product_customer_bindings pcb "
                   "JOIN products p ON p.id = pcb.product_id "
                   "JOIN customers c ON c.id = pcb.customer_id "
                   "WHERE p.name = 'JC6000-BGA-C0009' AND c.name = '重新绑定客户' "
                   "AND pcb.is_default = 1"))
            .toInt()
        != 1
        || scalar(databasePath,
                  QStringLiteral(
                      "SELECT COUNT(*) FROM product_customer_bindings pcb "
                      "JOIN products p ON p.id = pcb.product_id "
                      "JOIN customers c ON c.id = pcb.customer_id "
                      "WHERE p.name = 'JC6000-BGA-C0009' AND c.name = '安徽好运来叉车'"))
               .toInt()
            != 0) {
        return 82;
    }
    if (!manager.saveProductConfig(persistedTestOnlyConfig, testOnlyPath)) {
        return 83;
    }
    const QJsonArray persistedCards =
        persistedTestOnlyConfig.value(QStringLiteral("layout"))
            .toObject()
            .value(QStringLiteral("cards"))
            .toArray();
    bool hasBlankFront = false;
    bool hasBlankBack = false;
    bool hasBusStats = false;
    bool hasRecordInfo = false;
    bool hasUnexpectedBinding = false;
    for (const QJsonValue &cardValue : persistedCards) {
        const QJsonObject card = cardValue.toObject();
        const QJsonObject grid = card.value(QStringLiteral("grid")).toObject();
        const int row = grid.value(QStringLiteral("row")).toInt(-1);
        const int column = grid.value(QStringLiteral("column")).toInt(-1);
        const QString kind = card.value(QStringLiteral("kind")).toString();
        if (kind == QStringLiteral("leftRegion")
            || !card.value(QStringLiteral("elements")).toArray().isEmpty()) {
            hasUnexpectedBinding = true;
        }
        if (row == 0 && column == 0) {
            hasBlankFront =
                kind == QStringLiteral("controls")
                && card.value(QStringLiteral("title")).toString()
                       == QStringLiteral("正面");
        } else if (row == 1 && column == 0) {
            hasBlankBack =
                kind == QStringLiteral("controls")
                && card.value(QStringLiteral("title")).toString()
                       == QStringLiteral("背面");
        } else if (row == 0 && column == 1) {
            hasBusStats =
                kind == QStringLiteral("system")
                && card.value(QStringLiteral("systemType")).toString()
                       == QStringLiteral("busStats");
        } else if (row == 1 && column == 1) {
            hasRecordInfo =
                kind == QStringLiteral("system")
                && card.value(QStringLiteral("systemType")).toString()
                       == QStringLiteral("recordInfo");
        }
    }
    if (persistedCards.size() != 4
        || !hasBlankFront
        || !hasBlankBack
        || !hasBusStats
        || !hasRecordInfo
        || hasUnexpectedBinding) {
        return 39;
    }
    if (scalar(databasePath,
               QStringLiteral(
                   "SELECT COUNT(*) FROM product_config_versions pcv "
                   "JOIN products p ON p.id = pcv.product_id "
                   "WHERE p.name = 'JC6000-BGA-C0009' AND pcv.version_code = 'V1' "
                   "AND pcv.schema_version = 3 AND pcv.operation_mode = 'test_only' "
                   "AND pcv.firmware_source = 'external' AND pcv.description = '无固件纯测试产品' "
                   "AND pcv.status = 'active'"))
            .toInt()
        != 1) {
        return 24;
    }
    if (scalar(databasePath,
               QStringLiteral(
                   "SELECT COUNT(*) FROM product_version_firmwares pvf "
                   "JOIN product_config_versions pcv ON pcv.id = pvf.product_version_id "
                   "JOIN products p ON p.id = pcv.product_id "
                   "WHERE p.name = 'JC6000-BGA-C0009'"))
            .toInt()
        != 0
        || scalar(databasePath,
                  QStringLiteral(
                      "SELECT COUNT(*) FROM firmwares f "
                      "JOIN products p ON p.id = f.product_id "
                      "WHERE p.name = 'JC6000-BGA-C0009'"))
               .toInt()
            != 0) {
        return 25;
    }
    if (scalar(databasePath,
               QStringLiteral(
                   "SELECT COUNT(*) FROM product_customer_bindings pcb "
                   "JOIN products p ON p.id = pcb.product_id "
                   "JOIN customers c ON c.id = pcb.customer_id "
                   "WHERE p.name = 'JC6000-BGA-C0009' AND c.name = '安徽好运来叉车' "
                   "AND pcb.is_default = 1"))
            .toInt()
        != 1) {
        return 31;
    }
    const QJsonDocument savedTestOnly = QJsonDocument::fromJson(
        [&]() {
            QFile file(testOnlyPath);
            if (!file.open(QIODevice::ReadOnly))
                return QByteArray();
            return file.readAll();
        }());
    if (!savedTestOnly.isObject()
        || savedTestOnly.object().contains(QStringLiteral("customer"))
        || savedTestOnly.object().value(QStringLiteral("product")).toObject().contains(QStringLiteral("customer"))) {
        return 32;
    }

    // A valid external repair of an already registered JSON must update the
    // database hash/metadata and notify the editor to reload its in-memory copy.
    manager.getProductFiles();
    QCoreApplication::processEvents(QEventLoop::AllEvents, 50);
    QJsonObject externallyModified = persistedTestOnlyConfig;
    QJsonObject externallyModifiedProduct =
        externallyModified.value(QStringLiteral("product")).toObject();
    externallyModifiedProduct.insert(QStringLiteral("description"),
                                     QStringLiteral("外部映射修复后的配置"));
    externallyModified.insert(QStringLiteral("product"), externallyModifiedProduct);
    const QByteArray externallyModifiedBytes =
        QJsonDocument(externallyModified).toJson(QJsonDocument::Indented);
    const QString externallyModifiedHash = QString::fromLatin1(
        QCryptographicHash::hash(externallyModifiedBytes, QCryptographicHash::Sha256).toHex());
    if (!writeBytesAtomically(testOnlyPath, externallyModifiedBytes)) {
        return 84;
    }
    if (!waitUntil([&]() {
            return scalar(databasePath,
                          QStringLiteral(
                              "SELECT config_sha256 FROM product_config_versions pcv "
                              "JOIN products p ON p.id = pcv.product_id "
                              "WHERE p.name = 'JC6000-BGA-C0009' AND pcv.version_code = 'V1'"))
                       .toString()
                    == externallyModifiedHash
                && scalar(databasePath,
                          QStringLiteral(
                              "SELECT pcv.description FROM product_config_versions pcv "
                              "JOIN products p ON p.id = pcv.product_id "
                              "WHERE p.name = 'JC6000-BGA-C0009' AND pcv.version_code = 'V1'"))
                       .toString()
                    == QStringLiteral("外部映射修复后的配置")
                && externalChangeCount == 1;
        })) {
        std::fprintf(stderr,
                     "external sync state: hash=%s description=%s changes=%d\n",
                     qPrintable(scalar(databasePath,
                                       QStringLiteral(
                                           "SELECT config_sha256 FROM product_config_versions pcv "
                                           "JOIN products p ON p.id = pcv.product_id "
                                           "WHERE p.name = 'JC6000-BGA-C0009' AND pcv.version_code = 'V1'"))
                                    .toString()),
                     qPrintable(scalar(databasePath,
                                       QStringLiteral(
                                           "SELECT pcv.description FROM product_config_versions pcv "
                                           "JOIN products p ON p.id = pcv.product_id "
                                           "WHERE p.name = 'JC6000-BGA-C0009' AND pcv.version_code = 'V1'"))
                                    .toString()),
                     externalChangeCount);
        return 85;
    }
    if (QFileInfo(lastExternalChangePath).absoluteFilePath()
        != QFileInfo(testOnlyPath).absoluteFilePath()) {
        return 86;
    }

    // An invalid or half-written external file must never replace the last
    // known-good database hash, nor tell the editor to reload it.
    reportedErrors.clear();
    const int validExternalChangeCount = externalChangeCount;
    if (!writeBytesAtomically(testOnlyPath, QByteArrayLiteral("{ invalid json\n"))) {
        return 87;
    }
    if (!waitUntil([&reportedErrors]() {
            for (const QString &message : reportedErrors) {
                if (message.contains(QStringLiteral("external product config"),
                                     Qt::CaseInsensitive)) {
                    return true;
                }
            }
            return false;
        })) {
        return 88;
    }
    if (externalChangeCount != validExternalChangeCount
        || scalar(databasePath,
                  QStringLiteral(
                      "SELECT config_sha256 FROM product_config_versions pcv "
                      "JOIN products p ON p.id = pcv.product_id "
                      "WHERE p.name = 'JC6000-BGA-C0009' AND pcv.version_code = 'V1'"))
               .toString()
            != externallyModifiedHash) {
        return 89;
    }
    if (!writeBytesAtomically(testOnlyPath, externallyModifiedBytes)) {
        return 90;
    }

    // Merely dropping a new valid JSON into the directory must not publish a
    // new product implicitly. Only an already registered product/version is
    // eligible for automatic reconciliation.
    const QString unregisteredCode = QStringLiteral("UNREGISTERED-PRODUCT");
    const QJsonObject unregisteredConfig =
        testOnlyV3Config(manager, unregisteredCode, QStringLiteral("未登记产品"));
    const QString unregisteredPath =
        QDir(productsDir).filePath(unregisteredCode + QStringLiteral("_V1.json"));
    const int externalChangesBeforeUnregistered = externalChangeCount;
    if (!writeBytesAtomically(
            unregisteredPath,
            QJsonDocument(unregisteredConfig).toJson(QJsonDocument::Indented))) {
        return 91;
    }
    processEventsFor(500);
    if (externalChangeCount != externalChangesBeforeUnregistered
        || scalar(databasePath,
                  QStringLiteral(
                      "SELECT COUNT(*) FROM products WHERE name = 'UNREGISTERED-PRODUCT'"))
               .toInt()
            != 0) {
        return 92;
    }

    QJsonObject deprecatedConfig =
        testOnlyV3Config(manager, testOnlyCode, QStringLiteral("历史测试配置"));
    QJsonObject deprecatedProduct =
        deprecatedConfig.value(QStringLiteral("product")).toObject();
    deprecatedProduct.insert(QStringLiteral("version"), QStringLiteral("V2"));
    deprecatedConfig.insert(QStringLiteral("product"), deprecatedProduct);
    deprecatedConfig.insert(
        QStringLiteral("lifecycle"),
        QJsonObject{{QStringLiteral("status"), QStringLiteral("deprecated")}});
    if (!manager.saveProductConfigVersionAs(
            deprecatedConfig, testOnlyCode, QStringLiteral("V2"))) {
        return 33;
    }
    if (scalar(databasePath,
               QStringLiteral(
                   "SELECT COUNT(*) FROM products WHERE name = 'JC6000-BGA-C0009' "
                   "AND status = 'active'"))
            .toInt()
            != 1
        || scalar(databasePath,
                  QStringLiteral(
                      "SELECT COUNT(*) FROM product_config_versions pcv "
                      "JOIN products p ON p.id = pcv.product_id "
                      "WHERE p.name = 'JC6000-BGA-C0009' AND pcv.version_code = 'V2' "
                      "AND pcv.status = 'deprecated'"))
               .toInt()
            != 1) {
        return 34;
    }

    // Reconciliation of V1 must not steal the default flag from V2 merely
    // because V1 happened to be the file that changed.
    QJsonObject externallyModifiedAgain = externallyModified;
    QJsonObject externallyModifiedAgainProduct =
        externallyModifiedAgain.value(QStringLiteral("product")).toObject();
    externallyModifiedAgainProduct.insert(QStringLiteral("description"),
                                          QStringLiteral("二次外部映射修复"));
    externallyModifiedAgain.insert(QStringLiteral("product"), externallyModifiedAgainProduct);
    const QByteArray externallyModifiedAgainBytes =
        QJsonDocument(externallyModifiedAgain).toJson(QJsonDocument::Indented);
    const QString externallyModifiedAgainHash = QString::fromLatin1(
        QCryptographicHash::hash(externallyModifiedAgainBytes, QCryptographicHash::Sha256)
            .toHex());
    const int externalChangesBeforeSecondRepair = externalChangeCount;
    if (!writeBytesAtomically(testOnlyPath, externallyModifiedAgainBytes)
        || !waitUntil([&]() {
               return scalar(databasePath,
                             QStringLiteral(
                                 "SELECT config_sha256 FROM product_config_versions pcv "
                                 "JOIN products p ON p.id = pcv.product_id "
                                 "WHERE p.name = 'JC6000-BGA-C0009' AND pcv.version_code = 'V1'"))
                          .toString()
                       == externallyModifiedAgainHash
                   && externalChangeCount == externalChangesBeforeSecondRepair + 1;
           })) {
        return 93;
    }
    if (scalar(databasePath,
               QStringLiteral(
                   "SELECT COUNT(*) FROM product_config_versions pcv "
                   "JOIN products p ON p.id = pcv.product_id "
                   "WHERE p.name = 'JC6000-BGA-C0009' AND pcv.version_code = 'V2' "
                   "AND pcv.is_default = 1"))
            .toInt()
            != 1
        || scalar(databasePath,
                  QStringLiteral(
                      "SELECT COUNT(*) FROM product_config_versions pcv "
                      "JOIN products p ON p.id = pcv.product_id "
                      "WHERE p.name = 'JC6000-BGA-C0009' AND pcv.version_code = 'V1' "
                      "AND pcv.is_default = 0"))
               .toInt()
            != 1) {
        return 94;
    }

    const QString firmwareCode = QStringLiteral("JC6000-AR000003");
    const QString firmwareVersion = QStringLiteral("V2.0.2");
    const QString firmwareArtifact = firmwareCode + QStringLiteral("_V2.0.2.elf");
    const QString firmwareDirectory = QDir(productsDir).filePath(firmwareCode);
    if (!QDir().mkpath(firmwareDirectory)
        || !writeBytes(QDir(firmwareDirectory).filePath(firmwareArtifact),
                       QByteArrayLiteral("firmware fixture"))) {
        return 26;
    }
    const QJsonObject firmwareConfig =
        firmwareBackedV3Config(manager, firmwareCode, firmwareVersion, firmwareArtifact);
    const QString firmwareConfigPath =
        QDir(firmwareDirectory).filePath(firmwareCode + QStringLiteral("_V2.0.2.json"));
    if (!manager.saveProductConfig(firmwareConfig, firmwareConfigPath))
        return 27;
    if (scalar(databasePath,
               QStringLiteral(
                   "SELECT COUNT(*) FROM product_version_firmwares pvf "
                   "JOIN product_config_versions pcv ON pcv.id = pvf.product_version_id "
                   "JOIN products p ON p.id = pcv.product_id "
                   "JOIN firmwares f ON f.id = pvf.firmware_id "
                   "WHERE p.name = 'JC6000-AR000003' AND pcv.version_code = 'V2.0.2' "
                   "AND pcv.schema_version = 3 AND pcv.operation_mode = 'firmware-backed' "
                   "AND pcv.firmware_source = 'bundled' AND f.version = '2.0.2' "
                   "AND f.version_code = 'V2.0.2' "
                   "AND f.file_name = 'JC6000-AR000003_V2.0.2.elf' "
                   "AND pvf.compatibility_level = 'exact' AND pvf.is_default = 1"))
            .toInt()
        != 1) {
        return 28;
    }

    const QString missingCode = QStringLiteral("JC6000-MISSING-FW");
    const QString missingArtifact = missingCode + QStringLiteral("_V9.1.0.elf");
    const QJsonObject missingFirmwareConfig =
        firmwareBackedV3Config(manager, missingCode, QStringLiteral("V9.1.0"), missingArtifact);
    const QString missingConfigPath =
        QDir(productsDir).filePath(missingCode + QStringLiteral("_V9.1.0.json"));
    if (manager.saveProductConfig(missingFirmwareConfig, missingConfigPath)
        || QFileInfo::exists(missingConfigPath)) {
        return 29;
    }

    qunsetenv("CANJOYSTICK_DATABASE_PATH");
    QTemporaryDir implicitRoot;
    if (!implicitRoot.isValid())
        return 13;
    const QString implicitProducts = QDir(implicitRoot.path()).filePath(QStringLiteral("products"));
    const QString implicitData = QDir(implicitRoot.path()).filePath(QStringLiteral("data"));
    if (!QDir().mkpath(implicitProducts) || !QDir().mkpath(implicitData))
        return 14;
    const QString implicitDatabase = QDir(implicitData).filePath(QStringLiteral("production_data.db"));
    if (!createCanonicalDatabase(implicitDatabase))
        return 15;
    LayoutManager implicitManager;
    implicitManager.setProductsDirectory(implicitProducts);
    const QString implicitConfig = QDir(implicitProducts).filePath(QStringLiteral("RELEASED-PRODUCT_V3.json"));
    if (!implicitManager.saveProductConfig(released, implicitConfig))
        return 16;

    return 0;
}
