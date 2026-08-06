#include "LayoutManager.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>

namespace {

bool createCanonicalDatabase(const QString &path)
{
    const QString name = QStringLiteral("catalog_publish_db");
    bool ok = false;
    {
        QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), name);
        db.setDatabaseName(path);
        if (db.open()) {
            const QStringList statements = {
                QStringLiteral("CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, migration_name TEXT NOT NULL, application_version TEXT NOT NULL DEFAULT '', applied_at TEXT)"),
                QStringLiteral("CREATE TABLE products (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, protocol TEXT NOT NULL DEFAULT 'j1939', status TEXT NOT NULL DEFAULT 'active', created_at TEXT, updated_at TEXT)"),
                QStringLiteral("CREATE TABLE product_config_versions (id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL, version_code TEXT NOT NULL DEFAULT '', config_file TEXT NOT NULL DEFAULT '', config_sha256 TEXT NOT NULL DEFAULT '', schema_version INTEGER NOT NULL DEFAULT 2, operation_mode TEXT NOT NULL DEFAULT 'legacy', firmware_source TEXT NOT NULL DEFAULT '', description TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'active', is_default INTEGER NOT NULL DEFAULT 0, created_at TEXT, updated_at TEXT, UNIQUE(product_id, version_code))"),
                QStringLiteral("CREATE TABLE firmwares (id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER, customer_id INTEGER, version TEXT NOT NULL DEFAULT '', version_code TEXT NOT NULL DEFAULT '', description TEXT NOT NULL DEFAULT '', file_name TEXT NOT NULL, file_path TEXT NOT NULL UNIQUE, sha256 TEXT NOT NULL DEFAULT '', file_size INTEGER NOT NULL DEFAULT 0, file_mtime TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'active', created_at TEXT, updated_at TEXT)"),
                QStringLiteral("CREATE TABLE product_version_firmwares (id INTEGER PRIMARY KEY AUTOINCREMENT, product_version_id INTEGER NOT NULL, firmware_id INTEGER NOT NULL, compatibility_level TEXT NOT NULL DEFAULT 'exact', is_default INTEGER NOT NULL DEFAULT 0, created_at TEXT, updated_at TEXT, UNIQUE(product_version_id, firmware_id))"),
                QStringLiteral("CREATE TABLE customers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, code TEXT UNIQUE, type TEXT NOT NULL DEFAULT 'real', status TEXT NOT NULL DEFAULT 'active', created_at TEXT, updated_at TEXT)"),
                QStringLiteral("CREATE TABLE product_customer_bindings (id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL, customer_id INTEGER NOT NULL, is_default INTEGER NOT NULL DEFAULT 0, updated_at TEXT, UNIQUE(product_id, customer_id))"),
                QStringLiteral("INSERT INTO schema_migrations(version,migration_name) VALUES(1,'core-event-schema-v1')"),
                QStringLiteral("INSERT INTO schema_migrations(version,migration_name) VALUES(2,'functional-device-bindings-v2')"),
                QStringLiteral("INSERT INTO schema_migrations(version,migration_name) VALUES(3,'product-config-v3')"),
                QStringLiteral("PRAGMA user_version=3")};
            ok = true;
            for (const QString &sql : statements) {
                QSqlQuery query(db);
                if (!query.exec(sql)) {
                    ok = false;
                    break;
                }
            }
            db.close();
        }
    }
    QSqlDatabase::removeDatabase(name);
    return ok;
}

QVariant scalar(const QString &path, const QString &sql)
{
    const QString name = QStringLiteral("catalog_publish_read");
    QVariant value;
    {
        QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), name);
        db.setDatabaseName(path);
        if (db.open()) {
            QSqlQuery query(db);
            if (query.exec(sql) && query.next())
                value = query.value(0);
            db.close();
        }
    }
    QSqlDatabase::removeDatabase(name);
    return value;
}

class FakePublisher final : public QTcpServer
{
public:
    bool failCommit = false;
    bool failPublish = false;
    QStringList paths;

    FakePublisher()
    {
        connect(this, &QTcpServer::newConnection, this, [this]() {
            while (hasPendingConnections()) {
                QTcpSocket *socket = nextPendingConnection();
                connect(socket, &QTcpSocket::readyRead, socket, [this, socket]() {
                    const QByteArray request = socket->readAll();
                    const int firstSpace = request.indexOf(' ');
                    const int secondSpace = request.indexOf(' ', firstSpace + 1);
                    const QString path = QString::fromLatin1(
                        request.mid(firstSpace + 1, secondSpace - firstSpace - 1));
                    paths.append(path);
                    int status = 200;
                    QJsonObject body{{QStringLiteral("ok"), true}};
                    if (path == QStringLiteral("/publish")) {
                        if (failPublish) {
                            status = 409;
                            body = QJsonObject{{QStringLiteral("ok"), false},
                                               {QStringLiteral("error"), QStringLiteral("injected publish failure")}};
                        } else {
                            body.insert(QStringLiteral("changed"), true);
                            body.insert(QStringLiteral("catalogId"), QStringLiteral("catalog-test"));
                            body.insert(QStringLiteral("rollbackToken"), QStringLiteral("rollback-test"));
                        }
                    } else if (path == QStringLiteral("/commit") && failCommit) {
                        status = 409;
                        body = QJsonObject{{QStringLiteral("ok"), false},
                                           {QStringLiteral("error"), QStringLiteral("injected commit failure")}};
                    }
                    const QByteArray payload =
                        QJsonDocument(body).toJson(QJsonDocument::Compact);
                    const QByteArray reason = status == 200 ? "OK" : "Conflict";
                    socket->write("HTTP/1.1 " + QByteArray::number(status) + " " + reason
                                  + "\r\nContent-Type: application/json\r\nContent-Length: "
                                  + QByteArray::number(payload.size())
                                  + "\r\nConnection: close\r\n\r\n" + payload);
                    socket->disconnectFromHost();
                });
            }
        });
    }
};

QJsonObject config(LayoutManager &manager, const QString &description)
{
    QJsonObject value = manager.buildStandardProductConfigV3(
        QJsonObject{{QStringLiteral("code"), QStringLiteral("JC6000-BGA-UTPUB")},
                    {QStringLiteral("version"), QStringLiteral("V1")},
                    {QStringLiteral("description"), description},
                    {QStringLiteral("buttonCount"), 1}});
    QJsonObject product = value.value(QStringLiteral("product")).toObject();
    product.insert(
        QStringLiteral("customerBindings"),
        QJsonArray{QJsonObject{{QStringLiteral("name"), QStringLiteral("发布测试客户")},
                               {QStringLiteral("isDefault"), true}}});
    value.insert(QStringLiteral("product"), product);
    return value;
}

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QTemporaryDir root;
    if (!root.isValid())
        return 1;
    const QString databasePath = QDir(root.path()).filePath(QStringLiteral("production_data.db"));
    if (!createCanonicalDatabase(databasePath))
        return 2;

    FakePublisher publisher;
    if (!publisher.listen(QHostAddress::LocalHost, 0))
        return 3;
    qputenv("CANJOYSTICK_DATABASE_PATH", QFile::encodeName(databasePath));
    qputenv("CANJOYSTICK_CATALOG_PUBLISHER_URL",
            QByteArray("http://127.0.0.1:") + QByteArray::number(publisher.serverPort()));

    LayoutManager manager;
    const QString catalogRoot = QDir(root.path()).filePath(QStringLiteral("catalog"));
    manager.setProductCatalogRoot(catalogRoot);
    const QString active = QDir(catalogRoot).filePath(
        QStringLiteral("active/JC6000-BGA-UTPUB_V1.json"));

    const QJsonObject oldConfig = config(manager, QStringLiteral("old description"));
    if (!manager.saveProductConfig(oldConfig, active))
        return 4;
    if (publisher.paths != QStringList{QStringLiteral("/publish"), QStringLiteral("/commit")})
        return 5;
    if (scalar(databasePath,
               QStringLiteral("SELECT COUNT(*) FROM products p JOIN product_customer_bindings pcb ON pcb.product_id=p.id JOIN customers c ON c.id=pcb.customer_id WHERE p.name='JC6000-BGA-UTPUB' AND p.status='active' AND c.name='发布测试客户' AND pcb.is_default=1"))
            .toInt()
        != 1) {
        return 6;
    }

    publisher.paths.clear();
    publisher.failCommit = true;
    const QJsonObject newConfig = config(manager, QStringLiteral("must roll back"));
    if (manager.saveProductConfig(newConfig, active))
        return 7;
    if (publisher.paths != QStringList{QStringLiteral("/publish"),
                                       QStringLiteral("/commit"),
                                       QStringLiteral("/rollback")}) {
        return 8;
    }
    QFile restored(active);
    if (!restored.open(QIODevice::ReadOnly))
        return 9;
    const QJsonObject restoredConfig =
        QJsonDocument::fromJson(restored.readAll()).object();
    if (restoredConfig.value(QStringLiteral("product")).toObject()
            .value(QStringLiteral("description")).toString()
        != QStringLiteral("old description")) {
        return 10;
    }
    if (scalar(databasePath,
               QStringLiteral("SELECT description FROM product_config_versions pcv JOIN products p ON p.id=pcv.product_id WHERE p.name='JC6000-BGA-UTPUB' AND pcv.version_code='V1'"))
            .toString()
        != QStringLiteral("old description")) {
        return 11;
    }
    return 0;
}
