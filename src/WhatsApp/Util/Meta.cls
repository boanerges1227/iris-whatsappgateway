/// Meta WhatsApp Cloud API payload conversion.
Class WhatsApp.Util.Meta
{

/// Convert a Meta webhook payload into WhatsApp.Message.Inbound objects.
/// pMessages returns a count at the root and the messages in subscripts.
ClassMethod ParseWebhook(pRoot As %DynamicObject, Output pMessages) As %Status
{
	Set pMessages = 0
	Set tCount = 0
	Try {
		If '$IsObject(pRoot) {
			Quit
		}
		Set tEntries = pRoot.%Get("entry")
		If '$IsObject(tEntries) {
			Quit
		}
		For i = 0:1:tEntries.%Size() - 1 {
			Set tEntry = tEntries.%Get(i)
			Set tAccountId = tEntry.%Get("id")
			Set tChanges = tEntry.%Get("changes")
			If '$IsObject(tChanges) {
				Continue
			}
			For j = 0:1:tChanges.%Size() - 1 {
				Set tValue = tChanges.%Get(j).%Get("value")
				If '$IsObject(tValue) {
					Continue
				}
				Set tMetadata = tValue.%Get("metadata")
				Set tPhoneNumberId = $Select($IsObject(tMetadata):tMetadata.%Get("phone_number_id"), 1:"")

				Set tNames = ""
				Set tContacts = tValue.%Get("contacts")
				If $IsObject(tContacts) {
					For k = 0:1:tContacts.%Size() - 1 {
						Set tContact = tContacts.%Get(k)
						Set tProfile = tContact.%Get("profile")
						Set tWaId = tContact.%Get("wa_id")
						If ($IsObject(tProfile)) && (tWaId '= "") {
							Set tNames(tWaId) = tProfile.%Get("name")
						}
					}
				}

				Set tMessages = tValue.%Get("messages")
				If $IsObject(tMessages) {
					For k = 0:1:tMessages.%Size() - 1 {
						Set tMessage = tMessages.%Get(k)
						Set tIn = ..ParseMessage(tMessage, tAccountId, tPhoneNumberId)
						Set tIn.FromName = $Get(tNames(tIn.From))
						Set tIn.ConversationId = ##class(WhatsApp.Util.Http).ConversationId("meta", tIn.From)
						Set tCount = tCount + 1
						Set pMessages(tCount) = tIn
					}
				}

				Set tStatuses = tValue.%Get("statuses")
				If $IsObject(tStatuses) {
					For k = 0:1:tStatuses.%Size() - 1 {
						Set tStatus = tStatuses.%Get(k)
						Set tIn = ..ParseStatus(tStatus, tAccountId, tPhoneNumberId)
						Set tIn.ConversationId = ##class(WhatsApp.Util.Http).ConversationId("meta", tIn.To)
						Set tCount = tCount + 1
						Set pMessages(tCount) = tIn
					}
				}
			}
		}
	} Catch ex {
		Return ex.AsStatus()
	}
	Set pMessages = tCount
	Quit $$$OK
}

/// Convert a single Meta message object.
ClassMethod ParseMessage(pMessage As %DynamicObject, pAccountId As %String, pPhoneNumberId As %String) As WhatsApp.Message.Inbound
{
	Set tIn = ##class(WhatsApp.Message.Inbound).%New()
	Set tIn.Provider = "meta"
	Set tIn.AccountId = pAccountId
	Set tIn.PhoneNumberId = pPhoneNumberId
	Set tIn.MessageId = pMessage.%Get("id")
	Set tIn.From = ##class(WhatsApp.Util.Http).NormalizePhone(pMessage.%Get("from"))
	Set tIn.Timestamp = pMessage.%Get("timestamp")
	Set tIn.TimestampISO = ##class(WhatsApp.Util.Http).IsoFromEpoch(tIn.Timestamp)
	Set tIn.RawJSON = pMessage.%ToJSON()
	Set tType = pMessage.%Get("type")
	Set tIn.Type = $Select(tType = "": "unknown", 1: tType)
	Set tBody = $Select(tType = "": "", 1: pMessage.%Get(tType))

	If tType = "text" {
		Set tIn.Text = $Select($IsObject(tBody):tBody.%Get("body"), 1:"")
	} ElseIf (tType = "image") || (tType = "audio") || (tType = "video") || (tType = "document") || (tType = "sticker") {
		If $IsObject(tBody) {
			Set tIn.MediaId = tBody.%Get("id")
			Set tIn.MediaMimeType = tBody.%Get("mime_type")
			Set tIn.MediaSHA256 = tBody.%Get("sha256")
			Set tIn.MediaCaption = tBody.%Get("caption")
			Set tIn.Text = tBody.%Get("caption")
			Set tIn.MediaFilename = tBody.%Get("filename")
		}
	} ElseIf tType = "location" {
		If $IsObject(tBody) {
			Set tIn.Latitude = tBody.%Get("latitude")
			Set tIn.Longitude = tBody.%Get("longitude")
			Set tIn.LocationName = tBody.%Get("name")
			Set tIn.LocationAddress = tBody.%Get("address")
		}
	} ElseIf tType = "button" {
		If $IsObject(tBody) {
			Set tIn.Text = tBody.%Get("text")
			Set tIn.InteractiveId = tBody.%Get("payload")
		}
	} ElseIf tType = "interactive" {
		If $IsObject(tBody) {
			Set tReply = $Select($IsObject(tBody.%Get("button_reply")):tBody.%Get("button_reply"), 1:tBody.%Get("list_reply"))
			If $IsObject(tReply) {
				Set tIn.InteractiveId = tReply.%Get("id")
				Set tIn.Text = tReply.%Get("title")
			}
		}
	} ElseIf tType = "reaction" {
		If $IsObject(tBody) {
			Set tIn.Text = tBody.%Get("emoji")
			Set tIn.InteractiveId = tBody.%Get("message_id")
		}
	}

	Set tIn.To = pPhoneNumberId
	Quit tIn
}

/// Convert a single Meta delivery status object into a status event.
ClassMethod ParseStatus(pStatus As %DynamicObject, pAccountId As %String, pPhoneNumberId As %String) As WhatsApp.Message.Inbound
{
	Set tIn = ##class(WhatsApp.Message.Inbound).%New()
	Set tIn.Provider = "meta"
	Set tIn.AccountId = pAccountId
	Set tIn.PhoneNumberId = pPhoneNumberId
	Set tIn.IsStatus = 1
	Set tIn.Type = "status"
	Set tIn.MessageId = pStatus.%Get("id")
	Set tIn.Status = pStatus.%Get("status")
	Set tIn.To = ##class(WhatsApp.Util.Http).NormalizePhone(pStatus.%Get("recipient_id"))
	Set tIn.Timestamp = pStatus.%Get("timestamp")
	Set tIn.TimestampISO = ##class(WhatsApp.Util.Http).IsoFromEpoch(tIn.Timestamp)
	Set tIn.RawJSON = pStatus.%ToJSON()
	Set tErrors = pStatus.%Get("errors")
	If $IsObject(tErrors) && (tErrors.%Size() > 0) {
		Set tError = tErrors.%Get(0)
		Set tIn.ErrorCode = tError.%Get("code")
		Set tIn.ErrorTitle = tError.%Get("title")
	}
	Quit tIn
}

/// Build Meta payloads with explicit JSON boolean types rather than numeric 0/1 values.
ClassMethod BuildPayload(pRequest As WhatsApp.Message.Outbound, pPhoneNumberId As %String) As %DynamicObject
{
	Set tPayload = {}
	Do tPayload.%Set("messaging_product", "whatsapp")
	Do tPayload.%Set("recipient_type", "individual")
	Do tPayload.%Set("to", ##class(WhatsApp.Util.Http).NormalizePhone(pRequest.To))

	Set tType = $ZConvert(pRequest.Type, "L")
	If tType = "" {
		Set tType = "text"
	}

	If tType = "text" {
		Do tPayload.%Set("type", "text")
		Set tText = {}
		Do tText.%Set("body", pRequest.Text)
		Do tText.%Set("preview_url", pRequest.PreviewURL, "boolean")
		Do tPayload.%Set("text", tText)
	} ElseIf tType = "template" {
		Do tPayload.%Set("type", "template")
		Set tTemplate = {}
		Do tTemplate.%Set("name", pRequest.TemplateName)
		Set tLanguage = {}
		Do tLanguage.%Set("code", pRequest.LanguageCode)
		Do tTemplate.%Set("language", tLanguage)
		Set tComponents = []
		If $IsObject(pRequest.BodyParameters) && (pRequest.BodyParameters.Count() > 0) {
			Set tParameters = []
			For i = 1:1:pRequest.BodyParameters.Count() {
				Set tParameter = {}
				Do tParameter.%Set("type", "text")
				Do tParameter.%Set("text", pRequest.BodyParameters.GetAt(i))
				Do tParameters.%Push(tParameter)
			}
			Set tComponent = {}
			Do tComponent.%Set("type", "body")
			Do tComponent.%Set("parameters", tParameters)
			Do tComponents.%Push(tComponent)
		}
		If tComponents.%Size() > 0 {
			Do tTemplate.%Set("components", tComponents)
		}
		Do tPayload.%Set("template", tTemplate)
	} ElseIf tType = "media" {
		Set tKind = $ZConvert(pRequest.MediaKind, "L")
		If tKind = "" {
			Set tKind = "image"
		}
		Do tPayload.%Set("type", tKind)
		Set tMedia = {}
		If pRequest.MediaId '= "" {
			Do tMedia.%Set("id", pRequest.MediaId)
		} Else {
			Do tMedia.%Set("link", pRequest.MediaLink)
		}
		If pRequest.MediaCaption '= "" {
			Do tMedia.%Set("caption", pRequest.MediaCaption)
		}
		If (tKind = "document") && (pRequest.MediaFilename '= "") {
			Do tMedia.%Set("filename", pRequest.MediaFilename)
		}
		Do tPayload.%Set(tKind, tMedia)
	} ElseIf tType = "location" {
		Do tPayload.%Set("type", "location")
		Set tLocation = {}
		Do tLocation.%Set("latitude", +pRequest.Latitude)
		Do tLocation.%Set("longitude", +pRequest.Longitude)
		If pRequest.LocationName '= "" {
			Do tLocation.%Set("name", pRequest.LocationName)
		}
		If pRequest.LocationAddress '= "" {
			Do tLocation.%Set("address", pRequest.LocationAddress)
		}
		Do tPayload.%Set("location", tLocation)
	} ElseIf tType = "reaction" {
		Do tPayload.%Set("type", "reaction")
		Set tReaction = {}
		Do tReaction.%Set("message_id", pRequest.ReactionMessageId)
		Do tReaction.%Set("emoji", pRequest.ReactionEmoji)
		Do tPayload.%Set("reaction", tReaction)
	} ElseIf tType = "interactive" {
		Do tPayload.%Set("type", "interactive")
		If $IsObject(pRequest.ListRows) && (pRequest.ListRows.Count() > 0) {
			Do tPayload.%Set("interactive", ..BuildList(pRequest))
		} Else {
			Do tPayload.%Set("interactive", ..BuildButtons(pRequest))
		}
	} Else {
		Throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Unsupported outbound message type: "_pRequest.Type))
	}

	If pRequest.ReplyToMessageId '= "" {
		Set tContext = {}
		Do tContext.%Set("message_id", pRequest.ReplyToMessageId)
		Do tPayload.%Set("context", tContext)
	}

	Quit tPayload
}

/// Build an interactive reply-buttons object.
ClassMethod BuildButtons(pRequest As WhatsApp.Message.Outbound) As %DynamicObject
{
	Set tInteractive = {}
	Do tInteractive.%Set("type", "button")
	Set tBody = {}
	Do tBody.%Set("text", pRequest.Text)
	Do tInteractive.%Set("body", tBody)
	Set tButtons = []
	If $IsObject(pRequest.Buttons) {
		For i = 1:1:pRequest.Buttons.Count() {
			Set tPair = pRequest.Buttons.GetAt(i)
			Set tButton = {}
			Do tButton.%Set("type", "reply")
			Set tReply = {}
			Do tReply.%Set("id", $Piece(tPair, "|", 1))
			Do tReply.%Set("title", $Piece(tPair, "|", 2, *))
			Do tButton.%Set("reply", tReply)
			Do tButtons.%Push(tButton)
		}
	}
	Set tAction = {}
	Do tAction.%Set("buttons", tButtons)
	Do tInteractive.%Set("action", tAction)
	Quit tInteractive
}

/// Build an interactive list object.
ClassMethod BuildList(pRequest As WhatsApp.Message.Outbound) As %DynamicObject
{
	Set tInteractive = {}
	Do tInteractive.%Set("type", "list")
	Set tBody = {}
	Do tBody.%Set("text", pRequest.Text)
	Do tInteractive.%Set("body", tBody)
	Set tRows = []
	For i = 1:1:pRequest.ListRows.Count() {
		Set tRowSpec = pRequest.ListRows.GetAt(i)
		Set tRow = {}
		Do tRow.%Set("id", $Piece(tRowSpec, "|", 1))
		Do tRow.%Set("title", $Piece(tRowSpec, "|", 2))
		If $Piece(tRowSpec, "|", 3, *) '= "" {
			Do tRow.%Set("description", $Piece(tRowSpec, "|", 3, *))
		}
		Do tRows.%Push(tRow)
	}
	Set tSection = {}
	If pRequest.ListSectionTitle '= "" {
		Do tSection.%Set("title", pRequest.ListSectionTitle)
	}
	Do tSection.%Set("rows", tRows)
	Set tSections = []
	Do tSections.%Push(tSection)
	Set tAction = {}
	Do tAction.%Set("button", pRequest.ListButtonText)
	Do tAction.%Set("sections", tSections)
	Do tInteractive.%Set("action", tAction)
	Quit tInteractive
}

}
