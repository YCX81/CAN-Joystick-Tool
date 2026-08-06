#include "LayoutManager.h"

#include <QCoreApplication>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTemporaryDir>

namespace {

bool expect(bool condition, const QString &message)
{
    if (!condition) {
        qCritical().noquote() << message;
    }
    return condition;
}

bool writeBytes(const QString &path, const QByteArray &bytes)
{
    QFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(bytes) == bytes.size();
}

} // namespace

int main(int argc, char *argv[])
{
    QCoreApplication application(argc, argv);
    QTemporaryDir root;
    if (!expect(root.isValid(), QStringLiteral("could not create catalog hydration directory"))) {
        return 1;
    }

    const QString catalogId = QStringLiteral("catalog-unit-test");
    const QString activeDirectory = QDir(root.path()).filePath(QStringLiteral("active"));
    const QString releaseDirectory = QDir(root.path()).filePath(
        QStringLiteral("releases/%1/products").arg(catalogId));
    bool ok = expect(QDir().mkpath(activeDirectory),
                     QStringLiteral("could not create active directory"));
    ok &= expect(QDir().mkpath(releaseDirectory),
                 QStringLiteral("could not create formal directory"));

    const QByteArray editedBytes("{\"source\":\"edited-active\"}\n");
    const QByteArray formalExistingBytes("{\"source\":\"formal-existing\"}\n");
    const QByteArray formalMissingBytes("{\"source\":\"formal-missing\"}\n");
    const QString existingName = QStringLiteral("JC6000-BGA-EXISTING_V1.json");
    const QString missingName = QStringLiteral("JC6000-BGA-MISSING_V1.json");
    ok &= expect(writeBytes(QDir(activeDirectory).filePath(existingName), editedBytes),
                 QStringLiteral("could not write edited active product"));
    ok &= expect(writeBytes(QDir(releaseDirectory).filePath(existingName), formalExistingBytes),
                 QStringLiteral("could not write existing formal product"));
    ok &= expect(writeBytes(QDir(releaseDirectory).filePath(missingName), formalMissingBytes),
                 QStringLiteral("could not write missing formal product"));
    ok &= expect(writeBytes(
                     QDir(root.path()).filePath(QStringLiteral("current.json")),
                     QJsonDocument(QJsonObject{{QStringLiteral("catalogId"), catalogId}})
                         .toJson(QJsonDocument::Compact)),
                 QStringLiteral("could not write current pointer"));

    LayoutManager manager;
    manager.setProductCatalogRoot(root.path());

    QFile existingFile(QDir(activeDirectory).filePath(existingName));
    ok &= expect(existingFile.open(QIODevice::ReadOnly),
                 QStringLiteral("edited active product disappeared"));
    ok &= expect(existingFile.readAll() == editedBytes,
                 QStringLiteral("hydration overwrote edited active product"));

    QFile missingFile(QDir(activeDirectory).filePath(missingName));
    ok &= expect(missingFile.open(QIODevice::ReadOnly),
                 QStringLiteral("hydration did not add missing formal product"));
    ok &= expect(missingFile.readAll() == formalMissingBytes,
                 QStringLiteral("hydrated bytes differ from formal product"));

    const QString unsafeDirectory = QDir(root.path()).filePath(QStringLiteral("outside/products"));
    ok &= expect(QDir().mkpath(unsafeDirectory),
                 QStringLiteral("could not create unsafe pointer fixture"));
    ok &= expect(writeBytes(QDir(unsafeDirectory).filePath(QStringLiteral("SHOULD-NOT-COPY.json")),
                            QByteArray("{}\n")),
                 QStringLiteral("could not write unsafe pointer fixture"));
    ok &= expect(writeBytes(
                     QDir(root.path()).filePath(QStringLiteral("current.json")),
                     QByteArray("{\"catalogId\":\"../outside\"}")),
                 QStringLiteral("could not write unsafe current pointer"));
    LayoutManager unsafeManager;
    unsafeManager.setProductCatalogRoot(root.path());
    ok &= expect(!QFileInfo::exists(
                     QDir(activeDirectory).filePath(QStringLiteral("SHOULD-NOT-COPY.json"))),
                 QStringLiteral("catalog hydration followed an unsafe catalogId"));

    if (!ok) {
        return 1;
    }
    qInfo() << "Catalog active hydration smoke passed";
    return 0;
}
