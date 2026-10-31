/// Resolve secrets from Interoperability Credentials, falling back to literal settings.
Class WhatsApp.Util.Credentials
{

/// Resolve an explicit credential exclusively; return empty on failure instead of bypassing configuration.
ClassMethod Get(pCredentialID As %String, pLiteral As %String) As %String
{
	If pCredentialID '= "" {
		Try {
			If '##class(Ens.Config.Credentials).%ExistsId($ZConvert(pCredentialID, "L")) {
				Return ""
			}
			Return ##class(Ens.Config.Credentials).GetValue(pCredentialID, "Password")
		} Catch ex {
			Return ""
		}
	}
	Quit pLiteral
}

}
