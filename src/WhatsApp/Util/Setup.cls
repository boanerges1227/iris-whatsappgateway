/// Installation helpers: register the demo production, optional TLS config and CLI helpers.
Class WhatsApp.Util.Setup
{

/// Called by IPM after installation. Creates the optional TLS config and prints next steps.
ClassMethod Install() As %Status
{
	Do ..EnsureSSLConfig()
	Write !, "iris-whatsapp-gateway installed."
	Write !, "Next: add WhatsApp.BS.WebhookService (Pool Size 1) and WhatsApp.BO.SendMessageMeta / SendMessageTwilio to your production."
	Write !, "Run do ##class(WhatsApp.Util.Setup).Start() to launch the bundled demo production."
	Quit $$$OK
}

/// Called by IPM and by the Docker build. Sets the demo production to auto-start.
ClassMethod Setup() As %Status
{
	Set tSC = $$$OK
	Try {
		Do ..EnsureSSLConfig()
		Set ^Ens.AutoStart = "WhatsApp.Production.Demo"
		Set ^Ens.AutoStart("StartupPriority") = 1
		If '$Data(^Ens.Configuration("csp", "LastProduction")) {
			Set ^Ens.Configuration("csp", "LastProduction") = "WhatsApp.Production.Demo"
		}
		Write !, "WhatsApp demo production registered for auto-start."
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Verify Production startup and shutdown during the build and propagate failures.
ClassMethod Smoke() As %Status
{
	Set tSC = ##class(Ens.Director).StartProduction("WhatsApp.Production.Demo")
	If $$$ISERR(tSC) {
		Write !, "SMOKE: production did not start: ", $System.Status.GetErrorText(tSC)
		Quit tSC
	}
	Write !, "SMOKE: production started: ", ..Status()
	Set tSC = ##class(Ens.Director).StopProduction(10, 1)
	If $$$ISERR(tSC) {
		Write !, "SMOKE: production did not stop cleanly: ", $System.Status.GetErrorText(tSC)
	}
	Quit tSC
}

/// Best-effort creation of an outbound TLS configuration for graph.facebook.com / api.twilio.com.
ClassMethod EnsureSSLConfig() As %Status
{
	Set tNamespace = $NAMESPACE
	Set tSC = $$$OK
	Try {
		ZN "%SYS"
		If '$CLASSMETHOD("Security.SSLConfigs", "Exists", "WhatsApp.SSL") {
			Set tSC = $CLASSMETHOD("Security.SSLConfigs", "Create", "WhatsApp.SSL")
			If $$$ISERR(tSC) {
				Write !, "NOTE: TLS config WhatsApp.SSL was not created: ", $System.Status.GetErrorText(tSC)
				Set tSC = $$$OK
			}
		}
	} Catch ex {
		Set tSC = $$$OK
	}
	ZN tNamespace
	Quit tSC
}

ClassMethod Start() As %Status
{
	Set tSC = ##class(Ens.Director).StartProduction("WhatsApp.Production.Demo")
	If $$$ISOK(tSC) {
		Set ^Ens.AutoStart = "WhatsApp.Production.Demo"
		Set ^Ens.AutoStart("StartupPriority") = 1
	}
	Quit tSC
}

ClassMethod Stop() As %Status
{
	Quit ##class(Ens.Director).StopProduction(10, 1)
}

ClassMethod Status() As %String
{
	Set tProduction = ""
	Set tState = ""
	Set tSC = ##class(Ens.Director).GetProductionStatus(.tProduction, .tState)
	If $$$ISERR(tSC) {
		Quit "status error: "_$System.Status.GetErrorText(tSC)
	}
	Quit "production="_tProduction_", state="_tState
}

/// Send a message directly through the outbound adapter, without a production.
/// Useful for a quick smoke test from the terminal.
ClassMethod SendTest(pTo As %String, pText As %String, pBaseUrl As %String = "http://mock:8099", pHttpPhoneNumberId As %String = "1234567890") As %Status
{
	Set tAdapter = ##class(WhatsApp.Adapter.Outbound.Meta).%New()
	Set tAdapter.ApiBaseUrl = pBaseUrl
	Set tAdapter.PhoneNumberId = pHttpPhoneNumberId
	Set tAdapter.AccessToken = "mock-token"
	Set tRequest = ##class(WhatsApp.Message.Outbound).%New(pTo, pText)
	Set tResponse = ""
	Set tSC = tAdapter.Send(tRequest, .tResponse)
	If $IsObject(tResponse) {
		Write !, "success=", tResponse.Success, " provider=", tResponse.Provider, " id=", tResponse.MessageId, " http=", tResponse.HttpStatus
		If tResponse.ErrorMessage '= "" {
			Write !, "error=", tResponse.ErrorCode, " ", tResponse.ErrorMessage
		}
	}
	Quit tSC
}

/// Check the Production and both HTTP listeners rather than login availability alone.
ClassMethod Healthy() As %Boolean
{
	Set sc = ##class(Ens.Director).GetProductionStatus(.name, .state)
	If $$$ISERR(sc) || (name '= "WhatsApp.Production.Demo") || (state '= 1) Quit 0
	For port = 8090:1:8091 {
		Set http = ##class(%Net.HttpRequest).%New(), http.Server = "127.0.0.1", http.Port = port, http.Timeout = 7, http.OpenTimeout = 2
		Set sc = http.Get("/webhook")
		If $$$ISERR(sc) Quit
		If http.HttpResponse.StatusCode '= $Select(port = 8090:400, 1:405) {
			Set sc = $$$ERROR($$$GeneralError, "Unexpected webhook health response")
			Quit
		}
	}
	Quit $$$ISOK(sc)
}

}
