/// Demo business process: answers a few commands and echoes everything else,
/// showing the provider-neutral message model end to end.
Class WhatsApp.BP.EchoBot Extends Ens.BusinessProcess
{

/// Business Operation that delivers Meta replies
Property TargetOperationMeta As Ens.DataType.ConfigName [ InitialExpression = "SendMessageMeta" ];

/// Business Operation that delivers Twilio replies
Property TargetOperationTwilio As Ens.DataType.ConfigName [ InitialExpression = "SendMessageTwilio" ];

/// Approved Twilio template ContentSid; an empty value produces a demo configuration prompt.
Property TwilioDemoContentSid As %String(MAXLEN = 34);

Parameter SETTINGS = "TwilioDemoContentSid:Basic,TargetOperationMeta:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},TargetOperationTwilio:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId}";

Method OnRequest(pRequest As WhatsApp.Message.Inbound, Output pResponse As Ens.Response) As %Status
{
	Set tSC = $$$OK
	Try {
		Do ##class(WhatsApp.Data.MessageLog).LogInbound(pRequest)
		If pRequest.IsStatus {
			Quit
		}

		Set tReply = ..BuildReply(pRequest)
		If '$IsObject(tReply) {
			Quit
		}
		Do ..DowngradeForProvider(tReply, pRequest.Provider)
		Set tReply.To = pRequest.From
		Set tReply.Provider = pRequest.Provider
		Set tTarget = $Select($ZConvert(pRequest.Provider, "L") = "twilio":..TargetOperationTwilio, 1:..TargetOperationMeta)
		Set tResponse = ""
		Set tSC = ..SendRequestSync(tTarget, tReply, .tResponse)
	} Catch ex {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

Method BuildReply(pRequest As WhatsApp.Message.Inbound) As WhatsApp.Message.Outbound
{
	Set tCommand = $ZConvert($ZStrip($Select(pRequest.Type = "button" || pRequest.Type = "interactive":pRequest.InteractiveId, 1:pRequest.Text), "<>W"), "L")
	Set tReply = ##class(WhatsApp.Message.Outbound).%New()

	If (tCommand = "help") || (tCommand = "opt_help") {
		Set tReply.Text = "Commands:"_$Char(10)
		Set tReply.Text = tReply.Text _ "- help: this message"_$Char(10)
		Set tReply.Text = tReply.Text _ "- menu: interactive buttons"_$Char(10)
		Set tReply.Text = tReply.Text _ "- list: interactive list"_$Char(10)
		Set tReply.Text = tReply.Text _ "- image: send an image"_$Char(10)
		Set tReply.Text = tReply.Text _ "- template: send a template"_$Char(10)
		Set tReply.Text = tReply.Text _ "- status: conversation counters"_$Char(10)
		Set tReply.Text = tReply.Text _ "Anything else is echoed back."
		Quit tReply
	}

	If (tCommand = "menu") || (tCommand = "buttons") || (tCommand = "opt_menu") {
		Set tReply.Type = "interactive"
		Set tReply.Text = "Choose an option"
		Set tReply.Buttons = ##class(%ListOfDataTypes).%New()
		Do tReply.Buttons.Insert("opt_help|Help")
		Do tReply.Buttons.Insert("opt_image|Image")
		Do tReply.Buttons.Insert("opt_status|Status")
		Quit tReply
	}

	If (tCommand = "list") || (tCommand = "opt_list") {
		Set tReply.Type = "interactive"
		Set tReply.Text = "Pick a demo"
		Set tReply.ListButtonText = "Open demos"
		Set tReply.ListSectionTitle = "WhatsApp gateway"
		Set tReply.ListRows = ##class(%ListOfDataTypes).%New()
		Do tReply.ListRows.Insert("opt_image|Send image|Deliver a media message")
		Do tReply.ListRows.Insert("opt_template|Send template|Deliver a pre-approved template")
		Do tReply.ListRows.Insert("opt_status|Show status|Conversation counters")
		Quit tReply
	}

	If (tCommand = "image") || (tCommand = "opt_image") {
		Set tReply.Type = "media"
		Set tReply.MediaKind = "image"
		Set tReply.MediaLink = "https://picsum.photos/seed/iris-whatsapp/600/400"
		Set tReply.MediaCaption = "Sent by the IRIS WhatsApp gateway"
		Quit tReply
	}

	If (tCommand = "template") || (tCommand = "opt_template") {
		Set tReply.Type = "template"
		Set tReply.TemplateName = "hello_world"
		Set tReply.LanguageCode = "en_US"
		Quit tReply
	}

	If (tCommand = "status") || (tCommand = "opt_status") {
		Set tReply.Text = ##class(WhatsApp.Data.MessageLog).Stats(pRequest.ConversationId)
		Quit tReply
	}

	Set tReply.Text = "Echo: "_$Select(pRequest.Text '= "":pRequest.Text, 1:pRequest.DisplayText())
	Quit tReply
}

/// Render demo menus as text when needed, but send templates using their actual ContentSid.
Method DowngradeForProvider(pReply As WhatsApp.Message.Outbound, pProvider As %String)
{
	If $ZConvert(pProvider, "L") '= "twilio" {
		Quit
	}
	If pReply.Type = "interactive" {
		Set tText = pReply.Text
		If $IsObject(pReply.Buttons) {
			For i = 1:1:pReply.Buttons.Count() {
				Set tText = tText _ $Char(10) _ "- " _ $Piece(pReply.Buttons.GetAt(i), "|", 2)
			}
		}
		If $IsObject(pReply.ListRows) {
			For i = 1:1:pReply.ListRows.Count() {
				Set tText = tText _ $Char(10) _ "- " _ $Piece(pReply.ListRows.GetAt(i), "|", 2)
			}
		}
		Set pReply.Type = "text"
		Set pReply.Text = tText
	} ElseIf pReply.Type = "template" {
		If ..TwilioDemoContentSid '= "" {
			Set pReply.ContentSid = ..TwilioDemoContentSid
		} Else {
			Set pReply.Type = "text"
			Set pReply.Text = "Configure TwilioDemoContentSid with an approved Content template before sending templates."
		}
	}
}

}
