# /packages/intranet-rest/tcl/intranet-rest-get-procs.tcl
#
# Copyright (C) 2009 ]project-open[
#
# All rights reserved. Please check
# http://www.project-open.com/license/ for details.

ad_library {
    REST Web Service Component Library
    @author frank.bergmann@project-open.com
}


ad_proc -private im_rest_get_object_type {
    { -format "json" }
    { -rest_user_id 0 }
    { -rest_otype "" }
    { -rest_oid "" }
    { -query_hash_pairs {} }
    { -debug 0 }
} {
    Handler for GET rest calls on a whole object type -
    mapped to queries on the specified object type
} {
    ns_log Notice "im_rest_get_object_type: format=$format, rest_user_id=$rest_user_id, rest_otype=$rest_otype, rest_oid=$rest_oid, query_hash=$query_hash_pairs"

    array set query_hash $query_hash_pairs
    set rest_otype_id [util_memoize [list db_string otype_id "select object_type_id from im_rest_object_types where object_type = '$rest_otype'" -default 0]]
    set rest_columns [im_rest_get_rest_columns $query_hash_pairs]
    foreach col $rest_columns { set rest_columns_hash($col) 1 }

    # Check if the deref_p parameter was set
    array set query_hash $query_hash_pairs
    set deref_p 0
    if {[info exists query_hash(deref_p)]} { set deref_p $query_hash(deref_p) }
    im_security_alert_check_integer -location "im_rest_get_object: deref_p" -value $deref_p

    set base_url "[im_rest_system_url]/intranet-rest"

    set chars_to_be_escaped_list [list \
				      "\"" "\\\"" \\ \\\\ \b \\b \f \\f \n \\n \r \\r \t \\t \
				      \x00 \\u0000 \x01 \\u0001 \x02 \\u0002 \x03 \\u0003 \
				      \x04 \\u0004 \x05 \\u0005 \x06 \\u0006 \x07 \\u0007 \
				      \x0b \\u000b \x0e \\u000e \x0f \\u000f \x10 \\u0010 \
				      \x11 \\u0011 \x12 \\u0012 \x13 \\u0013 \x14 \\u0014 \
				      \x15 \\u0015 \x16 \\u0016 \x17 \\u0017 \x18 \\u0018 \
				      \x19 \\u0019 \x1a \\u001a \x1b \\u001b \x1c \\u001c \
				      \x1d \\u001d \x1e \\u001e \x1f \\u001f \x7f \\u007f \
				      \x80 \\u0080 \x81 \\u0081 \x82 \\u0082 \x83 \\u0083 \
				      \x84 \\u0084 \x85 \\u0085 \x86 \\u0086 \x87 \\u0087 \
				      \x88 \\u0088 \x89 \\u0089 \x8a \\u008a \x8b \\u008b \
				      \x8c \\u008c \x8d \\u008d \x8e \\u008e \x8f \\u008f \
				      \x90 \\u0090 \x91 \\u0091 \x92 \\u0092 \x93 \\u0093 \
				      \x94 \\u0094 \x95 \\u0095 \x96 \\u0096 \x97 \\u0097 \
				      \x98 \\u0098 \x99 \\u0099 \x9a \\u009a \x9b \\u009b \
				      \x9c \\u009c \x9d \\u009d \x9e \\u009e \x9f \\u009f \
				     ]

    # -------------------------------------------------------
    # Get some more information about the current object type
    set otype_info [util_memoize [list db_list_of_lists rest_otype_info "select table_name, id_column from acs_object_types where object_type = '$rest_otype'"]]
    set table_name [lindex [lindex $otype_info 0] 0]
    set id_column [lindex [lindex $otype_info 0] 1]
    if {"" == $table_name} {
	im_rest_error -format $format -http_status 500 -message "Invalid DynField configuration: Object type '$rest_otype' doesn't have a table_name specified in table acs_object_types."
    }
    # Deal with ugly situation that usre_id is defined multiple times for object_type=user
    if {"users" == $table_name} { set id_column "person_id" }
    
    # -------------------------------------------------------
    # Check for generic permissions to read all objects of this type
    set rest_otype_read_all_p [im_object_permission -object_id $rest_otype_id -user_id $rest_user_id -privilege "read"]

    # Deny completely access to the object type?
    set rest_otype_read_none_p 0

    if {!$rest_otype_read_all_p} {
	# There are "view_xxx_all" permissions allowing a user to see all objects:
	switch $rest_otype {
	    bt_bug		{ }
	    im_company		{ set rest_otype_read_all_p [im_permission $rest_user_id "view_companies_all"] }
	    im_cost		{ set rest_otype_read_all_p [im_permission $rest_user_id "view_finance"] }
	    im_conf_item	{ set rest_otype_read_all_p [im_permission $rest_user_id "view_conf_items_all"] }
	    im_invoices		{ set rest_otype_read_all_p [im_permission $rest_user_id "view_finance"] }
	    im_project		{ set rest_otype_read_all_p [im_permission $rest_user_id "view_projects_all"] }
	    im_user_absence	{ set rest_otype_read_all_p [im_permission $rest_user_id "view_absences_all"] }
	    im_office		{ set rest_otype_read_all_p [im_permission $rest_user_id "view_offices_all"] }
	    im_profile		{ set rest_otype_read_all_p 1 }
	    im_ticket		{ set rest_otype_read_all_p [im_permission $rest_user_id "view_tickets_all"] }
	    im_timesheet_task	{ set rest_otype_read_all_p [im_permission $rest_user_id "view_timesheet_tasks_all"] }
	    im_timesheet_invoices { set rest_otype_read_all_p [im_permission $rest_user_id "view_finance"] }
	    im_trans_invoices	{ set rest_otype_read_all_p [im_permission $rest_user_id "view_finance"] }
	    im_translation_task	{ }
	    user		{ }
	    default { 
		# No read permissions? 
		# Well, no object type except the ones above has a custom procedure,
		# so we can deny access here:
		set rest_otype_read_none_p 1
		ns_log Notice "im_rest_get_object_type: Denying access to $rest_otype"
	    }
	}
    }

    # -------------------------------------------------------
    # Check if there is a where clause specified in the URL
    # and validate the clause.
    set where_clause ""
    set where_clause_list [list]
    set where_clause_unchecked_list [list]
    if {[info exists query_hash(query)]} { set where_clause $query_hash(query)}
    if {"" != $where_clause} { lappend where_clause_list $where_clause }
    ns_log Notice "im_rest_get_object_type: where_clause=$where_clause"


    # -------------------------------------------------------
    # Check if there are "valid_vars" specified in the HTTP header
    # and add these vars to the SQL clause
    set valid_vars [util_memoize [list im_rest_object_type_columns -deref_p $deref_p -rest_otype $rest_otype]]
    foreach v $valid_vars {
	if {[info exists query_hash($v)]} { lappend where_clause_list "$v=$query_hash($v)" }
    }

    # -------------------------------------------------------
    # Check if there was a rest_oid provided as part of the URL
    # for example /im_project/8799. In this case add the oid to
    # the query.
    # rest_oid was already security checked to be an integer.
    if {"" != $rest_oid && 0 != $rest_oid} {
	lappend where_clause_list "$id_column=$rest_oid"
    }

    # -------------------------------------------------------
    # Transform the database table to deal with exceptions
    #
    switch $rest_otype {
	user - person - party {
	    set table_name "(
		select	*
		from	users u, parties pa, persons pe
		where	u.user_id = pa.party_id and u.user_id = pe.person_id and
			u.user_id in (
				SELECT  o.object_id
				FROM    acs_objects o,
				        group_member_map m,
				        membership_rels mr
				WHERE   m.member_id = o.object_id AND
				        m.group_id = acs__magic_object_id('registered_users'::character varying) AND
				        m.rel_id = mr.rel_id AND
				        m.container_id = m.group_id AND
				        m.rel_type::text = 'membership_rel'::text AND
				        mr.member_state = 'approved'
			)
		)"
	}
	file_storage_object {
	    # file storage object needs additional security
	    lappend where_clause_unchecked_list "'t' = acs_permission__permission_p(o.object_id, $rest_user_id, 'read')"
	}
	im_ticket {
	    # Testing per-ticket permissions
	    set read_sql [im_ticket_permission_read_sql -user_id $rest_user_id]
	    lappend where_clause_unchecked_list "o.object_id in ($read_sql)"
	}
    }

    # Check that the where_clause elements are valid SQL statements
    foreach where_clause $where_clause_list {
	set valid_sql_where [im_rest_valid_sql -string $where_clause -variables $valid_vars]
	if {!$valid_sql_where} {
	    im_rest_error -format $format -http_status 403 -message "The specified query is not a valid SQL where clause: '$where_clause'"
	    return
	}
    }

    # Build the complete where clause
    set where_clause_list [concat $where_clause_list $where_clause_unchecked_list]
    if {"" != $where_clause && [llength $where_clause_list] > 0} { append where_clause " and " }
    append where_clause [join $where_clause_list " and\n\t\t"]
    if {"" != $where_clause} { set where_clause "and $where_clause" }

    # -------------------------------------------------------
    # Select SQL: Pull out objects where the acs_objects.object_type 
    # is correct AND the object exists in the object type's primary table.
    # This way we avoid "dangling objects" in acs_objects and sub-types.
    set sql [im_rest_object_type_select_sql -deref_p $deref_p -rest_otype $rest_otype -no_where_clause_p 1]
    append sql "
	where	o.object_type = :rest_otype and
		o.object_id in (
			select  t.$id_column as rest_oid
			from    $table_name t
		)
		$where_clause
    "

    # Append sorting "ORDER BY" clause to the sql.
    append sql [im_rest_object_type_order_sql -query_hash_pairs $query_hash_pairs]

    # Append pagination "LIMIT $limit OFFSET $start" to the sql.
    set unlimited_sql $sql
    append sql [im_rest_object_type_pagination_sql -query_hash_pairs $query_hash_pairs]

    # -------------------------------------------------------
    # Loop through all objects of the specified type
    set obj_ctr 0
    set result ""
    db_foreach objects $sql {

	# Skip objects with empty object name
	if {"" == $object_name} { 
	    ns_log Error "im_rest_get_object_type: Skipping object #$object_id because object_name is empty."
	    continue
	}

	# -------------------------------------------------------
	# Permissions

	# Denied access?
	if {$rest_otype_read_none_p} { continue }

	# Check permissions
	set read_p $rest_otype_read_all_p
	
	if {!$read_p} {

	    
	    # This is one of the "custom" object types - check the permission:
	    # This may be quite slow checking 100.000 objects one-by-one...
	    catch {
		ns_log Notice "im_rest_get_object_type: Checking for individual permissions: ${rest_otype}_permissions $rest_user_id $rest_oid"
		eval "${rest_otype}_permissions $rest_user_id $rest_oid view_p read_p write_p admin_p"

		if {!$read_p && "" != $rest_oid} {
		    im_rest_error -format $format -http_status 403 -message "User does not have read access to this object"
		    return
		}
	    }
	}
	if {!$read_p} { continue }

	switch $format {
	    json {
		set komma ",\n"
		if {0 == $obj_ctr} { set komma "" }
		set dereferenced_result ""
		foreach v $valid_vars {
		    # Skip the column unless it is explicitely mentioned in the rest_columns list
		    if {{} != $rest_columns} { if {![info exists rest_columns_hash($v)]} { continue } }
		    eval "set a $$v"
		    set a [string map $chars_to_be_escaped_list $a]
                    append dereferenced_result ", \"$v\": \"$a\""

		    ns_log Notice "im_rest_get_object_type: var=$v, value=$a"
		}
		append result "$komma{\"id\": \"$rest_oid\", \"object_name\": \"[string map $chars_to_be_escaped_list $object_name]\"$dereferenced_result}" 
	    }
	    html { 
	        set url "$base_url/$rest_otype/$rest_oid"
		append result "<tr>
			<td>$rest_oid</td>
			<td><a href=\"$url?format=html\">$object_name</a>
		</tr>\n" 
	    }
	}
	incr obj_ctr
    }

    switch $format {
	html {
	    set page_title "object_type: $rest_otype"
	    im_rest_doc_return 200 "text/html" "
		[im_header $page_title [im_rest_header_extra_stuff]][im_navbar]<table>
		<tr class=rowtitle><td class=rowtitle>object_id</td><td class=rowtitle>Link</td></tr>$result
		</table>[im_footer]
	    " 
	}
	json {  
	    # Calculate the total number of objects
	    set total [db_string total "select count(*) from ($unlimited_sql) t" -default 0]
	    set result "{\"success\": true,\n\"total\": $total,\n\"message\": \"im_rest_get_object_type: Data loaded\",\n\"data\": \[\n$result\n\]\n}"
	    im_rest_doc_return 200 "text/html" $result
	    return
	}
	default {
	     ad_return_complaint 1 "Invalid format5: '$format'"
	     return
	}
    }
}


ad_proc -private im_rest_get_im_invoice_items {
    { -format "json" }
    { -rest_user_id 0 }
    { -rest_otype "" }
    { -rest_oid "" }
    { -query_hash_pairs {} }
    { -debug 0 }
} {
    Handler for GET rest calls on invoice items.
} {
    ns_log Notice "im_rest_get_invoice_items: format=$format, rest_user_id=$rest_user_id, rest_otype=$rest_otype, query_hash=$query_hash_pairs"

    array set query_hash $query_hash_pairs
    if {"" != $rest_oid} { set query_hash(item_id) $rest_oid }
    
    set base_url "[im_rest_system_url]/intranet-rest"
    set rest_otype_id [util_memoize [list db_string otype_id "select object_type_id from im_rest_object_types where object_type = 'im_invoice'" -default 0]]
    set rest_otype_read_all_p [im_object_permission -object_id $rest_otype_id -user_id $rest_user_id -privilege "read"]


    # -------------------------------------------------------
    # Check if there is a where clause specified in the URL and validate the clause.
    set where_clause ""
    if {[info exists query_hash(query)]} { set where_clause $query_hash(query)}
    # Determine the list of valid columns for the object type
    set valid_vars {item_id item_name project_id invoice_id item_units item_uom_id price_per_unit currency sort_order item_type_id item_status_id description item_material_id}
    # Check that the query is a valid SQL where clause
    set valid_sql_where [im_rest_valid_sql -string $where_clause -variables $valid_vars]
    if {!$valid_sql_where} {
	im_rest_error -format $format -http_status 403 -message "The specified query is not a valid SQL where clause: '$where_clause'"
	return
    }
    if {"" != $where_clause} { set where_clause "and $where_clause" }

    # Select SQL: Pull out invoice_items.
    set sql "
	select	ii.item_id as rest_oid,
		ii.item_name as object_name,
		ii.invoice_id
	from	im_invoice_items ii
	where	1=1
		$where_clause
    "

    # Append pagination "LIMIT $limit OFFSET $start" to the sql.
    set unlimited_sql $sql
    append sql [im_rest_object_type_pagination_sql -query_hash_pairs $query_hash_pairs]


    set result ""
    db_foreach objects $sql {

	# Check permissions
	set read_p $rest_otype_read_all_p
	if {!$read_p} { set read_p [im_permission $rest_user_id "view_finance"] }
	if {!$read_p} { im_invoice_permissions $rest_user_id $invoice_id view_p read_p write_p admin_p }
	if {!$read_p} { continue }

	set url "$base_url/$rest_otype/$rest_oid"
	switch $format {
	    html { 
		append result "<tr>
			<td>$rest_oid</td>
			<td><a href=\"$url?format=html\">$object_name</a>
		</tr>\n" 
	    }
	    json { 
		append result "{object_id: $rest_oid}\n" 
	    }
	    default {}
	}
    }
	
    switch $format {
	html { 
	    set page_title "object_type: $rest_otype"
	    im_rest_doc_return 200 "text/html" "
		[im_header $page_title [im_rest_header_extra_stuff]][im_navbar]<table>
		<tr class=rowtitle><td class=rowtitle>object_id</td><td class=rowtitle>Link</td></tr>$result
		</table>[im_footer]
	    " 
	    return
	}
	json {  
	    im_rest_doc_return 200 "text/html" "{object_type: \"$rest_otype\",\n$result\n}"
	    return
	}
    }

    return
}


ad_proc -private im_rest_get_im_hours {
    { -format "json" }
    { -rest_user_id 0 }
    { -rest_otype "" }
    { -rest_oid "" }
    { -query_hash_pairs {} }
    { -debug 0 }
} {
    Handler for GET rest calls on timesheet hours
} {
    ns_log Notice "im_rest_get_im_hours: format=$format, rest_user_id=$rest_user_id, rest_otype=$rest_otype, rest_oid=$rest_oid, query_hash=$query_hash_pairs"

    array set query_hash $query_hash_pairs
    if {"" != $rest_oid} { set query_hash(hour_id) $rest_oid }
    set base_url "[im_rest_system_url]/intranet-rest"

    # Permissions:
    # A user can normally read only his own hours,
    # unless he's got the view_hours_all privilege or explicitely 
    # the perms on the im_hour object type
    set rest_otype_id [util_memoize [list db_string otype_id "select object_type_id from im_rest_object_types where object_type = 'im_hour'" -default 0]]
    set rest_otype_read_all_p [im_object_permission -object_id $rest_otype_id -user_id $rest_user_id -privilege "read"]
    if {[im_permission $rest_user_id "view_hours_all"]} { set rest_otype_read_all_p 1 }

    set owner_perm_sql "and h.user_id = :rest_user_id"
    if {$rest_otype_read_all_p} { set owner_perm_sql "" }

    # -------------------------------------------------------
    # Check if there is a where clause specified in the URL and validate the clause.
    set where_clause ""
    if {[info exists query_hash(query)]} { set where_clause $query_hash(query)}

    # Determine the list of valid columns for the object type
    set valid_vars {hour_id user_id project_id day hours days note internal_note cost_id conf_object_id invoice_id material_id}



    # -------------------------------------------------------
    # Check if there are "valid_vars" specified in the HTTP header
    # and add these vars to the SQL clause
    set where_clause_list [list]
    foreach v $valid_vars {
        if {[info exists query_hash($v)]} { lappend where_clause_list "$v=$query_hash($v)" }
    }
    if {"" != $where_clause && [llength $where_clause_list] > 0} { append where_clause " and " }
    append where_clause [join $where_clause_list " and "]

    # Check that the query is a valid SQL where clause
    set valid_sql_where [im_rest_valid_sql -string $where_clause -variables $valid_vars]
    if {!$valid_sql_where} {
	im_rest_error -format $format -http_status 403 -message "The specified query is not a valid SQL where clause: '$where_clause'"
	return
    }
    if {"" != $where_clause} { set where_clause "and $where_clause" }



    # Select SQL: Pull out hours.
    set sql "
	select	h.hour_id as rest_oid,
		'(' || im_name_from_user_id(user_id) || ', ' || 
			im_project_name_from_id(h.project_id) || 
			day::date || ', ' || ' - ' || 
			h.hours || ')' as object_name,
		h.*
	from	im_hours h
	where	1=1
		$owner_perm_sql
		$where_clause
    "

    # Append pagination "LIMIT $limit OFFSET $start" to the sql.
    set unlimited_sql $sql
    append sql [im_rest_object_type_pagination_sql -query_hash_pairs $query_hash_pairs]

    set value ""
    set result ""
    set obj_ctr 0
    db_foreach objects $sql {

	# Check permissions
	set read_p $rest_otype_read_all_p
	if {!$read_p} { continue }

	set url "$base_url/$rest_otype/$rest_oid"
	switch $format {
	    html { 
		append result "<tr>
			<td>$rest_oid</td>
			<td><a href=\"$url?format=html\">$object_name</a>
		</tr>\n"
	    }
	    json {
		set komma ",\n"
		if {0 == $obj_ctr} { set komma "" }
		set dereferenced_result ""
		foreach v $valid_vars {
			eval "set a $$v"
			regsub -all {\n} $a {\n} a
			regsub -all {\r} $a {} a
			append dereferenced_result ", \"$v\": \"[ns_quotehtml $a]\""
		}
		append result "$komma{\"id\": \"$rest_oid\", \"object_name\": \"[ns_quotehtml $object_name]\"$dereferenced_result}" 
	    }
	    default {}
	}
	incr obj_ctr
    }
	
    switch $format {
	html { 
	    set page_title "object_type: $rest_otype"
	    im_rest_doc_return 200 "text/html" "
		[im_header $page_title [im_rest_header_extra_stuff]][im_navbar]<table>
		<tr class=rowtitle><td class=rowtitle>object_id</td><td class=rowtitle>Link</td></tr>$result
		</table>[im_footer]
	    " 
	    return
	}
	json {  
	    # Deal with different JSON variants for different AJAX frameworks
	    set result "{\"success\": true,\n\"message\": \"im_rest_get_im_hours: Data loaded\",\n\"data\": \[\n$result\n\]\n}"
	    im_rest_doc_return 200 "text/html" $result
	    return
	}
    }
    return
}



ad_proc -private im_rest_get_im_hour_intervals {
    { -format "json" }
    { -rest_user_id 0 }
    { -rest_otype "" }
    { -rest_oid "" }
    { -query_hash_pairs {} }
    { -debug 0 }
} {
    Handler for GET rest calls on timesheet hour intervals
} {
    ns_log Notice "im_rest_get_im_hour_intervals: format=$format, rest_user_id=$rest_user_id, rest_otype=$rest_otype, rest_oid=$rest_oid, query_hash=$query_hash_pairs"

    array set query_hash $query_hash_pairs
    if {"" != $rest_oid} { set query_hash(interval_id) $rest_oid }
    set base_url "[im_rest_system_url]/intranet-rest"

    # Permissions:
    # A user can normally read only his own hours,
    # unless he's got the view_hours_all privilege or explicitely 
    # the perms on the im_hour_interval object type
    set rest_otype_id [util_memoize [list db_string otype_id "select object_type_id from im_rest_object_types where object_type = 'im_hour_interval'" -default 0]]
    set rest_otype_read_all_p [im_object_permission -object_id $rest_otype_id -user_id $rest_user_id -privilege "read"]
    if {[im_permission $rest_user_id "view_hours_all"]} { set rest_otype_read_all_p 1 }

    set owner_perm_sql "and h.user_id = :rest_user_id"
    if {$rest_otype_read_all_p} { set owner_perm_sql "" }

    # -------------------------------------------------------
    # Check if there is a where clause specified in the URL and validate the clause.
    set where_clause ""
    if {[info exists query_hash(query)]} { set where_clause $query_hash(query)}

    # Determine the list of valid columns for the object type
    set valid_vars {interval_id user_id project_id interval_start interval_end note internal_note activity_id material_id}


    # -------------------------------------------------------
    # Check if there are "valid_vars" specified in the HTTP header
    # and add these vars to the SQL clause
    set where_clause_list [list]
    foreach v $valid_vars {
        if {[info exists query_hash($v)]} { lappend where_clause_list "$v=$query_hash($v)" }
    }
    if {"" != $where_clause && [llength $where_clause_list] > 0} { append where_clause " and " }
    append where_clause [join $where_clause_list " and "]

    # Check that the query is a valid SQL where clause
    set valid_sql_where [im_rest_valid_sql -string $where_clause -variables $valid_vars]
    if {!$valid_sql_where} {
	im_rest_error -format $format -http_status 403 -message "The specified query is not a valid SQL where clause: '$where_clause'"
	return
    }
    if {"" != $where_clause} { set where_clause "and $where_clause" }



    # Select SQL: Pull out hours.
    set sql "
	select	h.interval_id as rest_oid,
		'(' || im_name_from_user_id(user_id) || ', ' || 
			im_project_name_from_id(h.project_id) || ', ' ||
			interval_start || ' - ' || interval_end || ')' as object_name,
		h.*
	from	im_hour_intervals h
	where	1=1
		$owner_perm_sql
		$where_clause
    "

    # Append pagination "LIMIT $limit OFFSET $start" to the sql.
    set unlimited_sql $sql
    append sql [im_rest_object_type_pagination_sql -query_hash_pairs $query_hash_pairs]

    set value ""
    set result ""
    set obj_ctr 0
    db_foreach objects $sql {

	# Check permissions
	set read_p $rest_otype_read_all_p
	if {!$read_p} { continue }

	set url "$base_url/$rest_otype/$rest_oid"
	switch $format {
	    html { append result "<tr><td>$rest_oid</td><td><a href=\"$url?format=html\">$object_name</a></tr>\n" }
	    json {
		set komma ",\n"
		if {0 == $obj_ctr} { set komma "" }
		set dereferenced_result ""
		foreach v $valid_vars {
			eval "set a $$v"
			regsub -all {\n} $a {\n} a
			regsub -all {\r} $a {} a
			append dereferenced_result ", \"$v\": \"[ns_quotehtml $a]\""
		}
		append result "$komma{\"id\": \"$rest_oid\", \"object_name\": \"[ns_quotehtml $object_name]\"$dereferenced_result}" 
	    }
	    default {}
	}
	incr obj_ctr
    }
	
    switch $format {
	html { 
	    set page_title "object_type: $rest_otype"
	    im_rest_doc_return 200 "text/html" "
		[im_header $page_title [im_rest_header_extra_stuff]][im_navbar]<table>
		<tr class=rowtitle><td class=rowtitle>object_id</td><td class=rowtitle>Link</td></tr>$result
		</table>[im_footer]
	    " 
	    return
	}
	json {  
	    # Deal with different JSON variants for different AJAX frameworks
	    set result "{\"success\": true,\n\"message\": \"im_rest_get_im_hour_intervals: Data loaded\",\n\"data\": \[\n$result\n\]\n}"
	    im_rest_doc_return 200 "text/html" $result
	    return
	}
    }
    return
}


ad_proc -private im_rest_get_im_categories {
    { -format "json" }
    { -rest_user_id 0 }
    { -rest_otype "" }
    { -query_hash_pairs {} }
    { -debug 0 }
} {
    Handler for GET rest calls on invoice items.
} {
    ns_log Notice "im_rest_get_categories: format=$format, rest_user_id=$rest_user_id, rest_otype=$rest_otype, query_hash=$query_hash_pairs"
    array set query_hash $query_hash_pairs
    set base_url "[im_rest_system_url]/intranet-rest"

    set rest_otype_id [util_memoize [list db_string otype_id "select object_type_id from im_rest_object_types where object_type = 'im_category'" -default 0]]
    set rest_otype_read_all_p [im_object_permission -object_id $rest_otype_id -user_id $rest_user_id -privilege "read"]

    # Get locate for translation
    set locale [lang::user::locale -rest_user_id $rest_user_id]

    # -------------------------------------------------------
    # Valid variables to return for im_category
    set valid_vars {category_id tree_sortkey category category_translated category_description category_type category_gif enabled_p parent_only_p aux_int1 aux_int2 aux_string1 aux_string2 sort_order}

    # -------------------------------------------------------
    # Check if there is a where clause specified in the URL and validate the clause.
    set where_clause ""
    if {[info exists query_hash(query)]} { set where_clause $query_hash(query)}


    # -------------------------------------------------------
    # Check if there are "valid_vars" specified in the HTTP header
    # and add these vars to the SQL clause
    set where_clause_list [list]
    foreach v $valid_vars {
        if {[info exists query_hash($v)]} { lappend where_clause_list "$v=$query_hash($v)" }
    }
    if {"" != $where_clause && [llength $where_clause_list] > 0} { append where_clause " and " }
    append where_clause [join $where_clause_list " and "]


    # Check that the query is a valid SQL where clause
    set valid_sql_where [im_rest_valid_sql -string $where_clause -variables $valid_vars]
    if {!$valid_sql_where} {
	im_rest_error -format $format -http_status 403 -message "The specified query is not a valid SQL where clause: '$where_clause'"
	return
    }
    if {"" != $where_clause} { set where_clause "and $where_clause" }

    # Select SQL: Pull out categories.
    set sql "
	select	c.category_id as rest_oid,
		c.category as object_name,
		im_category_path_to_category(c.category_id) as tree_sortkey,
		c.*
	from	im_categories c
	where	(c.enabled_p is null OR c.enabled_p = 't')
		$where_clause
	order by category_id
    "

    # Append pagination "LIMIT $limit OFFSET $start" to the sql.
    set unlimited_sql $sql
    append sql [im_rest_object_type_pagination_sql -query_hash_pairs $query_hash_pairs]

    set value ""
    set result ""
    set obj_ctr 0
    db_foreach objects $sql {

	set category_key "intranet-core.[lang::util::suggest_key $category]"
        set category_translated [lang::message::lookup $locale $category_key $category]

        # Calculate indent
        set indent [expr [string length tree_sortkey] - 8]

	# Check permissions
	set read_p $rest_otype_read_all_p
	set read_p 1
	if {!$read_p} { continue }

	set url "$base_url/$rest_otype/$rest_oid"
	switch $format {
	    html { 
		append result "<tr>
			<td>$rest_oid</td>
			<td><a href=\"$url?format=html\">$object_name</a>
		</tr>\n" 
	    }
	    json {
		set komma ",\n"
		if {0 == $obj_ctr} { set komma "" }
		set dereferenced_result ""
		foreach v $valid_vars {
			eval "set a $$v"
			regsub -all {\n} $a {\n} a
			regsub -all {\r} $a {} a
			append dereferenced_result ", \"$v\": \"[ns_quotehtml $a]\""
		}
		append result "$komma{\"id\": \"$rest_oid\", \"object_name\": \"[ns_quotehtml $object_name]\"$dereferenced_result}" 
	    }
	    default {}
	}
	incr obj_ctr
    }
	
    switch $format {
	html { 
	    set page_title "object_type: $rest_otype"
	    im_rest_doc_return 200 "text/html" "
		[im_header $page_title [im_rest_header_extra_stuff]][im_navbar]<table>
		<tr class=rowtitle><td class=rowtitle>object_id</td><td class=rowtitle>Link</td></tr>$result
		</table>[im_footer]
	    " 
	    return
	}
	json {  
	    # Deal with different JSON variants for different AJAX frameworks
	    set result "{\"success\": true,\n\"message\": \"im_rest_get_im_categories: Data loaded\",\n\"data\": \[\n$result\n\]\n}"
	    im_rest_doc_return 200 "text/html" $result
	    return
	}
    }
    return
}


ad_proc -private im_rest_get_im_dynfield_attributes {
    { -format "json" }
    { -rest_user_id 0 }
    { -rest_otype "" }
    { -query_hash_pairs {} }
    { -debug 0 }
} {
    Handler for GET rest calls on dynfield attributes
} {
    ns_log Notice "im_rest_get_im_dynfield_attributes: format=$format, rest_user_id=$rest_user_id, rest_otype=$rest_otype, query_hash=$query_hash_pairs"
    array set query_hash $query_hash_pairs
    set base_url "[im_rest_system_url]/intranet-rest"

    set rest_otype_id [util_memoize [list db_string otype_id "select object_type_id from im_rest_object_types where object_type = 'im_dynfield_attribute'" -default 0]]
    set rest_otype_read_all_p [im_object_permission -object_id $rest_otype_id -user_id $rest_user_id -privilege "read"]

    # -------------------------------------------------------
    # Check if there is a where clause specified in the URL and validate the clause.
    set where_clause ""
    if {[info exists query_hash(query)]} { set where_clause $query_hash(query)}
    # Determine the list of valid columns for the object type
    set valid_vars {attribute_name object_type}
    # Check that the query is a valid SQL where clause
    set valid_sql_where [im_rest_valid_sql -string $where_clause -variables $valid_vars]
    if {!$valid_sql_where} {
	im_rest_error -format $format -http_status 403 -message "The specified query is not a valid SQL where clause: '$where_clause'"
	return
    }
    if {"" != $where_clause} { set where_clause "and $where_clause" }

    # Select SQL: Pull out values.
    set sql "
	select	
		aa.object_type||'.'||aa.attribute_name as rest_object_name,
		da.attribute_id as rest_oid,
		da.*,
		aa.*
	from	im_dynfield_attributes da,
		acs_attributes aa
	where	da.acs_attribute_id = aa.attribute_id
		$where_clause
	order by
		aa.object_type, 
		aa.attribute_name
    "

    # Append pagination "LIMIT $limit OFFSET $start" to the sql.
    set unlimited_sql $sql
    append sql [im_rest_object_type_pagination_sql -query_hash_pairs $query_hash_pairs]


    set result ""
    db_foreach objects $sql {

	# Check permissions
	set read_p $rest_otype_read_all_p
	if {!$read_p} { continue }

	set url "$base_url/$rest_otype/$rest_oid"
	switch $format {
	    html { 
		append result "<tr>
			<td>$rest_oid</td>
			<td><a href=\"$url?format=html\">$rest_object_name</a>
		</tr>\n" 
	    }
	    json { append result "{object_id: $rest_oid, object_name: \"[ns_quotehtml $rest_object_name\"}\n" }
	    default {}
	}
    }
	
    switch $format {
	html { 
	    set page_title "object_type: $rest_otype"
	    im_rest_doc_return 200 "text/html" "
		[im_header $page_title [im_rest_header_extra_stuff]][im_navbar]<table>
		<tr class=rowtitle><td class=rowtitle>object_id</td><td class=rowtitle>Link</td></tr>$result
		</table>[im_footer]
	    " 
	}
	json {  
	    im_rest_doc_return 200 "text/html" "\[\n$result\n\]\n"
	}
    }

    return
}

