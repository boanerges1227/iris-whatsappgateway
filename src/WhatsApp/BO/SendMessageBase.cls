/// Shared Business Operation logic for the provider specific send operations.
Class WhatsApp.BO.SendMessageBase Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Method Send(pRequest As WhatsApp.Message.Outbound, Output pResponse As WhatsApp.Message.SendResponse) As %Status
{
	Set tSC = ..Adapter.Send(pRequest, .pResponse)
	If '$IsObject(pResponse) {
		Set pResponse = ##class(WhatsApp.Message.SendResponse).%New()
	}
	Do ##class(WhatsApp.Data.MessageLog).LogOutbound(pRequest, pResponse)
	If $$$ISERR(tSC) {
		Quit tSC
	}
	If 'pResponse.Success {
		Quit $$$ERROR($$$GeneralError, "WhatsApp send failed: "_pResponse.ErrorCode_" "_pResponse.ErrorMessage)
	}
	Quit $$$OK
}

}