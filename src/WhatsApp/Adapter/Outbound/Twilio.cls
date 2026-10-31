/// Outbound adapter for Twilio Programmable Messaging (WhatsApp).
Class WhatsApp.Adapter.Outbound.Twilio Extends WhatsApp.Adapter.Outbound.Base
{

Parameter SETTINGS = "ApiBaseUrl:Basic,TwilioApiVersion:Basic,AccountSid:Basic,SenderAddress:Basic,TwilioAuthToken:Basic,TwilioTokenCredential:Basic,StatusCallbackURL:Basic,SSLConfig:Basic,Timeout:Basic,MaxRetries:Basic,RetryBaseSeconds:Basic";

/// Twilio REST API version
Property TwilioApiVersion As %String(MAXLEN = 20) [ InitialExpression = "2010-04-01" ];

/// Twilio Account SID
Property AccountSid As %String(MAXLEN = 100);

/// Sender address used by Twilio, for example whatsapp:+15550001111
Property SenderAddress As %String(MAXLEN = 40);

/// Literal Twilio auth token. Prefer TwilioTokenCredential.
Property TwilioAuthToken As %String(MAXLEN = 2000);

/// Interoperability credentials id whose Password is the Twilio auth token
Property TwilioTokenCredential As %String(MAXLEN = 100);

/// Default public status callback URL, overridden by the request StatusCallbackURL.
Property StatusCallbackURL As %String(MAXLEN = 2000);

Method ProviderName() As %String
{
	Quit "twilio"
}

Method DefaultBaseUrl() As %String
{
	Quit "https://api.twilio.com"
}

Method ValidateConfig() As %Status
{
	If ..AccountSid = "" {
		Quit $$$ERROR($$$GeneralError, "Twilio adapter requires AccountSid")
	}
	If ..SenderAddress = "" {
		Quit $$$ERROR($$$GeneralError, "Twilio adapter requires SenderAddress")
	}
	Quit $$$OK
}

/// Build the authenticated Twilio form with explicit UTF-8 wire encoding.
Method BuildRequest(pRequest As WhatsApp.Message.Outbound, pHttp As %Net.HttpRequest, Output pRelativePath As %String) As %Status
{
	Try {
		Set tBody = ##class(WhatsApp.Util.Twilio).BuildForm(pRequest, ..SenderAddress, ..StatusCallbackURL)
		Set pHttp.EntityBody = ##class(%Stream.GlobalCharacter).%New()
		Set pHttp.ContentType = "application/x-www-form-urlencoded"
		Set pHttp.ContentCharset = "utf-8"
		Do pHttp.EntityBody.Write(tBody)
		// HTTP authentication must not use MIME line wrapping; flag 1 disables Base64 CRLF insertion.
		Do pHttp.SetHeader("Authorization", "Basic " _ $SYSTEM.Encryption.Base64Encode(..AccountSid _ ":" _ ..GetTwilioToken(), 1))
		Set pRelativePath = "/" _ ..TwilioApiVersion _ "/Accounts/" _ ..AccountSid _ "/Messages.json"
	} Catch ex {
		Return ex.AsStatus()
	}
	Quit $$$OK
}

Method ParseSuccess(pBody As %String, pResponse As WhatsApp.Message.SendResponse)
{
	Try {
		Set tJSON = ##class(%DynamicObject).%FromJSON(pBody)
		Set pResponse.MessageId = tJSON.%Get("sid")
		If pResponse.MessageId = "" {
			Set pResponse.MessageId = tJSON.%Get("SmsMessageSid")
		}
	} Catch ex {
	}
}

Method ParseError(pBody As %String, pResponse As WhatsApp.Message.SendResponse)
{
	Try {
		Set tJSON = ##class(%DynamicObject).%FromJSON(pBody)
		Set pResponse.ErrorCode = tJSON.%Get("code")
		Set pResponse.ErrorMessage = tJSON.%Get("message")
	} Catch ex {
	}
	If pResponse.ErrorMessage = "" {
		Set pResponse.ErrorMessage = $Extract(pBody, 1, 500)
	}
}

Method GetTwilioToken() As %String
{
	Quit ..GetSecret(..TwilioTokenCredential, ..TwilioAuthToken)
}

}
