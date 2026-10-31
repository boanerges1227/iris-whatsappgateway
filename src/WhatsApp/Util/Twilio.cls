/// Twilio WhatsApp API payload conversion.
Class WhatsApp.Util.Twilio
{

/// Parse Twilio messages and callbacks, preferring MessageStatus while accepting legacy SmsStatus.
ClassMethod ParseWebhook(ByRef pFields, Output pMessages) As %Status
{
	Set pMessages = 0
	Try {
		Set tIn = ##class(WhatsApp.Message.Inbound).%New()
		Set tIn.Provider = "twilio"
		Set tIn.AccountId = $Get(pFields("AccountSid"))
		Set tIn.MessageId = $Select($Get(pFields("MessageSid")) '= "":$Get(pFields("MessageSid")), 1:$Get(pFields("SmsMessageSid")))
		Set tIn.FromName = $Get(pFields("ProfileName"))
		Set tIn.From = ##class(WhatsApp.Util.Http).NormalizePhone($Get(pFields("From")))
		Set tIn.To = ##class(WhatsApp.Util.Http).NormalizePhone($Get(pFields("To")))
		Set tIn.PhoneNumberId = tIn.To
		Set tIn.Timestamp = ##class(WhatsApp.Util.Http).EpochNow()
		Set tIn.TimestampISO = ##class(WhatsApp.Util.Http).IsoFromEpoch(tIn.Timestamp)
		Set tIn.RawJSON = ..FieldsToJSON(.pFields)

		Set tMediaCount = +$Get(pFields("NumMedia"))
		Set tStatus = $ZConvert($Select($Get(pFields("MessageStatus")) '= "":pFields("MessageStatus"), 1:$Get(pFields("SmsStatus"))), "L")
		Set tIsStatusValue = $ListFind($ListBuild("accepted", "scheduled", "canceled", "queued", "sending", "sent", "delivered", "read", "failed", "undelivered"), tStatus) > 0

		If (tMediaCount = 0) && ($Get(pFields("Body")) = "") && tIsStatusValue && (tIn.MessageId '= "") {
			Set tIn.IsStatus = 1
			Set tIn.Type = "status"
			Set tIn.Status = tStatus
			Set tIn.PhoneNumberId = tIn.From
			Set tIn.ErrorCode = $Get(pFields("ErrorCode"))
			Set tIn.ErrorTitle = $Select($Get(pFields("ChannelStatusMessage")) '= "":pFields("ChannelStatusMessage"), 1:$Get(pFields("ErrorMessage")))
			Set tUser = tIn.To
		} Else {
			Set tUser = $Select($Get(pFields("WaId")) '= "":##class(WhatsApp.Util.Http).NormalizePhone(pFields("WaId")), 1:tIn.From)
			Set tIn.From = tUser
			Set tIn.Text = $Get(pFields("Body"))
			If tMediaCount > 0 {
				Set tIn.MediaUrl = $Get(pFields("MediaUrl0"))
				Set tIn.MediaMimeType = $Get(pFields("MediaContentType0"))
				Set tIn.MediaCaption = $Get(pFields("Body"))
				Set tIn.Type = ..MediaType(tIn.MediaMimeType)
			} ElseIf $Get(pFields("ButtonPayload")) '= "" {
				Set tIn.Type = "button"
				Set tIn.InteractiveId = $Get(pFields("ButtonPayload"))
				Set tIn.Text = $Get(pFields("ButtonText"))
			} ElseIf ($Get(pFields("Latitude")) '= "") && ($Get(pFields("Longitude")) '= "") {
				Set tIn.Type = "location"
				Set tIn.Latitude = $Get(pFields("Latitude"))
				Set tIn.Longitude = $Get(pFields("Longitude"))
			} Else {
				Set tIn.Type = "text"
			}
		}
		Set tIn.ConversationId = ##class(WhatsApp.Util.Http).ConversationId("twilio", tUser)

		Set pMessages(1) = tIn
		Set pMessages = 1
	} Catch ex {
		Return ex.AsStatus()
	}
	Quit $$$OK
}

/// Map a media content type to a normalized media kind.
ClassMethod MediaType(pMimeType As %String) As %String
{
	Set tMime = $ZConvert(pMimeType, "L")
	If $Extract(tMime, 1, 6) = "image/" {
		Quit "image"
	}
	If $Extract(tMime, 1, 6) = "audio/" {
		Quit "audio"
	}
	If $Extract(tMime, 1, 6) = "video/" {
		Quit "video"
	}
	Quit "document"
}

/// Serialize the submitted form fields for audit.
ClassMethod FieldsToJSON(ByRef pFields) As %String
{
	Set tObject = {}
	Set tName = ""
	For {
		Set tName = $Order(pFields(tName))
		Quit:tName=""
		Do tObject.%Set(tName, pFields(tName))
	}
	Quit tObject.%ToJSON()
}

/// Build Twilio forms with ContentSid templates and per-request callback URL overrides.
ClassMethod BuildForm(pRequest As WhatsApp.Message.Outbound, pFrom As %String, pDefaultCallback As %String = "") As %String
{
	Set tType = $ZConvert(pRequest.Type, "L")
	Set tFrom = ..TwilioAddress(pFrom)
	Set tTo = ..TwilioAddress(pRequest.To)
	Set tFields = "From=" _ ##class(WhatsApp.Util.Http).UrlEncode(tFrom)
	Set tFields = tFields _ "&To=" _ ##class(WhatsApp.Util.Http).UrlEncode(tTo)

	If tType = "text" {
		Set tFields = tFields _ "&Body=" _ ##class(WhatsApp.Util.Http).UrlEncode(pRequest.Text)
	} ElseIf tType = "media" {
		Set tLink = pRequest.MediaLink
		If tLink = "" {
			Throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Twilio requires a public MediaLink (MediaId is a Meta-only concept)"))
		}
		Set tFields = tFields _ "&MediaUrl=" _ ##class(WhatsApp.Util.Http).UrlEncode(tLink)
		Set tCaption = $Select(pRequest.MediaCaption '= "":pRequest.MediaCaption, 1:pRequest.Text)
		If tCaption '= "" {
			Set tFields = tFields _ "&Body=" _ ##class(WhatsApp.Util.Http).UrlEncode(tCaption)
		}
	} ElseIf tType = "template" {
		If (pRequest.ContentSid '? 1"HX"32AN) {
			Throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Twilio template requires a valid ContentSid (HX followed by 32 hexadecimal digits)"))
		}
		If $Translate($ZConvert($Extract(pRequest.ContentSid, 3, *), "L"), "0123456789abcdef") '= "" {
			Throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Invalid Twilio ContentSid"))
		}
		Set tFields = tFields _ "&ContentSid=" _ ##class(WhatsApp.Util.Http).UrlEncode(pRequest.ContentSid)
		If pRequest.ContentVariables '= "" {
			Set tVariables = ##class(%DynamicObject).%FromJSON(pRequest.ContentVariables)
			If tVariables.%ClassName() '= "%DynamicObject" {
				Throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "ContentVariables must be a JSON object"))
			}
			Set tFields = tFields _ "&ContentVariables=" _ ##class(WhatsApp.Util.Http).UrlEncode(tVariables.%ToJSON())
		}
	} Else {
		Throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Twilio outbound supports text, media and Content templates"))
	}
	Set tCallback = $Select(pRequest.StatusCallbackURL '= "":pRequest.StatusCallbackURL, 1:pDefaultCallback)
	If tCallback '= "" Set tFields = tFields _ "&StatusCallback=" _ ##class(WhatsApp.Util.Http).UrlEncode(tCallback)
	Quit tFields
}

/// Return a Twilio WhatsApp address (whatsapp:+E164).
ClassMethod TwilioAddress(pValue As %String) As %String
{
	Set tValue = ##class(WhatsApp.Util.Http).NormalizePhone(pValue)
	If tValue = "" {
		Quit ""
	}
	Quit "whatsapp:+" _ tValue
}

}
