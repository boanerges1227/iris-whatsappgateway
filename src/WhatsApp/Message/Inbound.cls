/// Provider-neutral representation of a WhatsApp message or delivery status
/// received from Meta WhatsApp Cloud API or Twilio.
Class WhatsApp.Message.Inbound Extends Ens.Request
{

/// Provider that delivered the event: meta or twilio
Property Provider As %String(MAXLEN = 20);

/// Provider account id (WhatsApp Business Account id / Twilio Account SID)
Property AccountId As %String(MAXLEN = 100);

/// Business phone number id (Meta) or Twilio sender, as seen by the provider
Property PhoneNumberId As %String(MAXLEN = 100);

/// Provider message id (wamid... / SM...)
Property MessageId As %String(MAXLEN = 200);

/// Sender address without the whatsapp: prefix
Property From As %String(MAXLEN = 30);

/// Sender display name when the provider exposes it
Property FromName As %String(MAXLEN = 200);

/// Recipient business address without the whatsapp: prefix
Property To As %String(MAXLEN = 30);

/// Normalized message type: text, image, audio, video, document, sticker,
/// location, contacts, button, interactive, reaction, status, unknown
Property Type As %String(MAXLEN = 20);

/// Text body (text messages, captions, button titles)
Property Text As %String(MAXLEN = 4000);

/// Provider media id, when the media is hosted by the provider
Property MediaId As %String(MAXLEN = 300);

/// Public media URL (Twilio exposes one directly)
Property MediaUrl As %String(MAXLEN = 1000);

Property MediaMimeType As %String(MAXLEN = 100);

Property MediaFilename As %String(MAXLEN = 300);

Property MediaCaption As %String(MAXLEN = 1000);

Property MediaSHA256 As %String(MAXLEN = 100);

Property Latitude As %String(MAXLEN = 30);

Property Longitude As %String(MAXLEN = 30);

Property LocationName As %String(MAXLEN = 300);

Property LocationAddress As %String(MAXLEN = 500);

/// Identifier of the clicked button / list row
Property InteractiveId As %String(MAXLEN = 200);

/// Delivery status for receipt events: sent, delivered, read, failed, ...
Property Status As %String(MAXLEN = 30);

Property ErrorCode As %String(MAXLEN = 50);

Property ErrorTitle As %String(MAXLEN = 500);

/// Stable conversation key (provider + remote participant)
Property ConversationId As %String(MAXLEN = 220);

/// Epoch seconds reported by the provider
Property Timestamp As %String(MAXLEN = 30);

/// Human readable UTC timestamp (YYYY-MM-DD HH:MM:SS)
Property TimestampISO As %String(MAXLEN = 30);

/// True when this request is a delivery status receipt rather than a user message
Property IsStatus As %Boolean [ InitialExpression = 0 ];

/// Original provider payload, kept for audit and troubleshooting
Property RawJSON As %String(MAXLEN = 1000000);

/// Returns a readable one-line representation of the message
Method DisplayText() As %String
{
	If ..IsStatus {
		Quit "[status "_..Status_"]"
	}
	If ..Text '= "" {
		Quit ..Text
	}
	If ..Type = "location" {
		Quit "[location "_..Latitude_","_..Longitude_"]"
	}
	If ..Type = "interactive" || ..Type = "button" {
		Quit "["_..Type_": "_..InteractiveId_"]"
	}
	Quit "["_..Type_"]"
}

}