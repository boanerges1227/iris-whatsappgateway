/// Persistent audit log of inbound and outbound WhatsApp traffic.
Class WhatsApp.Data.MessageLog Extends %Persistent
{

Property Direction As %String(MAXLEN = 10);

Property Provider As %String(MAXLEN = 20);

Property MessageId As %String(MAXLEN = 200);

Property FromNumber As %String(MAXLEN = 30);

Property ToNumber As %String(MAXLEN = 30);

Property MsgType As %String(MAXLEN = 20);

Property Body As %String(MAXLEN = 4000);

Property ConversationId As %String(MAXLEN = 220);

Property TimestampISO As %String(MAXLEN = 30);

Property ErrorCode As %String(MAXLEN = 50);

Property ErrorMessage As %String(MAXLEN = 1000);

Property CreatedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($HOROLOG, 3, 1)} ];

Index CreatedAtIdx On CreatedAt;

Index ConversationIdx On ConversationId;

Index DirectionIdx On Direction;

/// Persist inbound audit records and provider receipt errors for send diagnostics.
ClassMethod LogInbound(pMessage As WhatsApp.Message.Inbound) As %Status
{
	Set tLog = ##class(WhatsApp.Data.MessageLog).%New()
	Set tLog.Direction = "IN"
	Set tLog.Provider = pMessage.Provider
	Set tLog.MessageId = pMessage.MessageId
	Set tLog.FromNumber = pMessage.From
	Set tLog.ToNumber = pMessage.To
	Set tLog.MsgType = $Select(pMessage.IsStatus:"status", 1:pMessage.Type)
	Set tLog.Body = $Extract($Select(pMessage.IsStatus:"status "_pMessage.Status, 1:pMessage.DisplayText()), 1, 4000)
	Set tLog.ConversationId = pMessage.ConversationId
	Set tLog.TimestampISO = pMessage.TimestampISO
	Set tLog.ErrorCode = pMessage.ErrorCode
	Set tLog.ErrorMessage = pMessage.ErrorTitle
	Quit tLog.%Save()
}

ClassMethod LogOutbound(pRequest As WhatsApp.Message.Outbound, pResponse As WhatsApp.Message.SendResponse) As %Status
{
	Set tLog = ##class(WhatsApp.Data.MessageLog).%New()
	Set tLog.Direction = "OUT"
	Set tLog.Provider = $Select($IsObject(pResponse):pResponse.Provider, 1:"")
	Set tLog.MessageId = $Select($IsObject(pResponse):pResponse.MessageId, 1:"")
	Set tLog.ToNumber = pRequest.To
	Set tLog.MsgType = pRequest.Type
	Set tLog.Body = $Extract($Select(pRequest.Text '= "":pRequest.Text, 1:"["_pRequest.Type_"]"), 1, 4000)
	Set tLog.ConversationId = ##class(WhatsApp.Util.Http).ConversationId(tLog.Provider, pRequest.To)
	Set tLog.TimestampISO = $ZDATETIME($HOROLOG, 3, 1)
	If $IsObject(pResponse) {
		Set tLog.ErrorCode = pResponse.ErrorCode
		Set tLog.ErrorMessage = $Extract(pResponse.ErrorMessage, 1, 1000)
	}
	Quit tLog.%Save()
}

ClassMethod Stats(pConversationId As %String) As %String
{
	Set tIn = 0
	Set tOut = 0
	Set tSQL = "select Direction, count(*) as Total from WhatsApp_Data.MessageLog where ConversationId = ? group by Direction"
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, tSQL, pConversationId)
	If $IsObject(tRS) {
		While tRS.%Next() {
			If tRS.%Get("Direction") = "IN" {
				Set tIn = +tRS.%Get("Total")
			} ElseIf tRS.%Get("Direction") = "OUT" {
				Set tOut = +tRS.%Get("Total")
			}
		}
	}
	Quit "Conversation "_pConversationId_": in="_tIn_", out="_tOut
}

}
