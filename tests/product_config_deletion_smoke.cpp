#include "LayoutManager.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonObject>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>
#include <QTemporaryDir>
#include <QUuid>

#include <cstdio>

namespace {

bool expect(bool condition, const char *message)
{
    if (!condition)
        std::fprintf(stderr, "%s\n", message);
    return condition;
}

bool executeAll(const QString &databasePath, const QStringList &statements)
{
    const QString connectionName = QStringLiteral("delete_smoke_%1")
                                       .arg(QUuid::createUuid().toString(QUuid::WithoutBraces));
    bool ok = false;
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connectionName);
        database.setDatabaseName(databasePath);
        if (database.open()) {
            ok = true;
            for (const QString &statement : statements) {
                QSqlQuery query(database);
                if (!query.exec(statement)) {
                    std::fprintf(stderr, "SQL failed: %s\n", qPrintable(query.lastError().text()));
                    ok = false;
                    break;
                }
            }
            database.close();
        }
    }
    QSqlDatabase::removeDatabase(connectionName);
    return ok;
}

QVariant scalar(const QString &databasePath, const QString &sql)
{
    const QString connectionName = QStringLiteral("delete_scalar_%1")
                                       .arg(QUuid::createUuid().toString(QUuid::WithoutBraces));
    QVariant value;
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connectionName);
        database.setDatabaseName(databasePath);
        if (database.open()) {
            QSqlQuery query(database);
            if (query.exec(sql) && query.next())
                value = query.value(0);
            database.close();
        }
    }
    QSqlDatabase::removeDatabase(connectionName);
    return value;
}

bool createDatabase(const QString &databasePath)
{
    return executeAll(databasePath, {
        QStringLiteral("CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, migration_name TEXT NOT NULL)"),
        QStringLiteral("INSERT INTO schema_migrations VALUES (1, 'core-event-schema-v1')"),
        QStringLiteral("INSERT INTO schema_migrations VALUES (2, 'functional-device-bindings-v2')"),
        QStringLiteral("INSERT INTO schema_migrations VALUES (3, 'product-config-v3')"),
        QStringLiteral("CREATE TABLE products (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, protocol TEXT NOT NULL DEFAULT 'j1939', status TEXT NOT NULL DEFAULT 'active', updated_at TEXT)"),
        QStringLiteral("CREATE TABLE product_config_versions (id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL, version_code TEXT NOT NULL, config_file TEXT NOT NULL, config_sha256 TEXT NOT NULL DEFAULT '', schema_version INTEGER NOT NULL DEFAULT 3, operation_mode TEXT NOT NULL DEFAULT 'test-only', firmware_source TEXT NOT NULL DEFAULT '', description TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'active', is_default INTEGER NOT NULL DEFAULT 0, updated_at TEXT, UNIQUE(product_id, version_code))"),
        QStringLiteral("CREATE TABLE firmwares (id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER, version TEXT NOT NULL DEFAULT '', version_code TEXT NOT NULL DEFAULT '', description TEXT NOT NULL DEFAULT '', file_name TEXT NOT NULL, file_path TEXT NOT NULL UNIQUE, sha256 TEXT NOT NULL DEFAULT '', file_size INTEGER NOT NULL DEFAULT 0, file_mtime TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'active', updated_at TEXT)"),
        QStringLiteral("CREATE TABLE product_version_firmwares (id INTEGER PRIMARY KEY AUTOINCREMENT, product_version_id INTEGER NOT NULL, firmware_id INTEGER NOT NULL, compatibility_level TEXT NOT NULL DEFAULT 'exact', is_default INTEGER NOT NULL DEFAULT 0, updated_at TEXT, UNIQUE(product_version_id, firmware_id))"),
        QStringLiteral("CREATE TABLE customers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, type TEXT NOT NULL DEFAULT 'real', status TEXT NOT NULL DEFAULT 'active')"),
        QStringLiteral("CREATE TABLE product_customer_bindings (id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL, customer_id INTEGER NOT NULL, is_default INTEGER NOT NULL DEFAULT 0, updated_at TEXT, UNIQUE(product_id, customer_id))"),
        QStringLiteral("CREATE TABLE aliases (id INTEGER PRIMARY KEY AUTOINCREMENT, target_type TEXT, target_id INTEGER, alias TEXT)"),
        QStringLiteral("CREATE TABLE production_records (id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER, product_version_id INTEGER)"),
        QStringLiteral("CREATE TABLE flash_records (id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER, product_version_id INTEGER)"),
        QStringLiteral("CREATE TABLE calibration_records (id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER, product_version_id INTEGER)"),
        QStringLiteral("CREATE TABLE functional_test_records (id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER, product_version_id INTEGER)"),
        QStringLiteral("CREATE TABLE functional_device_bindings (device_identity INTEGER PRIMARY KEY, product_id INTEGER, product_version_id INTEGER)"),
        QStringLiteral("PRAGMA user_version = 3")
    });
}

QJsonObject newConfig(LayoutManager &manager, const QString &code, const QString &version)
{
    return manager.buildStandardProductConfigV3(QJsonObject{
        {QStringLiteral("code"), code},
        {QStringLiteral("version"), version},
        {QStringLiteral("customerName"), QStringLiteral("删除测试客户")},
        {QStringLiteral("buttonCount"), 2},
        {QStringLiteral("buttonNumbers"), QJsonArray{1, 2}},
        {QStringLiteral("rollerCount"), 1}
    });
}

} // namespace

int main(int argc, char *argv[])
{
    QCoreApplication application(argc, argv);
    QTemporaryDir root;
    if (!root.isValid())
        return 2;

    const QString databasePath = QDir(root.path()).filePath(QStringLiteral("production_data.db"));
    const QString productsPath = QDir(root.path()).filePath(QStringLiteral("products"));
    const QString catalogPath = QDir(root.path()).filePath(QStringLiteral("catalog"));
    if (!QDir().mkpath(productsPath) || !QDir().mkpath(catalogPath)
        || !createDatabase(databasePath)) {
        return 3;
    }
    qputenv("CANJOYSTICK_DATABASE_PATH", databasePath.toUtf8());
    qputenv("CANJOYSTICK_PRODUCT_CATALOG_ROOT", catalogPath.toUtf8());

    LayoutManager manager;
    manager.setProductsDirectory(productsPath);

    bool ok = true;
    const QString code = QStringLiteral("DELETE-SAFE");
    const QString version = QStringLiteral("V1");
    const QString path = manager.productConfigVersionPath(code, version);
    ok &= expect(manager.saveProductConfigVersionWithCustomerAs(
                     newConfig(manager, code, version), code, version,
                     QStringLiteral("删除测试客户")),
                 "test product could not be created");

    const QJsonObject analysis = manager.analyzeProductConfigDeletion(path);
    ok &= expect(analysis.value(QStringLiteral("ok")).toBool()
                     && analysis.value(QStringLiteral("allowed")).toBool()
                     && analysis.value(QStringLiteral("confirmationText")).toString()
                         == QStringLiteral("DELETE-SAFE/V1"),
                 "unused product version should be deletable with an exact confirmation text");
    ok &= expect(!manager.deleteProductConfigVersion(path, QStringLiteral("DELETE-SAFE"))
                     && QFileInfo::exists(path),
                 "wrong deletion confirmation must not remove the product");
    ok &= expect(manager.deleteProductConfigVersion(path, QStringLiteral("DELETE-SAFE/V1"))
                     && !QFileInfo::exists(path)
                     && scalar(databasePath, QStringLiteral("SELECT COUNT(*) FROM products")).toInt() == 0
                     && scalar(databasePath, QStringLiteral("SELECT COUNT(*) FROM product_config_versions")).toInt() == 0,
                 "safe deletion did not remove the file and catalog rows together");

    const QDir deletionBackups(QDir(catalogPath).filePath(QStringLiteral("backups/deleted")));
    ok &= expect(!deletionBackups.entryInfoList(QDir::Files | QDir::NoDotAndDotDot,
                                                QDir::Time).isEmpty(),
                 "safe deletion must retain a recoverable config backup");
    ok &= expect(manager.saveProductConfigVersionWithCustomerAs(
                     newConfig(manager, code, version), code, version,
                     QStringLiteral("删除测试客户")),
                 "the same product identity could not be recreated after safe deletion");

    const qlonglong productId = scalar(
        databasePath, QStringLiteral("SELECT id FROM products WHERE name = 'DELETE-SAFE'")).toLongLong();
    const qlonglong versionId = scalar(
        databasePath, QStringLiteral("SELECT id FROM product_config_versions WHERE product_id = %1")
                          .arg(productId)).toLongLong();
    ok &= expect(executeAll(databasePath, {
                     QStringLiteral("INSERT INTO functional_device_bindings (device_identity, product_id, product_version_id) VALUES (7, %1, %2)")
                         .arg(productId).arg(versionId)
                 }),
                 "history blocker could not be inserted");
    const QJsonObject blocked = manager.analyzeProductConfigDeletion(path);
    ok &= expect(blocked.value(QStringLiteral("ok")).toBool()
                     && !blocked.value(QStringLiteral("allowed")).toBool()
                     && blocked.value(QStringLiteral("references")).toObject()
                            .value(QStringLiteral("functionalDeviceBindings")).toInt() == 1,
                 "device history must block hard deletion");
    ok &= expect(!manager.deleteProductConfigVersion(path, QStringLiteral("DELETE-SAFE/V1"))
                     && QFileInfo::exists(path),
                 "blocked product version was deleted");

    return ok ? 0 : 1;
}
