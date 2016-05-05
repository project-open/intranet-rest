# /packages/intranet-rest/tcl/intranet-rest-procs.tcl
#
# Copyright (C) 2009 ]project-open[
#
# All rights reserved. Please check
# http://www.project-open.com/license/ for details.

ad_library {
    REST Web Service Component Library - Authentication
    @author frank.bergmann@project-open.com
}


ad_proc -private im_rest_cookie_auth_user_id {
    {-debug 1}
} {
    Determine the user_id even if ns_conn doesn't work
    in a HTTP PUT call
} {
    # Get the user_id from the ad_user_login cookie
    set header_vars [ns_conn headers]
    set cookie_string [ns_set get $header_vars Cookie]
    set cookie_list [split $cookie_string ";"]

    array set cookie_hash {}
    foreach l $cookie_list {
	if {[regexp {([^ =]+)\=(.+)} $l match key value]} {
	    set key [ns_urldecode [string trim $key]]
	    set value [ns_urldecode [string trim $value]]
	    ns_log Notice "im_rest_cookie_auth_user_id: key=$key, value=$value"
	    set cookie_hash($key) $value
	}
    }
    set rest_user_id ""

    if {[info exists cookie_hash(ad_session_id)]} { 

	set ad_session_id $cookie_hash(ad_session_id)
        ns_log Notice "im_rest_cookie_auth_user_id: ad_session_id=$ad_session_id"

	set rest_user_id ""
	catch { set rest_user_id [ad_conn user_id] }

	if {"" ne $rest_user_id && 0 != $rest_user_id} {
	    ns_log Notice "im_rest_cookie_auth_user_id: found authenthicated rest_user_id=$rest_user_id from ad_session_id cookie: storing into cache"
	    ns_cache set im_rest $ad_session_id $rest_user_id    
	    return $rest_user_id
	}
	
	if {[ns_cache get im_rest $ad_session_id value]} { 
	    ns_log Notice "im_rest_cookie_auth_user_id: Didn't find authenticated rest_user_id: returning cached value"
	    return $value 
	}
    }

    if {[info exists cookie_hash(ad_user_login)]} { 

	set ad_user_login $cookie_hash(ad_user_login)
        ns_log Notice "im_rest_cookie_auth_user_id: ad_user_login=$ad_user_login"

	set rest_user_id ""
	catch { set rest_user_id [ad_conn user_id] }
	if {"" ne $rest_user_id && 0 != $rest_user_id} {
	    ns_log Notice "im_rest_cookie_auth_user_id: found authenticated rest_user_id=$rest_user_id from ad_user_login cookie: storing into cache"
	    ns_cache set im_rest $ad_user_login $rest_user_id    
	    return $rest_user_id
	}
	
	if {[ns_cache get im_rest $ad_user_login value]} { 
	    ns_log Notice "im_rest_cookie_auth_user_id: Didn't find authenticated rest_user_id: returning cached value"
	    return $value 
	}
    }
    ns_log Notice "im_rest_cookie_auth_user_id: Didn't find any information, returning {}"
    return ""
}


ad_proc -private im_rest_authenticate {
    {-debug 1}
    {-format "json" }
    -query_hash_pairs:required
} {
    Determine the authenticated user
} {
    array set query_hash $query_hash_pairs
    set header_vars [ns_conn headers]

    # --------------------------------------------------------
    # Check for token authentication
    set token_user_id ""
    set token_token ""
    if {[info exists query_hash(user_id)]} { set token_user_id $query_hash(user_id)}
    if {[info exists query_hash(auth_token)]} { set token_token $query_hash(auth_token)}
    if {[info exists query_hash(auto_login)]} { set token_token $query_hash(auto_login)}

    # Check if the token fits the user
    if {"" != $token_user_id && "" != $token_token} {
	if {![im_valid_auto_login_p -user_id $token_user_id -auto_login $token_token -check_user_requires_manual_login_p 0]} {
	    set token_user_id ""
	}
    }

    # --------------------------------------------------------
    # Check for HTTP "basic" authorization
    # Example: Authorization=Basic cHJvam9wOi5mcmFiZXI=
    set basic_auth [ns_set get $header_vars "Authorization"]
    set basic_auth_userpass ""
    set basic_auth_username ""
    set basic_auth_password ""
    if {[regexp {^([a-zA-Z_]+)\ (.*)$} $basic_auth match method userpass_base64]} {
	set basic_auth_userpass [base64::decode $userpass_base64]
	regexp {^([^\:]+)\:(.*)$} $basic_auth_userpass match basic_auth_username basic_auth_password
	if {$debug} { ns_log Notice "im_rest_authenticate: basic_auth: basic_auth_username=$basic_auth_username, basic_auth_password=$basic_auth_password" }
    } else {
	ns_log Notice "im_rest_authenticate: basic_auth: basic_auth=$basic_auth does not match with regexp"
    }
    set basic_auth_user_id [db_string userid "select user_id from users where lower(username) = lower(:basic_auth_username)" -default ""]
    if {"" == $basic_auth_user_id} {
	set basic_auth_user_id [db_string userid "select party_id from parties where lower(email) = lower(:basic_auth_username)" -default ""]
    }
    set basic_auth_password_ok_p undefined
    if {"" != $basic_auth_user_id} {
	set basic_auth_password_ok_p [ad_check_password $basic_auth_user_id $basic_auth_password]
	if {!$basic_auth_password_ok_p} { set basic_auth_user_id "" }
    }
    if {$debug} { ns_log Notice "im_rest_authenticate: format=$format, basic_auth=$basic_auth, basic_auth_username=$basic_auth_username, basic_auth_password=$basic_auth_password, basic_auth_user_id=$basic_auth_user_id, basic_auth_password_ok_p=$basic_auth_password_ok_p" }


    # --------------------------------------------------------
    # Determine the user_id from cookie.
    # Work around missing ns_conn user_id values in PUT and DELETE calls 
    set cookie_auth_user_id [im_rest_cookie_auth_user_id]
    if {$debug} { ns_log Notice "im_rest_authenticate: cookie_auth_user_id=$cookie_auth_user_id" }

    # Determine authentication method used
    set auth_method ""
    if {"" != $cookie_auth_user_id && 0 != $cookie_auth_user_id } { set auth_method "cookie" }
    if {"" != $token_token} { set auth_method "token" }
    if {"" != $basic_auth_user_id} { set auth_method "basic" }

    # --------------------------------------------------------
    # Check if one of the methods was successful...
    switch $auth_method {
	cookie { set auth_user_id $cookie_auth_user_id }
	token { set auth_user_id $token_user_id }
	basic { set auth_user_id $basic_auth_user_id }
	default { 
	    return [im_rest_error -format $format -http_status 401 -message "No authentication found ('$auth_method')."] 
	}
    }

    ns_log Notice "im_rest_authenticate: format=$format, auth_method=$auth_method, auth_user_id=$auth_user_id"
    return [list user_id $auth_user_id method $auth_method]
}




