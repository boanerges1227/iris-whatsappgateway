/// Business Operation that sends WhatsApp messages through Meta WhatsApp Cloud API.
Class WhatsApp.BO.SendMessageMeta Extends WhatsApp.BO.SendMessageBase
{

Parameter ADAPTER = "WhatsApp.Adapter.Outbound.Meta";

XData MessageMap
{
<MapItems>
  <MapItem MessageType="WhatsApp.Message.Outbound">
    <Method>Send</Method>
  </MapItem>
</MapItems>
}

}