#include <QCoreApplication>
#include <QFile>
#include <QTextStream>

#include <cstdio>

namespace {

QString readUtf8(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return QString::fromUtf8(file.readAll());
}

bool expect(bool condition, const char *message)
{
    if (!condition)
        std::fprintf(stderr, "%s\n", message);
    return condition;
}

} // namespace

int main(int argc, char *argv[])
{
    QCoreApplication application(argc, argv);
    const QString editor = readUtf8(QString::fromUtf8(PRODUCT_EDITOR_QML_SOURCE));
    const QString adapter = readUtf8(QString::fromUtf8(PRODUCT_CONFIG_V3_EDITOR_ADAPTER_SOURCE));

    bool ok = true;
    ok &= expect(!editor.isEmpty(), "ProductEditor.qml could not be read");
    ok &= expect(!adapter.isEmpty(), "ProductConfigV3EditorAdapter.js could not be read");

    ok &= expect(editor.contains(QStringLiteral("id: createProductConfirmationPopup")),
                 "new products must have a second confirmation popup");
    ok &= expect(editor.contains(QStringLiteral("pendingCloneProductConfig")),
                 "confirmation must retain the generated V3 config, not only form values");
    ok &= expect(editor.contains(QStringLiteral("确认创建"))
                     && editor.contains(QStringLiteral("返回修改")),
                 "confirmation popup must expose confirm and return actions");
    ok &= expect(editor.contains(QStringLiteral("summarizeProductConfigV3"))
                     && editor.contains(QStringLiteral("validateProductConfig")),
                 "confirmation must summarize and validate the generated config");
    ok &= expect(editor.contains(QStringLiteral(
                     "text: pendingCloneProductCustomer || \"---\"")),
                 "confirmation must show the customer's final form selection");
    ok &= expect(editor.contains(QStringLiteral(
                     "if (createProductConfirmationPopup.opened)"))
                     && editor.contains(QStringLiteral(
                         "createProductConfirmationError = error")),
                 "save failures must be routed into the open confirmation popup");
    ok &= expect(editor.contains(QStringLiteral(
                     "visible: createProductConfirmationError.length > 0"))
                     && editor.contains(QStringLiteral(
                         "text: createProductConfirmationError")),
                 "confirmation popup must render backend save errors");
    ok &= expect(editor.contains(QStringLiteral(
                     "if (!cloneProductUsesBlankTemplate && hasUnsavedChanges")),
                 "cloning an unchanged product must not reserialize and reject its loaded layout");
    ok &= expect(editor.contains(QStringLiteral(
                     "cloneProductError = saveProductMessage.length > 0")),
                 "layout synchronization failures must be visible inside the clone popup");
    ok &= expect(editor.contains(QStringLiteral(
                     "text: \"共 \" + cloneCustomerModel.count + \" 个客户"))
                     && editor.contains(QStringLiteral(
                         "policy: ScrollBar.AlwaysOn")),
                 "the complete customer list must advertise its count and remain visibly scrollable");

    ok &= expect(!editor.contains(QStringLiteral("ProductDraftPolicy"))
                     && !editor.contains(QStringLiteral("productDraftTimer"))
                     && !editor.contains(QStringLiteral("draftRecoveryPopup"))
                     && !editor.contains(QStringLiteral("saveProductDraft"))
                     && !editor.contains(QStringLiteral("loadProductDraft")),
                 "draft autosave and recovery must be removed from the editor");

    ok &= expect(!editor.contains(QStringLiteral("changePrimaryJoystickTopologyV3"))
                     && !editor.contains(QStringLiteral("primaryJoystickTopologyBox")),
                 "existing products must not mutate their canonical V3 topology in-place");
    ok &= expect(!adapter.contains(QStringLiteral("_reservedXAxis"))
                     && !adapter.contains(QStringLiteral("_reservedYAxis"))
                     && !adapter.contains(QStringLiteral("case \"joystickPad\": return \"MiniJoystick\""))
                     && !adapter.contains(QStringLiteral("case \"singleAxisGauge\"")),
                 "the layout adapter must not hide topology state in editor-only components");

    return ok ? 0 : 1;
}
