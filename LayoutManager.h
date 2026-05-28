#ifndef LAYOUTMANAGER_H
#define LAYOUTMANAGER_H

#include <QObject>
#include <QString>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonDocument>
#include <QFile>
#include <QDir>
#include <QStandardPaths>
#include <QUrl>
#include <QQmlEngine>

/**
 * @brief 布局管理器 - 处理布局和卡片模板的JSON持久化
 *
 * 提供以下功能：
 * - 保存/加载布局配置
 * - 保存/加载卡片模板
 * - 文件选择对话框
 */
class LayoutManager : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // 属性
    Q_PROPERTY(QString layoutsDirectory READ layoutsDirectory WRITE setLayoutsDirectory NOTIFY layoutsDirectoryChanged)
    Q_PROPERTY(QString templatesDirectory READ templatesDirectory WRITE setTemplatesDirectory NOTIFY templatesDirectoryChanged)
    Q_PROPERTY(QString productsDirectory READ productsDirectory WRITE setProductsDirectory NOTIFY productsDirectoryChanged)
    Q_PROPERTY(QString currentLayoutPath READ currentLayoutPath NOTIFY currentLayoutPathChanged)
    Q_PROPERTY(bool hasUnsavedChanges READ hasUnsavedChanges WRITE setHasUnsavedChanges NOTIFY hasUnsavedChangesChanged)

public:
    explicit LayoutManager(QObject *parent = nullptr);
    ~LayoutManager() override = default;

    // 创建单例实例
    static LayoutManager *create(QQmlEngine *qmlEngine, QJSEngine *jsEngine);

    // 属性访问器
    QString layoutsDirectory() const { return m_layoutsDirectory; }
    void setLayoutsDirectory(const QString &path);

    QString templatesDirectory() const { return m_templatesDirectory; }
    void setTemplatesDirectory(const QString &path);

    QString productsDirectory() const { return m_productsDirectory; }
    void setProductsDirectory(const QString &path);

    QString currentLayoutPath() const { return m_currentLayoutPath; }

    bool hasUnsavedChanges() const { return m_hasUnsavedChanges; }
    void setHasUnsavedChanges(bool value);

    // ========== 布局操作 ==========

    /**
     * @brief 保存布局到指定路径
     * @param layoutJson 布局JSON对象
     * @param filePath 文件路径 (可选，为空则使用currentLayoutPath)
     * @return 成功返回true
     */
    Q_INVOKABLE bool saveLayout(const QJsonObject &layoutJson, const QString &filePath = QString());

    /**
     * @brief 从指定路径加载布局
     * @param filePath 文件路径
     * @return 布局JSON对象，失败返回空对象
     */
    Q_INVOKABLE QJsonObject loadLayout(const QString &filePath);

    /**
     * @brief 保存布局到文件（使用对话框选择路径）
     * @param layoutJson 布局JSON对象
     * @param suggestedName 建议的文件名
     * @return 成功返回保存路径，失败返回空字符串
     */
    Q_INVOKABLE QString saveLayoutAs(const QJsonObject &layoutJson, const QString &suggestedName = QString());

    /**
     * @brief 获取布局目录下的所有布局文件
     * @return 布局文件列表 [{name, path, modified}, ...]
     */
    Q_INVOKABLE QJsonArray getLayoutFiles();

    // ========== 卡片模板操作 ==========

    /**
     * @brief 保存所有卡片模板
     * @param templatesJson 模板数组
     * @return 成功返回true
     */
    Q_INVOKABLE bool saveCardTemplates(const QJsonArray &templatesJson);

    /**
     * @brief 加载所有卡片模板
     * @return 模板JSON数组
     */
    Q_INVOKABLE QJsonArray loadCardTemplates();

    /**
     * @brief 保存单个卡片模板
     * @param templateJson 模板JSON对象
     * @param fileName 文件名 (不含扩展名)
     * @return 成功返回true
     */
    Q_INVOKABLE bool saveCardTemplate(const QJsonObject &templateJson, const QString &fileName);

    /**
     * @brief 删除卡片模板
     * @param fileName 文件名
     * @return 成功返回true
     */
    Q_INVOKABLE bool deleteCardTemplate(const QString &fileName);

    /**
     * @brief 获取模板目录下的所有模板文件
     * @return 模板文件列表
     */
    Q_INVOKABLE QJsonArray getTemplateFiles();

    // ========== 产品配置操作 ==========

    Q_INVOKABLE QJsonArray getProductFiles();
    Q_INVOKABLE QJsonObject loadProductConfig(const QString &filePath);
    Q_INVOKABLE bool saveProductConfig(const QJsonObject &configJson, const QString &filePath);
    Q_INVOKABLE QString sanitizeProductModel(const QString &model) const;
    Q_INVOKABLE bool productConfigExists(const QString &model) const;
    Q_INVOKABLE bool saveProductConfigAs(const QJsonObject &configJson, const QString &model);

    // ========== 工具方法 ==========

    /**
     * @brief 将QJsonObject转为格式化的JSON字符串
     */
    Q_INVOKABLE QString toJsonString(const QJsonObject &obj, bool compact = false);

    /**
     * @brief 将JSON字符串解析为QJsonObject
     */
    Q_INVOKABLE QJsonObject fromJsonString(const QString &jsonStr);

    /**
     * @brief 确保目录存在
     */
    Q_INVOKABLE bool ensureDirectoryExists(const QString &path);

    /**
     * @brief 获取文件的URL形式（用于QML FileDialog）
     */
    Q_INVOKABLE QUrl toFileUrl(const QString &path);

    /**
     * @brief 从URL获取本地路径
     */
    Q_INVOKABLE QString fromFileUrl(const QUrl &url);

signals:
    void layoutsDirectoryChanged();
    void templatesDirectoryChanged();
    void productsDirectoryChanged();
    void productConfigSaved(const QString &path);
    void productConfigLoaded(const QString &path);
    void currentLayoutPathChanged();
    void hasUnsavedChangesChanged();

    void layoutSaved(const QString &path);
    void layoutLoaded(const QString &path);
    void templatesSaved();
    void templatesLoaded();
    void errorOccurred(const QString &error);

private:
    QString m_layoutsDirectory;
    QString m_templatesDirectory;
    QString m_productsDirectory;
    QString m_currentLayoutPath;
    bool m_hasUnsavedChanges = false;

    // 初始化默认目录
    void initDefaultDirectories();

    // 写入JSON文件
    bool writeJsonFile(const QString &path, const QJsonDocument &doc);

    // 读取JSON文件
    QJsonDocument readJsonFile(const QString &path);
};

#endif // LAYOUTMANAGER_H
