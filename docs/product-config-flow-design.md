# 新产品配置流程

## 默认流程

JoystickTool 的“创建新产品”用于覆盖常见的 J1939 摇杆产品：

1. 输入型号和版本。
2. 从已有客户中选择，或直接输入一个新客户名称。
3. 设置按钮数量和滚轮数量。
4. 保存后生成可直接使用的通用 J1939 JSON。
5. JSON 保存成功后，同步产品、版本、客户和产品/客户绑定到生产目录数据库。

创建新版本与创建新产品不同：新版本完整复制当前版本的报文解析、组件和画布，只更新版本及表单中的元数据，不重新套用通用模板。

## 通用 J1939 模板

默认值和范围：

- 按钮：默认 10 个，可设置为 0 到 12 个。
- 滚轮：默认 4 个，可设置为 0 到 4 个。
- 波特率：默认 250 kbit/s。
- 源地址：默认 `0x33`。
- 帧格式：扩展帧。

生成的报文包括：

- `bjm` / PGN `0xFDD6`：X/Y 轴状态和位置；按钮按 J1939 2-bit 编码生成。
- `ejm` / PGN `0xFDD7`：每个滚轮占 2 字节，包含 6-bit 状态和 10-bit 位置；滚轮数量为 0 时不生成该报文。
- `addressClaim` / PGN `0x0EEFF`：地址声明中的 identity 字段。

按钮和滚轮数量会同时更新四层内容：

1. `can.messages[].fields` 的字段定义。
2. `components[]` 的按钮组和滚轮组件。
3. `layout.grid.cells[].components` 的组件引用。
4. `layout.grid.cells[].visualComponents` 的可视化绑定。

因此通用配置保存后已经是完整配置：

```json
{
  "editor": {
    "profile": "j1939Generic",
    "creationFlow": "genericJ1939",
    "manualMappingRequired": false,
    "mappingStatus": "complete",
    "buttonCount": 10,
    "rollerCount": 4
  }
}
```

## 客户输入和数据库同步

客户框是可编辑下拉框：

- 选择已有名称时复用现有客户。
- 输入新名称时，名称先写入产品 JSON 的 `product.customerBindings`。
- 保存同步时，如果数据库中不存在该客户，则创建 active/real 客户，再创建默认产品绑定。
- 客户名称会去除首尾空格；空名称表示不建立客户绑定。

JoystickTool 不负责创建或迁移生产数据库。目标数据库必须先由匹配版本的 DownloadTool 初始化。

## 非通用产品

下列情况不应继续扩展“创建新产品”表单，而应在保存后修改 JSON：

- PGN 不是通用 BJM/EJM。
- 字段字节、位宽或编码不同。
- 按钮不是 J1939 2-bit 编码。
- 滚轮不是 6-bit 状态加 10-bit 位置。
- 有额外报文、FNR、LED 或其他产品专用控制。
- 画布布局需要产品专用设计。

修改时保持三层引用一致：

```text
can.messages[].id + fields[].name
             -> components[].source/position/status
             -> layout.grid.cells[].visualComponents[].bindingId
```

保存非草稿配置前，JoystickTool 会校验报文、字段引用、组件数量和视觉绑定。手工映射尚未完成时，应保留 `manualMappingRequired: true`，避免 DownloadTool 把半成品当成有效产品。

## 验收项

1. 客户框既能选择已有客户，也能输入新客户。
2. 新产品默认生成 J1939 扩展帧、BJM、EJM 和地址声明解析。
3. 选择的按钮数量同步到 BJM 字段、按钮组件和按钮视觉绑定。
4. 选择的滚轮数量同步到 EJM 字段、滚轮组件和滚轮视觉绑定。
5. 新版本仍保留当前版本的定制 JSON，不被通用模板覆盖。
6. 生成的 JSON 通过 `validateProductConfig()`，并能同步到生产目录数据库。
