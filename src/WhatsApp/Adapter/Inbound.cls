/// Inbound adapter that hosts the WhatsApp webhook endpoint itself.
///
/// Unlike a CSP / REST based webhook, this adapter opens its own TCP listener
/// (optionally TLS) from the Business Service host job. That means no web
/// application, no web gateway route and no REST dispatch class are required:
/// point Meta or Twilio at http(s)://host:Port/Path and start the production.
///
/// It verifies Meta X-Hub-Signature-256 (HMAC-SHA256 over the raw body) and
/// Twilio X-Twilio-Signature (HMAC-SHA1 over the public URL plus sorted form
/// fields), converts both payload formats into WhatsApp.Message.Inbound and
/// forwards each message to the Business Service targets.
Class WhatsApp.Adapter.Inbound Extends Ens.InboundAdapter
{

Parameter SETTINGS = "Port:Basic,Path:Basic,Provider:Basic,VerifyToken:Basic,VerifyTokenCredential:Basic,AppSecret:Basic,AppSecretCredential:Basic,TwilioAuthToken:Basic,TwilioAuthTokenCredential:Basic,PublicUrl:Basic,AllowedClientIPs:Basic,MaxBodyBytes:Basic,ListenTimeout:Basic,MaxRequestsPerTask:Basic,SSLConfig:Basic";

/// TCP port the webhook listener binds to
Property Port As %Integer [ InitialExpression = 8090 ];

/// Request path accepted by the webhook (empty accepts any path)
Property Path As %String [ InitialExpression = "/webhook" ];

/// auto, meta or twilio. auto detects Twilio by the X-Twilio-Signature header.
Property Provider As %String(MAXLEN = 20) [ InitialExpression = "auto" ];

/// Meta webhook verify token (literal). Prefer VerifyTokenCredential.
Property VerifyToken As %String(MAXLEN = 300);

/// Credentials id whose Password is the Meta verify token
Property VerifyTokenCredential As %String(MAXLEN = 100);

/// Meta App Secret used to validate X-Hub-Signature-256 (literal). Prefer credentials.
Property AppSecret As %String(MAXLEN = 300);

/// Credentials id whose Password is the Meta App Secret
Property AppSecretCredential As %String(MAXLEN = 100);

/// Twilio auth token used to validate X-Twilio-Signature (literal). Prefer credentials.
Property TwilioAuthToken As %String(MAXLEN = 300);

/// Credentials id whose Password is the Twilio auth token
Property TwilioAuthTokenCredential As %String(MAXLEN = 100);

/// Public URL Twilio signs, for example https://example.com/webhook.
/// When empty, the URL is rebuilt from Host / X-Forwarded-Proto headers.
Property PublicUrl As %String(MAXLEN = 300);

/// Optional comma separated allow list of client IP addresses
Property AllowedClientIPs As %String(MAXLEN = 500);

/// Maximum accepted request body size in bytes
Property MaxBodyBytes As %Integer [ InitialExpression = 1048576 ];

/// Seconds Listen() waits for a new connection per OnTask cycle
Property ListenTimeout As %Numeric [ InitialExpression = 1 ];

/// Maximum connections served per OnTask cycle
Property MaxRequestsPerTask As %Integer [ InitialExpression = 20 ];

/// TLS configuration for the listener itself (leave empty to terminate TLS in a proxy)
Property SSLConfig As %String(MAXLEN = 100);

Property Server As %IO.ServerSocket [ Private ];

/// Validate secrets before opening the listener to prevent unauthenticated startup.
Method OnInit() As %Status
{
	Set tSC = ..ValidateSecurity()
	If $$$ISERR(tSC) Quit tSC
	Set ..Server = ##class(%IO.ServerSocket).%New()
	If ..SSLConfig '= "" {
		Set ..Server.SSLConfig = ..SSLConfig
	}
	Set tAttempt = 0
	Set tOpened = 0
	While ('tOpened) && (tAttempt < 5) {
		Set tAttempt = tAttempt + 1
		Set tTimeout = 10
		Set tOpened = ..Server.Open(..Port, .tTimeout, .tSC)
		If 'tOpened {
			If tAttempt < 5 {
				Hang 1
			}
		}
	}
	If 'tOpened {
		Set ..Server = ""
		Quit $$$ERROR($$$GeneralError, "Cannot listen on port "_..Port_": "_$System.Status.GetErrorText(tSC))
	}
	$$$LOGINFO("WhatsApp webhook listening on port "_..Port_..Path)
	Quit $$$OK
}

Method OnTearDown() As %Status
{
	If $IsObject(..Server) {
		Set tSC = $$$OK
		Do ..Server.Close(.tSC)
		Set ..Server = ""
	}
	Quit $$$OK
}

/// Process connections within a time budget and propagate listener errors.
Method OnTask() As %Status
{
	Set tSC = $$$OK
	Try {
		If '$IsObject(..Server) {
			Set tSC = ..OnInit()
			Quit:$$$ISERR(tSC)
		}
		Set tDeadline = ##class(WhatsApp.Util.Http).TimestampSeconds() + ..ListenTimeout
		Set tHandled = 0
		While tHandled < ..MaxRequestsPerTask {
			Set tTimeout = $Select(tHandled = 0:..ListenTimeout, 1:0.1)
			Set tOK = ..Server.Listen(.tTimeout, .tSC)
			If 'tOK {
				Set tErrorText = $System.Status.GetErrorText(tSC)
				If $Find(tErrorText, "Timed out") > 0 {
					Set tSC = $$$OK
				} Else {
					$$$LOGWARNING("Webhook listen error: "_tErrorText)
					Set tSC = ..Reopen()
				}
				Quit
			}
			Set tHandled = tHandled + 1
			Set tTaskSC = ..HandleConnection()
			If $$$ISERR(tTaskSC) {
				$$$LOGWARNING("Webhook connection error: "_$System.Status.GetErrorText(tTaskSC))
			}
			Set tDisconnectSC = $$$OK
			Do ..Server.Disconnect(.tDisconnectSC)
			If $$$ISERR(tDisconnectSC) {
				$$$LOGWARNING("Webhook disconnect error: "_$System.Status.GetErrorText(tDisconnectSC))
				Set tSC = ..Reopen()
				Quit
			}
			If ##class(WhatsApp.Util.Http).TimestampSeconds() >= tDeadline {
				Quit
			}
		}
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Validate secrets for the selected provider; automatic mode requires both providers.
Method ValidateSecurity() As %Status
{
	Kill headers
	Set provider = ..ResolveProvider(.headers)
	Set auto = (..%ClassName(1) = "WhatsApp.Adapter.Inbound") && ((..Provider = "auto") || (..Provider = ""))
	If (provider = "meta") || auto {
		If ##class(WhatsApp.Util.Credentials).Get(..AppSecretCredential, ..AppSecret) = "" {
			Quit $$$ERROR($$$GeneralError, "Meta AppSecret is required")
		}
		If ##class(WhatsApp.Util.Credentials).Get(..VerifyTokenCredential, ..VerifyToken) = "" {
			Quit $$$ERROR($$$GeneralError, "Meta VerifyToken is required")
		}
	}
	If (provider = "twilio") || auto {
		If ##class(WhatsApp.Util.Credentials).Get(..TwilioAuthTokenCredential, ..TwilioAuthToken) = "" {
			Quit $$$ERROR($$$GeneralError, "Twilio AuthToken is required")
		}
	}
	Quit $$$OK
}

Method Reopen() As %Status
{
	Set tSC = $$$OK
	If $IsObject(..Server) {
		Do ..Server.Close(.tSC)
	}
	Set ..Server = ""
	Hang 0.2
	Quit ..OnInit()
}

Method HandleConnection() As %Status
{
	Set tStatus = 0
	Set tContentType = "application/json"
	Set tResponseBody = ""
	Set tSC = ..ProcessRequest(.tStatus, .tContentType, .tResponseBody)
	If tStatus > 0 {
		Set tWriteSC = ..WriteResponse(tStatus, tContentType, tResponseBody)
		If $$$ISERR(tWriteSC) {
			Set tSC = tWriteSC
		}
	}
	Quit tSC
}

/// Parse one HTTP request and prepare the response.
/// Returning from this method (including the early Quit statements) skips no cleanup,
/// because the response is written by HandleConnection after this method returns.
Method ProcessRequest(Output pStatus As %Integer, Output pContentType As %String, Output pResponseBody As %String) As %Status
{
	Set tSC = $$$OK
	Set pStatus = 0
	Set pContentType = "application/json"
	Set pResponseBody = ""
	Try {
		Kill tHeaders
		Set tRawBody = ""
		Set tReadSC = ..ReadRawRequest(.tRequestLine, .tHeaders, .tRawBody)
		If $$$ISERR(tReadSC) {
			Set pStatus = 400
			Set pContentType = "application/json"
			Set pResponseBody = "{""error"":""invalid request""}"
			Quit
		}
		If tRequestLine = "" {
			Quit
		}

		Set tMethod = $ZConvert($Piece(tRequestLine, " ", 1), "U")
		Set tTarget = $Piece(tRequestLine, " ", 2)
		Do ##class(WhatsApp.Util.Http).SplitTarget(tTarget, .tPath, .tQuery)

		If (..Path '= "") && (tPath '= ..Path) {
			Set pStatus = 404
			Set pResponseBody = "{""error"":""not found""}"
			Quit
		}

		If (..AllowedClientIPs '= "") && ('..ClientAllowed()) {
			Set pStatus = 403
			Set pResponseBody = "{""error"":""forbidden""}"
			Quit
		}

		Set tProvider = ..ResolveProvider(.tHeaders)

		If tMethod = "OPTIONS" {
			Set pStatus = 204
			Set pContentType = "text/plain"
			Quit
		}

		If tMethod = "GET" {
			Set pStatus = ..HandleGet(tProvider, tQuery, .pContentType, .pResponseBody)
			Quit
		}

		If tMethod '= "POST" {
			Set pStatus = 405
			Set pResponseBody = "{""error"":""method not allowed""}"
			Quit
		}

		If tProvider = "twilio" {
			Set pStatus = ..HandleTwilioPost(tTarget, tRawBody, .tHeaders, .pContentType, .pResponseBody)
		} Else {
			Set pStatus = ..HandleMetaPost(tRawBody, .tHeaders, .pContentType, .pResponseBody)
		}
	} Catch ex {
		Set tSC = ex.AsStatus()
		$$$LOGERROR("Webhook handler error: "_ex.DisplayString())
		Set pStatus = 500
		Set pContentType = "application/json"
		Set pResponseBody = "{""error"":""internal error""}"
	}
	Quit tSC
}

Method HandleGet(pProvider As %String, pQuery As %String, Output pContentType As %String, Output pBody As %String) As %Integer
{
	Set pContentType = "text/plain"
	Set pBody = ""
	If pProvider '= "meta" {
		Quit 405
	}
	Do ##class(WhatsApp.Util.Http).ParseQueryString(pQuery, .tParams)
	If $Get(tParams("hub.mode")) '= "subscribe" {
		Quit 400
	}
	If '..VerifyTokenMatches($Get(tParams("hub.verify_token"))) {
		$$$LOGWARNING("Rejected Meta webhook verification: bad verify token")
		Quit 403
	}
	Set pBody = $Get(tParams("hub.challenge"))
	Quit 200
}

/// Validate raw bytes before parsing Meta events; return 503 if any dispatch fails.
Method HandleMetaPost(pRawBody As %String, ByRef pHeaders, Output pContentType As %String, Output pBody As %String) As %Integer
{
	Set pContentType = "application/json"
	Set pBody = "{}"
	Set tSecret = ##class(WhatsApp.Util.Credentials).Get(..AppSecretCredential, ..AppSecret)
	If '##class(WhatsApp.Util.Crypto).VerifyMetaSignature(pRawBody, $Get(pHeaders("x-hub-signature-256")), tSecret) {
		$$$LOGWARNING("Rejected Meta webhook: invalid X-Hub-Signature-256")
		Set pBody = "{""error"":""invalid signature""}"
		Quit 403
	}

	Set tJSON = ""
	Try {
		Set tJSON = ##class(%DynamicObject).%FromJSON($ZCONVERT(pRawBody, "I", "UTF8"))
	} Catch ex {
		Set tJSON = ""
	}
	If '$IsObject(tJSON) {
		Set pBody = "{""error"":""invalid json""}"
		Quit 400
	}

	Set tSC = ##class(WhatsApp.Util.Meta).ParseWebhook(tJSON, .tMessages)
	If $$$ISERR(tSC) {
		$$$LOGWARNING("Cannot parse Meta webhook: "_$System.Status.GetErrorText(tSC))
		Set pBody = "{""error"":""unsupported payload""}"
		Quit 400
	}

	Set tCount = $Get(tMessages, 0)
	Set tDispatchSC = $$$OK
	For i = 1:1:tCount {
		Set tDispatchSC = $$$ADDSC(tDispatchSC, ..Dispatch(tMessages(i)))
	}
	If $$$ISERR(tDispatchSC) {
		Set pBody = "{""error"":""delivery unavailable""}"
		Quit 503
	}
	Set pBody = "{""status"":""ok"",""received"":"_tCount_"}"
	Quit 200
}

/// Always validate Twilio signatures; return empty TwiML on success or 503 on dispatch failure.
Method HandleTwilioPost(pTarget As %String, pRawBody As %String, ByRef pHeaders, Output pContentType As %String, Output pBody As %String) As %Integer
{
	Set pContentType = "text/plain"
	Set pBody = ""
	Set tSC = ##class(WhatsApp.Util.Http).ParseUrlEncoded($ZCONVERT(pRawBody, "I", "UTF8"), .tFields)
	If $$$ISERR(tSC) {
		Quit 400
	}

	Set tToken = ##class(WhatsApp.Util.Credentials).Get(..TwilioAuthTokenCredential, ..TwilioAuthToken)
	If tToken = "" Quit 403
	If tToken '= "" {
		Set tURL = ..PublicUrl
		If tURL = "" {
			Set tProto = $Get(pHeaders("x-forwarded-proto"))
			If tProto = "" {
				Set tProto = $Select(..SSLConfig '= "":"https", 1:"http")
			}
			Set tURL = tProto _ "://" _ $Get(pHeaders("host")) _ pTarget
		}
		If '##class(WhatsApp.Util.Crypto).VerifyTwilioSignature(tURL, .tFields, tToken, $Get(pHeaders("x-twilio-signature"))) {
			$$$LOGWARNING("Rejected Twilio webhook: invalid X-Twilio-Signature")
			Quit 403
		}
	}

	Set tSC = ##class(WhatsApp.Util.Twilio).ParseWebhook(.tFields, .tMessages)
	If $$$ISERR(tSC) {
		$$$LOGWARNING("Cannot parse Twilio webhook: "_$System.Status.GetErrorText(tSC))
		Quit 400
	}
	Set tCount = $Get(tMessages, 0)
	Set tDispatchSC = $$$OK
	For i = 1:1:tCount {
		Set tDispatchSC = $$$ADDSC(tDispatchSC, ..Dispatch(tMessages(i)))
	}
	If $$$ISERR(tDispatchSC) Quit 503
	Set pContentType = "application/xml", pBody = "<Response/>"
	Quit 200
}

/// Forward to the business host and propagate errors to the HTTP handler.
Method Dispatch(pMessage As WhatsApp.Message.Inbound) As %Status
{
	Set tSC = $$$OK
	Set tOut = ""
	Try {
		Set tSC = ..BusinessHost.ProcessInput(pMessage, .tOut)
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	If $$$ISERR(tSC) {
		$$$LOGERROR("Webhook dispatch failed: "_$System.Status.GetErrorText(tSC))
	}
	Quit tSC
}

/// Verify the subscription token and reject missing configuration.
Method VerifyTokenMatches(pProvided As %String) As %Boolean
{
	Set tExpected = ##class(WhatsApp.Util.Credentials).Get(..VerifyTokenCredential, ..VerifyToken)
	If tExpected = "" {
		Quit 0
	}
	Quit ##class(WhatsApp.Util.Crypto).SecureEquals(pProvided, tExpected)
}

Method ResolveProvider(ByRef pHeaders) As %String
{
	Set tProvider = $ZConvert(..Provider, "L")
	If (tProvider '= "") && (tProvider '= "auto") {
		Quit tProvider
	}
	If $Get(pHeaders("x-twilio-signature")) '= "" {
		Quit "twilio"
	}
	Quit "meta"
}

Method ClientAllowed() As %Boolean
{
	Try {
		Set tRemote = ..Server.Remote
		Set tIP = $Piece(tRemote, ":", 1)
		If tIP = "" {
			Return 1
		}
		Set tAllowed = 0
		For i = 1:1:$Length(..AllowedClientIPs, ",") {
			If tIP = $ZStrip($Piece(..AllowedClientIPs, ",", i), "<>W") {
				Set tAllowed = 1
				Quit
			}
		}
		Return tAllowed
	} Catch ex {
		Return 1
	}
}

/// Read a complete HTTP request from the socket: request line, headers and body.
/// %IO.ServerSocket.Read() returns buffered socket data reliably, while mixing
/// ReadLine() and Read() can lose data on some releases, so headers are parsed
/// from the raw buffer.
Method ReadRawRequest(Output pRequestLine As %String, Output pHeaders, Output pBody As %String) As %Status
{
	Set pRequestLine = ""
	Set pBody = ""
	Set tSC = $$$OK
	Set tBuffer = ""
	Set tBodySep = 0
	While tBodySep = 0 {
		Set tChunk = ..Server.Read(8192, 5, .tSC)
		If $$$ISERR(tSC) {
			Quit
		}
		If tChunk = "" {
			Quit
		}
		Set tBuffer = tBuffer _ tChunk
		If $Length(tBuffer) > (..MaxBodyBytes + 65536) {
			Set tSC = $$$ERROR($$$GeneralError, "Request headers exceed the configured limit")
			Quit
		}
		Set tBodySep = $Find(tBuffer, $Char(13,10,13,10))
		If tBodySep = 0 {
			Set tBodySep = $Find(tBuffer, $Char(10,10))
		}
	}
	If $$$ISERR(tSC) {
		Quit tSC
	}
	If tBodySep = 0 {
		Quit $$$ERROR($$$GeneralError, "Incomplete HTTP request headers")
	}

	Set tHeaderBlock = $Replace($Extract(tBuffer, 1, tBodySep - 1), $Char(13,10), $Char(10))
	Set pBody = $Extract(tBuffer, tBodySep, *)
	Set pRequestLine = $ZStrip($Piece(tHeaderBlock, $Char(10), 1), "<>W")

	Set tLineCount = $Length(tHeaderBlock, $Char(10))
	For i = 2:1:tLineCount {
		Set tLine = $Piece(tHeaderBlock, $Char(10), i)
		If tLine = "" Continue
		Set tColon = $Find(tLine, ":")
		If tColon = 0 Continue
		Set tName = $ZConvert($ZStrip($Extract(tLine, 1, tColon - 2), "<>W"), "L")
		Set tValue = $ZStrip($Extract(tLine, tColon, *), "<>W")
		Set pHeaders(tName) = tValue
	}

	Set tTransfer = $ZConvert($Get(pHeaders("transfer-encoding")), "L")
	If $Find(tTransfer, "chunked") > 0 {
		Quit ..ReadChunkedBody(.pBody)
	}

	Set tLength = +$Get(pHeaders("content-length"))
	If tLength > ..MaxBodyBytes {
		Quit $$$ERROR($$$GeneralError, "Request body exceeds MaxBodyBytes")
	}
	While $Length(pBody) < tLength {
		Set tChunk = ..Server.Read(tLength - $Length(pBody), 5, .tSC)
		If $$$ISERR(tSC) {
			Quit
		}
		If tChunk = "" {
			Quit
		}
		Set pBody = pBody _ tChunk
	}
	Quit tSC
}

/// Decode a chunked transfer-encoded body. pBody initially contains the bytes
/// already received after the header block; more are read from the socket when required.
Method ReadChunkedBody(ByRef pBody As %String) As %Status
{
	Set tSC = $$$OK
	Set tData = pBody
	Set tOut = ""
	Set tPos = 1
	For {
		Set tSizeLine = ""
		For {
			Set tBuf = $Extract(tData, tPos, *)
			Set tIdx = $Find(tBuf, $Char(13,10))
			If tIdx > 0 {
				Set tSizeLine = $ZStrip($Extract(tBuf, 1, tIdx - 2), "<>W")
				Set tPos = tPos + tIdx - 1
				Quit
			}
			Set tMore = ..AppendMore(.tData, 5, .tSC)
			If $$$ISERR(tSC) || ('tMore) {
				Quit
			}
		}
		If $$$ISERR(tSC) {
			Quit
		}
		If tSizeLine = "" {
			Set tSC = $$$ERROR($$$GeneralError, "Malformed chunked body")
			Quit
		}
		Set tSize = ##class(WhatsApp.Util.Http).HexToDecimal($Piece(tSizeLine, ";", 1))
		If tSize = 0 {
			For {
				Set tBuf = $Extract(tData, tPos, *)
				Set tIdx = $Find(tBuf, $Char(13,10))
				If tIdx = 0 {
					Set tMore = ..AppendMore(.tData, 5, .tSC)
					If $$$ISERR(tSC) || ('tMore) {
						Quit
					}
					Continue
				}
				Set tTrailer = $Extract(tBuf, 1, tIdx - 2)
				Set tPos = tPos + tIdx - 1
				If tTrailer = "" Quit
			}
			Quit
		}
		While $Length(tData) < (tPos + tSize + 1) {
			Set tMore = ..AppendMore(.tData, 5, .tSC)
			If $$$ISERR(tSC) || ('tMore) {
				Quit
			}
		}
		If $Length(tData) < (tPos + tSize) {
			Set tSC = $$$ERROR($$$GeneralError, "Incomplete chunked body")
			Quit
		}
		Set tOut = tOut _ $Extract(tData, tPos, tPos + tSize - 1)
		Set tPos = tPos + tSize + 2
		If $Length(tOut) > ..MaxBodyBytes {
			Set tSC = $$$ERROR($$$GeneralError, "Chunked body exceeds MaxBodyBytes")
			Quit
		}
	}
	Set pBody = tOut
	Quit tSC
}

/// Append available socket bytes to pData. Returns 0 when no more data arrived.
Method AppendMore(ByRef pData As %String, pTimeout As %Numeric, Output pSC As %Status) As %Boolean
{
	Set pSC = $$$OK
	Set tChunk = ..Server.Read(8192, pTimeout, .pSC)
	If $$$ISERR(pSC) {
		Quit 0
	}
	If tChunk = "" {
		Quit 0
	}
	Set pData = pData _ tChunk
	Quit 1
}

Method WriteResponse(pStatus As %Integer, pContentType As %String, pBody As %String) As %Status
{
	Set tSC = $$$OK
	Set tBytes = $ZConvert(pBody, "O", "UTF8")
	Do ..Server.WriteLine("HTTP/1.1 "_pStatus_" "_##class(WhatsApp.Util.Http).Reason(pStatus), 1, .tSC)
	Do ..Server.WriteLine("Content-Type: "_pContentType_"; charset=utf-8", 1, .tSC)
	Do ..Server.WriteLine("Content-Length: "_$Length(tBytes), 1, .tSC)
	Do ..Server.WriteLine("Connection: close", 1, .tSC)
	Do ..Server.WriteLine("", 1, .tSC)
	If $Length(tBytes) > 0 {
		Do ..Server.Write(tBytes, 1, .tSC)
	}
	Quit tSC
}

}
