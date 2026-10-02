# moon-xmpp 开发任务清单

> 依据 [README](../README.mbt.md) 的协议覆盖表与 Roadmap 拆解。
>
> - 编号规则：`T<阶段>.<序号>`，阶段内顺序即建议实施顺序。
> - 进度规则：每完成一项就勾选；完成协议能力相关的任务后，同步更新 README（中英两份）的协议覆盖表状态与 Roadmap 复选框。
> - 依赖关系：T1 → T2 → … → T8 依次依赖；**T9.1（本地 ejabberd 环境）建议提前到 T2 开始前完成**，因为从流协商起就需要真实服务器联调。JID、XML、SCRAM 等纯计算任务不依赖服务器，可随时穿插进行。
> - 截至 2026-10-01：T1 至 T8 已完成；T9.1 至 T9.3、T9.5 已完成；T9.4 待人工 GUI 验收（docs/ACCEPTANCE.md）。

## T1 设计与基础

目标：定下编程模型，把 JID 和 XML 两块地基打好。

- [x] T1.1 API 编程模型已定（2026-10-01）：采用基于 moonbitlang/async 的 async fn（在 moon.mod 中锁版本），库内部写成顺序协议状态机；两份 README 示意性示例的刷新挪到 T7.2（API 落地时）进行
- [x] T1.2 包结构已创建：jid / xml / sasl / core，各自拥有一个公开 suberror 错误类型（JidError、XmlError、SaslError、XmppError）；根包保持 facade 角色，后续用 `pub using` 再导出
- [x] T1.3 JID 解析：`localpart@domainpart/resourcepart` 拆分与合法性校验（RFC 8264）——jid 包的 `Jid::parse`，含禁用字符与每段 1023 字节上限校验
- [x] T1.4 JID 规范化：width map、case map 与 NFKC（RFC 8264）——case map 与 NFKC 来自 moonbit-community/unicode@0.5.2（已锁版本），width map 自实现；resourcepart 只做 width map、保留大小写
- [x] T1.5 XML 层完成：`Framer` 把字节流切成 Root / Stanza / StreamEnd 帧（标签栈匹配，感知引号/注释/CDATA，StreamEnd 后可复用以支持流重启）；`parse_element` 把完整 stanza 交给 XMLParser@0.2.6 解析；序列化用 `escape_text` / `escape_attr`。注意：解析器会在子元素前后产出空文本节点，遍历 children 要按名字找而不是按下标

## T2 XML 流（RFC 6120 §4）

目标：能与服务器完成流握手，解析 features，正确处理流级错误。

- [x] T2.1 TCP 连接层：建立连接、读写循环、关闭（native 目标）——锁定 moonbitlang/async@0.22.4；`ByteStream` 从 socket 原始字节中解码完整 UTF-8 序列（跨 chunk 安全）并喂给分帧器；回环测试覆盖 connect/send/close
- [x] T2.2 stream header 往返：发送客户端头（`to`、`version` 等），解析服务端响应头；支持流重启（TLS 与 SASL 之后各一次）——`Connection::open_stream` / `restart_stream`；响应头校验流命名空间、version 1.0 与 id；同一次 socket 读取产出的多帧会缓冲，不会在读取间丢失
- [x] T2.3 stream features 解析：至少识别 `starttls`、`mechanisms`、`bind` 三类——`open_stream` / `restart_stream` 返回 `Features` 摘要；按局部名匹配、忽略未知特性。顺带修复回环测试暴露的分帧器 bug：标签属性区中的 `/` 现在能正确标记自闭合
- [x] T2.4 stream error 处理（RFC 6120 §4.9）：解析并向上层报告，断开连接——§4.9.3 全部条件映射为结构化 `StreamErrorCondition`（含 see-other-host）；从流上读到 `stream:error` stanza 即抛出带可选 `<text/>` 的 `XmppError::StreamError`
- [x] T2.5 stanza error 解析（RFC 6120 §8.3）：`<error/>` 子元素的 type 与 condition——`StanzaError::parse` 覆盖 §8.3.3 全部条件（含 redirect）、error type、可选 text 与未知应用条件

## T3 STARTTLS（RFC 6120 §5）

目标：把明文流升级为加密流，算法与证书校验遵循 RFC 7590。

- [x] T3.1 TLS 选型已定：moonbitlang/async/tls@0.22.4（基于 OpenSSL，版本随 moonbitlang/async 锁定）。已用回环 TLS 测试验证 `Tls::client` 能在已建立的 TCP 连接上升级加密；自签名测试证书在 core/testdata，仅测试中以 trust=NoVerification 使用
- [x] T3.2 `<starttls/>` 协商：`Connection::starttls` 校验服务器已通告该特性、发送请求、从原始 socket 逐字节读取 `proceed` / `failure`（避免同段合并的 TLS 握手字节丢失）、用 `Tls::client` 升级传输层（默认 `trust=SystemRoot` + 域名校验），并在 TLS 上重启流
- [x] T3.3 服务器证书校验：`starttls(verify=true)`（默认值）通过 `TrustedRoot::SystemRoot` + `host~` 域名匹配校验服务器证书；回环测试验证自签名证书会被拒绝且错误可捕获。`Connection::is_encrypted` 暴露加密状态——T4.2 必须在其为 false 时拒绝明文机制

## T4 SASL（RFC 6120 §6，框架为 RFC 4422）

目标：完成登录。三种机制按序实现，后者复用前者的协商框架。

- [x] T4.1 SASL 协商框架：机制选择（SCRAM-SHA-256 > SCRAM-SHA-1 > PLAIN，PLAIN 要求已加密）、`sasl_auth` / `sasl_respond`（同时作为自定义机制的公开 API）、逐字节读取 challenge/success/failure（服务器合并发送在 `</success>` 之后的字节在流重启后不丢失）；§6.5 failure 条件以 `XmppError::Auth` 抛出
- [x] T4.2 PLAIN（RFC 4616）：`Connection::authenticate` 自动选择机制或接受显式指定；明文流上拒绝 PLAIN；正常路径经真实 TLS 回环升级端到端测试
- [x] T4.3 SCRAM-SHA-1（RFC 5802）：sasl 包内完整客户端状态机（RFC 2104 HMAC、PBKDF2/Hi、saslname 转义、server-signature 校验），基于 moonbitlang/x/crypto；用 RFC 5802 §5.1 测试向量和带真实 proof 校验的回环线上测试验证；SASL challenge/success 载荷按 RFC 6120 §6.4.2 先 base64 解码再解析
- [x] T4.4 SCRAM-SHA-256（RFC 7677）：复用 T4.3 框架换 SHA-256 算法；用 RFC 7677 §3 测试向量和回环线上测试验证（两种算法共用一个参数化场景）
- [x] T4.5 SCRAM channel binding（`-PLUS` 变体）：`authenticate` 接受 `channel_binding~`——选择时优先 -PLUS，gs2 头标注 tls-server-end-point，绑定数据为服务器证书 DER 的 SHA-256（RFC 5929）。覆盖：c= 结构离线测试、机制偏好测试、以及假服务器断言 c= 绑定值的完整 TLS 线上测试

## T5 资源绑定（RFC 6120 §7）

目标：拿到完整 JID，形成可用的在线会话对象。

- [x] T5.1 bind iq：`bind_resource` 发送绑定 iq（无 resource 时用自闭合 bind 元素，有则带 `<resource/>`），解析服务器分配的完整 JID 并存储（`bound_jid`），iq 错误带 stanza 条件抛出
- [x] T5.2 会话对象与状态机：connecting → negotiating-tls → authenticating → bound（→ online 在 T6）经 `state()` 暴露，starttls/authenticate/bind 带顺序守卫；完整 TLS 会话有状态断言测试，bind 细节用白盒测试（直接快进到 Authenticating）覆盖

## T6 Presence（RFC 6121 §4）

目标：上线可见，能收到对方的上下线通知。

- [x] T6.1 发送 initial presence（RFC 6121 §4.2）——`send_initial_presence` 要求已绑定会话，发送后进入 Online
- [x] T6.2 接收 presence 广播并暴露给调用方（对方 available / unavailable）——`recv_presence` 解析 from/type/status；非 presence stanza 暂时跳过，T7 聊天支持落地后接入消息接收
- [x] T6.3 断开前发送 unavailable presence（优雅下线）——`signoff` 一次调用完成：发 unavailable presence、关 XML 流、断开连接

## T7 聊天消息（RFC 6120 §8，RFC 6121 §5.2）

目标：打通双向聊天，这是验收场景的核心。

- [x] T7.1 发送 chat message：`send_chat` 发出 `type='chat'`，生成 stanza id，body 做转义，守卫要求已绑定会话
- [x] T7.2 接收 chat message：`recv_stanza` 分发 Chat / Presence / Other；`ChatMessage` 含 from、id、body；`recv_presence` 改为分发之上的过滤封装
- [x] T7.3 未知内容健壮性：未知顶层元素归为 Other、未知子元素跳过，body 文本带完整实体解码（XML 解析器把实体引用存为独立子节点，get_text 会丢——测试抓出后已修）

## T8 CLI 演示（cmd/main）

目标：一条命令复现验收场景。

- [x] T8.1 参数解析：`--jid` / `--password` / `--to` / `--body`，可选 `--host` / `--port` / `--resource`，支持 `--name value` 与 `--name=value` 两种形式，带类型化 CliError
- [x] T8.2 串起全链路：connect → starttls → sasl → bind → presence → send——`run` 由 TLS 回环测试端到端覆盖，走完整个会话并检查发出的消息
- [x] T8.3 收消息循环：打印聊天消息与 presence 广播直到流结束；TLS 回环测试用收集型 printer 覆盖

## T9 测试与验收

目标：按验收场景完成验证并收尾。

- [x] T9.1 本地服务器测试环境：docker/ejabberd.yml + scripts/ejabberd.sh（start/stop/register，适用于 x86 主机），以及 scripts/prosody.sh + docker/prosody.Dockerfile 作为原生 arm64 替代（ejabberd 镜像在 Apple Silicon 的 amd64 模拟下 c2s acceptor 崩溃）；两账号已注册、STARTTLS 已用项目测试证书验证
- [x] T9.2 单元测试补全：JID 边界、XML 转义与畸形输入、SCRAM RFC 向量在各任务落地时已覆盖；覆盖率分析随后补齐剩余离线缺口（SCRAM challenge 错误分支、CLI 参数错误、authenticate 守卫）
- [x] T9.3 集成测试：scripts/e2e.sh 对真实本地服务器验证双向——在线送达（alice→bob）与离线暂存后送达（bob→alice），并暴露、修复了两个真实 SASL bug（载荷 base64、SCRAM 用户名）
- [ ] T9.4 端到端验收：用 Psi / Gajim / Conversations 实测互发消息，截图留证——步骤与命令已备好在 docs/ACCEPTANCE.md；需要有人在 GUI 客户端操作，待人工执行
- [x] T9.5 收尾：README 已更新（协议表、Roadmap、状态、演示）；演示材料为 CLI + scripts/e2e.sh + docs/ACCEPTANCE.md

---

[English](TASKS.md)
