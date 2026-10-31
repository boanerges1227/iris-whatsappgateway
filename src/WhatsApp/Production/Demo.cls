/// Self-contained demo production: provider webhook -> EchoBot -> provider send.
/// The demo points the outbound adapter at the offline mock WhatsApp server.
Class WhatsApp.Production.Demo Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="WhatsApp.Production.Demo" LogGeneralTraceEvents="false">
  <Description>WhatsApp gateway demo (Meta Cloud API and Twilio, offline mock)</Description>
  <ActorPoolSize>6</ActorPoolSize>
  <Item Name="WebhookMeta" Category="" ClassName="WhatsApp.BS.WebhookMeta" PoolSize="1" Enabled="true" Foreground="false" Comment="Meta webhook listener (own port)" LogTraceEvents="false" Schedule="">
    <Setting Target="Host" Name="TargetConfigNames">EchoBot</Setting>
    <Setting Target="Adapter" Name="Port">8090</Setting>
    <Setting Target="Adapter" Name="Path">/webhook</Setting>
    <Setting Target="Adapter" Name="VerifyToken">demo-verify-token</Setting>
    <Setting Target="Adapter" Name="AppSecret">demo-app-secret</Setting>
    <Setting Target="Adapter" Name="MaxBodyBytes">1048576</Setting>
    <Setting Target="Adapter" Name="ListenTimeout">1</Setting>
    <Setting Target="Adapter" Name="MaxRequestsPerTask">20</Setting>
    <Setting Target="Adapter" Name="CallInterval">1</Setting>
  </Item>
  <Item Name="WebhookTwilio" Category="" ClassName="WhatsApp.BS.WebhookTwilio" PoolSize="1" Enabled="true" Foreground="false" Comment="Twilio webhook listener (own port)" LogTraceEvents="false" Schedule="">
    <Setting Target="Host" Name="TargetConfigNames">EchoBot</Setting>
    <Setting Target="Adapter" Name="Port">8091</Setting>
    <Setting Target="Adapter" Name="Path">/webhook</Setting>
    <Setting Target="Adapter" Name="TwilioAuthToken">demo-twilio-token</Setting>
    <Setting Target="Adapter" Name="MaxBodyBytes">1048576</Setting>
    <Setting Target="Adapter" Name="ListenTimeout">1</Setting>
    <Setting Target="Adapter" Name="MaxRequestsPerTask">20</Setting>
    <Setting Target="Adapter" Name="CallInterval">1</Setting>
  </Item>
  <Item Name="EchoBot" Category="" ClassName="WhatsApp.BP.EchoBot" PoolSize="1" Enabled="true" Foreground="false" Comment="Demo bot: commands, media, templates, echo" LogTraceEvents="false" Schedule="">
	<Setting Target="Host" Name="TwilioDemoContentSid">HX0123456789abcdef0123456789abcdef</Setting>
    <Setting Target="Host" Name="TargetOperationMeta">SendMessageMeta</Setting>
    <Setting Target="Host" Name="TargetOperationTwilio">SendMessageTwilio</Setting>
  </Item>
  <Item Name="SendMessageMeta" Category="" ClassName="WhatsApp.BO.SendMessageMeta" PoolSize="1" Enabled="true" Foreground="false" Comment="Outbound WhatsApp Business Operation (Meta Cloud API)" LogTraceEvents="false" Schedule="">
    <Setting Target="Adapter" Name="ApiBaseUrl">http://mock:8099</Setting>
    <Setting Target="Adapter" Name="ApiVersion">v21.0</Setting>
    <Setting Target="Adapter" Name="PhoneNumberId">1234567890</Setting>
    <Setting Target="Adapter" Name="AccessToken">mock-token</Setting>
    <Setting Target="Adapter" Name="Timeout">10</Setting>
    <Setting Target="Adapter" Name="MaxRetries">2</Setting>
  </Item>
  <Item Name="SendMessageTwilio" Category="" ClassName="WhatsApp.BO.SendMessageTwilio" PoolSize="1" Enabled="true" Foreground="false" Comment="Outbound WhatsApp Business Operation (Twilio)" LogTraceEvents="false" Schedule="">
    <Setting Target="Adapter" Name="ApiBaseUrl">http://mock:8099</Setting>
    <Setting Target="Adapter" Name="AccountSid">ACdemo</Setting>
    <Setting Target="Adapter" Name="SenderAddress">whatsapp:+15550001111</Setting>
    <Setting Target="Adapter" Name="TwilioAuthToken">demo-twilio-token</Setting>
    <Setting Target="Adapter" Name="Timeout">10</Setting>
    <Setting Target="Adapter" Name="MaxRetries">2</Setting>
  </Item>
</Production>
}

}
