/// Shared target routing for webhook Business Services.
Class WhatsApp.BS.WebhookBase Extends Ens.BusinessService
{

/// Comma separated configuration names that receive WhatsApp.Message.Inbound requests
Property TargetConfigNames As %String(MAXLEN = 1000);

/// Deduplication retention, default seven days; positive values allow reprocessing after expiry.
Property DedupRetentionSeconds As %Integer [ InitialExpression = 604800 ];

Property LastReceiptCleanup As %BigInt [ Private ];

Parameter SETTINGS = "TargetConfigNames:Basic:selector?multiSelect=1&context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},DedupRetentionSeconds:Basic";

/// Persist per-target checkpoints, skip accepted targets, and allow failed targets to retry.
Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Set pOutput = ""
	If '$IsObject(pInput) Quit $$$ERROR($$$GeneralError, "Missing inbound event")
	If pInput.MessageId = "" Quit $$$ERROR($$$GeneralError, "Inbound MessageId is required for reliable delivery")
	If ..DedupRetentionSeconds < 1 Quit $$$ERROR($$$GeneralError, "DedupRetentionSeconds must be positive")
	// Reject caller transactions that would release the lock before the actual commit boundary.
	If $TLevel > 0 Quit $$$ERROR($$$GeneralError, "Webhook delivery requires an independent transaction boundary")
	Set now = ##class(WhatsApp.Util.Http).EpochNow()
	If (now - ..LastReceiptCleanup) >= 60 {
		Set cleanupSC = ##class(WhatsApp.Data.DeliveryReceipt).PurgeExpired()
		If $$$ISERR(cleanupSC) Quit cleanupSC
		Set ..LastReceiptCleanup = now
	}
	Set tSC = $$$OK
	Set tTargets = 0
	For i = 1:1:$Length(..TargetConfigNames, ",") {
		Set tTarget = $ZStrip($Piece(..TargetConfigNames, ",", i), "<>W")
		If tTarget = "" Continue
		Set tTargets = tTargets + 1
		Set tSC = $$$ADDSC(tSC, ..DeliverOnce(pInput, tTarget))
	}
	If tTargets = 0 Quit $$$ERROR($$$GeneralError, "At least one TargetConfigNames entry is required")
	Quit tSC
}

/// Lock each event-target pair across processes; persist pending, send, then persist accepted.
/// Native EnQueue commits caller transactions, so an outer transaction cannot roll back acceptance.
Method DeliverOnce(pInput As WhatsApp.Message.Inbound, pTarget As %String) As %Status
{
	Set key = ##class(WhatsApp.Data.DeliveryReceipt).KeyFor(pInput, pTarget)
	Lock +^WhatsAppDeliveryLock(key):5
	If '$Test Quit $$$ERROR($$$GeneralError, "Concurrent delivery is busy; retry later")
	Set sc = $$$OK
	Try {
		Set sc = ..ValidateTarget(pTarget)
		If $$$ISERR(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
		Set receipt = ##class(WhatsApp.Data.DeliveryReceipt).%OpenId(key)
		Set now = ##class(WhatsApp.Util.Http).EpochNow()
		Set fresh = 0
		If '$IsObject(receipt) || ((receipt.State = "accepted") && (receipt.ExpiresAt <= now)) {
			If '$IsObject(receipt) Set receipt = ##class(WhatsApp.Data.DeliveryReceipt).%New()
			Set receipt.ReceiptKey = key, receipt.ExpiresAt = now + ..DedupRetentionSeconds, receipt.State = "pending", receipt.HeaderId = ""
			Set receipt.CorrelationId = $System.Util.CreateGUID()
			Set sc = receipt.%Save()
			Set fresh = 1
		}
		If $$$ISOK(sc) && (receipt.State = "pending") {
			Set canSend = 1
			If 'fresh Set sc = ..RecoverPending(receipt, pTarget, .canSend)
			If $$$ISOK(sc) && canSend {
				Set sc = ..SendRequestAsync(pTarget, pInput, "WhatsApp:"_receipt.CorrelationId)
				If $$$ISOK(sc) {
					Set receipt.State = "accepted"
					Set receipt.ExpiresAt = ##class(WhatsApp.Util.Http).EpochNow() + ..DedupRetentionSeconds
					If $IsObject(..%RequestHeader) Set receipt.HeaderId = ..%RequestHeader.%Id()
					Set sc = receipt.%Save()
				}
			}
		}
	} Catch ex {
		Set sc = ex.AsStatus()
	}
	Lock -^WhatsAppDeliveryLock(key)
	Quit sc
}

/// Use the public Production configuration API and require persistent Queue invocation targets.
Method ValidateTarget(pTarget As %String) As %Status
{
	Set sc = ##class(Ens.Director).GetProductionStatus(.name, .state)
	If $$$ISERR(sc) Quit sc
	Set production = ##class(Ens.Config.Production).%OpenId(name)
	If '$IsObject(production) Quit $$$ERROR($$$GeneralError, "No active production configuration")
	Set item = production.FindItemByConfigName(pTarget, .sc)
	If $$$ISERR(sc) Quit sc
	If '$IsObject(item) Quit $$$ERROR($$$GeneralError, "Unknown delivery target")
	If $ClassMethod(item.ClassName, "%GetParameter", "INVOCATION") '= "Queue" {
		Quit $$$ERROR($$$GeneralError, "Reliable webhook targets must use INVOCATION=Queue")
	}
	Quit $$$OK
}

/// Recover interrupted acceptance through the correlation ID on the native message header.
/// Return 503 while a Queued header awaits native recovery; do not create another business message.
Method RecoverPending(pReceipt As WhatsApp.Data.DeliveryReceipt, pTarget As %String, Output pCanSend As %Boolean) As %Status
{
	Set pCanSend = 0
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM Ens.MessageHeader WHERE Description = ? AND TargetConfigName = ? ORDER BY ID DESC", "WhatsApp:"_pReceipt.CorrelationId, pTarget)
	If rs.%SQLCODE < 0 Quit $$$ERROR($$$GeneralError, rs.%Message)
	If 'rs.%Next() {
		Set pCanSend = 1
		Quit $$$OK
	}
	Set header = ##class(Ens.MessageHeader).%OpenId(rs.%Get("ID"))
	If '$IsObject(header) Quit $$$ERROR($$$GeneralError, "Delivery header unavailable; retry later")
	Set created = ##class(Ens.MessageHeader).StatusDisplayToLogical("Created")
	Set queued = ##class(Ens.MessageHeader).StatusDisplayToLogical("Queued")
	If header.Status = created {
		// Requeue the same persisted header instead of creating a new request.
		Set sc = ##class(Ens.Queue).EnQueue(header)
		If $$$ISERR(sc) Quit sc
	} ElseIf header.Status = queued {
		Quit $$$ERROR($$$GeneralError, "Pending native queue recovery; retry later")
	}
	Set pReceipt.HeaderId = header.%Id(), pReceipt.State = "accepted"
	Set pReceipt.ExpiresAt = ##class(WhatsApp.Util.Http).EpochNow() + ..DedupRetentionSeconds
	Quit pReceipt.%Save()
}

}
