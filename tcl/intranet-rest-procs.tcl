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
    Please see www.project-open.com/en/rest-version-history
    <li>3.0	(2014-09-11):	Removed XML support, changed single object GET,
    				test based dev, rewrite of read/list
    <li>2.2	(2013-10-18):	Added "deref_p=1" parameter for dereferencing
    <li>2.1	(2012-03-18):	Added new report and now deprecating single object calls
    <li>2.0	(2011-05-12):	Added support for JSOn and Sencha format variants
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
    # set rest_user_id [im_rest_cookie_auth_user_id]
    # ns_log Notice "im_rest_call_put: rest_user_id=$rest_user_id"
    return [im_rest_call_get -http_method PUT]
}

ad_proc -private im_rest_call_delete {} {
    Handler for DELETE rest calls
} {
    return [im_rest_call_get -http_method DELETE]
}


ad_proc -private im_rest_call_get {
    {-http_method GET }
    {-format "json" }
} {
    Handler for GET rest calls
} {
    ns_log Notice "im_rest_call_get: Starting"

    # Get the entire URL and decompose into the "rest_otype" 
    # and the "rest_oid" pieces. Splitting the URL on "/"
    # will result in "{} intranet-rest rest_otype rest_oid":
    set url [ns_conn url]
    set url_pieces [split $url "/"]
    set rest_otype [lindex $url_pieces 2]
    set rest_oid [lindex $url_pieces 3]
    ns_log Notice "im_rest_call_get: oid=$rest_oid, otype=$rest_otype"

    # Get the information about the URL parameters, parse
    # them and store them into a hash array.
    set query [ns_conn query]
    set query_pieces [split $query "&"]
    array set query_hash {}
    foreach query_piece $query_pieces {
	if {[regexp {^([^=]+)=(.+)$} $query_piece match var val]} {
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
    ns_log Notice "im_rest_call_get: before im_rest_authenticate:  format=$format, query_hash_pairs=[array get query_hash]"
    set auth_hash_list [im_rest_authenticate -format $format -query_hash_pairs [array get query_hash]]
    ns_log Notice "im_rest_call_get: after im_rest_authenticate: auth_hash=$auth_hash_list"
    array set auth_hash $auth_hash_list

    if {0 == [llength [array get auth_hash]]} { return [im_rest_error -format $format -http_status 401 -message "Not authenticated"] }
    set auth_user_id $auth_hash(user_id)
    set auth_method $auth_hash(method)
    ns_log Notice "im_rest_call_get: method=$http_method, format=$format, user_id=$auth_user_id, query_hash=[array get query_hash]"

    if {"" == $auth_user_id} { return [im_rest_error -format $format -http_status 401 -message "Not authenticated"] }

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
    set alert_p [expr {$alert_p || [im_security_alert_check_integer -location "im_rest_call: user_id" -value $auth_user_id]}]
    if {"data-source" != $rest_otype} {
	set alert_p [expr {$alert_p || [im_security_alert_check_integer -location "im_rest_call: rest_oid" -value $rest_oid]}]
	set alert_p [expr {$alert_p || [im_security_alert_check_alphanum -location "im_rest_call: rest_otype" -value $rest_otype]}]
    }
    if {$alert_p} {
    	return [im_rest_error -format $format -http_status 500 -message "Internal error: Found a security error, please check your security notifications"]
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
	return [im_rest_error -format $format -http_status 500 -message "Internal error: $err_msg"]
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
    The user has requested /intranet-rest/index or /intranet-rest/data-source/*
} {
    ns_log Notice "im_rest_page: rest_otype=$rest_otype, rest_oid=$rest_oid, query_hash=$query_hash_pairs"

    set params [list \
		    [list rest_otype $rest_otype] \
		    [list rest_oid $rest_oid] \
		    [list format $format] \
		    [list rest_user_id $rest_user_id] \
		    [list query_hash_pairs $query_hash_pairs] \
    ]

    set file "/packages/intranet-rest/www/$rest_otype"
    if {"data-source" == $rest_otype} {
	append file "/$rest_oid"
    }

    set result [ad_parse_template -params $params $file]
    # set result "{success:false, message: 'ad_parse_template -params $params $file'}"
    
    switch $format {
	json { set mime_type "application/json" }
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

    set pages {"" index version auto-login dynfield-widget-values "data-source" }
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
	from	acs_object_types 
		union
			select	'im_category'
		union 
			select  'im_indicator_result'
    "]]
    if {[lsearch $valid_rest_otypes $rest_otype] < 0} { 
	return [im_rest_error -format $format -http_status 406 -message "Invalid object_type '$rest_otype'. Valid object types include {im_project|im_company|...}."] 
    }

    # -------------------------------------------------------
    switch $method  {
	GET {
	    # Handle both "read" and "list" operations using the same procedure
	    switch $rest_otype {
                im_indicator_result {
                    return [im_rest_get_im_indicator_result_interval \
                                -format $format \
                                -rest_user_id $rest_user_id \
                                -rest_otype $rest_otype \
                                -rest_oid $rest_oid \
                                -query_hash_pairs $query_hash_pairs \
			    ]
                }
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
		im_invoice_item {
		    return [im_rest_get_im_invoice_items \
				-format $format \
				-rest_user_id $rest_user_id \
				-rest_otype $rest_otype \
				-rest_oid $rest_oid \
				-query_hash_pairs $query_hash_pairs \
			       ]
		}
		im_timesheet_task_dependency {
		    return [im_rest_get_im_timesheet_task_dependencies \
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

