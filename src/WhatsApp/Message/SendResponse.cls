/// Result of an outbound WhatsApp send.
Class WhatsApp.Message.SendResponse Extends Ens.Response
{

Property Success As %Boolean [ InitialExpression = 0 ];

Property Provider As %String(MAXLEN = 20);

Property MessageId As %String(MAXLEN = 200);

Property HttpStatus As %Integer;

Property ErrorCode As %String(MAXLEN = 50);

Property ErrorMessage As %String(MAXLEN = 2000);

Property RawJSON As %String(MAXLEN = 100000);

Property Attempts As %Integer [ InitialExpression = 1 ];

Property LatencyMs As %Integer;

}