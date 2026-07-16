#include "LayoutManager.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QTemporaryDir>

namespace {

bool writeBytes(const QString &path, const QByteArray &bytes)
{
    QFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(bytes) == bytes.size();
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

bool createCanonicalDatabase(const QString &databasePath)
{
    const QString connectionName = QStringLiteral("layoutmanager_smoke_create");
    bool success = false;
    {
        QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connectionName);
        db.setDatabaseName(databasePath);
        if (db.open()) {
            const QStringList schema = {
                QStringLiteral("CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, migration_name TEXT NOT NULL)"),
                QStringLiteral(
                    "CREATE TABLE products (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, "
                    "protocol TEXT NOT NULL DEFAULT 'j1939', status TEXT NOT NULL DEFAULT 'active', "
                    "description TEXT, calibration_mode TEXT, calibration_transport TEXT, "
                    "allowed_in_normal_mode_read_only INTEGER, updated_at TEXT)"),
                QStringLiteral(
                    "CREATE TABLE product_config_versions (id INTEGER PRIMARY KEY AUTOINCREMENT, "
                    "product_id INTEGER NOT NULL, version_code TEXT NOT NULL DEFAULT '', "
                    "config_file TEXT NOT NULL DEFAULT '', config_sha256 TEXT NOT NULL DEFAULT '', "
                    "is_default INTEGER NOT NULL DEFAULT 0, updated_at TEXT, UNIQUE(product_id, version_code))"),
                QStringLiteral(
                    "CREATE TABLE customers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, "
                    "type TEXT NOT NULL DEFAULT 'real', status TEXT NOT NULL DEFAULT 'active')"),
                QStringLiteral(
                    "CREATE TABLE product_customer_bindings (id INTEGER PRIMARY KEY AUTOINCREMENT, "
                    "product_id INTEGER NOT NULL, customer_id INTEGER NOT NULL, "
                    "is_default INTEGER NOT NULL DEFAULT 0, updated_at TEXT, UNIQUE(product_id, customer_id))"),
                QStringLiteral("INSERT INTO schema_migrations (version, migration_name) VALUES (1, 'core-event-schema-v1')"),
                QStringLiteral("PRAGMA user_version = 1")
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

    const QString syncedPath = QDir(productsDir).filePath(QStringLiteral("RELEASED-PRODUCT_V2.json"));
    if (!manager.saveProductConfig(released, syncedPath))
        return 10;
    if (databaseHasColumn(databasePath, QStringLiteral("products"), QStringLiteral("config_file"))
        || databaseHasColumn(databasePath, QStringLiteral("products"), QStringLiteral("config_json"))
        || databaseHasColumn(databasePath, QStringLiteral("product_config_versions"), QStringLiteral("status"))
        || databaseHasColumn(databasePath, QStringLiteral("product_config_versions"), QStringLiteral("schema_version"))) {
        return 11;
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
