/// Business Operation that sends WhatsApp messages through Twilio.
Class WhatsApp.BO.SendMessageTwilio Extends WhatsApp.BO.SendMessageBase
{

Parameter ADAPTER = "WhatsApp.Adapter.Outbound.Twilio";

XData MessageMap
{
<MapItems>
  <MapItem MessageType="WhatsApp.Message.Outbound">
    <Method>Send</Method>
  </MapItem>
</MapItems>
}

}