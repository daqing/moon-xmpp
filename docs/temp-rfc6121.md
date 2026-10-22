# RFC 6121 工作备忘（roster 与 presence 订阅）

> 临时记录，对应任务清单 T10，分支 `develop`，尚未提交。
> 截至 2026-10-16：132 个测试全绿（原 106 → 新增 26）。

## 一、文档改动

**申报书 `~/Desktop/moon-xmpp-v3.md`**

- 删掉「明确排除的范围」里的 roster/subscription 那条，该节现在只剩 XEP 扩展和 s2s
- 最小可用链路第 5 步补上 roster 与 presence 订阅管理（RFC 6121 §2、§3）

**`README.mbt.md`（`README.md` 是它的软链）+ `README.zh-CN.md`**

- 去掉「暂不实现」的排除项
- 协议覆盖表新增两行：roster 拉取/修改/推送、presence 订阅管理
- 「范围之外」补上 roster 版本号（RFC 6121 §2.6）
- 状态、验收场景（新增第 4 条）、用法示例、演示（新 CLI 开关）、路线图第 8/9 项、开发章节（`scripts/roster.sh`）全部同步

## 二、代码实现

新增 `core/roster.mbt`、`core/subscription.mbt`，改动 `core/message.mbt`、`core/transport.mbt`：

| 能力 | API |
| --- | --- |
| 拉取 roster | `get_roster() -> Array[RosterItem]`、`roster()` 返回缓存 |
| 修改 roster | `set_roster_item(jid, name, groups)`、`remove_roster_item(jid)` |
| roster push | 收 `type='set'` 先回 `<iq type='result'/>` 再更新缓存，以 `RosterPush(item)` 上报 |
| 订阅四动作 | `send_subscribe` / `send_subscribed` / `send_unsubscribe` / `send_unsubscribed` |
| 收到订阅 | `IncomingStanza::Subscription`，`recv_subscription()`；**库绝不自动回复**（§3.1.3） |

两个实现细节：

- 等待 iq 应答期间到达的消息/presence 会入队而非丢弃（`await_iq` + `pending` 队列，有专门用例）
- roster push 按 bare JID 原位替换，保持列表顺序

CLI 新增 `--roster` / `--subscribe` / `--approve`，`--to`/`--body` 变为可选但要求至少有一个动作。

## 三、端到端验收

新增 `scripts/roster.sh` + `docker/slixmpp_alice_roster.py`，用 prosody + slixmpp（独立 Python 实现）跑完整授权链，4/4 PASS：

```
PASS: bob surfaced alice's inbound subscription request
PASS: bob's roster lists alice with subscription both
PASS: bob received alice's presence broadcast
PASS: alice (slixmpp) received bob's presence broadcast
```

transcript 存在 `docs/acceptance/roster-*.txt`；`docs/ACCEPTANCE.md`、`docs/TASKS.md` / `TASKS.zh-CN.md` 已同步（新增 T10，5 个子任务全部勾选）。

## 四、待决定/需知晓

1. **版本号已 bump：`moon.mod` 和 `VERSION` → 0.11.0**（按项目「每个特性 bump 一次」惯例）。若参赛期间不想跳版本，可改回。
2. **`scripts/e2e.sh` 和 `scripts/interop.sh` 的 trap 里有 `rm -rf`**——既有代码。新脚本按全局规则未沿用，改为把临时目录 `mv` 到 `/Users/daqing/protected/tmp/`。是否把旧脚本也改掉待定。
3. **`moon-xmpp.mbt` 的 `version()` 返回 `"0.1.0"`**，与 `moon.mod` 的 0.11.0 不符（既有问题，未动）。根包也未做 README 里演示的 `@xmpp.connect` 再导出。
4. 申报书里的**「验收场景」那段仍只写了聊天消息**。既然 roster 已进范围，建议补一句，否则评审会看到范围与验收不一致。
5. roster 版本号（§2.6）明确列为非目标；XEP、s2s 的排除不变。

## 五、相关文件

- 实现：`core/roster.mbt`、`core/subscription.mbt`
- 测试：`core/roster_wbtest.mbt`、`core/subscription_wbtest.mbt`
- CLI：`cmd/main/args.mbt`、`cmd/main/run.mbt`、`cmd/main/receive.mbt`
- 验收脚本：`scripts/roster.sh`、`docker/slixmpp_alice_roster.py`
- 验收记录：`docs/acceptance/roster-bob-subscribe.txt`、`docs/acceptance/roster-bob-fetch.txt`、`docs/acceptance/roster-alice-slixmpp.txt`
