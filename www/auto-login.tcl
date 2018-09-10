# /packages/intranet-rest/www/auto-login.tcl
#
# Copyright (C) 2009 ]project-open[
#

ad_page_contract {
    Home page for REST service, when accessing from the browser.
    The page shows a link to the documentation Wiki and a status
    of CRUD for every object type.
    
    @author frank.bergmann@project-open.com
} {
}

# Parameters passed aside of page_contract
# from intranet-rest-procs.tcl:
#
#    [list object_type $object_type] \
#    [list format $format] \
#    [list user_id $user_id] \
#    [list object_id $object_id] \
#    [list query_hash $query_hash] \

set current_user_id [auth::require_login]

if {![info exists user_id] || "" eq $user_id} { set user_id $current_user_id }
if {![info exists format]} { set format "html" }

set auto_login [im_generate_auto_login -user_id $user_id]

set username ""
set name ""
db_0or1row user_info "
	select	*,
		im_name_from_user_id(user_id) as name
	from	cc_users
	where	user_id = :user_id
"

switch $format {
    json {
	set result "{\"success\": true,
\"message\": \"Authenticated\",
\"user_id\": $user_id,
\"user_name\": \"[im_quotejson $name]\",
\"username\": \"[im_quotejson $username]\",
\"token\": \"[im_quotejson $auto_token]\",
}"
	doc_return 200 "application/json" $result
	ad_script_abort
    }
    xml {
	doc_return 200 "text/xml" "<?xml version='1.0' encoding='UTF-8'?>
	<auto_login>
		<user_id>$user_id</user_id>
		<user_name>$name</user_name>
		<username>$username</username>
		<token>$auto_login</token>
	</auto_login>
        "
	ad_script_abort
    }
    default {
	# just continue with the HTML stuff below,
	# returning the result as text/html
    }
}


