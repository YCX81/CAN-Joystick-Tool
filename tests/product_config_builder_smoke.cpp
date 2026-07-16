#include "LayoutManager.h"

#include <QCoreApplication>
#include <QDebug>
#include <QDir>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QString>
#include <QStringList>
#include <QTemporaryDir>
#include <QUuid>

namespace {

bool expect(bool condition, const QString &message)
{
    if (!condition) {
        qCritical().noquote() << message;
    }
    return condition;
}

QJsonObject findObject(const QJsonArray &objects, const QString &key, const QString &value)
{
    for (const QJsonValue &entry : objects) {
        const QJsonObject object = entry.toObject();
        if (object.value(key).toString() == value) {
            return object;
        }
    }
    return {};
}

int countObjects(const QJsonArray &objects, const QString &key, const QString &value)
{
    int count = 0;
    for (const QJsonValue &entry : objects) {
        if (entry.toObject().value(key).toString() == value) {
            ++count;
        }
    }
    return count;
}

QJsonObject findCell(const QJsonArray &cells, int row, int column)
{
    for (const QJsonValue &entry : cells) {
        const QJsonObject cell = entry.toObject();
        if (cell.value(QStringLiteral("row")).toInt(-1) == row
            && cell.value(QStringLiteral("col")).toInt(-1) == column) {
            return cell;
        }
    }
    return {};
}

QString uniqueConnectionName(const QString &prefix)
{
    return prefix + QLatin1Char('_')
        + QUuid::createUuid().toString(QUuid::WithoutBraces);
}

bool createCanonicalDatabase(const QString &databasePath)
{
    const QString connectionName = uniqueConnectionName(QStringLiteral("generic_customer_create"));
    bool success = false;
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connectionName);
        database.setDatabaseName(databasePath);
        if (database.open()) {
            const QStringList statements{
                QStringLiteral(
                    "CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, migration_name TEXT NOT NULL, "
                    "application_version TEXT NOT NULL DEFAULT '', applied_at TEXT)"),
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
                QStringLiteral("INSERT INTO schema_migrations (version, migration_name) VALUES (2, 'functional-device-bindings-v2')"),
                QStringLiteral("PRAGMA user_version = 2")
            };

            success = true;
            for (const QString &statement : statements) {
                QSqlQuery query(database);
                if (!query.exec(statement)) {
                    success = false;
                    break;
                }
            }
            database.close();
        }
    }
    QSqlDatabase::removeDatabase(connectionName);
    return success;
}

int customerBindingCount(const QString &databasePath,
                         const QString &customerName,
                         const QString &productName)
{
    const QString connectionName = uniqueConnectionName(QStringLiteral("generic_customer_verify"));
    int count = -1;
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connectionName);
        database.setConnectOptions(QStringLiteral("QSQLITE_OPEN_READONLY"));
        database.setDatabaseName(databasePath);
        if (database.open()) {
            QSqlQuery query(database);
            query.prepare(QStringLiteral(
                "SELECT COUNT(*) FROM customers c "
                "JOIN product_customer_bindings pcb ON pcb.customer_id = c.id "
                "JOIN products p ON p.id = pcb.product_id "
                "WHERE c.name = ? AND c.type = 'real' AND c.status = 'active' "
                "AND p.name = ? AND pcb.is_default = 1"));
            query.addBindValue(customerName);
            query.addBindValue(productName);
            if (query.exec() && query.next()) {
                count = query.value(0).toInt();
            }
            database.close();
        }
    }
    QSqlDatabase::removeDatabase(connectionName);
    return count;
}

bool verifyTypedCustomerPersistence()
{
    QTemporaryDir root;
    if (!expect(root.isValid(), QStringLiteral("could not create customer integration temp directory"))) {
        return false;
    }

    const QString productsDirectory = QDir(root.path()).filePath(QStringLiteral("firmware"));
    if (!expect(QDir().mkpath(productsDirectory), QStringLiteral("could not create product directory"))) {
        return false;
    }

    const QString databasePath = QDir(root.path()).filePath(QStringLiteral("production_data.db"));
    if (!expect(createCanonicalDatabase(databasePath),
                QStringLiteral("could not create canonical customer integration database"))) {
        return false;
    }

    constexpr auto environmentName = "CANJOYSTICK_DATABASE_PATH";
    const bool hadPreviousDatabasePath = qEnvironmentVariableIsSet(environmentName);
    const QByteArray previousDatabasePath = qgetenv(environmentName);
    qputenv(environmentName, databasePath.toUtf8());

    LayoutManager manager;
    manager.setProductsDirectory(productsDirectory);
    const QString productName = QStringLiteral("GENERIC-CUSTOMER-SAVE");
    const QString customerName = QStringLiteral("TYPED-NEW-CUSTOMER");
    const QJsonObject config = manager.buildStandardProductConfig(QJsonObject{
        {QStringLiteral("model"), productName},
        {QStringLiteral("customerName"), customerName},
        {QStringLiteral("buttonCount"), 6},
        {QStringLiteral("rollerCount"), 2}
    });
    const bool saved = manager.saveProductConfigVersionAs(
        config, productName, QStringLiteral("V1"));

    if (hadPreviousDatabasePath) {
        qputenv(environmentName, previousDatabasePath);
    } else {
        qunsetenv(environmentName);
    }

    bool ok = expect(saved, QStringLiteral("generic config with a typed customer did not save"));
    ok &= expect(customerBindingCount(databasePath, customerName, productName) == 1,
                 QStringLiteral("typed customer was not created and bound to the product"));
    return ok;
}

bool verifyGenericConfig(LayoutManager &manager,
                         const QJsonObject &config,
                         int expectedButtonCount,
                         int expectedRollerCount,
                         const QString &expectedCustomer)
{
    bool ok = true;
    const QJsonObject product = config.value(QStringLiteral("product")).toObject();
    ok &= expect(product.value(QStringLiteral("protocol")).toString() == QStringLiteral("j1939"),
                 QStringLiteral("product.protocol must be j1939"));
    ok &= expect(product.value(QStringLiteral("canFrameFormat")).toString() == QStringLiteral("extended"),
                 QStringLiteral("J1939 must use extended CAN frames"));
    ok &= expect(product.value(QStringLiteral("sourceAddress")).toString() == QStringLiteral("0x33"),
                 QStringLiteral("default J1939 sourceAddress must be 0x33"));

    const QJsonArray customerBindings = product.value(QStringLiteral("customerBindings")).toArray();
    if (expectedCustomer.isEmpty()) {
        ok &= expect(customerBindings.isEmpty(), QStringLiteral("unexpected customer binding"));
    } else {
        ok &= expect(customerBindings.size() == 1,
                     QStringLiteral("typed customer must create exactly one binding"));
        ok &= expect(customerBindings.at(0).toObject().value(QStringLiteral("name")).toString()
                         == expectedCustomer,
                     QStringLiteral("typed customer binding was not preserved"));
    }

    const QJsonObject can = config.value(QStringLiteral("can")).toObject();
    const QJsonArray messages = can.value(QStringLiteral("messages")).toArray();
    const QJsonObject bjm = findObject(messages, QStringLiteral("id"), QStringLiteral("bjm"));
    const QJsonObject ejm = findObject(messages, QStringLiteral("id"), QStringLiteral("ejm"));
    const QJsonObject addressClaim = findObject(messages, QStringLiteral("id"), QStringLiteral("addressClaim"));
    ok &= expect(!bjm.isEmpty(), QStringLiteral("generic config is missing BJM"));
    ok &= expect(!addressClaim.isEmpty(), QStringLiteral("generic config is missing address claim"));

    const QJsonObject buttonField = findObject(
        bjm.value(QStringLiteral("fields")).toArray(),
        QStringLiteral("name"),
        QStringLiteral("buttons"));
    if (expectedButtonCount == 0) {
        ok &= expect(buttonField.isEmpty(), QStringLiteral("zero buttons must omit the BJM button field"));
    } else {
        ok &= expect(buttonField.value(QStringLiteral("buttonCount")).toInt() == expectedButtonCount,
                     QStringLiteral("BJM buttonCount does not match the selected count"));
        const int expectedBits = ((expectedButtonCount * 2 + 7) / 8) * 8;
        ok &= expect(buttonField.value(QStringLiteral("bitLength")).toInt() == expectedBits,
                     QStringLiteral("BJM button bitLength does not match j1939_2bit encoding"));
        ok &= expect(buttonField.value(QStringLiteral("encoding")).toString()
                         == QStringLiteral("j1939_2bit"),
                     QStringLiteral("BJM buttons must use j1939_2bit"));
    }

    if (expectedRollerCount == 0) {
        ok &= expect(ejm.isEmpty(), QStringLiteral("zero rollers must omit EJM"));
    } else {
        ok &= expect(!ejm.isEmpty(), QStringLiteral("generic config is missing EJM"));
        ok &= expect(ejm.value(QStringLiteral("fields")).toArray().size() == expectedRollerCount * 2,
                     QStringLiteral("EJM fields do not match the selected roller count"));
    }

    const QJsonArray components = config.value(QStringLiteral("components")).toArray();
    ok &= expect(countObjects(components, QStringLiteral("type"), QStringLiteral("joystick")) == 1,
                 QStringLiteral("generic config must contain one XY joystick component"));
    ok &= expect(countObjects(components, QStringLiteral("type"), QStringLiteral("roller"))
                     == expectedRollerCount,
                 QStringLiteral("roller components do not match the selected count"));
    const QJsonObject buttons = findObject(components, QStringLiteral("id"), QStringLiteral("buttons"));
    if (expectedButtonCount == 0) {
        ok &= expect(buttons.isEmpty(), QStringLiteral("zero buttons must omit the button component"));
    } else {
        ok &= expect(buttons.value(QStringLiteral("count")).toInt() == expectedButtonCount,
                     QStringLiteral("button component count does not match the selected count"));
    }

    const QJsonObject editor = config.value(QStringLiteral("editor")).toObject();
    ok &= expect(editor.value(QStringLiteral("profile")).toString() == QStringLiteral("j1939Generic"),
                 QStringLiteral("generic config must use the j1939Generic editor profile"));
    ok &= expect(editor.value(QStringLiteral("buttonCount")).toInt(-1) == expectedButtonCount,
                 QStringLiteral("editor.buttonCount does not match"));
    ok &= expect(editor.value(QStringLiteral("rollerCount")).toInt(-1) == expectedRollerCount,
                 QStringLiteral("editor.rollerCount does not match"));
    ok &= expect(!editor.value(QStringLiteral("manualMappingRequired")).toBool(false),
                 QStringLiteral("generic config must be immediately usable"));

    const QJsonArray cells = config.value(QStringLiteral("layout")).toObject()
                                 .value(QStringLiteral("grid")).toObject()
                                 .value(QStringLiteral("cells")).toArray();
    const QJsonObject frontCell = findCell(cells, 0, 0);
    const QJsonObject rearCell = findCell(cells, 1, 0);
    ok &= expect(frontCell.value(QStringLiteral("visualComponents")).toArray().size()
                     == expectedButtonCount,
                 QStringLiteral("button visuals do not match the selected count"));
    ok &= expect(rearCell.value(QStringLiteral("visualComponents")).toArray().size()
                     == expectedRollerCount,
                 QStringLiteral("roller visuals do not match the selected count"));

    const QJsonObject validation = manager.validateProductConfig(config);
    ok &= expect(validation.value(QStringLiteral("ok")).toBool(),
                 QStringLiteral("generated generic config did not pass validation: %1")
                     .arg(QString::fromUtf8(QJsonDocument(validation).toJson(QJsonDocument::Compact))));
    return ok;
}

} // namespace

int main(int argc, char *argv[])
{
    QCoreApplication application(argc, argv);
    LayoutManager manager;
    bool ok = true;

    const QJsonObject defaultConfig = manager.buildStandardProductConfig(QJsonObject{
        {QStringLiteral("model"), QStringLiteral("GENERIC-DEFAULT")},
        {QStringLiteral("customerName"), QStringLiteral("NEW-CUSTOMER")}
    });
    ok &= verifyGenericConfig(manager, defaultConfig, 10, 4, QStringLiteral("NEW-CUSTOMER"));

    const QJsonObject customConfig = manager.buildStandardProductConfig(QJsonObject{
        {QStringLiteral("model"), QStringLiteral("GENERIC-CUSTOM")},
        {QStringLiteral("buttonCount"), 3},
        {QStringLiteral("rollerCount"), 2}
    });
    ok &= verifyGenericConfig(manager, customConfig, 3, 2, QString());

    const QJsonObject boundedConfig = manager.buildStandardProductConfig(QJsonObject{
        {QStringLiteral("model"), QStringLiteral("GENERIC-BOUNDED")},
        {QStringLiteral("buttonCount"), 99},
        {QStringLiteral("rollerCount"), 99}
    });
    ok &= verifyGenericConfig(manager, boundedConfig, 12, 4, QString());

    const QJsonObject emptyConfig = manager.buildStandardProductConfig(QJsonObject{
        {QStringLiteral("model"), QStringLiteral("GENERIC-EMPTY")},
        {QStringLiteral("buttonCount"), -1},
        {QStringLiteral("rollerCount"), -1}
    });
    ok &= verifyGenericConfig(manager, emptyConfig, 0, 0, QString());
    ok &= verifyTypedCustomerPersistence();

    if (!ok) {
        return 1;
    }
    qInfo() << "Generic J1939 product config builder smoke passed";
    return 0;
}
