# 使用 moon-xmpp REPL

[English](REPL.md)

`cmd/moon-xmpp` 是一个小型的命令行 XMPP 客户端。只给 JID 和密码，它就会登录
并打开一个交互式 REPL，你可以在里面查看联系人、添加好友、发送聊天消息。
REPL 等待输入期间，收到的消息和 presence 广播会实时打印出来。

本指南按四个常见任务展开：

1. [登录](#1-登录)
2. [获取联系人列表](#2-获取联系人列表)
3. [添加好友](#3-添加好友)
4. [发送消息](#4-发送消息)

以下命令都在仓库根目录执行。

## 1. 登录

```bash
moon run cmd/moon-xmpp -- \
  --jid alice@example.com \
  --password 'secret'
```

客户端会依次：

1. 建立连接并协商 STARTTLS（服务器不支持时客户端会拒绝继续），
2. 通过 SASL 认证，
3. 绑定资源并发送初始 presence，让联系人看到你已上线，
4. 把 roster 拉取到本地缓存，
5. 启动 REPL。

你会看到：

```
moon-xmpp repl. Type 'help' for commands, 'quit' to exit.
>
```

默认连接 JID 的域名部分。当实际连接地址与域名不一致时，可以覆盖：

```bash
moon run cmd/moon-xmpp -- --jid alice@example.com --password 'secret' \
  --host xmpp.example.net --port 5222 --resource laptop
```

使用自签名证书时，用 `--ca-file` 指定服务器的 PEM 证书（或签发它的 CA）：

```bash
moon run cmd/moon-xmpp -- --jid alice@localhost --password secret123 \
  --ca-file core/testdata/test_cert.pem
```

想在本地跑通登录流程，可以参考
[ACCEPTANCE.md](ACCEPTANCE.md#1-start-the-server-and-accounts) 启动 Prosody
并注册测试账号。

连接成功后，`help` 列出所有命令，`quit`（或 `exit`、Ctrl-D）结束会话。
连接失败会报错并退出；单条命令失败只会打印错误，REPL 保持打开。

## 2. 获取联系人列表

```
> roster
roster: 1 item(s)
* bob@example.com name="Bob" subscription=SubBoth groups=[Friends] status=online
```

每行依次是联系人的裸 JID、可选的名字、订阅状态、分组和当前可用性。
`status=online` 表示对方至少有一个资源已广播 presence；否则显示
`status=offline`。

订阅状态取值为 `SubNone`、`SubTo`（你能看到对方 presence）、`SubFrom`
（对方能看到你的）、`SubBoth` 或 `SubRemove`。

roster 在登录时拉取一次，之后由本地缓存提供。服务器推送的 roster 变更会被
立即应用并打印，所以 `roster` 不需要再发起一次请求也能保持最新：

```
* roster: bob@example.com SubBoth
```

在线状态由一张独立的 presence 状态表维护：每条 presence 广播都会更新它，
包括联系人（或它的某个资源）下线时的 `unavailable`。`roster` 直接渲染这张
表，所以广播之后再执行一次 `roster` 就能看到最新状态；每条广播也会实时
打印出来。

## 3. 添加好友

在 XMPP 里，“加好友”本质上是双向的 presence 订阅：你先请求查看对方的
presence，再由对方决定是否同意。多数服务器在处理第一个订阅请求时，也会
为对方创建一条 roster 记录。

在你的 REPL 里发起订阅：

```
> subscribe bob@example.com
* subscription request sent to bob@example.com
```

此时 `bob@example.com` 的客户端会收到一条授权请求。CLI 绝不会自动回复这类
请求，只会把它打印出来，由用户自行决定：

```
* subscription subscribe from alice@example.com
```

Bob 可以接受：

```
> approve alice@example.com
* approved subscription from alice@example.com
```

也可以拒绝：

```
> deny alice@example.com
* refused subscription from alice@example.com
```

`approve` 发送的是 `subscribed`，`deny` 发送的是 `unsubscribed`。之后执行
`roster` 即可确认联系人是否已添加或更新。

要互相看到对方的 presence，订阅必须是双向的：如果 Bob 也想看到 Alice，
Bob 需要发送 `subscribe alice@example.com`，再由 Alice 执行
`approve bob@example.com`。两个方向都授权后，`roster` 会显示
`subscription=SubBoth`，双方也会收到可用状态更新：

```
* bob@example.com/phone is available
```

如果对方设置了详细状态，`<show/>` 的值会替代 `available`：离开显示
`is away`，请勿打扰显示 `is dnd`，另外还有 `chat` 和 `xa`。`<status/>`
的文本会以冒号追加在后面，例如 `* bob@example.com/phone is dnd: Busy`。

如果不想再接收某个联系人的 presence：

```
> unsubscribe bob@example.com
* unsubscribed from bob@example.com
```

## 4. 发送消息

```
> send bob@example.com Hello from the REPL!
message msg_2 sent to bob@example.com
```

`send` 之后、JID 之后的全部内容都是消息正文；不需要加引号，内部空格会
原样保留。`send` 后的第一个词始终被当作收件人 JID。打印出的 ID 是客户端
为这条 stanza 分配的编号。

收到的聊天消息会实时出现，即使此刻正在等待输入：

```
> [bob@example.com/phone] Hi Alice!
```

客户端只展示聊天消息、presence 广播、roster 推送和订阅请求，其他 stanza
会被忽略。

## 命令速查

| 命令 | 作用 |
| --- | --- |
| `roster` | 打印缓存的 roster 及在线状态 |
| `send <jid> <message>` | 发送聊天消息 |
| `subscribe <jid>` | 请求查看某个联系人的 presence |
| `approve <jid>` | 同意对方的订阅请求 |
| `unsubscribe <jid>` | 停止接收某个联系人的 presence |
| `deny <jid>` | 拒绝对方的订阅请求 |
| `help` | 列出所有命令 |
| `quit` | 结束会话（也可用 `exit`，或输入 EOF） |

空行会被忽略，命令名区分大小写。

## 不进入 REPL 执行一次性动作

用 `--to`/`--body`、`--roster`、`--subscribe`、`--approve` 可以执行一次性
动作而不进入 REPL。加上 `--repl` 可以先执行动作、再进入 REPL：

```bash
moon run cmd/moon-xmpp -- --jid alice@example.com --password 'secret' \
  --to bob@example.com --body 'Hello from MoonBit!'

moon run cmd/moon-xmpp -- --jid alice@example.com --password 'secret' \
  --roster --subscribe bob@example.com --approve bob@example.com --repl
```

不加 `--repl` 时，一次性调用会持续打印收到的 stanza，直到流结束。

## 常见问题

- **`connect ... failed`** —— 检查 `--host`/`--port`；如果服务器使用自签名
  证书，用 `--ca-file` 指定证书。
- **新联系人没有出现在 `roster` 里** —— `roster` 读取的是缓存。等服务器
  处理完订阅请求并推送 roster（会打印成 `* roster: ...`）后再试。
- **某条命令后出现 `error: ...`** —— 服务器拒绝了该命令，或会话已不再处于
  绑定状态。REPL 会保持打开，输入 `quit` 即可退出。
