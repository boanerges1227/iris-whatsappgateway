/// Inbound adapter that only accepts Meta WhatsApp Cloud API webhooks.
/// It reuses the self-hosted listener and HTTP parsing of WhatsApp.Adapter.Inbound,
/// but fixes the provider so a Meta-only endpoint never accepts Twilio traffic.
Class WhatsApp.Adapter.InboundMeta Extends WhatsApp.Adapter.Inbound
{

Parameter SETTINGS = "Port:Basic,Path:Basic,VerifyToken:Basic,VerifyTokenCredential:Basic,AppSecret:Basic,AppSecretCredential:Basic,AllowedClientIPs:Basic,MaxBodyBytes:Basic,ListenTimeout:Basic,MaxRequestsPerTask:Basic,SSLConfig:Basic";

Method ResolveProvider(ByRef pHeaders) As %String
{
	Quit "meta"
}

}