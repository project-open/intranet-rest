# /packages/intranet-rest/tcl/intranet-rest-post-procs.tcl
#
# Copyright (C) 2009 ]project-open[
#
# All rights reserved. Please check
# http://www.project-open.com/license/ for details.

ad_library {
    REST Web Service Component Library
    @author frank.bergmann@project-open.com
}


# --------------------------------------------------------
# POST on the object type - CREATE
# --------------------------------------------------------

ad_proc -private im_rest_post_object_type {
    { -format "json" }
    { -rest_user_id 0 }
    { -rest_otype "" }
    { -rest_oid "" }
    { -query_hash_pairs {} }
    { -debug 0 }
} {
    Handler for POST rest calls to an object type - create a new object.
} {
    ns_log Notice "im_rest_post_object_type: format=$format, rest_user_id=$rest_user_id, rest_otype=$rest_otype, rest_oid=$rest_oid, query_hash=$query_hash_pairs"

    set base_url "[im_rest_system_url]/intranet-rest"

    set rest_otype_id [util_memoize [list db_string otype_id "select object_type_id from im_rest_object_types where object_type = '$rest_otype'" -default 0]]
    set rest_otype_write_all_p [im_object_permission -object_id $rest_otype_id -user_id $rest_user_id -privilege "create"]

    # Get the content of the HTTP POST request
    set content [im_rest_get_content]
    ns_log Notice "im_rest_post_object_type: content='$content'"

    # Switch to object specific procedures for handling new object creation
    # Check if the procedure exists.
    ns_log Notice "im_rest_post_object_type: $rest_otype: [llength [info commands im_rest_post_object_type_$rest_otype]]"
    if {0 != [llength [info commands im_rest_post_object_type_$rest_otype]]} {
	
	ns_log Notice "im_rest_post_object_type: Before calling im_rest_post_object_type_$rest_otype"
	array set hash_array [eval [list im_rest_post_object_type_$rest_otype \
		  -format $format \
		  -rest_user_id $rest_user_id \
		  -content $content \
		  -rest_otype $rest_otype \
	]]

	# Extract the object's id from the return array and write into object_id in case a client needs the info
	if {![info exists hash_array(rest_oid)]} {
	    # Probably after an im_rest_error
	    ns_log Error "im_rest_post_object_type: Didn't find hash_array(rest_oid): This should never happened"
	}
	set rest_oid $hash_array(rest_oid)
	set hash_array(object_id) $rest_oid
	ns_log Notice "im_rest_post_object_type: After calling im_rest_post_object_type_$rest_otype: rest_oid=$rest_oid, hash_array=[array get hash_array]"

	switch $format {
	    html { 
		set page_title "object_type: $rest_otype"
		doc_return 200 "text/html" "
		[im_header $page_title [im_rest_header_extra_stuff]][im_navbar]<table>
		<tr class=rowtitle><td class=rowtitle>Object ID</td></tr>
		<tr<td>$rest_oid</td></tr>
		</table>[im_footer]
		"
	    }
	    json {
		# Return a JSON structure with all fields of the object.
		set data_list [list]
		foreach key [array names hash_array] {
		    set value $hash_array($key)
		    lappend data_list "\"$key\": \"[im_quotejson $value]\""
		}
		
		set data "\[{[join $data_list ", "]}\]"
		set result "{\"success\": \"true\",\"message\": \"Object created\",\"data\": $data}"
		doc_return 200 "application/json" $result
	    }
	    default {
		ad_return_complaint 1 "Invalid format6: '$format'"
	    }
	}

    } else {
	ns_log Notice "im_rest_post_object_type: Create for '$rest_otype' not implemented yet"
	im_rest_error -format $format -http_status 404 -message "Object creation for object type '$rest_otype' not implemented yet."
	return
    }
    return
}



# --------------------------------------------------------
# DELETE
# --------------------------------------------------------

ad_proc -private im_rest_post_object {
    { -format "json" }
    { -rest_user_id 0 }
    { -rest_otype "" }
    { -rest_oid "" }
    { -query_hash_pairs {} }
    { -debug 0 }
} {
    Handler for POST rest calls to an individual object:
    Update the specific object using a generic update procedure
} {
    ns_log Notice "im_rest_post_object: rest_otype=$rest_otype, rest_oid=$rest_oid, rest_user_id=$rest_user_id, format='$format', query_hash=$query_hash_pairs"

    # Get the content of the HTTP POST request
    set content [im_rest_get_content]
    ns_log Notice "im_rest_post_object: content='$content'"

    # Check the REST level permissions on the object type
    set rest_otype_id [util_memoize [list db_string otype_id "select object_type_id from im_rest_object_types where object_type = '$rest_otype'" -default 0]]
    set write_p [im_object_permission -object_id $rest_otype_id -user_id $rest_user_id -privilege "write"]
    if {!$write_p} {
	set msg "im_rest_post_object: User #$rest_user_id has no 'write' permission in general on object type '$rest_otype' - please check your REST permissions"
	im_rest_error -format $format -http_status 403 -message $msg
	return
    }

    # Check if there is an object type specific permission checker
    set write_p 0
    if {0 != [llength [info commands ${rest_otype}_permissions]]} {
	ns_log Notice "im_rest_post_object: found permission proc ${rest_otype}_permissions - evaluating permissions"
	catch {
	    eval "${rest_otype}_permissions $rest_user_id $rest_oid view_p read_p write_p admin_p"
	}
    } else {
	ns_log Notice "im_rest_post_object: Did not find permission proc ${rest_otype}_permissions - POST permissions denied"
    }
    if {!$write_p} {
	im_rest_error -format $format -http_status 403 -message "User #$rest_user_id has no write permission on object #$rest_oid"
	return
    }

    # Check if there is a customized version of this post handler
    if {0 != [llength [info commands im_rest_post_object_$rest_otype]]} {
	
	ns_log Notice "im_rest_post_object: found a customized POST handler for rest_otype=$rest_otype, rest_oid=$rest_oid, query_hash=$query_hash_pairs"
	set rest_oid [eval [list im_rest_post_object_$rest_otype \
		  -format $format \
		  -rest_user_id $rest_user_id \
		  -rest_otype $rest_otype \
		  -rest_oid $rest_oid \
		  -query_hash_pairs $query_hash_pairs \
		  -debug $debug \
		  -content $content \
	]]
    }

    # Parse the HTTP content
    # Extract a key-value list of variables from JSON POST request
    array set hash_array [im_rest_parse_json_content -rest_otype $rest_otype -format $format -content $content]

    # Audit + Callback before updating the object
    im_audit -user_id $rest_user_id -object_type $rest_otype -object_id $rest_oid -action before_update

    # Update the object. This routine will return a HTTP error in case 
    # of a database constraint violation
    ns_log Notice "im_rest_post_object: Before im_rest_object_type_update_sql"
    im_rest_object_type_update_sql \
	-format $format \
	-rest_otype $rest_otype \
	-rest_oid $rest_oid \
	-hash_array [array get hash_array]
    ns_log Notice "im_rest_post_object: After im_rest_object_type_update_sql"

    # Audit + Callback after updating the object
    im_audit -user_id $rest_user_id -object_type $rest_otype -object_id $rest_oid -action after_update


    # The update was successful - return a suitable message.
    switch $format {
	html { 
	    set page_title "object_type: $rest_otype"
	    doc_return 200 "text/html" "
		[im_header $page_title [im_rest_header_extra_stuff]][im_navbar]<table>
		<tr class=rowtitle><td class=rowtitle>Object ID</td></tr>
		<tr<td>$rest_oid</td></tr>
		</table>[im_footer]
	    "
	}
	json {
	    # Empty data: The empty array is necessary for Sencha in order to call callbacks
	    # without error. However, adding data here will create empty records in the store later,
	    # so the array needs to be empty.
	    set data_list [list]
	    foreach key [array names hash_array] {
		set value $hash_array($key)
		lappend data_list "\"$key\": \"[im_quotejson $value]\""
	    }

	    set data "\[{[join $data_list ", "]}\]"
	    set result "{\"success\": \"true\",\"message\": \"Object updated\",\"data\": $data}"
	    doc_return 200 "application/json" $result
	}
    }
    return
}






# --------------------------------------------------------
# im_hours
#
# Update operation. This is implemented here, because
# im_hour isn't a real object

ad_proc -private im_rest_post_object_im_hour {
    { -format "json" }
    { -rest_user_id 0 }
    { -rest_otype "" }
    { -rest_oid "" }
    { -content "" }
    { -debug 0 }
    { -query_hash_pairs ""}
} {
    Handler for POST calls on particular im_hour objects.
    im_hour is not a real object type and performs a "delete" 
    operation specifying hours=0 or hours="".
} {
    ns_log Notice "im_rest_post_object_im_hour: rest_oid=$rest_oid"

    # Permissions
    # ToDo

    # Extract a key-value list of variables from JSON POST request
    array set hash_array [im_rest_parse_json_content -rest_otype $rest_otype -format $format -content $content]
    ns_log Notice "im_rest_post_object_$rest_otype: hash_array=[array get hash_array]"

    # write hash values as local variables
    foreach key [array names hash_array] {
	set value $hash_array($key)
	set $key $value
    }

    set hours $hash_array(hours)
    set hour_id $hash_array(hour_id)
    if {"" == $hours || 0.0 == $hours} {
	# Delete the hour instead of updating it.
	# im_hours is not a real object, so we don't need to
	# cleanup acs_objects.
	ns_log Notice "im_rest_post_object_im_hour: deleting hours because hours='$hours', hour_id=$hour_id"
	db_dml del_hours "delete from im_hours where hour_id = :hour_id"
    } else {
	# Update the object. This routine will return a HTTP error in case 
	# of a database constraint violation
	ns_log Notice "im_rest_post_object_im_hour: Before updating hours=$hours with hour_id=$hour_id"
	im_rest_object_type_update_sql \
	    -rest_otype $rest_otype \
	    -rest_oid $rest_oid \
	    -hash_array [array get hash_array]
	ns_log Notice "im_rest_post_object_im_hour: After updating hours=$hours with hour_id=$hour_id"
    }

    # The update was successful - return a suitable message.
    switch $format {
	html { 
	    set page_title "object_type: $rest_otype"
	    doc_return 200 "text/html" "
		[im_header $page_title][im_navbar]<table>
		<tr class=rowtitle><td class=rowtitle>Object ID</td></tr>
		<tr<td>$rest_oid</td></tr>
		</table>[im_footer]
	    "
	}
	json {  
	    set data_list [list]
	    foreach key [array names hash_array] {
		set value $hash_array($key)
		lappend data_list "\"$key\": \"[im_quotejson $value]\""
	    }

	    set data "\[{[join $data_list ", "]}\]"
	    set result "{\"success\": \"true\",\"message\": \"Object updated\",\"data\": $data}"
	    doc_return 200 "application/json" $result
	}
    }
}

# --------------------------------------------------------
# im_hour_intervals
#
# Update operation. This is implemented here, because
# im_hour_interval isn't a real object

ad_proc -private im_rest_post_object_im_hour_interval {
    { -format "json" }
    { -rest_user_id 0 }
    { -rest_otype "" }
    { -rest_oid "" }
    { -content "" }
    { -debug 0 }
    { -query_hash_pairs ""}
} {
    Handler for POST calls on particular im_hour_interval objects.
    im_hour_interval is not a real object type and performs a "delete" 
    operation when interval_start = interval_end
} {
    ns_log Notice "im_rest_post_object_im_hour_interval: rest_oid=$rest_oid"

    # Permissions
    # ToDo

    # Extract a key-value list of variables from JSON POST request
    array set hash_array [im_rest_parse_json_content -rest_otype $rest_otype -format $format -content $content]
    ns_log Notice "im_rest_post_object_$rest_otype: hash_array=[array get hash_array]"

    # write hash values as local variables
    foreach key [array names hash_array] {
	set value $hash_array($key)
	set $key $value
    }

    set interval_id $hash_array(interval_id)
    if {$interval_start == $interval_end} {
	# Delete the hour_interval instead of updating it.
	# im_hour_intervals is not a real object, so we don't need to
	# cleanup acs_objects.
	ns_log Notice "im_rest_post_object_im_hour_interval: deleting hours because interval_start = interval_end = $interval_start', interval_id=$interval_id"
	db_dml del_hours "delete from im_hour_intervals where interval_id = :interval_id"
    } else {
	# Update the object. This routine will return a HTTP error in case 
	# of a database constraint violation
	ns_log Notice "im_rest_post_object_im_hour_interval: Before updating interval_id=$interval_id"
	im_rest_object_type_update_sql \
	    -rest_otype $rest_otype \
	    -rest_oid $rest_oid \
	    -hash_array [array get hash_array]
	ns_log Notice "im_rest_post_object_im_hour_interval: After updating interval_id=$interval_id"
    }

    # The update was successful - return a suitable message.
    switch $format {
	html { 
	    set page_title "object_type: $rest_otype"
	    doc_return 200 "text/html" "
		[im_header $page_title][im_navbar]<table>
		<tr class=rowtitle><td class=rowtitle>Object ID</td></tr>
		<tr<td>$rest_oid</td></tr>
		</table>[im_footer]
	    "
	}
	json {
	    set data_list [list]
	    foreach key [array names hash_array] {
		set value $hash_array($key)
		lappend data_list "\"$key\": \"[im_quotejson $value]\""
	    }

	    set data "\[{[join $data_list ", "]}\]"
	    set result "{\"success\": \"true\",\"message\": \"Object updated\",\"data\": $data}"
	    doc_return 200 "application/json" $result
	}
    }
}



# --------------------------------------------------------
# DELETE
# --------------------------------------------------------

ad_proc -private im_rest_delete_object {
    { -format "json" }
    { -rest_user_id 0 }
    { -rest_otype "" }
    { -rest_oid "" }
    { -query_hash_pairs {} }
    { -debug 0 }
} {
    Handler for DELETE rest calls to an individual object:
    Update the specific object using a generic update procedure
} {
    set content [im_rest_get_content]
    ns_log Notice "im_rest_delete_object: rest_otype=$rest_otype, rest_oid=$rest_oid, rest_user_id=$rest_user_id, format='$format', query_hash=$query_hash_pairs, content=$content"

    # Deletion requires administrator rights or admin_p permissions
    set admin_p [im_user_is_admin_p $rest_user_id]
    if {!$admin_p && 0 != [llength [info commands ${rest_otype}_permissions]]} {
	catch {
	    eval "${rest_otype}_permissions $rest_user_id $rest_oid view_p read_p admin_p admin_p"
	}
    }
    if {!$admin_p} {
	im_rest_error -format $format -http_status 403 -message "User #$rest_user_id has no 'admin' permission to perform DELETE on object #$rest_oid"
	return
    }
    
    # Deal with certain subtypes
    switch $rest_otype {
	im_ticket {
	    # use im_project_nuke that also serves to delete tickets
	    set nuke_otype "im_project"
	}
	default {
	    set nuke_otype $rest_otype
	}
    }

    # Destroy the object. Try first with an object_type_nuke TCL procedure.
    set destroyed_err_msg ""
    if {[catch {
	set nuke_tcl [list "${nuke_otype}_nuke" -current_user_id $rest_user_id $rest_oid]
	ns_log Notice "im_rest_delete_object: nuke_tcl=$nuke_tcl"
    eval $nuke_tcl
    } err_msg]} {
	ns_log Notice "im_rest_delete_object: Error nuking object $rest_oid using TCL code: $err_msg"
	set destroyed_p 0
	append destroyed_err_msg "$err_msg\n"
    } else {
	ns_log Notice "im_rest_delete_object: Successfully nuked object $rest_oid using TCL code"
	set destroyed_p 1
    }

    # Then try with a object_type__delete PL/SQL procedure
    if {!$destroyed_p} {
	if {[catch {
	    set destructor_name "${nuke_otype}__delete"
	    set destructor_exists_p [util_memoize [list db_string destructor_exists "select count(*) from pg_proc where lower(proname) = '$destructor_name'"]]
	    if {$destructor_exists_p} {
		ns_log Notice "im_rest_delete_object: About to try to nuke using plsql='select $destructor_name($rest_oid)'"
		db_string destruct_object "select $destructor_name($rest_oid) from dual"
	    }
	    set destroyed_p 1
	    ns_log Notice "im_rest_delete_object: Successfully nuked object $rest_oid using PL/SQLL code"
	} err_msg]} {
	    append destroyed_err_msg "$err_msg\n"
	    ns_log Notice "im_rest_delete_object: Error nuking object $rest_oid using PL/SQL code"
	}
    }

    # Try to destruct the object
    if {!$destroyed_p} {
	im_rest_error -format $format -http_status 404 -message "DELETE for object #$rest_oid of type \"$rest_otype\" created errors: $destroyed_err_msg"
	return
    }

    # The delete was successful - return a suitable message.
    switch $format {
	html { 
	    set page_title "object_type: $rest_otype"
	    doc_return 200 "text/html" "
		[im_header $page_title [im_rest_header_extra_stuff]][im_navbar]<table>
		<tr class=rowtitle><td class=rowtitle>Object ID</td></tr>
		<tr<td>$rest_oid</td></tr>
		</table>[im_footer]
	    "
	}
	json {
	    set result "{\"success\": \"true\",\"message\": \"Object deleted\"}"
	    doc_return 200 "application/json" $result
	}
    }
    return
}

