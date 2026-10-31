/// Provider-neutral outbound WhatsApp message.
Class WhatsApp.Message.Outbound Extends Ens.Request
{

/// Optional provider override: meta, twilio or mock (defaults to the operation setting)
Property Provider As %String(MAXLEN = 20);

/// Recipient phone number, with or without the whatsapp: prefix
Property To As %String(MAXLEN = 30);

/// text, template, media, location, interactive or reaction
Property Type As %String(MAXLEN = 20) [ InitialExpression = "text" ];

/// Free-form text body (also used as the interactive body / media caption fallback)
Property Text As %String(MAXLEN = 4000);

/// Ask Meta to render link previews for text messages
Property PreviewURL As %Boolean [ InitialExpression = 0 ];

/// Media kind for Type=media: image, audio, video, document, sticker
Property MediaKind As %String(MAXLEN = 20) [ InitialExpression = "image" ];

/// Provider media id (Meta)
Property MediaId As %String(MAXLEN = 300);

/// Public media URL (Meta and Twilio)
Property MediaLink As %String(MAXLEN = 1000);

Property MediaCaption As %String(MAXLEN = 1000);

Property MediaFilename As %String(MAXLEN = 300);

/// Template name, for Type=template
Property TemplateName As %String(MAXLEN = 200);

Property LanguageCode As %String(MAXLEN = 20) [ InitialExpression = "en_US" ];

/// Positional body parameters for the template
Property BodyParameters As %ListOfDataTypes;

/// Approved Twilio Content template SID, configured separately from Meta TemplateName.
Property ContentSid As %String(MAXLEN = 34);

/// JSON object string for Twilio template variables, for example {"1":"Alice"}.
Property ContentVariables As %String(MAXLEN = 10000);

/// Public status callback URL for this Twilio message; empty uses the outbound adapter default.
Property StatusCallbackURL As %String(MAXLEN = 2000);

/// Interactive buttons, one "id|title" per entry (max 3)
Property Buttons As %ListOfDataTypes;

/// Label of the button that opens a list message
Property ListButtonText As %String(MAXLEN = 60) [ InitialExpression = "Choose" ];

/// Title of the single list section
Property ListSectionTitle As %String(MAXLEN = 60);

/// List rows, one "id|title|description" per entry (max 10)
Property ListRows As %ListOfDataTypes;

Property Latitude As %String(MAXLEN = 30);

Property Longitude As %String(MAXLEN = 30);

Property LocationName As %String(MAXLEN = 300);

Property LocationAddress As %String(MAXLEN = 500);

/// Message id being reacted to (Type=reaction)
Property ReactionMessageId As %String(MAXLEN = 200);

Property ReactionEmoji As %String(MAXLEN = 20);

/// Set the reply context on the outgoing message
Property ReplyToMessageId As %String(MAXLEN = 200);

Method %OnNew(pTo As %String = "", pText As %String = "") As %Status
{
	Set ..To = pTo
	Set ..Text = pText
	Quit $$$OK
}

}
