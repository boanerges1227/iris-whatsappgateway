/// Small HTTP / encoding helpers shared by the adapters.
Class WhatsApp.Util.Http
{

/// $HOROLOG day number for 1970-01-01 (the Unix epoch)
Parameter UnixEpochDay = 47117;

/// Decode a percent-encoded value ("+" is treated as space).
ClassMethod UrlDecode(pValue As %String) As %String
{
	Set tValue = $Replace(pValue, "+", " ")
	Set tOut = ""
	Set tLen = $Length(tValue)
	Set i = 1
	While i <= tLen {
		Set tChar = $Extract(tValue, i)
		If (tChar = "%") && ((i + 2) <= tLen) {
			Set tOut = tOut _ $Char(..HexByte($Extract(tValue, i + 1, i + 2)))
			Set i = i + 3
		} Else {
			Set tOut = tOut _ tChar
			Set i = i + 1
		}
	}
	Quit $ZConvert(tOut, "I", "UTF8")
}

/// Percent-encode a UTF-8 string.
ClassMethod UrlEncode(pValue As %String) As %String
{
	Set tBytes = $ZConvert(pValue, "O", "UTF8")
	Set tOut = ""
	For i = 1:1:$Length(tBytes) {
		Set tCode = $Ascii(tBytes, i)
		Set tChar = $Char(tCode)
		If ((tCode >= 48) && (tCode <= 57)) || ((tCode >= 65) && (tCode <= 90)) || ((tCode >= 97) && (tCode <= 122)) || (tChar = "-") || (tChar = "_") || (tChar = ".") || (tChar = "~") {
			Set tOut = tOut _ tChar
		} Else {
			Set tHex = $ZConvert($ZHex(tCode), "U")
			If $Length(tHex) < 2 {
				Set tHex = "0" _ tHex
			}
			Set tOut = tOut _ "%" _ tHex
		}
	}
	Quit tOut
}

/// Convert a hexadecimal number to a decimal integer.
ClassMethod HexToDecimal(pHex As %String) As %Integer
{
	Set tValue = 0
	Set tHex = $ZConvert($ZStrip(pHex, "<>W"), "U")
	For i = 1:1:$Length(tHex) {
		Set tDigit = $Find("0123456789ABCDEF", $Extract(tHex, i)) - 2
		If tDigit < 0 {
			Quit
		}
		Set tValue = (tValue * 16) + tDigit
	}
	Quit tValue
}
ClassMethod HexByte(pHex As %String) As %Integer
{
	Set tDigits = "0123456789ABCDEF"
	Set tHigh = $Find(tDigits, $ZConvert($Extract(pHex, 1), "U")) - 2
	Set tLow = $Find(tDigits, $ZConvert($Extract(pHex, 2), "U")) - 2
	If (tHigh < 0) || (tLow < 0) {
		Quit 0
	}
	Quit (tHigh * 16) + tLow
}

/// Decode forms and retain distinct repeated values; keep the final scalar for message parsing.
ClassMethod ParseUrlEncoded(pBody As %String, Output pFields) As %Status
{
	Set pFields = ""
	If pBody = "" {
		Quit $$$OK
	}
	For i = 1:1:$Length(pBody, "&") {
		Set tPair = $Piece(pBody, "&", i)
		If tPair = "" Continue
		Set tKey = ..UrlDecode($Piece(tPair, "=", 1))
		Set tValue = ..UrlDecode($Piece(tPair, "=", 2, *))
		If $Data(pFields(tKey))#2 Set pFields(tKey, "v"_pFields(tKey)) = pFields(tKey)
		Set pFields(tKey) = tValue
		Set pFields(tKey, "v"_tValue) = tValue
	}
	Quit $$$OK
}

/// Parse a raw query string into pFields.
ClassMethod ParseQueryString(pQuery As %String, Output pFields) As %Status
{
	Quit ..ParseUrlEncoded(pQuery, .pFields)
}

/// Split an HTTP request target into path and query.
ClassMethod SplitTarget(pTarget As %String, Output pPath As %String, Output pQuery As %String) As %Status
{
	Set tQuestion = $Find(pTarget, "?")
	If tQuestion = 0 {
		Set pPath = pTarget
		Set pQuery = ""
	} Else {
		Set pPath = $Extract(pTarget, 1, tQuestion - 2)
		Set pQuery = $Extract(pTarget, tQuestion, *)
	}
	Quit $$$OK
}

/// Normalize a WhatsApp address: strip the whatsapp: prefix and formatting characters.
ClassMethod NormalizePhone(pValue As %String) As %String
{
	Set tValue = $ZStrip(pValue, "<>W")
	If $Extract($ZConvert(tValue, "L"), 1, 9) = "whatsapp:" {
		Set tValue = $Extract(tValue, 10, *)
	}
	Set tValue = $Translate(tValue, " -()")
	If $Extract(tValue, 1) = "+" {
		Set tValue = $Extract(tValue, 2, *)
	}
	Quit tValue
}

/// Build a conversation key from a provider and a remote participant.
ClassMethod ConversationId(pProvider As %String, pRemote As %String) As %String
{
	Quit $ZConvert(pProvider, "L") _ ":" _ ..NormalizePhone(pRemote)
}

/// Convert epoch seconds into a readable UTC timestamp.
ClassMethod IsoFromEpoch(pEpoch As %String) As %String
{
	If pEpoch = "" {
		Quit ""
	}
	Set tEpoch = +pEpoch
	Set tDays = ..#UnixEpochDay + (tEpoch \ 86400)
	Set tSeconds = tEpoch # 86400
	Quit $ZDATETIME(tDays _ "," _ tSeconds, 3, 1)
}

/// Current time as Unix epoch seconds.
ClassMethod EpochNow() As %Integer
{
	Set tDays = +$Piece($ZTIMESTAMP, ",", 1)
	Set tSeconds = +$Piece($ZTIMESTAMP, ",", 2)
	Quit ((tDays - ..#UnixEpochDay) * 86400) + (tSeconds \ 1)
}

/// Combine UTC days and seconds with fractional precision instead of truncating time with unary plus.
ClassMethod TimestampSeconds(pStamp As %String = "") As %Numeric
{
	If pStamp = "" Set pStamp = $ZTIMESTAMP
	Quit (+$Piece(pStamp, ",", 1) * 86400) + (+$Piece(pStamp, ",", 2))
}

/// Compute day and second differences separately before converting to milliseconds to preserve precision.
ClassMethod ElapsedMs(pStart As %String, pEnd As %String = "") As %Integer
{
	If pEnd = "" Set pEnd = $ZTIMESTAMP
	Set seconds = ((+$Piece(pEnd, ",", 1) - (+$Piece(pStart, ",", 1))) * 86400) + (+$Piece(pEnd, ",", 2) - (+$Piece(pStart, ",", 2)))
	Quit $Justify($Select(seconds < 0:0, 1:seconds * 1000), 0, 0)
}

/// HTTP reason phrase for common webhook response codes.
ClassMethod Reason(pStatus As %Integer) As %String
{
	Set tMap(200) = "OK"
	Set tMap(202) = "Accepted"
	Set tMap(204) = "No Content"
	Set tMap(400) = "Bad Request"
	Set tMap(401) = "Unauthorized"
	Set tMap(403) = "Forbidden"
	Set tMap(404) = "Not Found"
	Set tMap(405) = "Method Not Allowed"
	Set tMap(413) = "Payload Too Large"
	Set tMap(415) = "Unsupported Media Type"
	Set tMap(500) = "Internal Server Error"
	Set tMap(503) = "Service Unavailable"
	Quit $Get(tMap(pStatus), "OK")
}

}
