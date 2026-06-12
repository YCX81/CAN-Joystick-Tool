# 新产品 CAN 报文映射 SOP

## 目标

新产品创建流程不再自动推断报文到组件的映射，也不再区分 CANopen/J1939 模板。

新的 SOP 是：

1. 在 JoystickTool 中创建新产品。
2. JoystickTool 生成一个 `protocol: "can"` 的产品 JSON 草稿。
3. 保存草稿后自动打开该 JSON 文件。
4. 用户在 JSON 中手动填写 CAN 报文、字段解析、组件绑定和视觉 `bindingId`。
5. 填写完成后把 `editor.manualMappingRequired` 改为 `false`，`editor.mappingStatus` 改为 `"complete"`。
6. DownloadTool 扫描到完整 JSON 后，按 `can.messages[].canId` 匹配 CAN 帧并解析字段。

## 草稿 JSON 规则

新建产品默认生成：

```json
{
  "schemaVersion": 2,
  "version": "2.0",
  "product": {
    "model": "PRODUCT-MODEL",
    "protocol": "can",
    "canFrameFormat": "standard",
    "canAddress": "0x000"
  },
  "calibration": {
    "mode": "centerOnly",
    "transport": "manualCanMapping",
    "allowedInNormalModeReadOnly": true
  },
  "can": {
    "defaultBaudRate": 250,
    "messages": [
      {
        "id": "can_message_1",
        "name": "CAN报文1",
        "canId": "0x000",
        "frameFormat": "standard",
        "dlc": 8,
        "period": 20,
        "fields": []
      }
    ]
  },
  "components": [],
  "layout": {
    "grid": {
      "rows": 2,
      "columns": 2,
      "cells": []
    }
  },
  "editor": {
    "creationFlow": "manualCanMessageMapping",
    "manualMappingRequired": true,
    "mappingStatus": "draft"
  }
}
```

草稿允许在 JoystickTool 中保存，但 DownloadTool 会把 `manualMappingRequired: true` 视为未完成，不会加载为有效产品。

## 手工填写顺序

### 1. 填写报文

在 `can.messages[]` 中填写每条 CAN 报文：

- `id`：报文逻辑 ID，例如 `main`、`aux`。
- `canId`：原始 CAN ID，例如 `0x181`、`0x18FF50E5`。
- `frameFormat`：`standard` 或 `extended`。
- `dlc`：数据长度。
- `period`：期望周期，事件报文可填 `0`。
- `fields[]`：字段解析定义。

`protocol: "can"` 下，DownloadTool 直接用 `canId` 匹配收到的 CAN 帧。

### 2. 填写字段

每个字段至少需要：

```json
{
  "name": "xPos",
  "startByte": 0,
  "startBit": 0,
  "bitLength": 16,
  "type": "position",
  "encoding": "raw_16bit",
  "endian": "little"
}
```

字段解析结果 key 固定为：

```text
<message.id>.<field.name>
```

例如 `main.xPos`、`main.buttons`。

### 3. 填写组件

`components[]` 手动引用字段 key：

```json
{
  "id": "joystick_xy",
  "type": "joystick",
  "label": "XY轴",
  "xAxis": { "position": "main.xPos", "status": "main.xStatus" },
  "yAxis": { "position": "main.yPos", "status": "main.yStatus" }
}
```

按钮组：

```json
{
  "id": "buttons",
  "type": "buttonGroup",
  "label": "按钮",
  "source": "main.buttons",
  "count": 8
}
```

FNR 独立字段：

```json
{
  "id": "fnr",
  "type": "fnrSwitch",
  "label": "FNR",
  "source": "main.fnr"
}
```

FNR 按钮映射：

```json
{
  "id": "fnr",
  "type": "fnrSwitch",
  "label": "FNR",
  "buttonMapping": {
    "source": "main.buttons",
    "forward": 0,
    "neutral": -1,
    "reverse": 1
  }
}
```

### 4. 填写视觉绑定

`layout.grid.cells[].visualComponents[].bindingId` 必须指向组件端点：

- 按钮：`buttons.0`
- 滚轮：`roller_x`
- FNR：`fnr`

所有运行时视觉组件都必须有合法 `bindingId`。

### 5. 标记完成

手动映射完成并通过校验后，修改：

```json
{
  "editor": {
    "manualMappingRequired": false,
    "mappingStatus": "complete"
  }
}
```

## 两个工具的分工

JoystickTool：

- 创建产品 JSON 草稿。
- 保存草稿时不强制校验 `messages/components/layout`。
- 创建后自动打开 JSON，让用户手工填写映射。
- 后续保存完整 JSON 时继续执行字段引用和视觉绑定校验。

DownloadTool：

- 支持 `product.protocol: "can"`。
- 对 `protocol: "can"` 的产品按 `can.messages[].canId` 匹配原始 CAN ID。
- 如果 `editor.manualMappingRequired` 为 `true`，产品视为未完成，不能作为 active product。
- 当 `manualMappingRequired` 为 `false` 且校验通过时，按现有 `DynamicDataParser` 和 `PixelCanvas` 运行。

## 验收项

1. JoystickTool 新建产品后生成 `protocol: "can"` 草稿。
2. 新建完成后系统自动打开该产品 JSON。
3. 草稿能保存到 DownloadTool 的 `products` 目录。
4. DownloadTool 扫描草稿时标记为无效，不会误加载。
5. 用户补完 `can.messages[]`、`components[]`、`layout` 并关闭 `manualMappingRequired` 后，DownloadTool 能按 `canId` 匹配并解析。
6. JoystickTool 和 DownloadTool 构建、启动 smoke 均通过。
