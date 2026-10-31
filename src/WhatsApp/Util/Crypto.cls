/// Signature helpers for WhatsApp webhooks.
Class WhatsApp.Util.Crypto
{

/// HMAC-SHA256 of pData with pKey, returned as lowercase hex.
/// The raw request body must be passed byte-for-byte (no character translation).
ClassMethod HmacSha256Hex(pData As %String, pKey As %String) As %String
{
	Quit ..ToHex($SYSTEM.Encryption.HMACSHA(256, pData, pKey))
}

/// HMAC-SHA1 of pData with pKey, returned as base64 (Twilio signature format).
ClassMethod HmacSha1Base64(pData As %String, pKey As %String) As %String
{
	Quit $SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.HMACSHA1(pData, pKey))
}

/// Lowercase hexadecimal representation of a binary string.
ClassMethod ToHex(pBinary As %String) As %String
{
	Set tHex = ""
	For i = 1:1:$Length(pBinary) {
		Set tByteHex = $ZConvert($ZHex($Ascii(pBinary, i)), "L")
		If $Length(tByteHex) < 2 {
			Set tByteHex = "0" _ tByteHex
		}
		Set tHex = tHex _ tByteHex
	}
	Quit tHex
}

/// Constant-time-ish string comparison used for signatures.
ClassMethod SecureEquals(pLeft As %String, pRight As %String) As %Boolean
{
	If $Length(pLeft) '= $Length(pRight) {
		Quit 0
	}
	Set tDiff = 0
	For i = 1:1:$Length(pLeft) {
		Set tDiff = tDiff + ($Ascii(pLeft, i) '= $Ascii(pRight, i))
	}
	Quit tDiff = 0
}

/// Verify the Meta raw-byte signature and reject a missing secret or standard prefix.
ClassMethod VerifyMetaSignature(pRawBody As %String, pSignatureHeader As %String, pAppSecret As %String) As %Boolean
{
	If pAppSecret = "" {
		Quit 0
	}
	Set tHeader = $ZStrip(pSignatureHeader, "<>W")
	If $Extract($ZConvert(tHeader, "L"), 1, 7) = "sha256=" {
		Set tHeader = $Extract(tHeader, 8, *)
	} Else {
		Quit 0
	}
	If tHeader = "" {
		Quit 0
	}
	Quit ..SecureEquals($ZConvert(tHeader, "L"), ..HmacSha256Hex(pRawBody, pAppSecret))
}

/// Sort and concatenate fields using the Twilio algorithm, encoding both text and key as UTF-8.
ClassMethod TwilioSignature(pPublicUrl As %String, ByRef pFields, pAuthToken As %String) As %String
{
	Set tData = pPublicUrl
	Set tName = ""
	For {
		Set tName = $Order(pFields(tName))
		Quit:tName=""
		Set names("n"_tName) = tName
	}
	Set nameKey = ""
	For {
		Set nameKey = $Order(names(nameKey))
		Quit:nameKey=""
		Set tName = names(nameKey)
		If $Data(pFields(tName)) > 1 {
			// A nonnumeric prefix sorts 10 before 2, matching SDK string ordering.
			Set valueKey = ""
			For {
				Set valueKey = $Order(pFields(tName, valueKey))
				Quit:valueKey=""
				Set tData = tData _ tName _ pFields(tName, valueKey)
			}
		} Else {
			Set tData = tData _ tName _ $Get(pFields(tName))
		}
	}
	Quit ..HmacSha1Base64($ZConvert(tData, "O", "UTF8"), $ZConvert(pAuthToken, "O", "UTF8"))
}

/// Verify the Twilio signature; an empty secret must not disable authentication.
ClassMethod VerifyTwilioSignature(pPublicUrl As %String, ByRef pFields, pAuthToken As %String, pSignatureHeader As %String) As %Boolean
{
	If pAuthToken = "" {
		Quit 0
	}
	Quit ..SecureEquals($ZStrip(pSignatureHeader, "<>W"), ..TwilioSignature(pPublicUrl, .pFields, pAuthToken))
}

}
