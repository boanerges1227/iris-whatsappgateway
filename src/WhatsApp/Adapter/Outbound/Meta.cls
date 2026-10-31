/// Outbound adapter for Meta WhatsApp Cloud API (Graph API).
Class WhatsApp.Adapter.Outbound.Meta Extends WhatsApp.Adapter.Outbound.Base
{

Parameter SETTINGS = "ApiBaseUrl:Basic,ApiVersion:Basic,PhoneNumberId:Basic,AccessToken:Basic,TokenCredential:Basic,SSLConfig:Basic,Timeout:Basic,MaxRetries:Basic,RetryBaseSeconds:Basic";

/// Graph API version, for example v21.0
Property ApiVersion As %String(MAXLEN = 20) [ InitialExpression = "v21.0" ];

/// Meta Phone Number ID (not the phone number itself)
Property PhoneNumberId As %String(MAXLEN = 100);

/// Literal access token. Prefer TokenCredential.
Property AccessToken As %String(MAXLEN = 2000);

/// Interoperability credentials id whose Password is the Meta access token
Property TokenCredential As %String(MAXLEN = 100);

Method ProviderName() As %String
{
	Quit "meta"
}

Method DefaultBaseUrl() As %String
{
	Quit "https://graph.facebook.com"
}

Method ValidateConfig() As %Status
{
	If ..PhoneNumberId = "" {
		Quit $$$ERROR($$$GeneralError, "Meta adapter requires PhoneNumberId")
	}
	Quit $$$OK
}

/// Create the entity stream before setting JSON and UTF-8 to preserve Unicode text and emoji.
Method BuildRequest(pRequest As WhatsApp.Message.Outbound, pHttp As %Net.HttpRequest, Output pRelativePath As %String) As %Status
{
	Try {
		Set tPayload = ##class(WhatsApp.Util.Meta).BuildPayload(pRequest, ..PhoneNumberId)
		Set pHttp.EntityBody = ##class(%Stream.GlobalCharacter).%New()
		Set pHttp.ContentType = "application/json"
		Set pHttp.ContentCharset = "utf-8"
		Do pHttp.EntityBody.Write(tPayload.%ToJSON())
		Do pHttp.SetHeader("Authorization", "Bearer " _ ..GetToken())
		Set pRelativePath = "/" _ ..ApiVersion _ "/" _ ..PhoneNumberId _ "/messages"
	} Catch ex {
		Return ex.AsStatus()
	}
	Quit $$$OK
}

Method ParseSuccess(pBody As %String, pResponse As WhatsApp.Message.SendResponse)
{
	Try {
		Set tJSON = ##class(%DynamicObject).%FromJSON(pBody)
		Set tMessages = tJSON.%Get("messages")
		If $IsObject(tMessages) && (tMessages.%Size() > 0) {
			Set pResponse.MessageId = tMessages.%Get(0).%Get("id")
		}
	} Catch ex {
	}
}

Method ParseError(pBody As %String, pResponse As WhatsApp.Message.SendResponse)
{
	Try {
		Set tJSON = ##class(%DynamicObject).%FromJSON(pBody)
		Set tError = tJSON.%Get("error")
		If $IsObject(tError) {
			Set pResponse.ErrorCode = tError.%Get("code")
			Set pResponse.ErrorMessage = tError.%Get("message")
			If pResponse.ErrorMessage = "" {
				Set pResponse.ErrorMessage = tError.%Get("error_user_msg")
			}
		}
	} Catch ex {
	}
	If pResponse.ErrorMessage = "" {
		Set pResponse.ErrorMessage = $Extract(pBody, 1, 500)
	}
}

Method GetToken() As %String
{
	Quit ..GetSecret(..TokenCredential, ..AccessToken)
}

}
