#!/bin/zsh --no-rcs

readonly sqlQuery="SELECT r.ZFIRSTNAME, r.ZMIDDLENAME, r.ZLASTNAME, r.ZMAIDENNAME, r.ZSUFFIX, r.ZNICKNAME, r.ZJOBTITLE, r.ZORGANIZATION, r.ZSORTINGLASTNAME, r.ZUNIQUEID, JSON_GROUP_ARRAY(p.ZFULLNUMBER) AS ZPHONENUMBER, JSON_GROUP_ARRAY(e.ZADDRESSNORMALIZED) AS ZEMAILADDRESS, a.ZSTREET, n.ZTEXT
FROM ZABCDRECORD r
LEFT JOIN ZABCDPHONENUMBER p ON p.ZOWNER = r.Z_PK
LEFT JOIN ZABCDEMAILADDRESS e ON e.ZOWNER = r.Z_PK
LEFT JOIN ZABCDPOSTALADDRESS a ON a.ZOWNER = r.Z_PK
LEFT JOIN ZABCDNOTE n ON n.ZCONTACT = r.Z_PK
GROUP BY r.ZUNIQUEID;"

# Load Contacts
find "${contacts_dir}" -name "AddressBook-v22.abcddb" \
-exec echo '[{"ABpath": "{}", "data":' \; \
-exec sqlite3 -json {} "${sqlQuery}" \; \
-exec echo "}]" \; |
jq -cs \
   --argjson useJobTitle "${useJobTitle}" \
   --argjson useOrganization "${useOrganization}" \
   --argjson usePhone "${usePhone}" \
   --argjson useEmail "${useEmail}" \
   --argjson useStreet "${useStreet}" \
   --argjson useNotes "${useNotes}" \
   --argjson sortBy "${sortBy}" \
'def substrings:
    if . == null then empty else
        (explode) as $chars |
        [range(0; $chars|length) as $i | range($i + 1; ($chars|length) + 1) as $j | ($chars[$i:$j] | implode)] | join(" ")
    end;
{
    "items": (if (length > 0) then walk(if . == "" then null end) |
    map((.[].ABpath[:-23]) as $ABpath | .[].data[] | select(.ZUNIQUEID | endswith("ABPerson")) |
        (.ZPHONENUMBER | fromjson | join(" ") | gsub("(\\(|\\))"; "")) as $PHONES |
        (.ZEMAILADDRESS | fromjson | join(" ")) as $EMAILS |
        (if (.ZFIRSTNAME == null and .ZLASTNAME == null and .ZSUFFIX == null and .ZORGANIZATION != null) then false else true end) as $isNotORG |
        (if (.ZFIRSTNAME == null and .ZLASTNAME == null and .ZSUFFIX == null and .ZORGANIZATION == null) then "No Name" elif (.ZFIRSTNAME == null and .ZLASTNAME == null and .ZSUFFIX != null) then .ZSUFFIX elif $isNotORG then ([.ZFIRSTNAME, .ZLASTNAME] | map(select(.)) | join(" ")) else .ZORGANIZATION end) as $title |
    	{
	        "title": "\($title) \(.ZSUFFIX | if (. and . != $title) then "("+.+")" else "" end) \(.ZNICKNAME | if . then "["+.+"]" else "" end)",
            "subtitle": (if $isNotORG then ([.ZJOBTITLE, .ZORGANIZATION] | map(select(.)) | join(" • ")) else "" end),
            "arg": .ZUNIQUEID,
            "dedupe_key": (if (($EMAILS | length) > 0) then ("email:" + ($EMAILS | ascii_downcase)) elif (($PHONES | gsub("[^0-9]"; "") | length) > 0) then ("phone:" + ($PHONES | gsub("[^0-9]"; ""))) elif (.ZSUFFIX != null) then ("name:" + .ZSUFFIX + "|" + (.ZORGANIZATION // "") + "|" + (.ZJOBTITLE // "")) else ("name:" + $title + "|" + (.ZORGANIZATION // "") + "|" + (.ZJOBTITLE // "")) end),
            "icon": { "path": "images/VCard.png" },
            "match": [
                $title, .ZMIDDLENAME, .ZMAIDENNAME, .ZSUFFIX, (.ZSUFFIX | substrings), .ZNICKNAME,
                (if $useJobTitle == 1 then .ZJOBTITLE else empty end),
                (if $useOrganization == 1 then .ZORGANIZATION else empty end),
                (if $usePhone == 1 then ($PHONES | .+" "+gsub("[^0-9]"; "")) else empty end),
                (if $useEmail == 1 then $EMAILS else empty end),
                (if $useStreet == 1 then .ZSTREET else empty end),
                (if $useNotes == 1 then .ZTEXT else empty end)
            ] | map(select(.)) | join(" "),
            "variables": {"ABpath": $ABpath},
            "sortindex": (if $title != "No Name" then (if $sortBy == 0 then $title else .ZSORTINGLASTNAME end) else "~" end)
    	}
    ) | unique_by(.dedupe_key) | sort_by(.sortindex) | map(del(.dedupe_key, .sortindex)) else
        [{ "title": "Search Contacts...","subtitle": "No contacts found","valid": "false" }]
    end)
}'
