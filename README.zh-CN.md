# iris-whatsapp-gateway

[English](README.md) | 简体中文

**用于 InterSystems IRIS Interoperability 的多平台 WhatsApp 适配器。**

本应用提供入站适配器、出站适配器、Business Service（BS）和 Business Operation（BO），让 IRIS Production 可以接收和发送 WhatsApp 消息。支持 **Meta WhatsApp Cloud API** 与 **Twilio Programmable Messaging（WhatsApp）**，使用统一消息模型，并验证 Webhook 签名。

入站适配器自行监听 HTTP/TLS 端口，不需要另外创建 CSP Web 应用、Web Gateway 路由或 REST 分发类。项目还包含两个平台的离线模拟服务，可在没有真实账号和凭据的情况下演示完整消息往返。

本项目对应 InterSystems Ideas 创意 [DPI-I-882：为 IRIS Interoperability 提供 WhatsApp 适配器](https://ideas.intersystems.com/ideas/DPI-I-882)。

## 应用提供哪些组件

| 组件 | IRIS 基类 | 实现 |
|---|---|---|
| 入站适配器 | `Ens.InboundAdapter` | `WhatsApp.Adapter.InboundMeta`、`WhatsApp.Adapter.InboundTwilio` |
| 出站适配器 | `Ens.OutboundAdapter` | `WhatsApp.Adapter.Outbound.Meta`、`WhatsApp.Adapter.Outbound.Twilio` |
| Business Service | `Ens.BusinessService` | `WhatsApp.BS.WebhookMeta`、`WhatsApp.BS.WebhookTwilio` |
| Business Operation | `Ens.BusinessOperation` | `WhatsApp.BO.SendMessageMeta`、`WhatsApp.BO.SendMessageTwilio` |

Meta 出站支持文本、模板、媒体引用、位置、交互按钮、列表和表情回应；当前 Twilio 出站实现支持文本、媒体 URL 和 Content 模板。两套实现共用入站/出站消息类、队列路由、去重机制和审计日志。

项目内置的 EchoBot 用于演示。实际业务可替换为自己的 Business Process，完成业务查询、流程触发和消息回复。

## 系统架构

```text
Meta Webhook   -> InboundMeta   :8090 -> WebhookMeta (BS)
Twilio Webhook -> InboundTwilio :8091 -> WebhookTwilio (BS)
                           |
                           v
                    WhatsApp.BP.EchoBot
                           |
                           v
             SendMessageMeta / SendMessageTwilio
                           |
                           v
              Outbound.Meta / Outbound.Twilio
                           |
                           v
                  Meta / Twilio API
```

上图中的 BS 使用对应的入站适配器接收请求。两个平台各自拥有独立端口、配置项、队列、日志和出站操作，应用层共用 `WhatsApp.Message.Inbound` 与 `WhatsApp.Message.Outbound`。

如果需要单端口入口，可使用 `WhatsApp.BS.WebhookService` 及其适配器 `WhatsApp.Adapter.Inbound`，通过 `X-Twilio-Signature` 请求头识别 Twilio。自动识别模式需要同时配置两个平台的认证信息；独立 BS 便于分别配置和观察各平台流量。

## 安装说明

### 环境要求

Docker 演示需要：

- 支持 BuildKit 的 Docker，以及 Docker Compose 插件。
- 主机端口 `1972`、`52773`、`8090`、`8091`、`8099` 可用；如有冲突，可修改 `docker-compose.yml` 中的主机端口映射。
- 首次构建时需要下载基础镜像和 Python 依赖，除非已有缓存；运行演示不需要 Meta/Twilio 账号。

默认镜像为 `intersystems/irishealth-community:2026.2`，已在 Ubuntu ARM64 的 **InterSystems IRIS for Health Community 2026.2（Build 221U）** 上重新构建并完成验证。此前的 InterSystems IRIS `2026.3.0AI` 构建也已验证；其他版本和架构尚未验证。采用 Docker 安装时，IRIS 和 Python 由镜像提供，不必在主机上另行安装。

### 方式一：通过 Docker 运行演示

1. 克隆仓库或下载源码 ZIP 并解压，在包含 `docker-compose.yml` 的项目根目录打开终端。
2. 构建并启动：

   ```bash
   docker compose up -d --build
   docker compose ps
   ```

   构建会创建启用 Interoperability 的 `WHATSAPP` 命名空间、编译运行源码并验证 Demo Production。容器启动后自动运行 `WhatsApp.Production.Demo`；健康检查确认 Production 和两个 Webhook 监听器正常后，Compose 再启动模拟服务。
3. 打开[离线控制台](http://localhost:8099)，使用 **Send to IRIS (Meta format)** 表单发送 `hello`。流量表应出现入站消息和出站回复 `Echo: hello`。**Send to IRIS (Twilio format)** 按钮用于验证另一套平台链路。
4. 尝试 `help`、`menu`、`list`、`image`、`template` 和 `status`。演示使用模拟号码、密钥和 Twilio Content SID，不发送真实 WhatsApp 消息。

默认演示不需要私有 `.env` 文件。如需覆盖配置，可执行：

```bash
cp .env.example .env
```

`IRIS_IMAGE` 用于选择基础镜像。示例中其他启用的环境变量用于配置模拟服务，**不会自动更新 IRIS 中已保存的 Production 设置**。模拟服务和 Production 的密钥、号码 ID、发送号码必须保持一致。真实凭据应配置到 IRIS 适配器或 Interoperability Credentials 中；`.env` 文件已由 Git 忽略。

### 确认安装成功

控制台应同时显示 `IN` 和 `OUT` 流量。也可以在主机上使用 HTTP 客户端验证 Meta 握手：

```bash
curl -fsS 'http://localhost:8090/webhook?hub.mode=subscribe&hub.verify_token=demo-verify-token&hub.challenge=ready'
```

预期响应为 `ready`。如有启动问题，查看容器状态和日志：

```bash
docker compose ps
docker compose logs --tail=100 iris mock
```

| 地址 | 用途 |
|---|---|
| [http://localhost:8099](http://localhost:8099) | 离线控制台、流量列表和消息模拟 |
| `http://localhost:8099/mock/inbound` | POST 模拟 Meta 用户消息，支持 JSON 或表单 |
| `http://localhost:8099/mock/messages` | 查询模拟流量 JSON |
| `http://localhost:8090/webhook` | Meta Webhook 入口 |
| `http://localhost:8091/webhook` | Twilio Webhook 入口 |
| [IRIS 管理门户](http://localhost:52773/csp/sys/UtilHome.csp) | 演示登录账号：`_SYSTEM` / `SYS` |

管理门户属于管理接口，演示账号应仅用于本地环境；接真实账号前应调整演示安全配置。`scripts/healthcheck.sh` 由 Compose 在 **IRIS 容器内部**执行，不是主机上的测试命令。

### 停止和重新启动

```bash
docker compose stop
docker compose start
```

当前 Compose 示例把 IRIS 数据库存放在容器文件系统内，没有配置外部数据库持久卷。停止容器会保留该容器；删除或重建容器可能丢失审计数据和已保存配置。需要保留业务数据时，应先配置持久化存储与备份。

### 方式二：安装到已有 IRIS 实例

先选择启用了 Interoperability 的目标命名空间，并让 **IRIS 服务器进程可以访问**源码目录。主机上的路径不一定在容器中可见。该目录应包含 `module.xml` 和 `src/`。

如果已经安装 InterSystems Package Manager（IPM/ZPM），在目标命名空间执行：

```objectscript
zpm "load /absolute/path/to/iris-whatsapp-gateway"
```

将路径替换为服务器上的实际源码目录。尚未验证注册表中是否已有此模块，以上源码加载方式不依赖已发布的注册表条目。

没有 IPM 时，可直接加载类：

```objectscript
Set sc = $SYSTEM.OBJ.LoadDir("/absolute/path/to/iris-whatsapp-gateway/src", "ck", , 1)
Do $SYSTEM.Status.DisplayError(sc)
If $SYSTEM.Status.IsOK(sc) Do ##class(WhatsApp.Util.Setup).Install()
```

`Install()` 尝试创建可选的 `WhatsApp.SSL` 配置并输出安装指引，不会自动启动 Demo 或把组件添加到已有 Production。请按下文添加和配置 BS/BO，然后启动自己的 Production。内置 Demo 的出站地址是 Compose 网络中的 `http://mock:8099`；接真实平台时必须换成真实 API 地址及凭据。

## 应用程序工作原理

### 1. 接收和验证事件

平台向入站适配器发送 HTTP Webhook。入站适配器自行维护监听套接字；演示中 Meta 使用 `8090` 端口，Twilio 使用 `8091` 端口。可以让适配器直接终止 TLS，也可以由反向代理提供公网 HTTPS 后转发到适配器。

适配器先验证签名，再把 POST 交给业务组件。Meta 根据原始请求字节验证签名；Twilio 根据公开 URL 和解码后的表单字段，按 UTF-8 算法验证签名。Meta 的 GET 订阅请求只有在验证令牌匹配时才返回 challenge。漏配密钥不会自动关闭校验。

随后，平台解析器把原始负载转换为 `WhatsApp.Message.Inbound`，包含平台、消息 ID、参与者、账号/业务号码、文本或媒体引用、状态和错误信息。这样两个平台进入业务流程时使用的是同一 ObjectScript 请求类型。

### 2. 通过 BS 可靠路由

Business Service 按 `TargetConfigNames` 把请求送入目标的持久队列。它根据平台、账号、业务号码、消息/事件阶段和目标生成去重键，为每个目标保存持久化投递检查点。

重复事件会跳过已经接收的目标；批次中部分目标失败后，重试可以继续补投其他目标。全部目标接收后返回 HTTP `200`，可靠分发不可用时返回 `503`。这里的成功表示消息已被队列接收，不表示业务已经执行完成，也不表示消息已经送达用户设备。

### 3. 业务处理并生成回复

Demo 把入站请求路由到 `WhatsApp.BP.EchoBot`。EchoBot 写入审计记录、识别命令，再构造 `WhatsApp.Message.Outbound`。例如 `hello` 会产生 `Echo: hello`，`menu` 会生成 Meta 交互菜单。

流程根据消息的平台字段选择对应出站操作。实际应用可以把 EchoBot 换成自己的队列式业务流程，先查询订单、触发内部工作流或执行其他业务规则，再生成回复；网关本身不负责这些业务查询。

### 4. 通过 BO 和出站适配器发送

BO 接收统一出站请求，再调用其绑定的出站适配器。Meta 适配器生成 Graph API JSON，并使用 Bearer Token 认证；Twilio 适配器生成 Messages API 表单，并使用 HTTP Basic 认证。两者均明确使用 UTF-8 编码及配置的 TLS、超时参数。

符合条件的传输错误和 HTTP `429`/`5xx` 会在 `MaxRetries` 范围内重试，尝试间的等待时间为 `RetryBaseSeconds * attempt`。

出站适配器返回 `WhatsApp.Message.SendResponse`，包括平台返回的消息 ID、HTTP 状态、成功/错误信息、尝试次数和耗时。BO 写入出站审计并把结果返回调用流程。API 成功表示平台接收了发送请求，最终设备送达需要看后续状态回调。

### 5. 接收状态回调与保存审计

送达回执通过同一套认证 Webhook 入口进入系统。解析器设置 `IsStatus=1` 并归一化状态和平台错误。EchoBot 只记录状态，不再次自动回复，避免回执触发新的消息。Twilio 的状态回调地址可配置在出站适配器中，也可由单条请求覆盖。

`WhatsApp.Data.MessageLog` 保存审计记录；状态作为独立事件记录，不会自动原地修改之前的发送审计行。`WhatsApp.Data.DeliveryReceipt` 保存用于去重和中断恢复的路由检查点。

媒体事件只携带平台媒体 ID 或 URL；本应用不自动下载入站媒体，也没有提供媒体上传服务。

### 离线演示链路

模拟控制台生成用户消息并按演示密钥签名。IRIS 使用与真实集成相同的适配器、BS、流程和 BO 处理事件；出站 API 地址指向模拟服务，由它记录回复并显示到控制台：

```text
模拟控制台 -> 带签名 Webhook -> 入站适配器 -> BS -> EchoBot
          -> BO -> 出站适配器 -> 模拟平台 API -> 控制台
```

这能验证无平台账号的完整消息链路；真实账号权限、公网 HTTPS 回调及实际送达仍需单独联调。

## 命令行辅助操作

Docker 演示可以先进入 IRIS 终端：

```bash
docker compose exec iris iris session IRIS -U WHATSAPP
```

在 `WHATSAPP` 命名空间中执行：

```objectscript
Do ##class(WhatsApp.Util.Setup).Start()        ; Start the demo and enable automatic startup
Write ##class(WhatsApp.Util.Setup).Status(),!  ; Show the Production name and state
Do ##class(WhatsApp.Util.Setup).SendTest("15551234567", "hello from the terminal")
Do ##class(WhatsApp.Util.Setup).Stop()
```

`SendTest` 是离线辅助方法，默认访问 `http://mock:8099` 并使用固定的模拟 Token。仅修改 API 地址不会提供真实凭据；真实发送应使用配置好的 BO 和 `WhatsApp.Message.Outbound`。

## 接入自己的 Production

完成目标命名空间的安装后：

### 配置入站 BS

添加需要的 Business Service，将 `TargetConfigNames` 设置为自己的业务流程，并配置对应适配器。

**Meta：`WhatsApp.BS.WebhookMeta`，适配器为 `WhatsApp.Adapter.InboundMeta`**

| 配置项 | 含义 |
|---|---|
| `Port` | Webhook 端口，默认 `8090` |
| `Path` | 接收路径，默认 `/webhook` |
| `VerifyToken` / `VerifyTokenCredential` | Meta 订阅验证令牌 |
| `AppSecret` / `AppSecretCredential` | 用于验证签名的 Meta App Secret |
| `AllowedClientIPs` | 可选的客户端 IP 白名单，以逗号分隔 |
| `SSLConfig` | 适配器直接终止 TLS 时使用的配置 |
| `MaxBodyBytes`、`ListenTimeout`、`MaxRequestsPerTask` | 请求大小和监听处理参数 |

**Twilio：`WhatsApp.BS.WebhookTwilio`，适配器为 `WhatsApp.Adapter.InboundTwilio`**

| 配置项 | 含义 |
|---|---|
| `Port` | Webhook 端口，默认 `8091` |
| `Path` | 接收路径，默认 `/webhook` |
| `TwilioAuthToken` / `TwilioAuthTokenCredential` | 用于验证 Twilio 签名的 Auth Token |
| `PublicUrl` | Twilio 签名使用的精确公开 URL；空值时从请求重建 |
| `AllowedClientIPs` | 可选的客户端 IP 白名单 |
| `SSLConfig` | 适配器直接终止 TLS 时使用的配置 |
| `MaxBodyBytes`、`ListenTimeout`、`MaxRequestsPerTask` | 请求大小和监听处理参数 |

每个 BS 的 **Pool Size 保持为 1**，因为适配器持有自己的监听套接字。目标必须采用 `INVOCATION="Queue"`，空目标列表会被拒绝。Host 设置 `DedupRetentionSeconds` 默认为 `604800` 秒（七天），从成功接收开始计算。

两个独立端口可以通过反向代理映射到不同公开 URL；代理改写路径时应匹配适配器的 `Path`。若使用单端口 `WebhookService`，自动模式 `Provider=auto` 需要配置两套平台认证。

### 配置出站 BO

**Meta：`WhatsApp.BO.SendMessageMeta`，适配器为 `WhatsApp.Adapter.Outbound.Meta`**

| 配置项 | 含义 |
|---|---|
| `ApiBaseUrl` | 默认 `https://graph.facebook.com` |
| `ApiVersion` | Graph API 版本；接真实账号时选择其支持的版本 |
| `PhoneNumberId` | Meta Phone Number ID，不是电话号码 |
| `AccessToken` / `TokenCredential` | 访问令牌，优先使用凭据项 |
| `SSLConfig` | 出站 TLS 配置，例如 `WhatsApp.SSL` |
| `Timeout`、`MaxRetries`、`RetryBaseSeconds` | 超时、重试次数和等待基数 |

**Twilio：`WhatsApp.BO.SendMessageTwilio`，适配器为 `WhatsApp.Adapter.Outbound.Twilio`**

| 配置项 | 含义 |
|---|---|
| `ApiBaseUrl` | 默认 `https://api.twilio.com` |
| `TwilioApiVersion` | 默认 `2010-04-01` |
| `AccountSid`、`SenderAddress` | Twilio 账号 SID 与 `whatsapp:+...` 发送地址 |
| `TwilioAuthToken` / `TwilioTokenCredential` | Twilio Auth Token |
| `StatusCallbackURL` | 默认公开状态回调地址，可由单条请求覆盖 |
| `SSLConfig` | 出站 TLS 配置，例如 `WhatsApp.SSL` |
| `Timeout`、`MaxRetries`、`RetryBaseSeconds` | 超时与重试参数 |

`ADAPTER` 是类参数，因此平台由 BO 类选择，出站适配器没有可配置的 `Provider` 设置。出站消息对象本身可以指定 `Provider`，如果与接收它的适配器不一致，会被明确拒绝。

### 在业务流程中发送消息

```objectscript
Set req = ##class(WhatsApp.Message.Outbound).%New("15551234567", "Your order shipped")
Set req.Type = "text"
Set resp = ""
Set sc = ..SendRequestSync("SendMessageMeta", req, .resp)  ; Use SendMessageTwilio for Twilio
```

Meta 模板使用 `TemplateName`、`LanguageCode` 和可选的 `BodyParameters`；Twilio 模板使用 `Type="template"`、真实的 `ContentSid` 及可选的 `ContentVariables` JSON 对象字符串。两种平台的模板标识不能混用，设置类型也不会自动创建或审批模板。

### 在业务流程中接收入站事件

```objectscript
/// Distinguish status receipts from user messages in your queued business process.
Method OnRequest(pRequest As WhatsApp.Message.Inbound, Output pResponse As Ens.Response) As %Status
{
    If pRequest.IsStatus {
        ; Handle sent / delivered / read / failed receipts here
    } Else {
        Set text = pRequest.DisplayText()
        Set who = pRequest.From
        Set conversation = pRequest.ConversationId
    }
    Quit $$$OK
}
```

### 连接真实 Meta WhatsApp Cloud API

1. 准备带 WhatsApp 产品的 Meta 应用、业务账号和测试号码。
2. 配置 App Secret 与自己定义的验证令牌，优先使用凭据项。
3. 将适配器通过 HTTPS 公开，在 Meta 中登记回调地址并完成 GET challenge 验证。
4. 使用 `WhatsApp.BO.SendMessageMeta`，设置真实 API 地址、账号支持的 API 版本、Phone Number ID、访问令牌和出站 TLS 配置。
5. 为业务账号订阅需要的 WhatsApp 消息 Webhook，并验证用户消息和状态回调。平台会话规则要求模板时，应使用已批准模板。

账号、令牌和权限的具体要求见 [Meta 官方 WhatsApp Cloud API 集合](https://www.postman.com/meta/whatsapp-business-platform/collection/wlk6lh4/whatsapp-cloud-api)。

### 连接真实 Twilio WhatsApp

1. 配置入站 Auth Token；如果经过反向代理，设置精确的 `PublicUrl`。
2. 把 Twilio WhatsApp 发送号码的消息回调指向公开 HTTPS 入口。
3. 使用 `WhatsApp.BO.SendMessageTwilio`，配置真实 Account SID、发送地址、Auth Token、API 地址和出站 TLS 配置。
4. 配置状态回调地址，验证状态事件进入 BS。解析器优先读取 `MessageStatus`，兼容 `SmsStatus`。
5. 使用 Content SID 发送批准模板；24 小时自由会话窗口外，普通文本不能代替批准模板。Demo 的 `TwilioDemoContentSid` 是模拟值，必须替换。Demo 交互菜单可以降级为文本，模板保留 Content 模板形式。

详见 [Twilio Messages API](https://www.twilio.com/docs/messaging/api/message-resource) 和 [Content 模板发送说明](https://www.twilio.com/docs/content/send-templates-created-with-the-content-template-builder)。

## 主要类

| 类 | 职责 |
|---|---|
| `WhatsApp.Message.Inbound` | 平台无关的入站消息与状态事件 |
| `WhatsApp.Message.Outbound` | 平台无关的发送请求 |
| `WhatsApp.Message.SendResponse` | 统一发送结果 |
| `WhatsApp.Adapter.Inbound` | 自行监听 HTTP/TLS 并识别平台的基础入站适配器 |
| `WhatsApp.Adapter.InboundMeta` / `InboundTwilio` | 各平台专用入站适配器 |
| `WhatsApp.Adapter.Outbound.Base` | HTTP、TLS、凭据、重试和响应处理 |
| `WhatsApp.Adapter.Outbound.Meta` / `Twilio` | 各平台出站协议转换 |
| `WhatsApp.BS.WebhookBase` | 目标路由、持久去重及恢复 |
| `WhatsApp.BS.WebhookMeta` / `WebhookTwilio` / `WebhookService` | 专用或统一入站 BS |
| `WhatsApp.BO.SendMessageMeta` / `SendMessageTwilio` | 对应平台的发送 BO |
| `WhatsApp.BP.EchoBot` | 命令识别、菜单、模板和回显演示 |
| `WhatsApp.Data.MessageLog` | 持久审计日志 |
| `WhatsApp.Data.DeliveryReceipt` | 分目标投递检查点 |
| `WhatsApp.Production.Demo` | 离线演示 Production |
| `WhatsApp.Util.Meta` / `Twilio` | 平台负载转换 |
| `WhatsApp.Util.Crypto` | 签名与比较方法 |
| `WhatsApp.Util.Http` | 编码、号码和时间辅助方法 |
| `WhatsApp.Util.Credentials` | 凭据读取 |
| `WhatsApp.Util.Setup` | 安装、TLS、启动与终端辅助方法 |

## 安全与配置

- 入站 POST 必须有合法平台签名，缺少密钥不会跳过校验；缺少入站认证设置会阻止启动。
- Meta 对原始请求字节验签；Twilio 对 URL 和全部表单字段按其协议验签，包括非 ASCII 字符及重复参数的不同值。
- 优先使用 Interoperability Credentials。显式配置的凭据 ID 无法读取时，会拒绝使用，不回退到明文配置；未指定凭据 ID 时才使用相应字面量设置。
- 对外公开 Webhook 入口即可，管理门户不应暴露。使用反向代理终止 TLS 时，入站适配器 `SSLConfig` 留空，并为 Twilio 设置正确 `PublicUrl`。
- `AllowedClientIPs` 可用于增加网络访问限制；应结合实际网络环境配置和验证。

## 投递恢复与去重边界

HTTP `200` 表示全部目标队列已接收事件，或已有对应 accepted 回执；路由失败返回 `503`。它与平台后续的 delivered/read 状态不同。

IRIS 原生 `Ens.Queue.EnQueue` 会先提交调用方事务，再写入队列。因此本应用没有依赖外层事务把去重和入队包装成原子操作，而是使用持久化 pending 检查点、唯一的 `WhatsApp:<CorrelationId>` 消息描述，以及 accepted 检查点。

如果过程被中断，程序会通过关联描述查找并复用原生消息头。Created 可恢复原头；Queued 尚未推进时返回 `503`，等待 IRIS 原生处理或恢复，不盲目创建第二条业务消息。持续停滞时，应检查 Production 队列与事件日志。

原生消息头保留周期至少应覆盖去重保留期。未核对前不要清理 pending 对应的消息头，否则会丢失恢复依据。过期的 accepted 回执按有界批次清理，pending 保留供核查。这不构成对外部平台 exactly-once 送达的保证。

## 仓库内容与验证范围

| 路径 | 内容 |
|---|---|
| `README.md` / `README.zh-CN.md` | 英文与中文安装、配置及工作原理说明 |
| `src/WhatsApp/` | 运行所需适配器、BS、BO、消息类和工具 |
| `mock/` | 离线模拟平台与控制台 |
| `scripts/healthcheck.sh` | 容器运行健康检查 |
| `Dockerfile`、`docker-compose.yml`、`iris.script`、`merge.cpf` | 构建及演示启动配置 |
| `module.xml` | IPM 包描述 |
| `.env.example` | 公开的演示配置示例 |

本地测试类、脚本、内部记录与私有配置统一存放在 `local-only/`，已从 Git 和 Docker 构建中排除；公开源码安装和演示启动不依赖它们。

实现已完成 32 项 IRIS 测试、5 项脚本检查、5 项 Mock 契约和 8 项 HTTP E2E 本地验证。尚未完成真实账号的公网 HTTPS、权限和最终送达联调；Mock 不是完整的平台仿真。

## 常见问题

| 现象 | 检查方向 |
|---|---|
| `403 invalid signature` | App Secret/Auth Token、原始请求体、代理改写 |
| Twilio 经过代理后才出现 `403` | `PublicUrl` 是否与平台调用的精确 URL 一致 |
| 端口占用 | `8090`/`8091` 是否被其他监听器使用；主机映射是否冲突 |
| 只有入站，没有回复 | Production 队列、目标名称、BO 配置和事件日志 |
| `503` | 目标是否存在并使用 Queue；投递检查点是否等待原生队列恢复 |
| Twilio 模板失败 | 是否使用真实已批准的 Content SID，是否误用 Meta 模板名称 |
| 修改 `.env` 后验签失败 | Mock 密钥与 IRIS 中保存的适配器设置是否同步 |
| Production 无法启动 | 入站密钥/验证令牌，以及出站 Phone Number ID 或 Account SID/发送地址 |

## 许可证

MIT。本项目不隶属于 Meta、WhatsApp、Twilio 或 InterSystems。
