# moon-xmpp 开发任务清单

> 依据 [README](../README.mbt.md) 的协议覆盖表与 Roadmap 拆解。
>
> - 编号规则：`T<阶段>.<序号>`，阶段内顺序即建议实施顺序。
> - 进度规则：每完成一项就勾选；完成协议能力相关的任务后，同步更新 README（中英两份）的协议覆盖表状态与 Roadmap 复选框。
> - 依赖关系：T1 → T2 → … → T8 依次依赖；**T9.1（本地 ejabberd 环境）建议提前到 T2 开始前完成**，因为从流协商起就需要真实服务器联调。JID、XML、SCRAM 等纯计算任务不依赖服务器，可随时穿插进行。
> - 截至 2026-10-01：T1、T2 已完成（T2.1 至 T2.5）。

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

- [ ] T3.1 TLS 选型已定：moonbitlang/async/tls（基于 OpenSSL）。剩余工作：锁版本，并验证 `Tls::client_from_pair` 能在已建立的 TCP 连接上升级加密（STARTTLS 的要求）
- [ ] T3.2 `<starttls/>` 协商：识别 `required` 标志、发送请求、处理 `proceeded` / `failure`，TLS 握手后重启流
- [ ] T3.3 服务器证书校验：通过 Tls 的 `host~` + `TrustedRoot::SystemRoot` 做域名匹配与有效期校验；未加密流上禁用明文机制（与 T4.2 配合）

## T4 SASL（RFC 6120 §6，框架为 RFC 4422）

目标：完成登录。三种机制按序实现，后者复用前者的协商框架。

- [ ] T4.1 SASL 协商框架：机制选择、`challenge` / `response` / `success` / `failure` 解析，成功后重启流
- [ ] T4.2 PLAIN（RFC 4616）：仅允许在已加密流上使用
- [ ] T4.3 SCRAM-SHA-1（RFC 5802）：构造 client-first / client-final 消息，校验 server-signature（依赖 HMAC、PBKDF2、SHA-1 基础函数，用 RFC 5802 自带测试向量验证）
- [ ] T4.4 SCRAM-SHA-256（RFC 7677）：复用 T4.3 的框架换哈希
- [ ] T4.5（可选加分）SCRAM channel binding（`-PLUS` 变体）——async/tls 已提供 tls-unique 与 tls-server-end-point 绑定（RFC 5929），原语现成

## T5 资源绑定（RFC 6120 §7）

目标：拿到完整 JID，形成可用的在线会话对象。

- [ ] T5.1 bind iq：发送绑定请求（携带或省略 resource），解析返回的完整 JID
- [ ] T5.2 会话对象与状态机：connecting → negotiating-tls → authenticating → bound → online，对外暴露 bound JID 与当前状态

## T6 Presence（RFC 6121 §4）

目标：上线可见，能收到对方的上下线通知。

- [ ] T6.1 发送 initial presence（RFC 6121 §4.2）
- [ ] T6.2 接收 presence 广播并暴露给调用方（对方 available / unavailable）
- [ ] T6.3 断开前发送 unavailable presence（优雅下线）

## T7 聊天消息（RFC 6120 §8，RFC 6121 §5.2）

目标：打通双向聊天，这是验收场景的核心。

- [ ] T7.1 发送 chat message：`type='chat'` + `<body/>` + `to`，生成 stanza id
- [ ] T7.2 接收 chat message：解析 `from` / `body`，按 T1.1 定型的 API 形态暴露给调用方
- [ ] T7.3 未知内容健壮性：对不认识的 stanza 与子元素按 RFC 6120 的忽略规则处理，不崩溃

## T8 CLI 演示（cmd/main）

目标：一条命令复现验收场景。

- [ ] T8.1 参数解析：`--jid` / `--password` / `--to` / `--body`，可选 `--host` / `--port` 覆盖
- [ ] T8.2 串起全链路：connect → starttls → sasl → bind → presence → send
- [ ] T8.3 收消息循环：打印收到的消息，作为反向链路可用的证明

## T9 测试与验收

目标：按验收场景完成验证并收尾。

- [ ] T9.1 本地 ejabberd 测试环境：Docker 起 ejabberd，注册两个测试账号，一键起停脚本（**务必在 T2 之前完成**）
- [ ] T9.2 单元测试补全：JID 边界用例、XML 转义与畸形输入、SCRAM 用 RFC 5802 测试向量
- [ ] T9.3 集成测试：走完整链路互发消息（CLI 对 CLI 或库级测试）
- [ ] T9.4 端到端验收：用 Psi / Gajim / Conversations 实测互发消息，截图留证
- [ ] T9.5 收尾：更新 README（协议表状态、Roadmap 勾选、Status 段落改为可用），准备演示材料

---

[English](TASKS.md)
