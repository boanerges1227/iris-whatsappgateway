/// Single-port webhook Business Service with provider auto-detection
/// (adapter WhatsApp.Adapter.Inbound). Accepts both Meta and Twilio on one port.
/// For separate Meta/Twilio ports use WhatsApp.BS.WebhookMeta / WebhookTwilio.
Class WhatsApp.BS.WebhookService Extends WhatsApp.BS.WebhookBase
{

Parameter ADAPTER = "WhatsApp.Adapter.Inbound";

}