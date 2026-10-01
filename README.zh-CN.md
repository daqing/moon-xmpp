# moon-xmpp

MoonBit 的 XMPP 客户端库，实现 XMPP Core（[RFC 6120](https://www.rfc-editor.org/rfc/rfc6120)）与 XMPP IM（[RFC 6121](https://www.rfc-editor.org/rfc/rfc6121)）的客户端侧协议。

## 项目状态

**开发中。** moon-xmpp 是一个 MoonBit 黑客松参赛项目，仓库目前是项目骨架，协议实现正在进行中——构建顺序见下文「路线图」。

## 它做什么

moon-xmpp 让 MoonBit 程序能够连接 ejabberd 这类标准 XMPP 服务器，安全登录，并收发一对一聊天消息；消息可与 Psi、Gajim、Conversations 等现成客户端互通。

本项目的验收场景：

1. moon-xmpp 连接一台 ejabberd 服务器，完成 STARTTLS 加密、SASL 认证与资源绑定。
2. 向另一个账号发送聊天消息，消息在第三方客户端中实时到达。
3. 从该客户端回复的消息，能够被 moon-xmpp 收到。

## 协议覆盖

| 能力 | 标准 | 状态 |
| --- | --- | --- |
| XML 流 | [RFC 6120 §4](https://www.rfc-editor.org/rfc/rfc6120#section-4) | 计划中 |
| STARTTLS | [RFC 6120 §5](https://www.rfc-editor.org/rfc/rfc6120#section-5) | 计划中 |
| SASL：PLAIN、SCRAM-SHA-1、SCRAM-SHA-256 | [RFC 4422](https://www.rfc-editor.org/rfc/rfc4422)、[RFC 4616](https://www.rfc-editor.org/rfc/rfc4616)、[RFC 5802](https://www.rfc-editor.org/rfc/rfc5802)、[RFC 7677](https://www.rfc-editor.org/rfc/rfc7677) | 计划中 |
| 资源绑定 | [RFC 6120 §7](https://www.rfc-editor.org/rfc/rfc6120#section-7) | 计划中 |
| 初始 presence | [RFC 6121 §4.2](https://www.rfc-editor.org/rfc/rfc6121#section-4.2) | 计划中 |
| 聊天消息 | [RFC 6120 §8](https://www.rfc-editor.org/rfc/rfc6120#section-8)、[RFC 6121 §5.2](https://www.rfc-editor.org/rfc/rfc6121#section-5.2) | 计划中 |
| JID 解析与规范化 | [RFC 8264](https://www.rfc-editor.org/rfc/rfc8264) | 计划中 |

## 范围之外

- roster 与 presence 订阅管理（RFC 6121 §2–3）：暂不实现，核心链路打通后再评估。
- 各类 XEP 扩展，如 SASL2（XEP-0388）、Stream Management（XEP-0198）、Message Carbons（XEP-0280）、MAM（XEP-0313）。
- 服务器到服务器（s2s）互联及一切服务端功能——这是纯客户端库。

## 安装

```
moon add daqing/moon-xmpp
```

然后在你包的 `moon.pkg` 中导入：

```
import {
  "daqing/moon-xmpp" @xmpp,
}
```

## 用法

> API 尚未定型，但方向已定：基于 [moonbitlang/async](https://mooncakes.io/docs/moonbitlang/async) 的 async fn。MoonBit 没有 `await` 关键字——async 调用与普通调用写法一致，错误隐式传播。以下示例是示意性的，展示一次会话的预期形态；API 落地后会同步更新。

```moonbit nocheck
///|
async fn main {
  let conn = @xmpp.connect(host="example.com", port=5222)
  conn.starttls()
  conn.authenticate(jid="alice@example.com", password="secret")
  conn.bind_resource("laptop")
  conn.send_initial_presence()
  conn.send_chat(to="bob@example.com", body="Hello from MoonBit!")
}
```

## 演示

`cmd/main` 下有一个小型命令行客户端。客户端功能可用后，完整的验收运行方式如下：

```bash
git clone https://github.com/daqing/moon-xmpp
cd moon-xmpp
moon run cmd/main -- \
  --jid alice@example.com \
  --password '…' \
  --to bob@example.com \
  --body 'Hello from MoonBit!'
```

用标准客户端（Psi、Gajim、Conversations）登录 `bob@example.com`，消息会立刻到达；从该客户端发送回复，正在运行的 CLI 也能收到。CLI 的参数名在开发过程中可能还会调整。

## 路线图

1. [ ] XML 流协商 — RFC 6120 §4
2. [ ] STARTTLS — RFC 6120 §5
3. [ ] SASL 认证：PLAIN、SCRAM-SHA-1、SCRAM-SHA-256
4. [ ] 资源绑定 — RFC 6120 §7
5. [ ] 初始 presence — RFC 6121 §4.2
6. [ ] 聊天消息收发 — RFC 6120 §8、RFC 6121 §5.2
7. [ ] `cmd/main` 命令行演示

## 开发

需要 [MoonBit 工具链](https://docs.moonbitlang.com)（`moon`）。目标后端为 native。

```bash
moon build   # 构建所有包（native 目标）
moon test    # 运行测试
moon fmt     # 格式化代码
moon info    # 重新生成包接口
```

集成测试计划在本地 ejabberd 实例上进行。

## 许可证

[MIT](LICENSE)

---

[English](README.md)
