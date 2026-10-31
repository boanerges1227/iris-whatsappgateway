/// Inbound adapter that only accepts Twilio WhatsApp webhooks.
/// It reuses the self-hosted listener and HTTP parsing of WhatsApp.Adapter.Inbound,
/// but fixes the provider so a Twilio-only endpoint never accepts Meta traffic.
Class WhatsApp.Adapter.InboundTwilio Extends WhatsApp.Adapter.Inbound
{

Parameter SETTINGS = "Port:Basic,Path:Basic,TwilioAuthToken:Basic,TwilioAuthTokenCredential:Basic,PublicUrl:Basic,AllowedClientIPs:Basic,MaxBodyBytes:Basic,ListenTimeout:Basic,MaxRequestsPerTask:Basic,SSLConfig:Basic";

Method ResolveProvider(ByRef pHeaders) As %String
{
	Quit "twilio"
}

}