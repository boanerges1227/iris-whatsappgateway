# iris-whatsapp-gateway

English | [简体中文](README.zh-CN.md)

**A provider-neutral WhatsApp adapter for InterSystems IRIS Interoperability.**

Send and receive WhatsApp messages from any production through one message model.
The gateway speaks both **Meta WhatsApp Cloud API** and **Twilio Programmable
Messaging (WhatsApp)**, verifies webhook signatures, and receives webhooks through
a **self-hosted inbound adapter** &mdash; no CSP application, no web gateway route and
no REST dispatch class are required.

It also ships an **offline mock of both providers**, so the complete round trip can be
built, demonstrated and tested without any Meta or Twilio credentials.

Implements the InterSystems Ideas request
[DPI-I-882 &mdash; Introduce a WhatsApp adapter for IRIS Interoperability](https://ideas.intersystems.com/ideas/DPI-I-882)
(Community Bounty Program "Idea to Application", Round 3).

---

## What the application provides

The application adds reusable WhatsApp components to an InterSystems IRIS
Interoperability Production:

| Component | IRIS foundation | Implementations |
|---|---|---|
| Inbound adapter | `Ens.InboundAdapter` | `WhatsApp.Adapter.InboundMeta`, `WhatsApp.Adapter.InboundTwilio` |
| Outbound adapter | `Ens.OutboundAdapter` | `WhatsApp.Adapter.Outbound.Meta`, `WhatsApp.Adapter.Outbound.Twilio` |
| Business Service (BS) | `Ens.BusinessService` | `WhatsApp.BS.WebhookMeta`, `WhatsApp.BS.WebhookTwilio` |
| Business Operation (BO) | `Ens.BusinessOperation` | `WhatsApp.BO.SendMessageMeta`, `WhatsApp.BO.SendMessageTwilio` |

Meta supports text, templates, media references, locations, interactive buttons
and lists, and reactions. The Twilio outbound implementation supports text,
media URLs and Content templates. Both providers share inbound/outbound message
classes, signature validation, queued routing, deduplication and audit logging.

The included EchoBot demonstrates the components. Replace it with your own
business process to connect WhatsApp conversations to your application logic.

## Architecture

```
  Meta webhook    ──▶  BS.WebhookMeta    (InboundMeta,   :8090)
  Twilio webhook  ──▶  BS.WebhookTwilio  (InboundTwilio, :8091)
                                │
                                ▼
                    WhatsApp.BP.EchoBot (your process)
                                │
                                ▼
             BO: SendMessageMeta / SendMessageTwilio
                adapters: Outbound.Meta / .Twilio
                                │
                                ▼
                       Meta / Twilio API
```

Meta and Twilio each get their own inbound adapter, Business Service, outbound adapter
and Business Operation. That gives separate ports, configuration items, queues, logs and
retry settings on both directions. Both directions still use the same normalized message
model (`WhatsApp.Message.Inbound` / `WhatsApp.Message.Outbound`), so application
processes can use the same request types for both supported providers.

If you prefer a single endpoint, `WhatsApp.BS.WebhookService` (adapter
`WhatsApp.Adapter.Inbound`) accepts both providers on one port and detects Twilio by its
`X-Twilio-Signature` header. Automatic mode requires both providers' authentication
settings. The split classes keep provider configuration and observability separate.

## Installation

### Prerequisites

For the Docker demo you need:

- Docker with BuildKit support and the Docker Compose plugin.
- Available host ports `1972`, `52773`, `8090`, `8091` and `8099`, or adjusted
  host-side port mappings in `docker-compose.yml`.
- Network access for the first build to retrieve images and Python dependencies,
  unless they are already cached. No Meta/Twilio account is required for the demo.

The default image is `intersystems/irishealth-community:2026.2`. It was rebuilt
and validated with **InterSystems IRIS for Health Community 2026.2 (Build 221U)**
on Ubuntu ARM64. The earlier InterSystems IRIS `2026.3.0AI` build was also
validated. Other releases and architectures have not been verified. Docker
supplies IRIS and Python; neither needs to be installed directly on your host
for this installation method.

### Option A: Docker demo

1. Clone this repository or download and extract its source ZIP. Open a terminal
   in the directory containing `docker-compose.yml`.
2. Build and start the application:

   ```bash
   docker compose up -d --build
   docker compose ps
   ```

   The build creates the `WHATSAPP` namespace with Interoperability enabled,
   compiles the runtime classes and validates the Demo Production. At startup,
   IRIS starts `WhatsApp.Production.Demo`. The mock starts after the IRIS health
   check confirms the Production and both webhook listeners are responding.
3. Open [the offline console](http://localhost:8099). Send `hello` using the
   **Send to IRIS (Meta format)** form. The traffic table should show the inbound
   message and an outbound `Echo: hello` reply. The
   **Send to IRIS (Twilio format)** button exercises the second provider path.
4. Try `help`, `menu`, `list`, `image`, `template` and `status`. The demo uses
   synthetic numbers, secrets and a synthetic Twilio Content SID. It sends no
   real WhatsApp messages.

The default configuration works without a private `.env` file. For overrides:

```bash
cp .env.example .env
```

`IRIS_IMAGE` selects the base image. The other active example values configure
the mock; changing them does **not** update saved IRIS Production settings.
Keep mock secrets, number IDs and sender settings consistent with the Production.
Real provider credentials must be configured on the IRIS adapters or in
Interoperability Credentials. `.env` files are ignored by Git.

### Confirm that the demo is working

The console should display both `IN` and `OUT` traffic. You can also check the
Meta subscription handshake with a host-side HTTP client:

```bash
curl -fsS 'http://localhost:8090/webhook?hub.mode=subscribe&hub.verify_token=demo-verify-token&hub.challenge=ready'
```

Expected response: `ready`.

To inspect startup problems:

```bash
docker compose ps
docker compose logs --tail=100 iris mock
```

| URL | Purpose |
|---|---|
| [http://localhost:8099](http://localhost:8099) | mock console: traffic log and message simulator |
| `http://localhost:8099/mock/inbound` | POST a simulated Meta user message, using JSON or a form |
| `http://localhost:8099/mock/messages` | read the mock traffic as JSON |
| `http://localhost:8090/webhook` | Meta webhook listener |
| `http://localhost:8091/webhook` | Twilio webhook listener |
| [Management Portal](http://localhost:52773/csp/sys/UtilHome.csp) | IRIS administration; demo login: `_SYSTEM` / `SYS` |

The Portal is an administrative interface with demo credentials. Keep it local
and replace the demo security configuration before using real accounts.
`./scripts/healthcheck.sh` is invoked **inside the IRIS container** by Compose;
it is not a host-side test command.

### Stop and restart

```bash
docker compose stop
docker compose start
```

The sample Compose file stores the IRIS databases in the container filesystem,
not an external database volume. Stopping preserves that container; removing or
recreating it can discard audit records and saved configuration. Add persistent
database storage and backups before retaining business data.

### Option B: Install from source in an existing IRIS instance

Use an Interoperability-enabled namespace and make the source directory
accessible **to the IRIS server**. A host path is not automatically visible
inside a container. This path must contain `module.xml` and `src/`.

If InterSystems Package Manager (IPM/ZPM) is installed, select the target
namespace and load the local module:

```objectscript
zpm "load /absolute/path/to/iris-whatsapp-gateway"
```

Registry availability has not been verified; this source-loading method does not
require an already published `iris-whatsapp-gateway` registry entry.

Without IPM, load the classes directly in the target namespace:

```objectscript
Set sc = $SYSTEM.OBJ.LoadDir("/absolute/path/to/iris-whatsapp-gateway/src", "ck", , 1)
Do $SYSTEM.Status.DisplayError(sc)
If $SYSTEM.Status.IsOK(sc) Do ##class(WhatsApp.Util.Setup).Install()
```

`Install()` attempts to create the optional `WhatsApp.SSL` configuration and
prints setup guidance. It does not start the demo or add items to your existing
Production. Add and configure the BS/BO items described below, then start your
Production. The preconfigured Demo Production expects the Compose mock at
`http://mock:8099`; use real provider URLs and credentials for your own deployment.

## How the application works

### Receiving a WhatsApp event

A provider sends an HTTP webhook to an inbound adapter. Unlike a CSP-dispatched
endpoint, each adapter owns its listener socket: Meta uses port `8090` and
Twilio uses `8091` in the demo. The adapter can terminate TLS itself, or a reverse
proxy can terminate public HTTPS and forward requests to the listener.

Before dispatching a POST, the adapter validates the provider signature. Meta is
verified against the raw request bytes; Twilio is verified against the public
URL and decoded form fields using its UTF-8 signature algorithm. A valid Meta
GET subscription request returns the challenge only when its verify token
matches. Missing authentication configuration does not disable these checks.

The provider-specific parser converts the payload to
`WhatsApp.Message.Inbound`. The object carries the provider, message ID,
participant, account/phone identifiers, text or media reference, and status/error
fields. Business logic therefore receives the same ObjectScript request type
for both providers.

The Business Service forwards the request to its configured queued targets.
Before sending to each target it records a persistent delivery checkpoint keyed
by the provider, account, phone, message/event stage and destination. A repeated
event skips an already accepted target; a partial batch retry can complete other
targets. The HTTP response is `200` after all targets accept the event, or `503`
when reliable dispatch is unavailable. This acknowledges queue acceptance, not
business completion or delivery to a WhatsApp user's device.

### Processing and replying

The demo routes inbound requests to `WhatsApp.BP.EchoBot`. It writes an audit
record, recognizes commands and constructs a `WhatsApp.Message.Outbound` reply.
For example, a text message containing `hello` produces `Echo: hello`; `menu`
creates an interactive menu for Meta. The provider field selects the matching
outbound operation. Your own queued process can replace EchoBot to perform an
order lookup, trigger a workflow or apply other business rules before replying.

A Business Operation receives the outbound request and delegates transport to
its configured outbound adapter. The Meta adapter produces a Graph API JSON
request authenticated with a bearer token. The Twilio adapter produces a
Messages API form authenticated with HTTP Basic authentication. Both use
explicit UTF-8 encoding and the configured TLS/timeout settings. Eligible
transport failures and HTTP `429`/`5xx` responses are retried within
`MaxRetries`, with a delay of `RetryBaseSeconds * attempt` between attempts.

The adapter returns `WhatsApp.Message.SendResponse`, containing the provider
message ID when supplied, HTTP status, success/error information, attempt count
and latency. The BO writes an outbound audit record and returns the result to
the calling process. A successful API response indicates that the provider
accepted the send request; it does not prove final device delivery.

### Delivery callbacks and audit records

Delivery receipts enter through the same authenticated webhook path. The parser
sets `IsStatus=1` and normalizes the state and any provider error. EchoBot logs
these events without generating another reply. Twilio's callback URL can be set
on the outbound adapter or overridden per request.

`WhatsApp.Data.MessageLog` stores audit entries. Delivery receipts are separate
events rather than an automatic in-place update to an earlier audit row.
`WhatsApp.Data.DeliveryReceipt` stores routing checkpoints used for duplicate
suppression and interrupted-delivery recovery. Media events carry a provider ID
or URL; this application does not automatically download inbound media or
provide a media-upload service.

### Offline demonstration flow

The mock console generates a synthetic user event and signs it with the demo
provider secret. IRIS receives and processes it through the same adapter, BS,
process and BO classes used for a real integration. The outbound API base URLs
point back to the mock, which records the reply and displays it in the console:

```text
Mock console -> signed webhook -> inbound adapter -> BS -> EchoBot
             -> BO -> outbound adapter -> mock provider API -> console
```

This demonstrates the message pipeline without a provider account. Real
account permissions, public HTTPS callbacks and actual delivery must still be
verified separately.

## CLI helpers

For the Docker demo, enter its terminal first:

```bash
docker compose exec iris iris session IRIS -U WHATSAPP
```

Inside the `WHATSAPP` namespace:

```objectscript
Do ##class(WhatsApp.Util.Setup).Start()      ; start + auto-start the demo production
Write ##class(WhatsApp.Util.Setup).Status(),!  ; production name and state
Do ##class(WhatsApp.Util.Setup).SendTest("15551234567", "hello from the terminal")
Do ##class(WhatsApp.Util.Setup).Stop()
```

`SendTest` is an offline helper: it uses `http://mock:8099` and a fixed mock
access token. Changing its base URL does not supply real credentials. Use the
configured BO and `WhatsApp.Message.Outbound` for real messages.

## Use it in your own production

After completing the installation in your target namespace:

1. Add the inbound Business Service(s), set `TargetConfigNames` to your business
   process, and configure the adapters.

   **`WhatsApp.BS.WebhookMeta`** (adapter `WhatsApp.Adapter.InboundMeta`)

   | Setting | Meaning |
   |---|---|
   | `Port` | Meta webhook port (default `8090`) |
   | `Path` | accepted request path (default `/webhook`) |
   | `VerifyToken` / `VerifyTokenCredential` | Meta `hub.verify_token` |
   | `AppSecret` / `AppSecretCredential` | Meta App Secret for `X-Hub-Signature-256` |
   | `AllowedClientIPs` | optional comma separated IP allow list |
   | `SSLConfig` | terminate TLS in the adapter itself (optional) |
   | `MaxBodyBytes`, `ListenTimeout`, `MaxRequestsPerTask` | tuning |

   **`WhatsApp.BS.WebhookTwilio`** (adapter `WhatsApp.Adapter.InboundTwilio`)

   | Setting | Meaning |
   |---|---|
   | `Port` | Twilio webhook port (default `8091`) |
   | `Path` | accepted request path (default `/webhook`) |
   | `TwilioAuthToken` / `TwilioAuthTokenCredential` | Twilio token for `X-Twilio-Signature` |
   | `PublicUrl` | exact public URL Twilio signs (otherwise rebuilt from `Host`) |
   | `AllowedClientIPs` | optional comma separated IP allow list |
   | `SSLConfig` | terminate TLS in the adapter itself (optional) |
   | `MaxBodyBytes`, `ListenTimeout`, `MaxRequestsPerTask` | tuning |

   Two dedicated ports mean two public URLs (e.g. `wa.example.com/meta` → `:8090`
   and `wa.example.com/twilio` → `:8091` through a reverse proxy). If you would rather
   expose one URL, use `WhatsApp.BS.WebhookService` instead: it accepts both providers
   on a single port with `Provider=auto`.

   Keep each Business Service **Pool Size = 1**: the adapter owns its listener socket.

   Targets must use `INVOCATION="Queue"`. The service rejects an empty target list
   and persists a receipt for each account/phone/message/event-stage/target.
   `DedupRetentionSeconds` is a host setting (default `604800`, seven days), measured
   from successful acceptance. A repeated event does not enqueue the same target twice;
   a batch retry can complete targets that failed earlier.

2. Add one or both outbound operations.

   **`WhatsApp.BO.SendMessageMeta`** (adapter `WhatsApp.Adapter.Outbound.Meta`)

   | Setting | Meaning |
   |---|---|
   | `ApiBaseUrl` | `https://graph.facebook.com` (default) |
   | `ApiVersion` | Meta Graph version, e.g. `v21.0` |
   | `PhoneNumberId` | Meta Phone Number ID (not the phone number) |
   | `AccessToken` / `TokenCredential` | Meta access token (credentials recommended) |
   | `SSLConfig` | outbound TLS config, e.g. `WhatsApp.SSL` |
   | `Timeout`, `MaxRetries`, `RetryBaseSeconds` | HTTP behavior (429/5xx are retried) |

   **`WhatsApp.BO.SendMessageTwilio`** (adapter `WhatsApp.Adapter.Outbound.Twilio`)

   | Setting | Meaning |
   |---|---|
   | `ApiBaseUrl` | `https://api.twilio.com` (default) |
   | `TwilioApiVersion` | `2010-04-01` (default) |
   | `AccountSid`, `SenderAddress` | Twilio account and `whatsapp:+...` sender |
   | `TwilioAuthToken` / `TwilioTokenCredential` | Twilio auth token |
   | `StatusCallbackURL` | default public delivery-status callback; a request can override it |
   | `SSLConfig` | outbound TLS config, e.g. `WhatsApp.SSL` |
   | `Timeout`, `MaxRetries`, `RetryBaseSeconds` | HTTP behavior (429/5xx are retried) |

   Because `ADAPTER` is a class parameter, each provider is its own Production item
   (`SendMessageMeta` / `SendMessageTwilio`). A request whose `Provider` field names
   the other provider is rejected by the adapter with a clear error.

3. Send a message from any process (pick the matching operation):

   ```objectscript
   Set req = ##class(WhatsApp.Message.Outbound).%New("15551234567", "Your order shipped")
   Set req.Type = "text"
   Set resp = ""
   Set sc = ..SendRequestSync("SendMessageMeta", req, .resp)   ; or "SendMessageTwilio"
   ```

   When routing an inbound message, choose the operation from `pRequest.Provider`
   (the bundled `WhatsApp.BP.EchoBot` does this via `TargetOperationMeta` and
   `TargetOperationTwilio`).

   Meta also accepts `template`, `media`, `location`, `interactive` (buttons/list)
   and `reaction`. Twilio accepts text, media and Content templates. For a Twilio
   template set `Type="template"`, `ContentSid="HX..."` and optionally
   `ContentVariables` to a JSON object string. `TemplateName` / `BodyParameters`
   are Meta fields and do not identify a Twilio template. See
   `WhatsApp.Message.Outbound` for all fields.

4. Consume inbound messages in your process:

   ```objectscript
   Method OnRequest(pRequest As WhatsApp.Message.Inbound, Output pResponse As Ens.Response) As %Status
   {
       If pRequest.IsStatus {
           ; sent / delivered / read / failed receipt
       } Else {
           Set text = pRequest.DisplayText()
           Set who  = pRequest.From
           Set conversation = pRequest.ConversationId
       }
       Quit $$$OK
   }
   ```

### Connecting real Meta WhatsApp Cloud API

1. Create a Meta app with the WhatsApp product and a test number.
2. Set `AppSecret` / `AppSecretCredential`, and the **verify token** you invent.
3. Expose the listener publicly (reverse proxy or tunnel) and register
   `https://<public-host>/webhook` in Meta. Meta calls `GET /webhook` once for the
   challenge and then `POST /webhook` for every event.
4. Use `WhatsApp.BO.SendMessageMeta` and configure its adapter with your
   `PhoneNumberId`, access token (prefer `TokenCredential`), real `ApiBaseUrl`,
   an API version supported by your account, and `SSLConfig=WhatsApp.SSL`.
   The provider is selected by the BO class; there is no outbound `Provider` setting.
5. Subscribe the app to the required WhatsApp messaging webhooks for your business
   account. Verify both an incoming message and a delivery callback. Use approved
   templates when provider conversation rules require them; setting
   `Type="template"` alone does not create or approve a template.

Account onboarding, access tokens and permissions are described in the
[Meta WhatsApp Cloud API collection](https://www.postman.com/meta/whatsapp-business-platform/collection/wlk6lh4/whatsapp-cloud-api).

### Connecting real Twilio WhatsApp

1. Set the inbound `TwilioAuthToken` and, if you are behind a proxy, `PublicUrl`
   (Twilio signs the exact URL it called).
2. Point the Twilio WhatsApp sender webhook at `https://<public-host>/webhook`.
3. Use `WhatsApp.BO.SendMessageTwilio` and configure its adapter with `AccountSid`,
   `SenderAddress`, `ApiBaseUrl=https://api.twilio.com`, `SSLConfig=WhatsApp.SSL`
   and the Twilio auth token. The BO class selects the provider.
4. Set `StatusCallbackURL` to the public Twilio listener to receive delivery events,
   or configure the callback in Twilio. A request's `StatusCallbackURL` overrides
   the adapter setting. `MessageStatus` is preferred; legacy `SmsStatus` is supported.
5. Send approved templates using `ContentSid` and `ContentVariables`. Outside the
   24-hour free-form session, plain text is not a substitute for an approved template.
   The demo's `TwilioDemoContentSid` is a mock HX identifier: replace it with a real
   approved Content SID for real accounts. Only the demo's interactive menus are
   rendered as text; templates retain their Content template form.

See the [Twilio Messages API](https://www.twilio.com/docs/messaging/api/message-resource)
and [Content template sending guide](https://www.twilio.com/docs/content/send-templates-created-with-the-content-template-builder)
for platform configuration and template requirements.

## Classes

| Class | Role |
|---|---|
| `WhatsApp.Message.Inbound` | provider-neutral inbound message / status event |
| `WhatsApp.Message.Outbound` | provider-neutral outbound request |
| `WhatsApp.Message.SendResponse` | normalized send result (id, HTTP status, error, latency) |
| `WhatsApp.Adapter.Inbound` | `Ens.InboundAdapter` with self-hosted HTTP(S) listener, auto provider detection |
| `WhatsApp.Adapter.InboundMeta` | Meta only inbound adapter (handshake + HMAC-SHA256) |
| `WhatsApp.Adapter.InboundTwilio` | Twilio only inbound adapter (form + HMAC-SHA1) |
| `WhatsApp.Adapter.Outbound.Base` | shared transport: HTTP, TLS, retries, credentials, response normalization |
| `WhatsApp.Adapter.Outbound.Meta` | Meta Cloud API wire format |
| `WhatsApp.Adapter.Outbound.Twilio` | Twilio Messages API wire format |
| `WhatsApp.BS.WebhookBase` | shared inbound target routing |
| `WhatsApp.BS.WebhookMeta` | Business Service for the Meta listener |
| `WhatsApp.BS.WebhookTwilio` | Business Service for the Twilio listener |
| `WhatsApp.BS.WebhookService` | single-port Business Service with provider auto-detection |
| `WhatsApp.BO.SendMessageMeta` | Business Operation for Meta |
| `WhatsApp.BO.SendMessageTwilio` | Business Operation for Twilio |
| `WhatsApp.BP.EchoBot` | demo process with commands, media, templates and status |
| `WhatsApp.Data.MessageLog` | persistent audit log and per-conversation counters |
| `WhatsApp.Data.DeliveryReceipt` | persistent per-target deduplication and recovery checkpoints |
| `WhatsApp.Production.Demo` | self-contained demo production |
| `WhatsApp.Util.Meta` / `WhatsApp.Util.Twilio` | payload conversion |
| `WhatsApp.Util.Crypto` | HMAC helpers and constant-time comparison |
| `WhatsApp.Util.Http` | URL/form helpers and phone normalization |
| `WhatsApp.Util.Credentials` | credential lookup with literal fallback |
| `WhatsApp.Util.Setup` | auto-start, TLS config, CLI helpers |

## Security notes

* Every inbound POST is signature-checked before it reaches the production. Requests
  without a valid Meta `X-Hub-Signature-256` or Twilio `X-Twilio-Signature` get
  `403` and never create a message.
* Meta signatures are checked against the **raw** request bytes. Twilio signatures
  use the public URL and all decoded form values, including UTF-8 characters and
  distinct repeated parameter values.
* Prefer Interoperability Credentials (`*Credential` settings) over literal secrets.
  Missing inbound secrets or verify tokens prevent startup and never disable
  authentication. An explicit credential ID that cannot be resolved fails closed;
  literal settings are used only when no credential ID is selected.
* Only expose the webhook port(s); do not expose the Management Portal. A Meta-only or
  Twilio-only adapter rejects traffic for the other provider.
  If you terminate TLS in a proxy, keep `SSLConfig` empty on the adapter and use
  `PublicUrl` so Twilio signatures match.
* `AllowedClientIPs` is available for an extra network-level gate.

## Repository contents

| Path | Purpose |
|---|---|
| `README.md`, `README.zh-CN.md` | English and Chinese installation and operating guides |
| `src/WhatsApp/` | runtime adapters, Business Services, Business Operations, messages and utilities |
| `mock/` | offline demonstration provider and console |
| `scripts/healthcheck.sh` | runtime container health check |
| `Dockerfile`, `docker-compose.yml`, `iris.script`, `merge.cpf` | build and demo startup |
| `module.xml` | InterSystems package definition |
| `.env.example` | public sample settings; contains demo values |

Local tests, internal review records, work logs and private configuration are kept
in `local-only/`, which is excluded from Git and Docker builds. They are not
required to install the runtime package or start the demo. The published source
has no dependency on the local test runner.

The implementation was locally checked with 32 IRIS tests, 5 script checks,
5 mock contract checks and 8 HTTP end-to-end checks. Real Meta/Twilio account
permissions, public HTTPS and actual delivery still require account-specific
integration verification. The mock is not a complete provider emulator.

## Delivery recovery

HTTP 200 means each event was accepted by all configured native queues or had an
existing accepted receipt. A routing failure returns 503. This is separate from
the eventual provider `delivered`/`read` status.

IRIS `Ens.Queue.EnQueue` commits the caller's transactions before inserting into
the native queue. The gateway therefore uses a persisted `pending` checkpoint,
a unique `WhatsApp:<correlation-id>` message description, and an `accepted`
checkpoint instead of relying on a surrounding transaction. If interrupted, it
reuses the native header. A header still marked Queued returns 503 until native
processing/recovery advances it, so an uncertain outcome is not blindly resent.
Inspect the IRIS Production queues and event log if this persists. Keep native
message headers for at least the receipt retention period; purging a pending
header removes the evidence needed to reconcile that delivery. Pending receipts
are retained for investigation; accepted expired receipts are cleaned in bounded
batches. This does not guarantee exactly-once delivery by external providers.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `403 invalid signature` | wrong App Secret / Twilio token, or a proxy rewrote the body |
| Twilio `403` only when behind a tunnel | `PublicUrl` does not match the URL Twilio called |
| Webhook port already in use | another service or production owns `8090`/`8091`; change `Port` |
| `131047` (Meta) | free-form text outside the 24-hour window; use a template |
| `Mock` shows `OUT` but no `IN` | the inbound listener did not start; check `$System.Status` in the production log |
| Production does not come up | `SendMessageMeta` needs `PhoneNumberId`; `SendMessageTwilio` needs `AccountSid` + `SenderAddress` |

## License

MIT. Not affiliated with Meta, WhatsApp, Twilio or InterSystems.
