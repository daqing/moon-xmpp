# moon-xmpp：RFC 6121 能力核对与端到端测试指南

> 核对日期：2026-10-19　代码版本：`0.11.0`（`VERSION`／`moon.mod`）
>
> 核对方法：通读 README、`docs/` 全部文档、`scripts/` 全部验收脚本、
> `core/pkg.generated.mbti` 与 `core/{roster,subscription,presence,message,features}.mbt`，
> 并实际运行 `moon test` 与 `scripts/e2e.sh`。
>
> 本文档回答两个问题：**怎么跑端到端测试**，以及**RFC 6121 是否已全部实现**。

---

## 1. 文档地图

| 文件 | 作用 |
| --- | --- |
| `README.mbt.md`（`README.md` 是软链） | 协议覆盖表、Roadmap、CLI 用法 |
| `docs/ACCEPTANCE.md` | 验收场景：自动化互操作 + GUI 手工步骤 |
| `docs/rfc6121-e2e.md` | Adium 手动验证 roster／订阅／presence 的完整步骤 |
| `docs/TASKS.zh-CN.md` | T1–T10 任务与完成情况 |
| `docs/temp-rfc6121.md` | RFC 6121（T10）工作备忘，含已知遗留项 |
| `docs/acceptance/*.txt` | 历史运行的 transcript 证据 |
| `scripts/{e2e,interop,roster,prosody,ejabberd}.sh` | 自动化 E2E 入口 |
| `docker/{prosody.Dockerfile,prosody.cfg.lua,slixmpp*.py}` | 测试服务器与第三方客户端容器 |

---

## 2. 端到端测试怎么跑

测试分四层：单元／白盒 → 真实服务器双向投递 → 第三方实现互操作 → 手工 GUI。

### 2.0 前置条件

- MoonBit 工具链（native 后端），`moon` 在 PATH 中；
- Docker Desktop 运行中；
- macOS／Apple Silicon **用 prosody**，不要用 ejabberd
  （ejabberd 镜像在 amd64 模拟下 c2s acceptor 会崩，文档已注明）；
- 服务器使用自签名测试证书 `core/testdata/test_cert.pem`，CLI 必须传
  `--ca-file` 才会信任；
- 手工 GUI 层可选装 Adium／Psi／Gajim／Conversations。

### 2.1 单元／白盒测试（不需要服务器）

```bash
moon test
moon info && moon fmt
```

实测结果（2026-10-19）：

```text
Total tests: 132, passed: 132, failed: 0.
```

### 2.2 真实服务器双向投递（最核心的 E2E）

```bash
scripts/prosody.sh stop          # 先清掉同名旧容器
scripts/prosody.sh start
scripts/prosody.sh register alice secret123
scripts/prosody.sh register bob secret123
scripts/e2e.sh
```

`e2e.sh` 验证两条路径：

1. bob 在线时，alice → bob 直接投递；
2. alice 离线时，bob → alice 由服务器离线存储，alice 上线后补投。

预期输出：

```text
PASS: bob received the message from alice (online delivery)
PASS: alice received the stored message from bob (offline delivery)
```

一键版：`just e2e`（等价于 stop → start → `scripts/e2e.sh` → stop）。

### 2.3 与独立实现互操作（slixmpp，Python）

```bash
scripts/interop.sh   # 聊天双向：Hello from MoonBit! / pong from slixmpp
scripts/roster.sh    # RFC 6121 §2/§3：入站订阅请求、SubBoth、双向 presence
```

`interop.sh` 预期 2 行 PASS，`roster.sh` 预期 4 行 PASS：

```text
PASS: bob surfaced alice's inbound subscription request
PASS: bob's roster lists alice with subscription both
PASS: bob received alice's presence broadcast
PASS: alice (slixmpp) received bob's presence broadcast
```

两者都会把 transcript 写入 `docs/acceptance/` 作为证据。

### 2.4 手工 GUI 验收（Adium／Psi／Gajim）

按 `docs/rfc6121-e2e.md` 操作。先建账号：

```bash
scripts/prosody.sh start
scripts/prosody.sh register alice secret123
scripts/prosody.sh register bob secret123
```

Adium 用 `alice@localhost` 登录（host `localhost`、port `5222`、要求 STARTTLS，
接受自签名证书），moon-xmpp 侧作为 bob 运行：

```bash
moon run cmd/main -- \
  --jid bob@localhost --password secret123 \
  --host localhost --port 5222 \
  --subscribe alice@localhost --approve alice@localhost \
  --ca-file core/testdata/test_cert.pem
```

在 Adium 接受 bob 的授权请求后，终端应依次出现（资源名与顺序不重要）：

```text
* subscription Subscribe from alice@localhost
* roster: alice@localhost SubTo
* roster: alice@localhost SubBoth
* alice@localhost/<resource> is available
```

随后用新会话复查 roster：

```bash
moon run cmd/main -- \
  --jid bob@localhost --password secret123 \
  --roster \
  --ca-file core/testdata/test_cert.pem
```

预期：

```text
roster: 1 item(s)
* alice@localhost name="" subscription=SubBoth groups=[]
```

最后保持 `--roster` 会话运行，在 Adium 里把 alice 置为离线再上线，应看到
`is unavailable` 与 `is available` 两条 presence。

### 2.5 清理

```bash
scripts/prosody.sh stop
```

`scripts/e2e.sh` 结束后容器仍在运行；要彻底重置 roster／订阅状态，
必须 `stop` 后重新 `start` 并重新注册账号。

### 2.6 实测结果与踩坑记录

| 项 | 实测结果 |
| --- | --- |
| `moon test` | 132/132 通过 |
| `scripts/e2e.sh` | 双向 2/2 PASS（配合 2.6.1 的 `timeout` 处理后） |
| `scripts/roster.sh` / `interop.sh` | 本次未重跑（会覆盖证据文件），文档记录为 4/4 与 2/2 通过 |

#### 2.6.1 macOS 没有 `timeout`

三个集成脚本都使用了 `timeout`，而 macOS 默认不带 GNU coreutils。
`timeout` 缺失时命令返回 127，被脚本里的 `|| true` 吞掉，最终表现为
**莫名其妙的 FAIL**（远端输出为空），而不是明确的报错。

解决方式（任选其一）：

```bash
brew install coreutils
export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"
```

或把脚本中的 `timeout` 改为 `gtimeout`。

#### 2.6.2 必须用 SIGTERM 终止被测进程

CLI 的 stdout 在重定向到文件时是块缓冲。若用 SIGALRM／SIGKILL 强杀，
缓冲区不会落盘，脚本 grep 不到输出，会误判为 FAIL；SIGTERM（GNU `timeout`
的默认信号）下 MoonBit 运行时能正常收尾并 flush。

本次核对使用了一个临时 `timeout` shim（放在 `/tmp/finch-shim`，未入库），
其核心是 `kill -TERM` 而非 `alarm`。

#### 2.6.3 同名容器残留会阻断启动

`scripts/prosody.sh start` 只检查“运行中”的容器。若存在同名但已退出的容器，
`docker run` 会报：

```text
Conflict. The container name "/moon-xmpp-prosody" is already in use
```

先 `scripts/prosody.sh stop`，或直接用 `just e2e`（它开头就会 stop）。

#### 2.6.4 脚本的其它可移植性问题

- `e2e.sh`／`interop.sh`／`roster.sh` 里写死了 `$HOME/.moon/bin/moon`，
  若 `moon` 安装位置不同需改脚本；
- `roster.sh` 的 cleanup 写死了 `/Users/daqing/protected/tmp`，换机器会失败
  （且它在开头会 `stop` 容器以重置订阅状态）；
- `roster.sh`、`interop.sh` 会**覆盖** `docs/acceptance/*.txt`，重跑前先备份证据。

---

## 3. RFC 6121 覆盖评估

### 3.1 结论

**没有实现 RFC 6121 的全部能力。**

准确说法是：**面向 IM 客户端的 MUST 级功能基本齐备**，但

- §12 一致性清单中的 **4 个 Client SHOULD 全部缺失**；
- **1 个 Client MAY（预批准）缺失**；
- §2.1.6 的一条 **MUST（校验 roster push 的来源）未实现**；
- §4／§5 还有若干细节缺口（presence 的 priority、发送侧 show／status 与更新、
  message 的 subject／thread／type）。

项目本身也在 README 的「Non-goals」里明确排除了 roster 版本号（§2.6）与全部
XEP 扩展，因此这里说的“全部能力”是指 RFC 6121 正文中与客户端相关的部分。

### 3.2 分章节覆盖表

| 章节 | 能力 | 状态 | 说明 |
| --- | --- | --- | --- |
| §2.1.1 | `ver` 属性 | ❌ | 不解析 |
| §2.1.2.1 | `approved` 属性 | ❌ | 预批准状态被丢弃 |
| §2.1.2.2 | `ask` 属性 | ⚠️ | 保留为原始字符串，未映射为枚举 |
| §2.1.2.5 | `subscription` 取值 | ✅ | 未知值按 `none`，`remove` 仅用于推送 |
| §2.1.2.6 | `<group/>` | ✅ | 多组、转义均处理 |
| §2.1.3–2.1.5 | roster get／set／删除 | ✅ | `get_roster`、`set_roster_item`、`remove_roster_item` |
| §2.1.6 | roster push | ⚠️ | 会回 result、更新缓存、上报 `RosterPush`；**未校验 `from`**（RFC 要求忽略非本账号 bare JID 的推送） |
| §2.2 | 登录后先取 roster | ⚠️ | 有 API 但不自动；CLI 在 initial presence 之后才取（RFC 建议之前） |
| §2.6 | roster 版本号 | ❌ | README 明确列为非目标 |
| §3.1 | subscribe／subscribed | ✅ | 入站请求只上报、绝不自动回复（符合 §3.1.4） |
| §3.1.1 | 订阅 stanza 带 `id` | ❌ | RFC 的 SHOULD，便于追踪；当前所有订阅 stanza 都不带 id |
| §3.2 | unsubscribed（拒绝／撤销授权） | ✅ | |
| §3.3 | unsubscribe | ✅ | |
| §3.4 | 预批准（pre-approval） | ❌ | 不识别 `urn:xmpp:features:pre-approval`，不处理 `approved` |
| §4.2 | initial presence | ⚠️ | 只能发空 `<presence/>`，无法带 show／status／priority |
| §4.4 | 后续 presence 广播（away／dnd／状态更新） | ❌ | 无 API；`send_initial_presence` 要求 `state == Bound`，Online 后再调用会报错 |
| §4.5 | unavailable | ✅ | `signoff()` |
| §4.6 | directed presence | ❌ | 无 API（主要影响 MUC 等扩展场景） |
| §4.7.1 | type 语义 | ✅ | 无 type 视为 available，`unavailable` 正确区分 |
| §4.7.2.1 | `<show/>` | ✅ | 已解析为 `show` 字段，`away`／`dnd` 等会显示成对应状态 |
| §4.7.2.2 | `<status/>` | ✅ | 仅取最后一个，未处理 `xml:lang` 多语言 |
| §4.7.2.3 | `<priority/>` | ❌ | 不解析 |
| §5.1 | 一对一 chat | ✅ | 双向互操作验证过 |
| §5.2.1 | `to` | ✅ | |
| §5.2.2 | message type 支持 | ⚠️ | 只发 `chat`；收到任何 `message` 都归为 `Chat`，不暴露 type；`type='error'` 不解析 error 子元素 |
| §5.2.3 | `<body/>` | ✅ | 实体解码正确（含 CDATA／文本节点拼接） |
| §5.2.4 | `<subject/>` | ❌ | 未暴露 |
| §5.2.5 | `<thread/>` | ❌ | 未暴露；发送侧也不带 thread（§5.1 的 SHOULD） |
| §6 | 通用 IQ／扩展内容 | ❌ | 只有 roster iq；服务端发来的 `iq get` 不回复 |
| §8 | 服务器处理 XML stanza 的规则 | N/A | 纯服务端行为 |
| §9 | `xmpp:` URI 处理 | ❌ | 未实现，客户端可选 |
| §12 | 一致性清单 | ⚠️ | 见 §3.3 |
| 附录 A | 订阅状态机 | N/A | 服务端状态表 |

### 3.3 §12 一致性清单对照

RFC 6121 §12 把一致性要求拆成如下特性：

| 特性 | 角色要求 | 状态 |
| --- | --- | --- |
| `message-body` | Client MUST | ✅ |
| `presence-notype` | Client MUST | ✅ |
| `presence-sub-approval` | Client MUST | ✅ |
| `presence-sub-cancel` | Client MUST | ✅ |
| `presence-sub-request` | Client MUST | ✅ |
| `presence-sub-unsubscribe` | Client MUST | ✅ |
| `presence-unavailable` | Client MUST | ✅ |
| `roster-get` | Client MUST | ✅ |
| `roster-set` | Client MUST | ✅ |
| `roster-push` | Client MUST | ⚠️ 功能具备，但缺少 §2.1.6 的来源校验 |
| `message-subject` | Client SHOULD | ❌ |
| `message-thread` | Client SHOULD | ❌ |
| `message-type-support` | Client SHOULD | ❌（五种 type 未区分） |
| `roster-version` | Client SHOULD | ❌ |
| `presence-sub-preapproval` | Client MAY | ❌ |

统计：

- MUST 10 项：9 项完全满足，1 项（`roster-push`）功能满足但安全校验缺失；
- SHOULD 4 项：**0 项实现**；
- MAY 1 项：未实现。

### 3.4 主要缺口（按影响排序）

1. **presence 表达力不足**：无法发送 `show`（away／chat／dnd／xa）、状态文本、
   priority，也无法在会话中进行 presence 更新。这是 IM 客户端最实际的缺口。
2. **presence 细节仍不完整**：接收侧已解析 `show`，但 `priority` 仍未解析，
   发送侧也无法表达 show／status。
3. **message 语义不完整**：不暴露 `type`，不解析 `subject`／`thread`，
   不区分 `error` 消息，发送 chat 时也不带 thread。
4. **roster push 未校验来源**（安全相关的 MUST）。
5. **roster 版本号缺失**：每次全量拉取，弱网／大 roster 下开销大（已列为非目标）。
6. **订阅 stanza 不带 `id`**：无法与请求／批准配对追踪。
7. **预批准未实现**：`approved` 属性被丢弃。
8. **通用 IQ 与服务端 `iq get` 不回应**：不属于 6121，但影响与部分服务器的长期互操作。

---

## 4. 代码审读发现的两个缺陷

以下两条来自读代码，未包含在现有测试覆盖内，建议先补测试再修。

### 4.1 roster set 后本地缓存可能被错误覆盖

位置：`core/roster.mbt:274` `send_roster_set`，以及 `:290` 的
`self.apply_roster_push(cache)`。

流程是：发送 `iq set` → `await_iq` 等待 result（期间到达的 roster push 会被
`handle_iq` 应用）→ 再用本地构造的 `cache` 覆盖一次缓存。

问题在于本地 `cache` 的 `subscription` 恒为 `SubNone`（见 `:304`）。RFC 6121
§2.3.2 的处理顺序是“更新 roster → 向 interested resource 推送 → 回 result”，
实际服务器也**通常先发推送**：push 写入 `SubBoth`，随后被 `SubNone` 覆盖。
结果是修改备注／分组后，客户的订阅状态显示为 `none`，直到下一次推送或重新
`get_roster` 才恢复。若某个服务器先回 result 再推送，则不会触发此问题——
这也是它属于“顺序依赖”缺陷的原因。

现有白盒测试（`roster_wbtest.mbt:158`）的假服务器只回 result、不发 push，
所以测不出这个顺序问题。

修复方向：`send_roster_set` 不应覆盖 `subscription`／`ask`，或在收到 push 后
跳过本地覆盖（push 是权威数据）。

### 4.2 roster push 未校验来源

位置：`core/roster.mbt:142` `handle_iq`。

RFC 6121 §2.1.6 明确规定：接收方必须忽略 `from` 既不存在、也不等于本账号
bare JID 的 roster push。当前实现只检查 `type='set'` 和 `jabber:iq:roster`
命名空间，任何实体发来的推送都会被应用，并回 result。

修复方向：在 `handle_iq` 入口比较 `el.get_attribute("from")` 与
`bound_jid().bare()`，不匹配则直接返回 `None`（不回 result）。

---

## 5. 建议的补齐顺序

| 优先级 | 内容 | 理由 |
| --- | --- | --- |
| P0 | presence 的 `show`／`status`／`priority` 发送、`priority` 解析，以及“后续 presence 广播”API | 不做就无法表达离开／勿扰／自定义状态 |
| P0 | 修复 §4.1、§4.2 两个缺陷 | 改动小，前者影响正确性，后者影响安全 |
| P1 | 接收侧暴露 message `type`，解析 `subject`／`thread`，区分 `error` | 对齐 §12 的 SHOULD |
| P1 | 订阅 stanza 带 `id` | 便于请求／批准配对 |
| P2 | roster versioning（§2.6）、预批准（§3.4）、directed presence（§4.6） | 前者已公开列为非目标，后两者按需 |
| P2 | 通用 IQ API 与 `iq get` 自动回错 | 主要影响长期互操作 |

---

## 附录 A：命令速查

```bash
# 单元／白盒
moon test
moon info && moon fmt

# 本地服务器
scripts/prosody.sh start
scripts/prosody.sh stop
scripts/prosody.sh register <user> <password>

# 自动化 E2E
scripts/e2e.sh        # 在线直投 + 离线补投（2 项）
scripts/interop.sh    # 与 slixmpp 聊天双向（2 项）
scripts/roster.sh     # roster／订阅／presence（4 项）
just e2e              # stop → start → e2e.sh → stop

# 手工 CLI
moon run cmd/main -- --jid bob@localhost --password secret123 \
  --to alice@localhost --body "Hello from MoonBit!" \
  --ca-file core/testdata/test_cert.pem

moon run cmd/main -- --jid bob@localhost --password secret123 \
  --roster --ca-file core/testdata/test_cert.pem

moon run cmd/main -- --jid bob@localhost --password secret123 \
  --subscribe alice@localhost --approve alice@localhost \
  --ca-file core/testdata/test_cert.pem
```

CLI 动作开关：`--to/--body`（发消息）、`--roster`（拉取并打印 roster）、
`--subscribe`（请求订阅）、`--approve`（批准对方请求）；至少需要其一。

## 附录 B：证据文件

| 文件 | 对应能力 |
| --- | --- |
| `docs/acceptance/interop-bob-cli.txt` | CLI 侧收发的聊天消息 |
| `docs/acceptance/interop-alice-slixmpp.txt` | slixmpp 侧收发记录 |
| `docs/acceptance/roster-bob-subscribe.txt` | 入站订阅请求、roster push |
| `docs/acceptance/roster-bob-fetch.txt` | `--roster` 拉取结果、presence 广播 |
| `docs/acceptance/roster-alice-slixmpp.txt` | slixmpp 侧看到的 bob presence |

## 附录 C：本次核对的执行记录

```text
$ moon test
Total tests: 132, passed: 132, failed: 0.

$ scripts/e2e.sh        # 使用 SIGTERM 版 timeout shim
PASS: bob received the message from alice (online delivery)
PASS: alice received the stored message from bob (offline delivery)
```

核对结束后已执行 `scripts/prosody.sh stop`，`git status` 无改动。
