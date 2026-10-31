/// Persist delivery checkpoints and recover independent native queue commits through correlated headers.
Class WhatsApp.Data.DeliveryReceipt Extends %Persistent
{

Property ReceiptKey As %String(MAXLEN = 64) [ Required ];

Property ExpiresAt As %BigInt [ Required ];

Property State As %String(VALUELIST = ",pending,accepted") [ InitialExpression = "pending" ];

Property HeaderId As %BigInt;

/// Use a distinct correlation ID per retention cycle so expired retries cannot match an older header.
Property CorrelationId As %String(MAXLEN = 64);

Index Key On ReceiptKey [ IdKey, Unique ];

Index Expiry On ExpiresAt;

/// Hash a length-prefixed list to isolate provider, account, phone, event stage, and target unambiguously.
ClassMethod KeyFor(pMessage As WhatsApp.Message.Inbound, pTarget As %String) As %String
{
	Set identity = $ListBuild(pMessage.Provider, pMessage.AccountId, pMessage.PhoneNumberId, pMessage.MessageId, pMessage.IsStatus, $Select(pMessage.IsStatus:pMessage.Status, 1:""), $Select(pMessage.IsStatus:pMessage.ErrorCode, 1:""), pTarget)
	Quit ##class(WhatsApp.Util.Crypto).ToHex($System.Encryption.SHAHash(256, $ZConvert(identity, "O", "UTF8")))
}

/// Purge expired receipts in bounded batches using the delivery lock to avoid concurrent overwrites.
ClassMethod PurgeExpired(pLimit As %Integer = 100) As %Status
{
	Set now = ##class(WhatsApp.Util.Http).EpochNow()
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP "_+pLimit_" ReceiptKey FROM WhatsApp_Data.DeliveryReceipt WHERE State = 'accepted' AND ExpiresAt <= ?", now)
	If rs.%SQLCODE < 0 Quit $$$ERROR($$$GeneralError, rs.%Message)
	Set sc = $$$OK
	While rs.%Next() {
		Set key = rs.%Get("ReceiptKey")
		Lock +^WhatsAppDeliveryLock(key):0
		If '$Test Continue
		Try {
			Set receipt = ..%OpenId(key)
			If $IsObject(receipt) && (receipt.State = "accepted") && (receipt.ExpiresAt <= now) Set sc = $$$ADDSC(sc, ..%DeleteId(key))
		} Catch ex {
			Set sc = $$$ADDSC(sc, ex.AsStatus())
		}
		Lock -^WhatsAppDeliveryLock(key)
	}
	Quit sc
}

}
