# /packages/intranet-rest/tcl/intranet-rest-procs.tcl
#
# Copyright (C) 2009 ]project-open[
#
# All rights reserved. Please check
# http://www.project-open.com/license/ for details.

ad_library {
    REST Web Service Component Library
    @author frank.bergmann@project-open.com
}

# -------------------------------------------------------
# REST Version
# -------------------------------------------------------

ad_proc -private im_rest_version {} {
    Returns the current server version of the REST interface.
    Please see www.project-open.org/en/rest_version_history
    <li>3.0	(2014-09-11):	Removed XML format, test based dev, rewrite of read/list
    <li>2.2	(2013-10-18):	Added "deref_p=1" parameter for dereferencing
    <li>2.1	(2012-03-18):	Added new report and now deprecating single object calls
    <li>2.0	(2011-05-12):	Added support for JSOn and Sencha format variants
				ToDo: Always return "id" instead of "object_id"
    <li>1.5.2	(2010-12-21):	Fixed bug of not applying where_query
    <li>1.5.1	(2010-12-01):	Fixed bug with generic objects, improved rendering of some fields
    <li>1.5	(2010-11-03):	Added rest_object_permissions and rest_group_memberships reports
    <li>1.4	(2010-06-11):	Added /intranet-rest/dynfield-widget-values
    <li>1.3	(2010-04-01):	First public version
} {
    return "3.0"
}

# -------------------------------------------------------
# HTTP Interface
#
# Deal HTTP parameters, authentication etc.
# -------------------------------------------------------

ad_proc -private im_rest_call_post {} {
    Handler for GET rest calls
} {
    return [im_rest_call_get -http_method POST]
}

ad_proc -private im_rest_call_put {} {
    Handler for PUT rest calls
} {
    set rest_user_id [im_rest_cookie_auth_user_id]
    ns_log Notice "im_rest_call_put: rest_user_id=$rest_user_id"
    return [im_rest_call_get -http_method PUT]
}

ad_proc -private im_rest_call_delete {} {
    Handler for DELETE rest calls
} {
    return [im_rest_call_get -http_method DELETE]
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
	catch { set rest_user_id [ad_get_user_id] }

	if {"" != $rest_user_id} {
	    ns_log Notice "im_rest_cookie_auth_user_id: found authenthicated rest_user_id: storing into cache"
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
	catch { set rest_user_id [ad_get_user_id] }
	if {"" != $rest_user_id} {
	    ns_log Notice "im_rest_cookie_auth_user_id: found authenticated rest_user_id: storing into cache"
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

    if {"" == $auth_user_id} { set auth_user_id 0 }
    ns_log Notice "im_rest_authenticate: format=$format, auth_method=$auth_method, auth_user_id=$auth_user_id"

    return [list user_id $auth_user_id method $auth_method]
}


ad_proc -private im_rest_call_get {
    {-http_method GET }
    {-format "json" }
} {
    Handler for GET rest calls
} {
    # Get the entire URL and decompose into the "rest_otype" 
    # and the "rest_oid" pieces. Splitting the URL on "/"
    # will result in "{} intranet-rest rest_otype rest_oid":
    set url [ns_conn url]
    set url_pieces [split $url "/"]
    set rest_otype [lindex $url_pieces 2]
    set rest_oid [lindex $url_pieces 3]

    # Get the information about the URL parameters, parse
    # them and store them into a hash array.
    set query [ns_conn query]
    set query_pieces [split $query "&"]
    array set query_hash {}
    foreach query_piece $query_pieces {
	if {[regexp {^([^=]+)=(.+)$} $query_piece match var val]} {
	    # ns_log Notice "im_rest_call_get: var='$var', val='$val'"

	    # Additional decoding: replace "+" by " "
	    regsub -all {\+} $var { } var
	    regsub -all {\+} $val { } val

	    set var [ns_urldecode $var]
	    set val [ns_urldecode $val]
	    ns_log Notice "im_rest_call_get: var='$var', val='$val'"
	    set query_hash($var) $val
	}
    }

    if {[info exists query_hash(format)]} { set format $query_hash(format) }

    # Determine the authenticated user_id. 0 means not authenticated.
    array set auth_hash [im_rest_authenticate -format $format -query_hash_pairs [array get query_hash]]
    if {0 == [llength [array get auth_hash]]} { return [im_rest_error -format $format -http_status 401 -message "Not authenticated"] }
    set auth_user_id $auth_hash(user_id)
    set auth_method $auth_hash(method)
    if {0 == $auth_user_id} { return [im_rest_error -format $format -http_status 401 -message "Not authenticated"] }

    # Default format are:
    # - "html" for cookie authentication
    # - "json" for basic authentication
    # - "json" for auth_token authentication
    switch $auth_method {
	basic { set format "json" }
	cookie { set format "html" }
	token { set format "json" }
	default { return [im_rest_error -format $format -http_status 401 -message "Invalid authentication method '$auth_method'."] }
    }
    # Overwrite default format with explicitely specified format in URL
    if {[info exists query_hash(format)]} { set format $query_hash(format) }
    set valid_formats {html json}
    if {[lsearch $valid_formats $format] < 0} { 
	return [im_rest_error -format $format -http_status 406 -message "Invalid output format '$format'. Valid formats include {html|json}."] 
    }

    # Security checks
    set alert_p 0
    set alert_p [expr $alert_p || [im_security_alert_check_integer -location "im_rest_call: user_id" -value $auth_user_id]]
    set alert_p [expr $alert_p || [im_security_alert_check_integer -location "im_rest_call: rest_oid" -value $rest_oid]]
    set alert_p [expr $alert_p || [im_security_alert_check_alphanum -location "im_rest_call: rest_otype" -value $rest_otype]]
    if {$alert_p} {
    	return [im_rest_error -format $format -http_status 500 -message "Internal error: Found a security error, please read your notifications"]
    }

    # Call the main request processing routine
    if {[catch {
	im_rest_call \
	    -method $http_method \
	    -format $format \
	    -rest_user_id $auth_user_id \
	    -rest_otype $rest_otype \
	    -rest_oid $rest_oid \
	    -query_hash_pairs [array get query_hash]

    } err_msg]} {
	append err_msg "\nStack Trace:\n"
	append err_msg $::errorInfo
	ns_log Notice "im_rest_call_get: im_rest_call returned an error: $err_msg"
	return [im_rest_error -format $format -http_status 500 -message "Internal error: [ns_quotehtml $err_msg]"]
    }
}


ad_proc -private im_rest_page {
    { -rest_otype "index" }
    { -format "json" }
    { -rest_user_id 0 }
    { -rest_oid "" }
    { -query_hash_pairs {} }
    { -debug 0 }
} {
    The user has requested /intranet-rest/ or /intranet-rest/index
} {
    ns_log Notice "im_rest_index_page: rest_otype=$rest_otype, query_hash=$query_hash_pairs"

    set params [list \
		    [list rest_otype $rest_otype] \
		    [list rest_oid $rest_oid] \
		    [list format $format] \
		    [list rest_user_id $rest_user_id] \
		    [list query_hash_pairs $query_hash_pairs] \
    ]

    set result [ad_parse_template -params $params "/packages/intranet-rest/www/$rest_otype"]
    switch $format {
	json { set mime_type "text/plain" }
	default { set mime_type "text/html" }
    }
    doc_return 200 $mime_type $result
    return
}


# -------------------------------------------------------
# REST Call Drivers
# -------------------------------------------------------

ad_proc -private im_rest_call {
    { -method GET }
    { -format "json" }
    { -rest_user_id 0 }
    { -rest_otype "" }
    { -rest_oid "" }
    { -query_hash_pairs {} }
    { -debug 0 }
} {
    Handler for all REST calls
} {
    ns_log Notice "im_rest_call: method=$method, format=$format, rest_user_id=$rest_user_id, rest_otype=$rest_otype, rest_oid=$rest_oid, query_hash=$query_hash_pairs"

    # -------------------------------------------------------
    # Special treatment for /intranet-rest/ and /intranet/rest/index URLs
    #
    if {"" == $rest_otype} { set rest_otype "index" }
    set pages {"" index version auto-login dynfield-widget-values }
    if {[lsearch $pages $rest_otype] >= 0} {
	return [im_rest_page \
		    -format $format \
		    -rest_user_id $rest_user_id \
		    -rest_otype $rest_otype \
		    -rest_oid $rest_oid \
		    -query_hash_pairs $query_hash_pairs \
		   ]
    }

    # -------------------------------------------------------
    # Check the "rest_otype" to be a valid object type
    set valid_rest_otypes [util_memoize [list db_list otypes "
	select	object_type 
	from	acs_object_types union
	select	'im_category'
    "]]
    if {[lsearch $valid_rest_otypes $rest_otype] < 0} { 
	return [im_rest_error -format $format -http_status 406 -message "Invalid object_type '$rest_otype'. Valid object types include {im_project|im_company|...}."] 
    }

    # -------------------------------------------------------
    switch $method  {
	GET {
	    # Handle both "read" and "list" operations using the same procedure
	    switch $rest_otype {
		im_category {
		    return [im_rest_get_im_categories \
				-format $format \
				-rest_user_id $rest_user_id \
				-rest_otype $rest_otype \
				-rest_oid $rest_oid \
				-query_hash_pairs $query_hash_pairs \
			       ]
		}
		im_dynfield_attribute {
		    return [im_rest_get_im_dynfield_attributes \
				-format $format \
				-rest_user_id $rest_user_id \
				-rest_otype $rest_otype \
				-rest_oid $rest_oid \
				-query_hash_pairs $query_hash_pairs \
			       ]
		}
		im_invoice_item {
		    return [im_rest_get_im_invoice_items \
				-format $format \
				-rest_user_id $rest_user_id \
				-rest_otype $rest_otype \
				-rest_oid $rest_oid \
				-query_hash_pairs $query_hash_pairs \
			       ]
		}
		im_hour {
		    return [im_rest_get_im_hours \
				-format $format \
				-rest_user_id $rest_user_id \
				-rest_otype $rest_otype \
				-rest_oid $rest_oid \
				-query_hash_pairs $query_hash_pairs \
			       ]
		}
		im_hour_interval {
		    return [im_rest_get_im_hour_intervals \
				-format $format \
				-rest_user_id $rest_user_id \
				-rest_otype $rest_otype \
				-rest_oid $rest_oid \
				-query_hash_pairs $query_hash_pairs \
			       ]
		}
		default {
		    # Return query from the object rest_otype
		    return [im_rest_get_object_type \
				-format $format \
				-rest_user_id $rest_user_id \
				-rest_otype $rest_otype \
				-rest_oid $rest_oid \
				-query_hash_pairs $query_hash_pairs \
			       ]
		    
		}
	    }
	}
	POST - PUT {
	    # Is the post operation performed on a particular object or on the object_type?
	    if {"" != $rest_oid} {
		# POST with object_id => Update operation on an object
		ns_log Notice "im_rest_call: Found a POST operation on object_type=$rest_otype with object_id=$rest_oid"
		im_rest_post_object \
		    -format $format \
		    -rest_user_id $rest_user_id \
		    -rest_otype $rest_otype \
		    -rest_oid $rest_oid \
		    -query_hash_pairs $query_hash_pairs
	    } else {
		# POST without object_id => Update operation on the "factory" object_type
		ns_log Notice "im_rest_call: Found a POST operation on object_type=$rest_otype"
		im_rest_post_object_type \
		    -format $format \
		    -rest_user_id $rest_user_id \
		    -rest_otype $rest_otype \
		    -query_hash_pairs $query_hash_pairs
	    }
	}
	DELETE {
	    # Is the post operation performed on a particular object or on the object_type?
	    if {"" != $rest_oid && 0 != $rest_oid} {

		# DELETE with object_id => delete operation
		ns_log Notice "im_rest_call: Found a DELETE operation on object_type=$rest_otype with object_id=$rest_oid"
		im_rest_delete_object \
		    -format $format \
		    -rest_user_id $rest_user_id \
		    -rest_otype $rest_otype \
		    -rest_oid $rest_oid \
		    -query_hash_pairs $query_hash_pairs

	    } else {
		# DELETE without object_id is not allowed - you can only destroy a known object
		ns_log Error "im_rest_call: You have to specify an object to DELETE."
		return [im_rest_error -format $format -http_status 500 -message "You have to specify an object to DELETE."]
	    }
	}
	default {
	    return [im_rest_error -format $format -http_status 400 -message "Unknown HTTP request '$method'. Valid requests include {GET|POST|PUT|DELETE}."]
	}
    }
}

