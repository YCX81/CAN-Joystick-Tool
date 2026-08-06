#include "LayoutManager.h"

#include <QCoreApplication>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QString>
#include <QStringList>
#include <QTemporaryDir>
#include <QUuid>
#include <cstdio>

namespace {

bool expect(bool condition, const QString &message)
{
    if (!condition) {
        qCritical().noquote() << message;
        std::fprintf(stderr, "%s\n", qPrintable(message));
    }
    return condition;
}

bool writeBytes(const QString &path, const QByteArray &bytes)
{
    QFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(bytes) == bytes.size();
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

QJsonObject findCard(const QJsonArray &cards, int row, int column)
{
    for (const QJsonValue &entry : cards) {
        const QJsonObject card = entry.toObject();
        const QJsonObject grid = card.value(QStringLiteral("grid")).toObject();
        if (grid.value(QStringLiteral("row")).toInt(-1) == row
            && grid.value(QStringLiteral("column")).toInt(-1) == column) {
            return card;
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
                    "schema_version INTEGER NOT NULL DEFAULT 2, "
                    "operation_mode TEXT NOT NULL DEFAULT 'legacy', "
                    "firmware_source TEXT NOT NULL DEFAULT '', "
                    "description TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'active', "
                    "is_default INTEGER NOT NULL DEFAULT 0, updated_at TEXT, "
                    "UNIQUE(product_id, version_code))"),
                QStringLiteral(
                    "CREATE TABLE firmwares (id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER, "
                    "version TEXT NOT NULL DEFAULT '', version_code TEXT NOT NULL DEFAULT '', "
                    "description TEXT NOT NULL DEFAULT '', file_name TEXT NOT NULL, "
                    "file_path TEXT NOT NULL UNIQUE, sha256 TEXT NOT NULL DEFAULT '', "
                    "file_size INTEGER NOT NULL DEFAULT 0, file_mtime TEXT NOT NULL DEFAULT '', "
                    "status TEXT NOT NULL DEFAULT 'active', updated_at TEXT)"),
                QStringLiteral(
                    "CREATE TABLE product_version_firmwares (id INTEGER PRIMARY KEY AUTOINCREMENT, "
                    "product_version_id INTEGER NOT NULL, firmware_id INTEGER NOT NULL, "
                    "compatibility_level TEXT NOT NULL DEFAULT 'exact', "
                    "is_default INTEGER NOT NULL DEFAULT 0, updated_at TEXT, "
                    "UNIQUE(product_version_id, firmware_id))"),
                QStringLiteral(
                    "CREATE TABLE customers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, "
                    "type TEXT NOT NULL DEFAULT 'real', status TEXT NOT NULL DEFAULT 'active')"),
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
    const QString savedConfigPath = QDir(productsDirectory).filePath(
        productName + QLatin1Char('/') + productName + QStringLiteral("_V1.json"));
    QFile savedConfigFile(savedConfigPath);
    ok &= expect(savedConfigFile.open(QIODevice::ReadOnly),
                 QStringLiteral("could not read persisted generic config"));
    if (savedConfigFile.isOpen()) {
        const QJsonObject persistedConfig =
            QJsonDocument::fromJson(savedConfigFile.readAll()).object();
        ok &= expect(!persistedConfig.contains(QStringLiteral("firmware")),
                     QStringLiteral("test-only external products must not gain a synthetic firmware block"));
    }
    ok &= expect(customerBindingCount(databasePath, customerName, productName) == 1,
                 QStringLiteral("typed customer was not created and bound to the product"));
    return ok;
}

bool verifyCloneCustomerReplacementPersistence()
{
    QTemporaryDir root;
    if (!expect(root.isValid(), QStringLiteral("could not create clone customer temp directory"))) {
        return false;
    }

    const QString productsDirectory = QDir(root.path()).filePath(QStringLiteral("firmware"));
    if (!expect(QDir().mkpath(productsDirectory), QStringLiteral("could not create clone product directory"))) {
        return false;
    }

    const QString databasePath = QDir(root.path()).filePath(QStringLiteral("production_data.db"));
    if (!expect(createCanonicalDatabase(databasePath),
                QStringLiteral("could not create clone customer database"))) {
        return false;
    }

    constexpr auto environmentName = "CANJOYSTICK_DATABASE_PATH";
    const bool hadPreviousDatabasePath = qEnvironmentVariableIsSet(environmentName);
    const QByteArray previousDatabasePath = qgetenv(environmentName);
    qputenv(environmentName, databasePath.toUtf8());

    LayoutManager manager;
    manager.setProductsDirectory(productsDirectory);
    const QString productName = QStringLiteral("GENERIC-CLONED-CUSTOMER");
    const QString oldCustomer = QStringLiteral("OLD-CUSTOMER");
    const QString newCustomer = QStringLiteral("NEW-CUSTOMER");
    const QJsonObject source = manager.buildStandardProductConfigV3(QJsonObject{
        {QStringLiteral("code"), QStringLiteral("GENERIC-SOURCE-CUSTOMER")},
        {QStringLiteral("customerName"), oldCustomer},
        {QStringLiteral("buttonCount"), 1},
        {QStringLiteral("rollerCount"), 0}
    });
    const QJsonObject cloned =
        manager.cloneProductConfigV3(source,
                                     productName,
                                     QStringLiteral("customer replacement"),
                                     QStringLiteral("V1"));
    const bool saved = manager.saveProductConfigVersionWithCustomerAs(
        cloned, productName, QStringLiteral("V1"), newCustomer);

    if (hadPreviousDatabasePath) {
        qputenv(environmentName, previousDatabasePath);
    } else {
        qunsetenv(environmentName);
    }

    bool ok = expect(saved, QStringLiteral("source-based clone with changed customer did not save"));
    const QString savedConfigPath = QDir(productsDirectory).filePath(
        productName + QLatin1Char('/') + productName + QStringLiteral("_V1.json"));
    QFile savedConfigFile(savedConfigPath);
    ok &= expect(savedConfigFile.open(QIODevice::ReadOnly),
                 QStringLiteral("could not read source-based cloned config"));
    if (savedConfigFile.isOpen()) {
        const QJsonArray bindings =
            QJsonDocument::fromJson(savedConfigFile.readAll())
                .object()
                .value(QStringLiteral("product"))
                .toObject()
                .value(QStringLiteral("customerBindings"))
                .toArray();
        ok &= expect(bindings.size() == 1
                         && bindings.first().toObject().value(QStringLiteral("name")).toString()
                                == newCustomer,
                     QStringLiteral("changed clone customer must replace the inherited JSON binding"));
    }
    ok &= expect(customerBindingCount(databasePath, newCustomer, productName) == 1,
                 QStringLiteral("changed clone customer was not bound in the database"));
    ok &= expect(customerBindingCount(databasePath, oldCustomer, productName) == 0,
                 QStringLiteral("inherited clone customer remained bound in the database"));
    return ok;
}

QJsonObject workLightCommand(const QJsonObject &config, const QString &commandId)
{
    return findObject(config.value(QStringLiteral("commands")).toArray(),
                      QStringLiteral("id"),
                      commandId);
}

bool verifyV3BuilderAndClone()
{
    LayoutManager manager;
    bool ok = true;

    const QJsonObject basic = manager.buildStandardProductConfigV3(QJsonObject{
        {QStringLiteral("code"), QStringLiteral("JC6000-BGA-C0009")},
        {QStringLiteral("description"), QStringLiteral("无固件测试产品")},
        {QStringLiteral("customerName"), QStringLiteral("测试客户")},
        {QStringLiteral("buttonCount"), 1},
        {QStringLiteral("buttonNumbers"), QJsonArray{1}},
        {QStringLiteral("rollerCount"), 0}
    });
    ok &= expect(basic.value(QStringLiteral("schemaVersion")).toInt() == 3,
                 QStringLiteral("V3 builder did not set schemaVersion 3"));
    const QJsonObject product = basic.value(QStringLiteral("product")).toObject();
    ok &= expect(product.value(QStringLiteral("code")).toString()
                     == QStringLiteral("JC6000-BGA-C0009"),
                 QStringLiteral("V3 builder did not persist product.code"));
    ok &= expect(product.value(QStringLiteral("version")).toString() == QStringLiteral("V1"),
                 QStringLiteral("V3 builder must default product.version to V1"));
    const QJsonArray customerBindings =
        product.value(QStringLiteral("customerBindings")).toArray();
    ok &= expect(customerBindings.size() == 1
                     && customerBindings.first()
                            .toObject()
                            .value(QStringLiteral("name"))
                            .toString()
                         == QStringLiteral("测试客户")
                     && customerBindings.first()
                            .toObject()
                            .value(QStringLiteral("isDefault"))
                            .toBool(),
                 QStringLiteral("V3 builder must persist the typed default customer"));
    const QJsonArray basicBindingChannels =
        basic.value(QStringLiteral("bindingChannels")).toArray();
    ok &= expect(basicBindingChannels.size() == 1
                     && basicBindingChannels.first()
                            .toObject()
                            .value(QStringLiteral("id"))
                            .toString()
                         == QStringLiteral("button1")
                     && basicBindingChannels.first()
                            .toObject()
                            .value(QStringLiteral("kind"))
                            .toString()
                         == QStringLiteral("button"),
                 QStringLiteral(
                     "V3 builder must persist the selected physical button inventory"));
    ok &= expect(basic.value(QStringLiteral("lifecycle")).toObject()
                     .value(QStringLiteral("status")).toString()
                     == QStringLiteral("active"),
                 QStringLiteral("V3 builder must default lifecycle to active"));
    const QJsonObject operation = basic.value(QStringLiteral("operation")).toObject();
    ok &= expect(operation.value(QStringLiteral("mode")).toString()
                     == QStringLiteral("test_only"),
                 QStringLiteral("V3 builder must default to test_only"));
    ok &= expect(operation.value(QStringLiteral("firmware")).toObject()
                     == QJsonObject{{QStringLiteral("source"), QStringLiteral("external")}},
                 QStringLiteral("V3 test_only builder must only declare external firmware"));
    ok &= expect(basic.value(QStringLiteral("bus")).toObject()
                     .value(QStringLiteral("sourceAddress")).toString()
                     == QStringLiteral("0x33"),
                 QStringLiteral("V3 builder must use canonical hexadecimal J1939 addresses"));
    ok &= expect(basic.value(QStringLiteral("layout")).toObject()
                      .value(QStringLiteral("mode")).toString()
                      == QStringLiteral("designed"),
                   QStringLiteral("V3 builder must generate designed layout"));
    const QJsonArray blankCards =
        basic.value(QStringLiteral("layout")).toObject()
            .value(QStringLiteral("cards")).toArray();
    const QJsonObject frontCard = findCard(blankCards, 0, 0);
    const QJsonObject busStatsCard = findCard(blankCards, 0, 1);
    const QJsonObject backCard = findCard(blankCards, 1, 0);
    const QJsonObject recordInfoCard = findCard(blankCards, 1, 1);
    ok &= expect(blankCards.size() == 4
                     && frontCard.value(QStringLiteral("kind")).toString()
                            == QStringLiteral("controls")
                     && frontCard.value(QStringLiteral("title")).toString()
                            == QStringLiteral("正面")
                     && backCard.value(QStringLiteral("kind")).toString()
                            == QStringLiteral("controls")
                     && backCard.value(QStringLiteral("title")).toString()
                            == QStringLiteral("背面"),
                 QStringLiteral(
                     "blank V3 products must place front/back canvases in the left column"));
    ok &= expect(busStatsCard.value(QStringLiteral("kind")).toString()
                         == QStringLiteral("system")
                     && busStatsCard.value(QStringLiteral("systemType")).toString()
                            == QStringLiteral("busStats")
                     && busStatsCard.value(QStringLiteral("title")).toString()
                            == QStringLiteral("总线统计")
                     && recordInfoCard.value(QStringLiteral("kind")).toString()
                            == QStringLiteral("system")
                     && recordInfoCard.value(QStringLiteral("systemType")).toString()
                            == QStringLiteral("recordInfo")
                     && recordInfoCard.value(QStringLiteral("title")).toString()
                            == QStringLiteral("记录信息"),
                 QStringLiteral(
                     "blank V3 products must place bus/record cards in the right column"));
    ok &= expect(frontCard.value(QStringLiteral("elements")).toArray().isEmpty()
                     && backCard.value(QStringLiteral("elements")).toArray().isEmpty(),
                 QStringLiteral(
                     "blank V3 products must not place or bind visual components by default"));
    ok &= expect(countObjects(blankCards,
                              QStringLiteral("kind"),
                              QStringLiteral("leftRegion"))
                     == 0,
                 QStringLiteral(
                     "blank V3 products must not create an implicit bound left-region component"));
    const QJsonObject basicJoystick =
        findObject(basic.value(QStringLiteral("controls")).toArray(),
                   QStringLiteral("id"),
                   QStringLiteral("joystickXY"));
    ok &= expect(basicJoystick.value(QStringLiteral("topology")).toObject()
                         == QJsonObject{
                                {QStringLiteral("kind"), QStringLiteral("xy2D")},
                                {QStringLiteral("gate"),
                                 QStringLiteral("omnidirectional")}
                            },
                 QStringLiteral("V3 builder must default to an omnidirectional XY joystick"));
    const QJsonObject basicValidation = manager.validateProductConfig(basic);
    ok &= expect(basicValidation.value(QStringLiteral("ok")).toBool(),
                  QStringLiteral("V3 builder output failed validation: %1")
                      .arg(QString::fromUtf8(
                          QJsonDocument(basicValidation).toJson(QJsonDocument::Compact))));
    ok &= expect(workLightCommand(basic, QStringLiteral("workLightOn")).isEmpty(),
                   QStringLiteral("V3 builder added work-light commands when disabled"));

    const QJsonObject physicalMapping =
        manager.buildStandardProductConfigV3(QJsonObject{
            {QStringLiteral("code"), QStringLiteral("JC6000-PHYSICAL-MAPPING")},
            {QStringLiteral("buttonCount"), 5},
            {QStringLiteral("buttonNumbers"), QJsonArray{1, 2, 3, 4, 5}},
            {QStringLiteral("rollerCount"), 4}
        });
    const QJsonArray physicalSignals =
        physicalMapping.value(QStringLiteral("signals")).toArray();
    const QJsonArray physicalControls =
        physicalMapping.value(QStringLiteral("controls")).toArray();
    const QJsonArray physicalBindingChannels =
        physicalMapping.value(QStringLiteral("bindingChannels")).toArray();
    ok &= expect(physicalBindingChannels.size() == 9
                     && !findObject(physicalBindingChannels,
                                    QStringLiteral("id"),
                                    QStringLiteral("button5")).isEmpty()
                     && !findObject(physicalBindingChannels,
                                    QStringLiteral("id"),
                                    QStringLiteral("roller4")).isEmpty(),
                 QStringLiteral(
                     "selected five buttons and four rollers must remain nine stable binding channels"));
    const QJsonObject axisXStatus =
        findObject(physicalSignals, QStringLiteral("id"), QStringLiteral("axisXStatus"));
    const QJsonObject axisX =
        findObject(physicalSignals, QStringLiteral("id"), QStringLiteral("axisX"));
    const QJsonObject physicalJoystick =
        findObject(physicalControls, QStringLiteral("id"), QStringLiteral("joystickXY"));
    ok &= expect(axisXStatus.value(QStringLiteral("kind")).toString()
                         == QStringLiteral("status")
                     && axisXStatus.value(QStringLiteral("source")).toObject()
                            .value(QStringLiteral("startBit")).toInt()
                         == 0
                     && axisXStatus.value(QStringLiteral("source")).toObject()
                            .value(QStringLiteral("bitLength")).toInt()
                         == 6
                     && axisXStatus.value(QStringLiteral("source")).toObject()
                            .value(QStringLiteral("encoding")).toString()
                         == QStringLiteral("j1939_axis_status")
                     && axisX.value(QStringLiteral("source")).toObject()
                            .value(QStringLiteral("startBit")).toInt()
                         == 6
                     && axisX.value(QStringLiteral("source")).toObject()
                            .value(QStringLiteral("bitLength")).toInt()
                         == 10
                     && physicalJoystick.value(QStringLiteral("xAxis")).toObject()
                            .value(QStringLiteral("statusSignalId")).toString()
                         == QStringLiteral("axisXStatus")
                     && physicalJoystick.value(QStringLiteral("xAxis")).toObject()
                            .value(QStringLiteral("transform")).toObject()
                            .value(QStringLiteral("rawMin")).toInt()
                         == 0
                     && physicalJoystick.value(QStringLiteral("xAxis")).toObject()
                            .value(QStringLiteral("transform")).toObject()
                            .value(QStringLiteral("rawCenter")).toInt()
                         == 0
                     && physicalJoystick.value(QStringLiteral("xAxis")).toObject()
                            .value(QStringLiteral("transform")).toObject()
                            .value(QStringLiteral("rawMax")).toInt()
                         == 1000,
                 QStringLiteral("V3 BJM X axis must retain separate status and magnitude signals"));

    const QJsonObject buttonSignal =
        findObject(physicalSignals, QStringLiteral("id"), QStringLiteral("buttons"));
    const QJsonObject buttonSource =
        buttonSignal.value(QStringLiteral("source")).toObject();
    ok &= expect(buttonSource.value(QStringLiteral("bitLength")).toInt() == 16
                     && buttonSource.value(QStringLiteral("buttonBitPositions")).toArray()
                         == QJsonArray{6, 4, 2, 0, 14},
                 QStringLiteral("five J1939 buttons must use byte-local reverse positions over 16 bits"));

    const QJsonObject roller1Status =
        findObject(physicalSignals, QStringLiteral("id"), QStringLiteral("roller1Status"));
    const QJsonObject roller1Position =
        findObject(physicalSignals, QStringLiteral("id"), QStringLiteral("roller1Position"));
    const QJsonObject roller1 =
        findObject(physicalControls, QStringLiteral("id"), QStringLiteral("roller1"));
    ok &= expect(roller1Status.value(QStringLiteral("source")).toObject()
                         .value(QStringLiteral("startBit")).toInt()
                         == 0
                     && roller1Status.value(QStringLiteral("source")).toObject()
                            .value(QStringLiteral("bitLength")).toInt()
                         == 6
                     && roller1Position.value(QStringLiteral("source")).toObject()
                            .value(QStringLiteral("startBit")).toInt()
                         == 6
                     && roller1Position.value(QStringLiteral("source")).toObject()
                            .value(QStringLiteral("bitLength")).toInt()
                         == 10
                     && roller1.value(QStringLiteral("axis")).toObject()
                            .value(QStringLiteral("statusSignalId")).toString()
                         == QStringLiteral("roller1Status")
                     && roller1.value(QStringLiteral("axis")).toObject()
                            .value(QStringLiteral("transform")).toObject()
                            .value(QStringLiteral("rawCenter")).toInt()
                         == 0,
                 QStringLiteral("V3 EJM rollers must split six-bit status from ten-bit travel"));
    const QJsonObject physicalValidation =
        manager.validateProductConfig(physicalMapping);
    ok &= expect(physicalValidation.value(QStringLiteral("ok")).toBool(),
                 QStringLiteral("physical J1939 V3 output failed validation: %1")
                     .arg(QString::fromUtf8(
                         QJsonDocument(physicalValidation).toJson(QJsonDocument::Compact))));

    const QJsonObject singleX = manager.buildStandardProductConfigV3(QJsonObject{
        {QStringLiteral("code"), QStringLiteral("JC6000-SINGLE-X")},
        {QStringLiteral("joystickTopology"), QStringLiteral("singleAxisX")},
        {QStringLiteral("buttonCount"), 0},
        {QStringLiteral("rollerCount"), 0}
    });
    const QJsonArray singleXSignals = singleX.value(QStringLiteral("signals")).toArray();
    const QJsonObject singleXControl =
        findObject(singleX.value(QStringLiteral("controls")).toArray(),
                   QStringLiteral("id"),
                   QStringLiteral("joystickX"));
    ok &= expect(!findObject(singleXSignals, QStringLiteral("id"), QStringLiteral("axisX")).isEmpty()
                     && findObject(singleXSignals, QStringLiteral("id"), QStringLiteral("axisY")).isEmpty(),
                 QStringLiteral("single-axis X config must declare only axisX"));
    ok &= expect(singleXControl.value(QStringLiteral("type")).toString() == QStringLiteral("axis")
                     && singleXControl.value(QStringLiteral("role")).toString()
                            == QStringLiteral("joystick")
                     && singleXControl.value(QStringLiteral("axis")).toObject()
                            .value(QStringLiteral("signalId")).toString()
                            == QStringLiteral("axisX"),
                 QStringLiteral("single-axis X config must bind one joystick axis control"));
    ok &= expect(manager.validateProductConfig(singleX).value(QStringLiteral("ok")).toBool(),
                 QStringLiteral("single-axis X V3 output failed validation"));

    const QJsonObject singleY = manager.buildStandardProductConfigV3(QJsonObject{
        {QStringLiteral("code"), QStringLiteral("JC6000-SINGLE-Y")},
        {QStringLiteral("joystickTopology"), QStringLiteral("singleAxisY")},
        {QStringLiteral("buttonCount"), 0},
        {QStringLiteral("rollerCount"), 0}
    });
    const QJsonArray singleYSignals = singleY.value(QStringLiteral("signals")).toArray();
    const QJsonObject singleYControl =
        findObject(singleY.value(QStringLiteral("controls")).toArray(),
                   QStringLiteral("id"),
                   QStringLiteral("joystickY"));
    ok &= expect(findObject(singleYSignals, QStringLiteral("id"), QStringLiteral("axisX")).isEmpty()
                     && !findObject(singleYSignals, QStringLiteral("id"), QStringLiteral("axisY")).isEmpty(),
                 QStringLiteral("single-axis Y config must declare only axisY"));
    ok &= expect(singleYControl.value(QStringLiteral("type")).toString() == QStringLiteral("axis")
                     && singleYControl.value(QStringLiteral("topology")).toObject()
                            .value(QStringLiteral("orientation")).toString()
                            == QStringLiteral("vertical"),
                 QStringLiteral("single-axis Y config must use a vertical single-axis topology"));
    ok &= expect(manager.validateProductConfig(singleY).value(QStringLiteral("ok")).toBool(),
                  QStringLiteral("single-axis Y V3 output failed validation"));

    const QJsonObject crossXY = manager.buildStandardProductConfigV3(QJsonObject{
        {QStringLiteral("code"), QStringLiteral("JC6000-CROSS-XY")},
        {QStringLiteral("joystickTopology"), QStringLiteral("crossXY")},
        {QStringLiteral("buttonCount"), 0},
        {QStringLiteral("rollerCount"), 0}
    });
    const QJsonObject crossJoystick =
        findObject(crossXY.value(QStringLiteral("controls")).toArray(),
                   QStringLiteral("id"),
                   QStringLiteral("joystickXY"));
    ok &= expect(crossJoystick.value(QStringLiteral("topology")).toObject()
                         == QJsonObject{
                                {QStringLiteral("kind"), QStringLiteral("cross2D")},
                                {QStringLiteral("gate"), QStringLiteral("cross")}
                            },
                 QStringLiteral("explicit cross-XY config must retain cross2D topology"));
    ok &= expect(manager.validateProductConfig(crossXY).value(QStringLiteral("ok")).toBool(),
                 QStringLiteral("cross-XY V3 output failed validation"));

    const QJsonObject withLight = manager.buildStandardProductConfigV3(QJsonObject{
        {QStringLiteral("code"), QStringLiteral("JC6000-BGA-HM025")},
        {QStringLiteral("description"), QStringLiteral("带灯光测试")},
        {QStringLiteral("buttonCount"), 1},
        {QStringLiteral("buttonNumbers"), QJsonArray{1}},
        {QStringLiteral("rollerCount"), 0},
        {QStringLiteral("hasWorkLight"), true}
    });
    const QJsonObject lightOn =
        workLightCommand(withLight, QStringLiteral("workLightOn"))
            .value(QStringLiteral("frame")).toObject();
    const QJsonObject lightOff =
        workLightCommand(withLight, QStringLiteral("workLightOff"))
            .value(QStringLiteral("frame")).toObject();
    ok &= expect(lightOn.value(QStringLiteral("dlc")).toInt() == 3
                     && lightOn.value(QStringLiteral("data")).toString()
                            == QStringLiteral("00 FA 00"),
                 QStringLiteral("workLightOn must use DLC 3 / 00 FA 00"));
    ok &= expect(lightOff.value(QStringLiteral("dlc")).toInt() == 3
                     && lightOff.value(QStringLiteral("data")).toString()
                            == QStringLiteral("00 00 00"),
                 QStringLiteral("workLightOff must use DLC 3 / 00 00 00"));
    ok &= expect(!findObject(withLight.value(QStringLiteral("controls")).toArray(),
                             QStringLiteral("id"),
                             QStringLiteral("workLight")).isEmpty(),
                 QStringLiteral("work-light builder did not add binaryOutput control"));
    const QJsonObject lightValidation = manager.validateProductConfig(withLight);
    ok &= expect(lightValidation.value(QStringLiteral("ok")).toBool(),
                 QStringLiteral("work-light V3 output failed validation: %1")
                     .arg(QString::fromUtf8(
                         QJsonDocument(lightValidation).toJson(QJsonDocument::Compact))));

    const QJsonObject cloned = manager.cloneProductConfigV3(
        withLight,
        QStringLiteral("JC6000-BGA-HM099"),
        QStringLiteral("克隆产品"),
        QStringLiteral("V3"));
    QJsonObject expected = withLight;
    QJsonObject expectedProduct = expected.value(QStringLiteral("product")).toObject();
    expectedProduct.insert(QStringLiteral("code"), QStringLiteral("JC6000-BGA-HM099"));
    expectedProduct.insert(QStringLiteral("description"), QStringLiteral("克隆产品"));
    expectedProduct.insert(QStringLiteral("version"), QStringLiteral("V3"));
    expected.insert(QStringLiteral("product"), expectedProduct);
    ok &= expect(cloned == expected,
                 QStringLiteral("test_only V3 clone changed fields beyond code/description"));
    ok &= expect(withLight.value(QStringLiteral("product")).toObject()
                     .value(QStringLiteral("code")).toString()
                     == QStringLiteral("JC6000-BGA-HM025"),
                 QStringLiteral("V3 clone mutated the source config"));
    ok &= expect(!cloned.value(QStringLiteral("layout")).toObject()
                      .value(QStringLiteral("grid")).toObject()
                      .contains(QStringLiteral("cells")),
                 QStringLiteral("V3 clone injected legacy layout.grid.cells"));

    QTemporaryDir firmwareRoot;
    ok &= expect(firmwareRoot.isValid(),
                 QStringLiteral("could not create firmware clone temp directory"));
    manager.setProductsDirectory(firmwareRoot.path());
    QJsonObject firmwareBacked = basic;
    QJsonObject firmwareProduct = firmwareBacked.value(QStringLiteral("product")).toObject();
    firmwareProduct.insert(QStringLiteral("code"), QStringLiteral("SOURCE-FIRMWARE"));
    firmwareProduct.insert(QStringLiteral("version"), QStringLiteral("V2.0.2"));
    firmwareBacked.insert(QStringLiteral("product"), firmwareProduct);
    firmwareBacked.insert(
        QStringLiteral("operation"),
        QJsonObject{
            {QStringLiteral("mode"), QStringLiteral("firmware-backed")},
            {QStringLiteral("firmware"),
             QJsonObject{
                 {QStringLiteral("source"), QStringLiteral("bundled")},
                 {QStringLiteral("version"), QStringLiteral("2.0.2")},
                 {QStringLiteral("artifact"), QStringLiteral("SOURCE-FIRMWARE_V2.0.2.elf")}
             }}
        });

    const QJsonObject firmwareClone = manager.cloneProductConfigV3(
        firmwareBacked,
        QStringLiteral("TARGET-FIRMWARE"),
        QStringLiteral("目标固件产品"),
        QStringLiteral("V3"));
    ok &= expect(firmwareClone.value(QStringLiteral("operation")).toObject()
                      .value(QStringLiteral("firmware")).toObject()
                      .value(QStringLiteral("artifact")).toString()
                      == QStringLiteral("TARGET-FIRMWARE_V3.elf"),
                 QStringLiteral("firmware-backed clone did not rename its artifact metadata"));
    ok &= expect(firmwareClone.value(QStringLiteral("product")).toObject()
                      .value(QStringLiteral("version")).toString()
                      == QStringLiteral("V3"),
                 QStringLiteral("firmware-backed clone ignored the requested target version"));

    return ok;
}

bool verifyCatalogStorePersistence()
{
    QTemporaryDir root;
    if (!expect(root.isValid(), QStringLiteral("could not create catalog store temp directory"))) {
        return false;
    }

    LayoutManager manager;
    manager.setProductCatalogRoot(root.path());
    manager.setProductsDirectory(QDir(root.path()).filePath(QStringLiteral("active")));

    QJsonObject config = manager.buildStandardProductConfigV3(QJsonObject{
        {QStringLiteral("code"), QStringLiteral("JC6000-BGA-STORETEST")},
        {QStringLiteral("description"), QStringLiteral("first revision")},
        {QStringLiteral("buttonCount"), 1},
        {QStringLiteral("buttonNumbers"), QJsonArray{1}},
        {QStringLiteral("rollerCount"), 0}
    });
    bool ok = expect(
        manager.saveProductConfigVersionAs(
            config,
            QStringLiteral("JC6000-BGA-STORETEST"),
            QStringLiteral("V1")),
        QStringLiteral("first catalog save failed"));

    const QString activePath = QDir(root.path()).filePath(
        QStringLiteral("active/JC6000-BGA-STORETEST_V1.json"));
    QFile firstFile(activePath);
    ok &= expect(firstFile.open(QIODevice::ReadOnly),
                 QStringLiteral("first active config could not be read"));
    const QByteArray firstBytes = firstFile.readAll();
    firstFile.close();

    QJsonObject product = config.value(QStringLiteral("product")).toObject();
    product.insert(QStringLiteral("description"), QStringLiteral("second revision"));
    config.insert(QStringLiteral("product"), product);
    ok &= expect(manager.saveProductConfig(config, activePath),
                 QStringLiteral("changed catalog save failed"));

    const QDir backupDirectory(QDir(root.path()).filePath(
        QStringLiteral("backups/JC6000-BGA-STORETEST")));
    const QFileInfoList backups = backupDirectory.entryInfoList(
        QStringList{QStringLiteral("*.json")}, QDir::Files, QDir::Name);
    ok &= expect(backups.size() == 1,
                 QStringLiteral("changed catalog save must create one backup"));
    if (backups.size() == 1) {
        QFile backup(backups.constFirst().absoluteFilePath());
        ok &= expect(backup.open(QIODevice::ReadOnly),
                     QStringLiteral("catalog backup could not be read"));
        ok &= expect(backup.readAll() == firstBytes,
                     QStringLiteral("catalog backup did not preserve exact prior bytes"));
    }

    QFile changedFile(activePath);
    ok &= expect(changedFile.open(QIODevice::ReadOnly),
                 QStringLiteral("changed active config could not be read"));
    const QByteArray changedBytes = changedFile.readAll();
    changedFile.close();
    ok &= expect(changedBytes == QJsonDocument(config).toJson(QJsonDocument::Indented),
                 QStringLiteral("changed active config serialization was not stable"));

    ok &= expect(manager.saveProductConfig(config, activePath),
                 QStringLiteral("identical catalog save failed"));
    ok &= expect(backupDirectory.entryInfoList(
                     QStringList{QStringLiteral("*.json")}, QDir::Files).size() == 1,
                 QStringLiteral("identical catalog save must not create another backup"));

    ok &= expect(manager.saveProductDraft(config, activePath),
                 QStringLiteral("catalog draft save failed"));
    const QString draftPath = manager.productDraftPath(activePath);
    ok &= expect(QFileInfo::exists(draftPath),
                 QStringLiteral("catalog draft was not persisted"));
    ok &= expect(manager.loadProductDraft(activePath)
                     .value(QStringLiteral("product")).toObject()
                     .value(QStringLiteral("description")).toString()
                     == QStringLiteral("second revision"),
                 QStringLiteral("catalog draft could not be recovered"));
    ok &= expect(manager.discardProductDraft(activePath),
                 QStringLiteral("catalog draft discard failed"));
    ok &= expect(!QFileInfo::exists(draftPath),
                 QStringLiteral("catalog draft was not removed after save"));
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

bool verifySparseButtonConfig(LayoutManager &manager, const QJsonObject &config)
{
    bool ok = true;
    const QJsonArray messages = config.value(QStringLiteral("can")).toObject()
                                    .value(QStringLiteral("messages")).toArray();
    const QJsonObject bjm = findObject(messages, QStringLiteral("id"), QStringLiteral("bjm"));
    const QJsonObject buttonField = findObject(
        bjm.value(QStringLiteral("fields")).toArray(),
        QStringLiteral("name"),
        QStringLiteral("buttons"));
    ok &= expect(buttonField.value(QStringLiteral("buttonCount")).toInt() == 8,
                 QStringLiteral("buttons 2/3/8 require decoding through physical button 8"));
    ok &= expect(buttonField.value(QStringLiteral("bitLength")).toInt() == 16,
                 QStringLiteral("buttons 2/3/8 require two J1939 button bytes"));

    const QJsonObject buttons = findObject(
        config.value(QStringLiteral("components")).toArray(),
        QStringLiteral("id"),
        QStringLiteral("buttons"));
    ok &= expect(buttons.value(QStringLiteral("count")).toInt() == 8,
                 QStringLiteral("button component must retain the decoded physical range"));
    ok &= expect(buttons.value(QStringLiteral("visibleButtonIndices")).toArray()
                     == QJsonArray{1, 2, 7},
                 QStringLiteral("button component must expose only physical buttons 2/3/8"));

    const QJsonObject editor = config.value(QStringLiteral("editor")).toObject();
    ok &= expect(editor.value(QStringLiteral("buttonCount")).toInt() == 3,
                 QStringLiteral("editor buttonCount must remain the number of fitted buttons"));
    ok &= expect(editor.value(QStringLiteral("buttonNumbers")).toArray()
                     == QJsonArray{2, 3, 8},
                 QStringLiteral("editor must preserve the selected one-based button numbers"));

    const QJsonArray cells = config.value(QStringLiteral("layout")).toObject()
                                 .value(QStringLiteral("grid")).toObject()
                                 .value(QStringLiteral("cells")).toArray();
    const QJsonArray visuals = findCell(cells, 0, 0)
                                   .value(QStringLiteral("visualComponents")).toArray();
    QStringList bindings;
    QStringList labels;
    for (const QJsonValue &entry : visuals) {
        const QJsonObject visual = entry.toObject();
        bindings.append(visual.value(QStringLiteral("bindingId")).toString());
        labels.append(visual.value(QStringLiteral("config")).toObject()
                          .value(QStringLiteral("label")).toString());
    }
    ok &= expect(bindings == QStringList{QStringLiteral("buttons.1"),
                                         QStringLiteral("buttons.2"),
                                         QStringLiteral("buttons.7")},
                 QStringLiteral("canvas must bind only physical buttons 2/3/8"));
    ok &= expect(labels == QStringList{QStringLiteral("2"),
                                       QStringLiteral("3"),
                                       QStringLiteral("8")},
                 QStringLiteral("canvas labels must use physical button numbers"));

    const QJsonObject validation = manager.validateProductConfig(config);
    ok &= expect(validation.value(QStringLiteral("ok")).toBool(),
                 QStringLiteral("sparse button config did not pass validation: %1")
                     .arg(QString::fromUtf8(QJsonDocument(validation).toJson(QJsonDocument::Compact))));
    return ok;
}

QJsonObject withMiniJoystickVisual(const QJsonObject &source,
                                   const QString &xBindingId,
                                   const QString &yBindingId)
{
    QJsonObject config = source;
    QJsonObject layout = config.value(QStringLiteral("layout")).toObject();
    QJsonObject grid = layout.value(QStringLiteral("grid")).toObject();
    QJsonArray cells = grid.value(QStringLiteral("cells")).toArray();

    for (int index = 0; index < cells.size(); ++index) {
        QJsonObject cell = cells.at(index).toObject();
        if (cell.value(QStringLiteral("row")).toInt(-1) != 1
            || cell.value(QStringLiteral("col")).toInt(-1) != 0) {
            continue;
        }

        QJsonArray visuals = cell.value(QStringLiteral("visualComponents")).toArray();
        QJsonObject miniJoystick{
            {QStringLiteral("type"), QStringLiteral("MiniJoystick")},
            {QStringLiteral("x"), 300},
            {QStringLiteral("y"), 20},
            {QStringLiteral("config"), QJsonObject{}},
            {QStringLiteral("xBindingId"), xBindingId}
        };
        if (!yBindingId.isNull()) {
            miniJoystick.insert(QStringLiteral("yBindingId"), yBindingId);
        }
        visuals.append(miniJoystick);
        cell.insert(QStringLiteral("visualComponents"), visuals);
        cells[index] = cell;
        break;
    }

    grid.insert(QStringLiteral("cells"), cells);
    layout.insert(QStringLiteral("grid"), grid);
    config.insert(QStringLiteral("layout"), layout);
    return config;
}

QJsonObject withArbitrarilyNamedRollers(const QJsonObject &source)
{
    QJsonObject config = source;
    QJsonArray components = config.value(QStringLiteral("components")).toArray();
    components.append(QJsonObject{
        {QStringLiteral("id"), QStringLiteral("travel_axis_a")},
        {QStringLiteral("type"), QStringLiteral("roller")},
        {QStringLiteral("label"), QStringLiteral("任意滚轮 A")},
        {QStringLiteral("position"), QStringLiteral("ejm.handleXPos")},
        {QStringLiteral("status"), QStringLiteral("ejm.handleXStatus")}
    });
    components.append(QJsonObject{
        {QStringLiteral("id"), QStringLiteral("travel_axis_b")},
        {QStringLiteral("type"), QStringLiteral("roller")},
        {QStringLiteral("label"), QStringLiteral("任意滚轮 B")},
        {QStringLiteral("position"), QStringLiteral("ejm.handleYPos")},
        {QStringLiteral("status"), QStringLiteral("ejm.handleYStatus")}
    });
    config.insert(QStringLiteral("components"), components);
    return config;
}

bool verifyMiniJoystickDualBindingValidation(LayoutManager &manager)
{
    const QJsonObject standard = manager.buildStandardProductConfig(QJsonObject{
        {QStringLiteral("model"), QStringLiteral("GENERIC-MINI-JOYSTICK")},
        {QStringLiteral("buttonCount"), 0},
        {QStringLiteral("rollerCount"), 2}
    });
    const QJsonObject base = withArbitrarilyNamedRollers(standard);

    bool ok = true;
    const QJsonObject valid = withMiniJoystickVisual(
        base, QStringLiteral("travel_axis_a"), QStringLiteral("travel_axis_b"));
    const QJsonObject validResult = manager.validateProductConfig(valid);
    ok &= expect(validResult.value(QStringLiteral("ok")).toBool(),
                 QStringLiteral("MiniJoystick must accept any two roller component IDs"));

    const QJsonObject missingY = withMiniJoystickVisual(
        base, QStringLiteral("travel_axis_a"), QString());
    const QJsonObject missingYResult = manager.validateProductConfig(missingY);
    ok &= expect(!missingYResult.value(QStringLiteral("ok")).toBool(),
                 QStringLiteral("MiniJoystick without yBindingId must be rejected"));

    const QJsonObject unknownY = withMiniJoystickVisual(
        base, QStringLiteral("travel_axis_a"), QStringLiteral("missing_axis"));
    const QJsonObject unknownYResult = manager.validateProductConfig(unknownY);
    ok &= expect(!unknownYResult.value(QStringLiteral("ok")).toBool(),
                 QStringLiteral("MiniJoystick with an unknown Y binding must be rejected"));

    const QJsonObject sameRoller = withMiniJoystickVisual(
        base, QStringLiteral("travel_axis_a"), QStringLiteral("travel_axis_a"));
    const QJsonObject sameRollerResult = manager.validateProductConfig(sameRoller);
    ok &= expect(!sameRollerResult.value(QStringLiteral("ok")).toBool(),
                 QStringLiteral("MiniJoystick must bind two different rollers"));

    const QJsonObject joystickComponent = withMiniJoystickVisual(
        base, QStringLiteral("travel_axis_a"), QStringLiteral("joystick_xy"));
    const QJsonObject joystickComponentResult = manager.validateProductConfig(joystickComponent);
    ok &= expect(!joystickComponentResult.value(QStringLiteral("ok")).toBool(),
                 QStringLiteral("MiniJoystick bindings must not reference a joystick component"));
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

    const QJsonObject sparseButtonConfig = manager.buildStandardProductConfig(QJsonObject{
        {QStringLiteral("model"), QStringLiteral("GENERIC-SPARSE-BUTTONS")},
        {QStringLiteral("buttonCount"), 3},
        {QStringLiteral("buttonNumbers"), QJsonArray{2, 3, 8}},
        {QStringLiteral("rollerCount"), 0}
    });
    ok &= verifySparseButtonConfig(manager, sparseButtonConfig);

    const QJsonObject emptyConfig = manager.buildStandardProductConfig(QJsonObject{
        {QStringLiteral("model"), QStringLiteral("GENERIC-EMPTY")},
        {QStringLiteral("buttonCount"), -1},
        {QStringLiteral("rollerCount"), -1}
    });
    ok &= verifyGenericConfig(manager, emptyConfig, 0, 0, QString());
    ok &= verifyMiniJoystickDualBindingValidation(manager);
    ok &= verifyTypedCustomerPersistence();
    ok &= verifyCloneCustomerReplacementPersistence();
    ok &= verifyV3BuilderAndClone();
    ok &= verifyCatalogStorePersistence();

    if (!ok) {
        return 1;
    }
    qInfo() << "Generic J1939 product config builder smoke passed";
    return 0;
}
