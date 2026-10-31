/// Shared transport for provider specific outbound adapters.
///
/// Handles the HTTP call, TLS configuration, timeout, retries, credentials and
/// the normalized WhatsApp.Message.SendResponse. Subclasses only describe the
/// wire format (path, body, authentication) and how to read the response.
Class WhatsApp.Adapter.Outbound.Base Extends Ens.OutboundAdapter
{

/// Provider API base URL. Subclasses supply the default when empty.
Property ApiBaseUrl As %String(MAXLEN = 300);

/// TLS configuration used for HTTPS calls
Property SSLConfig As %String(MAXLEN = 100);

Property Timeout As %Integer [ InitialExpression = 30 ];

Property MaxRetries As %Integer [ InitialExpression = 2 ];

Property RetryBaseSeconds As %Numeric [ InitialExpression = 1 ];

/// Provider name used in responses and validation: meta or twilio
Method ProviderName() As %String
{
	Quit ""
}

/// Default API base URL for this provider
Method DefaultBaseUrl() As %String
{
	Quit ""
}

/// Validate provider specific configuration before the operation starts.
Method ValidateConfig() As %Status
{
	Quit $$$OK
}

/// Build the provider request: path, content type, body and authentication.
Method BuildRequest(pRequest As WhatsApp.Message.Outbound, pHttp As %Net.HttpRequest, Output pRelativePath As %String) As %Status
{
	Quit $$$ERROR($$$GeneralError, "BuildRequest is not implemented")
}

/// Extract the provider message id from a successful response.
Method ParseSuccess(pBody As %String, pResponse As WhatsApp.Message.SendResponse)
{
}

/// Extract a provider error code and message from a failed response.
Method ParseError(pBody As %String, pResponse As WhatsApp.Message.SendResponse)
{
	If pResponse.ErrorMessage = "" {
		Set pResponse.ErrorMessage = $Extract(pBody, 1, 500)
	}
}

/// Send a normalized message, measure full-timestamp latency, and retry transient failures.
Method Send(pRequest As WhatsApp.Message.Outbound, Output pResponse As WhatsApp.Message.SendResponse) As %Status
{
	Set pResponse = ##class(WhatsApp.Message.SendResponse).%New()
	Set pResponse.Provider = ..ProviderName()
	Set tStart = $ZTIMESTAMP

	Set tSC = ..ValidateRequest(pRequest)
	If $$$ISERR(tSC) {
		Set pResponse.ErrorMessage = $System.Status.GetErrorText(tSC)
		Quit tSC
	}

	Set tAttempt = 0
	Set tDone = 0
	While ('tDone) && (tAttempt <= ..MaxRetries) {
		Set tAttempt = tAttempt + 1
		Set pResponse.Attempts = tAttempt
		Set tRetry = 0
		Set tSC = ..SendOnce(pRequest, pResponse, .tRetry)
		If $$$ISOK(tSC) && (pResponse.HttpStatus >= 200) && (pResponse.HttpStatus < 300) {
			Set pResponse.Success = 1
			Set tDone = 1
		} ElseIf 'tRetry {
			Set tDone = 1
		} ElseIf tAttempt <= ..MaxRetries {
			Hang (..RetryBaseSeconds * tAttempt)
		}
	}

	Set pResponse.LatencyMs = ##class(WhatsApp.Util.Http).ElapsedMs(tStart)
	If pResponse.Success {
		Quit $$$OK
	}
	If $$$ISERR(tSC) && (pResponse.ErrorMessage = "") {
		Set pResponse.ErrorMessage = $System.Status.GetErrorText(tSC)
	}
	Quit $$$ERROR($$$GeneralError, "WhatsApp send failed ("_pResponse.Provider_"): "_pResponse.ErrorCode_" "_pResponse.ErrorMessage)
}

/// Reject a request explicitly addressed to another provider.
Method ValidateRequest(pRequest As WhatsApp.Message.Outbound) As %Status
{
	Set tRequested = $ZConvert(pRequest.Provider, "L")
	If (tRequested = "") || (tRequested = "mock") {
		Quit $$$OK
	}
	If tRequested '= ..ProviderName() {
		Quit $$$ERROR($$$GeneralError, "Request provider '"_pRequest.Provider_"' cannot be sent by the "_..ProviderName()_" adapter")
	}
	Quit $$$OK
}

/// Perform a single HTTP attempt.
Method SendOnce(pRequest As WhatsApp.Message.Outbound, pResponse As WhatsApp.Message.SendResponse, Output pRetry As %Boolean) As %Status
{
	Set pRetry = 0
	Set tSC = $$$OK
	Try {
		Set tHttp = ##class(%Net.HttpRequest).%New()
		Set tHttp.Timeout = ..Timeout
		Set tHttp.OpenTimeout = ..Timeout
		If ..SSLConfig '= "" {
			Set tHttp.SSLConfiguration = ..SSLConfig
		}

		Set tRelative = ""
		Set tSC = ..BuildRequest(pRequest, tHttp, .tRelative)
		If $$$ISERR(tSC) {
			Set pResponse.ErrorMessage = $System.Status.GetErrorText(tSC)
			Quit
		}

		Set tParts = ""
		Do ##class(%Net.URLParser).Parse(..ApiBaseUrl _ tRelative, .tParts)
		Set tHttp.Server = $Get(tParts("host"))
		Set tHttp.Https = ($ZConvert($Get(tParts("scheme")), "L") = "https")
		Set tHttp.Port = $Select($Get(tParts("port")) '= "": +$Get(tParts("port")), tHttp.Https: 443, 1: 80)

		Set tPath = $Get(tParts("path"))
		If tPath = "" {
			Set tPath = "/"
		}
		If $Get(tParts("query")) '= "" {
			Set tPath = tPath _ "?" _ $Get(tParts("query"))
		}

		Set tSC = tHttp.Post(tPath)

		If $$$ISERR(tSC) {
			Set pResponse.HttpStatus = 0
			Set pResponse.ErrorMessage = $System.Status.GetErrorText(tSC)
			Set pRetry = 1
			Quit
		}

		Set pResponse.HttpStatus = tHttp.HttpResponse.StatusCode
		Set tResponseBody = ""
		If $IsObject(tHttp.HttpResponse.Data) {
			Set tResponseBody = tHttp.HttpResponse.Data.Read()
		}
		Set pResponse.RawJSON = tResponseBody

		If (pResponse.HttpStatus >= 200) && (pResponse.HttpStatus < 300) {
			Do ..ParseSuccess(tResponseBody, pResponse)
		} Else {
			Set pRetry = (pResponse.HttpStatus = 429) || (pResponse.HttpStatus >= 500)
			Do ..ParseError(tResponseBody, pResponse)
		}
	} Catch ex {
		Set tSC = ex.AsStatus()
		Set pRetry = 1
		Set pResponse.ErrorMessage = ex.DisplayString()
	}
	Quit tSC
}

/// Resolve credentials consistently without literal fallback for an invalid explicit credential.
ClassMethod GetSecret(pCredentialID As %String, pLiteral As %String) As %String
{
	Quit ##class(WhatsApp.Util.Credentials).Get(pCredentialID, pLiteral)
}

Method OnInit() As %Status
{
	If ..ApiBaseUrl = "" {
		Set ..ApiBaseUrl = ..DefaultBaseUrl()
	}
	Quit ..ValidateConfig()
}

}
