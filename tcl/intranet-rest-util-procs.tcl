# /packages/intranet-rest/tcl/intranet-rest-util-procs.tcl
#
# Copyright (C) 2009 ]project-open[
#
# All rights reserved. Please check
# http://www.project-open.com/license/ for details.

ad_library {
    REST Web Service Library
    Utility functions
    @author frank.bergmann@project-open.com
}

# --------------------------------------------------------
# Auxillary functions
# --------------------------------------------------------

ad_proc -public im_rest_doc_return {args} {
    This is a replacement for doc_return that values if the
    gzip_p URL parameters has been set.
} {
    # Perform some magic work
    db_release_unused_handles
    ad_http_cache_control

    # find out if we should compress or not
    set query_set [ns_conn form]
    set gzip_p [ns_set get $query_set gzip_p]
    ns_log Notice "im_rest_doc_return: gzip_p=$gzip_p"

    # Return the data
    if {"1" == $gzip_p} {
	return [eval "ns_returnz $args"]
    } else {
	return [eval "ns_return $args"]
    }

}


ad_proc -public im_rest_get_rest_columns {
    query_hash_pairs
} {
    Reads the "columns" URL variable and returns the 
    list of selected REST columns or an empty list 
    if the variable was not specified.
} {
    set rest_columns [list]
    set rest_column_arg ""
    array set query_hash $query_hash_pairs
    if {[info exists query_hash(columns)]} { set rest_column_arg $query_hash(columns) }
    if {"" != $rest_column_arg} {
        # Accept both space (" ") and komma (",") separated columns
	set rest_columns [split $rest_column_arg " "]
	if {[llength $rest_columns] <= 1} {
	    set rest_columns [split $rest_column_arg ","]
	}
    }

    return $rest_columns
}


ad_proc -private im_rest_header_extra_stuff {
    {-debug 1}
} {
    Returns a number of HTML header code in order to make the 
    REST interface create reasonable HTML pages.
} {
    set extra_stuff "
	<link rel='stylesheet' href='/resources/acs-subsite/default-master.css' type='text/css' media='all'>
	<link rel='stylesheet' href='/intranet/style/style.saltnpepper.css' type='text/css' media='screen'>
	<link rel='stylesheet' href='/resources/acs-developer-support/acs-developer-support.css' type='text/css' media='all'> 
	<link rel='stylesheet' href='/intranet/style/smartmenus/sm-core-css.css'  type='text/css' media='screen'>
	<link rel='stylesheet' href='/intranet/style/smartmenus/sm-simple/sm-simple.css'  type='text/css' media='screen'>
	<script type='text/javascript' src='/intranet/js/jquery.min.js'></script>
	<script type='text/javascript' src='/intranet/js/showhide.js'></script>
	<script type='text/javascript' src='/intranet/js/rounded_corners.inc.js'></script>
	<script type='text/javascript' src='/resources/acs-subsite/core.js'></script>
	<script type='text/javascript' src='/intranet/js/smartmenus/jquery.smartmenus.min.js'></script>
	<script type='text/javascript' src='/intranet/js/style.saltnpepper.js'></script>
    "
}


ad_proc -private im_rest_debug_headers {
    {-debug 1}
} {
    Show REST call headers
} {
    set debug "\n"
    append debug "method: [ns_conn method]\n"
    
    set header_vars [ns_conn headers]
    foreach var [ad_ns_set_keys $header_vars] {
	set value [ns_set get $header_vars $var]
	append debug "header: $var=$value\n"
    }
    
    set form_vars [ns_conn form]
    foreach var [ad_ns_set_keys $form_vars] {
	set value [ns_set get $form_vars $var]
	append debug "form: $var=$value\n"
    }
    
    append debug "content: [ns_conn content]\n"
    
    ns_log Notice "im_rest_debug_headers: $debug"
    return $debug
}


ad_proc -private im_rest_system_url { } {
    Returns a the system's "official" URL without trailing slash
    suitable to prefix all hrefs used for the JSON format.
} {
    return [util_current_location]
}


# ----------------------------------------------------------------------
# Extract all fields from an object type's tables
# ----------------------------------------------------------------------

ad_proc -public im_rest_object_type_pagination_sql { 
    -query_hash_pairs:required
} {
    Appends pagination information to a SQL statement depending on
    URL parameters: "LIMIT $limit OFFSET $start".
} {
    set pagination_sql ""
    array set query_hash $query_hash_pairs

    if {[info exists query_hash(limit)]} { 
	set limit $query_hash(limit) 
	im_security_alert_check_integer -location "im_rest_get_object_type" -value $limit
	append pagination_sql "LIMIT $limit\n"
    }

    if {[info exists query_hash(start)]} { 
	set start $query_hash(start) 
	im_security_alert_check_integer -location "im_rest_get_object_type" -value $start
	append pagination_sql "OFFSET $start\n"
    }

    return $pagination_sql
}

ad_proc -public im_rest_object_type_order_sql { 
    -query_hash_pairs:required
} {
    returns an "ORDER BY" statement for the *_get_object_type SQL.
    URL parameter example: sort=[{"property":"creation_date", "direction":"DESC"}]
} {
    set order_sql ""
    array set query_hash $query_hash_pairs

    set order_by_clauses {}
    if {[info exists query_hash(sort)]} { 
	set sort_json $query_hash(sort)
	array set parsed_json [util::json::parse $sort_json]
	set json_list $parsed_json(_array_)

	foreach sorter $json_list {
	    # Skpe the leading "_object_" key
	    set sorter_list [lindex $sorter 1]
	    array set sorter_hash $sorter_list

	    set property $sorter_hash(property)
	    set direction [string toupper $sorter_hash(direction)]
	    
	    # Perform security checks on the sorters
	    if {![regexp {} $property match]} { 
		ns_log Error "im_rest_object_type_order_sql: Found invalid sort property='$property'"
		continue 
	    }
	    if {[lsearch {DESC ASC} $direction] < 0} { 
		ns_log Error "im_rest_object_type_order_sql: Found invalid sort direction='$direction'"
		continue 
	    }
	    
	    lappend order_by_clauses "$property $direction"
	}
    }

    if {"" != $order_by_clauses} {
	return "order by [join $order_by_clauses ", "]\n"
    } else {
	# No order by clause specified
	return ""
    }
}

# ---------------------------------------------------------------
# Get meta-informatoin information about columns
#
# The deref_plpgsql_function is able to transform an attribute
# reference (i.e. an object_id or a category_id) into the name
# of the object.
# ---------------------------------------------------------------

ad_proc -public im_rest_hard_coded_deref_plpgsql_functions { 
    -rest_otype:required
} {
    Returns a key-value list of hard coded attribues per object type.
    These values are only necessary in order to work around missing
    dynfield metadata information for certain object types
} {
    set list {
	"acs_objects-creation_user" im_name_from_id
	"im_projects-parent_id" im_name_from_id
	"im_projects-company_id" im_name_from_id
	"im_projects-project_type_id" im_category_from_id 
	"im_projects-project_status_id" im_category_from_id 
	"im_projects-billing_type_id" im_category_from_id 
	"im_projects-on_track_status_id" im_category_from_id 
	"im_projects-project_lead_id" im_name_from_id 
	"im_projects-supervisor_id" im_name_from_id 
	"im_projects-company_contact_id" im_name_from_id 
	"im_projects-project_cost_center_id" im_name_from_id 
	"im_conf_items-conf_item_parent_id" im_name_from_id
	"im_conf_items-conf_item_cost_center_id" im_name_from_id
	"im_conf_items-conf_item_owner_id" im_name_from_id
	"im_conf_items-conf_item_type_id" im_name_from_id
	"im_conf_items-conf_item_status_id" im_name_from_id
    }
    return $list
}

ad_proc -public im_rest_deref_plpgsql_functions { 
    -rest_otype:required
} {
    Returns a key-value list of dereference functions per table-column.
} {
    set dynfield_sql "
    	select	*
	from	acs_attributes aa,
		im_dynfield_attributes da,
		im_dynfield_widgets dw
	where	aa.attribute_id = da.acs_attribute_id and
		da.widget_name = dw.widget_name and
		aa.object_type = :rest_otype
    "
    # Get a list of hard-coded attributes
    array set dynfield_hash [im_rest_hard_coded_deref_plpgsql_functions -rest_otype $rest_otype]
    # Overwrite/add with list of meta information from DynFields
    db_foreach dynfields $dynfield_sql {
	set key "$table_name-$attribute_name"
	set dynfield_hash($key) $deref_plpgsql_function
    }

    return [array get dynfield_hash]
}


ad_proc -public im_rest_object_type_select_sql { 
    {-deref_p 0}
    {-no_where_clause_p 0}
    -rest_otype:required
} {
    Calculates the SQL statement to extract the value for an object
    of the given rest_otype. The SQL will contains a ":rest_oid"
    colon-variables, so the variable "rest_oid" must be defined in 
    the context where this statement is to be executed.
} {
    # get the list of super-types for rest_otype, including rest_otype
    # and remove "acs_object" from the list
    set super_types [im_object_super_types -object_type $rest_otype]
    set s [list]
    foreach t $super_types {
	if {$t eq "acs_object"} { continue }
	lappend s $t
    }
    set super_types $s

    # Get a list of dereferencing functions
    if {$deref_p} {
	array set dynfield_hash [im_rest_deref_plpgsql_functions -rest_otype $rest_otype]
    }

    # ---------------------------------------------------------------
    # Construct a SQL that pulls out all information about one object
    # Start with the core object tables, so that all important fields
    # are available in the query, even if there are duplicates.
    #
    set letters {a b c d e f g h i j k l m n o p q r s t u v w x y z}
    set from {}
    set froms {}
    set selects { "1 as one" }
    set selected_columns {}
    set selected_tables {}

    set tables_sql "
	select	table_name,
		id_column
	from	(
		select	table_name,
			id_column,
			1 as sort_order
		from	acs_object_types
		where	object_type in ('[join $super_types "', '"]')
		UNION
		select	table_name,
			id_column,
			2 as sort_order
		from	acs_object_type_tables
		where	object_type in ('[join $super_types "', '"]')
		) t
	order by t.sort_order
    "
    set table_list [db_list_of_lists tables $tables_sql]

    set cnt 0
    foreach table_tuple $table_list {
	set table_name [lindex $table_tuple 0]
	set id_column [lindex $table_tuple 1]

	# Make sure not to include a table twice! There are duplicates in the query.
	if {[lsearch $selected_tables $table_name] >= 0} { continue }

	# Define an abbreviation for each table
	set letter [lindex $letters $cnt]
	lappend froms "LEFT OUTER JOIN $table_name $letter ON (o.object_id = $letter.$id_column)"

	# Iterate through table columns
	set columns_sql "
		select	lower(column_name) as column_name
		from	user_tab_columns
		where	lower(table_name) = lower(:table_name)
	"
	db_foreach columns $columns_sql {
	    if {[lsearch $selected_columns $column_name] >= 0} { 
		ns_log Notice "im_rest_object_type_select_sql: found ambiguous field: $table_name.$column_name"
		continue 
	    }
	    lappend selects "$letter.$column_name"
	    lappend selected_columns $column_name

	    # Check for dereferencing function
	    set key [string tolower "$table_name-$column_name"]
	    if {[info exists dynfield_hash($key)]} {
		set deref_function $dynfield_hash($key)
		lappend selects "${deref_function}($letter.$column_name) as ${column_name}_deref"
		lappend selected_columns ${column_name}_deref
	    }
	}

	lappend selected_tables $table_name
	incr cnt
    }

    set acs_object_deref_sql "im_name_from_user_id(o.creation_user) as creation_user_deref,"
    if {!$deref_p} { set acs_object_deref_sql "" }

    set sql "
	select	o.*,
		o.object_id as rest_oid,
		$acs_object_deref_sql
		acs_object__name(o.object_id) as object_name,
		[join $selects ",\n\t\t"]
	from	acs_objects o
		[join $froms "\n\t\t"]
    "
    if {!$no_where_clause_p} { append sql "
	where	o.object_id = :rest_oid
    "}

    return $sql
}


ad_proc -public im_rest_object_type_columns { 
    {-deref_p 0}
    {-include_acs_objects_p 1}
    -rest_otype:required
} {
    Returns a list of all columns for a given object type.
} {
    set super_types [im_object_super_types -object_type $rest_otype]
    if {!$include_acs_objects_p} {
	# Exclude base tables if not necessary
	set super_types [lsearch -inline -all -not -exact $super_types acs_object]
	set super_types [lsearch -inline -all -not -exact $super_types im_biz_object]
    }

    # Get a list of dereferencing functions
    if {$deref_p} {
	array set dynfield_hash [im_rest_deref_plpgsql_functions -rest_otype $rest_otype]
    }

    # ---------------------------------------------------------------
    # Construct a SQL that pulls out all tables for an object type,
    # plus all table columns via user_tab_colums.
    set columns_sql "
	select distinct
		lower(utc.column_name) as column_name,
		lower(utc.table_name) as table_name
	from
		user_tab_columns utc
	where
		(-- check the main tables for all object types
		lower(utc.table_name) in (
			select	lower(table_name)
			from	acs_object_types
			where	object_type in ('[join $super_types "', '"]')
		) OR
		-- check the extension tables for all object types
		lower(utc.table_name) in (
			select	lower(table_name)
			from	acs_object_type_tables
			where	object_type in ('[join $super_types "', '"]')
		)) and
		-- avoid returning 'format' because format=json is part of every query
		lower(utc.column_name) not in ('format', 'rule_engine_old_value')
    "

    set columns [list]
    db_foreach columns $columns_sql {
	lappend columns $column_name
	set key "$table_name-$column_name"
	if {[info exists dynfield_hash($key)]} {
	    lappend columns ${column_name}_deref
	}
    }
    return $columns
}



ad_proc -public im_rest_object_type_index_columns { 
    -rest_otype:required
} {
    Returns a list of all "index columns" for a given object type.
    The index columns are the primary key columns of the object
    types's tables. They will all contains the same object_id of
    the object.
} {
    # ---------------------------------------------------------------
    # Construct a SQL that pulls out all tables for an object type,
    # plus all table columns via user_tab_colums.
    set index_columns_sql "
	select	id_column
	from	acs_object_type_tables
	where	object_type = :rest_otype
    UNION
	select	id_column
	from	acs_object_types
	where	object_type = :rest_otype
    UNION
	select	'rest_oid'
    "

    return [db_list index_columns $index_columns_sql]
}




ad_proc -public im_rest_object_type_subtypes { 
    -rest_otype:required
} {
    Returns a list of all object types equal or below
    rest_otype (including rest_otype).
} {
    set breach_p [im_security_alert_check_alphanum -location "im_rest_object_type_subtypes" -value $rest_otype]
    # Return a save value to calling procedure
    if {$breach_p} { return $rest_otype }

    set sub_type_sql "
	select	sub.object_type
	from	acs_object_types ot, 
		acs_object_types sub
	where	ot.object_type = '$rest_otype' and 
		sub.tree_sortkey between ot.tree_sortkey and tree_right(ot.tree_sortkey)
	order by sub.tree_sortkey
    "

    return [util_memoize [list db_list sub_types $sub_type_sql] 3600000]
}



# ----------------------------------------------------------------------
# Update all tables of an object type.
# ----------------------------------------------------------------------

ad_proc -public im_rest_object_type_update_sql { 
    { -format "json" }
    -rest_otype:required
    -rest_oid:required
    -hash_array:required
} {
    Updates all the object's tables with the information from the
    hash array.
} {
    ns_log Notice "im_rest_object_type_update_sql: format=$format, rest_otype=$rest_otype, rest_oid=$rest_oid, hash_array=$hash_array"

    # Stuff the list of variables into a hash
    array set hash $hash_array

    # ---------------------------------------------------------------
    # Get all relevant tables for the object type
    set tables_sql "
			select	table_name,
				id_column
			from	acs_object_types
			where	object_type = :rest_otype
		    UNION
			select	table_name,
				id_column
			from	acs_object_type_tables
			where	object_type = :rest_otype
    "
    db_foreach tables $tables_sql {
	set index_column($table_name) $id_column
	set index_column($id_column) $id_column
    }

    set columns_sql "
	select	lower(utc.column_name) as column_name,
		lower(utc.table_name) as table_name
	from
		user_tab_columns utc,
		($tables_sql) tables
	where
		lower(utc.table_name) = lower(tables.table_name)
	order by
		lower(utc.table_name),
		lower(utc.column_name)
    "

    array unset sql_hash
    db_foreach cols $columns_sql {

	# Skip variables that are not available in the var hash
	if {![info exists hash($column_name)]} { continue }

	# Skip index columns
	if {[info exists index_column($column_name)]} { continue }

	# skip tree_sortkey stuff
	if {"tree_sortkey" == $column_name} { continue }
	if {"max_child_sortkey" == $column_name} { continue }

	# ignore reserved variables
	if {"rest_otype" == $column_name} { contiue }
	if {"rest_oid" == $column_name} { contiue }
	if {"hash_array" == $column_name} { contiue }

	# ignore any "*_cache" variables (financial cache)
	if {[regexp {_cache$} $column_name match]} { continue }

	# Start putting together the SQL
	set sqls [list]
	if {[info exists sql_hash($table_name)]} { set sqls $sql_hash($table_name) }
	lappend sqls "$column_name = :$column_name"
	set sql_hash($table_name) $sqls
    }

    # Add the rest_oid to the hash
    set hash(rest_oid) $rest_oid

    ns_log Notice "im_rest_object_type_update_sql: [array get sql_hash]"

    foreach table [array names sql_hash] {
	ns_log Notice "im_rest_object_type_update_sql: Going to update table '$table'"
	set sqls $sql_hash($table)
	set update_sql "update $table set [join $sqls ", "] where $index_column($table) = :rest_oid"

	if {[catch {
	    db_dml sql_$table $update_sql -bind [array get hash]
	} err_msg]} {
	    return [im_rest_error -format $format -http_status 404 -message "Error updating $rest_otype: '$err_msg'"]
	}
    }

    # Audit the action
    im_audit -action after_update -object_id $rest_oid

    ns_log Notice "im_rest_object_type_update_sql: returning"
    return
}


# ----------------------------------------------------------------------
# Error Handling
# ----------------------------------------------------------------------

ad_proc -public im_rest_error {
    { -http_status 404 }
    { -format "json" }
    { -message "" }
} {
    Returns a suitable REST error message
} {
    ns_log Notice "im_rest_error: http_status=$http_status, format=$format, message=$message"
    set url [im_url_with_query]

    switch $http_status {
	200 { set status_message "OK: Success!" }
	304 { set status_message "Not Modified: There was no new data to return." }
	400 { set status_message "Bad Request: The request was invalid. An accompanying error message will explain why." }
	401 { set status_message "Not Authorized: Authentication credentials were missing or incorrect." }
	403 { set status_message "Forbidden: The request is understood, but it has been refused.  An accompanying error message will explain why." }
	404 { set status_message "Not Found: The URI requested is invalid or the resource requested, for example a non-existing project." }
	406 { set status_message "Not Acceptable: Returned when an invalid format is specified in the request." }
	500 { set status_message "Internal Server Error: Something is broken.  Please post to the &\#93;project-open&\#91; Open Discussions forum." }
	502 { set status_message "Bad Gateway: project-open is probably down." }
	503 { set status_message "Service Unavailable: project-open is up, but overloaded with requests. Try again later." }
	default { set status_message "Unknown http_status '$http_status'." }
    }

    set page_title [lindex [split $status_message ":"] 0]

    switch $format {
	html { 
	    doc_return 200 "text/html" "
		[im_header $page_title [im_rest_header_extra_stuff]][im_navbar]
		<p>$status_message</p>
		<pre>[ns_quotehtml $message]</pre>
		[im_footer]
	    " 
	}
	json {  
	    set result "{\"success\": false,\n\"message\": \"[im_quotejson $message]\"\n}"
	    doc_return 200 "application/json" $result
	}
	default {
	     ad_return_complaint 1 "Invalid format1: '$format'"
	}
    }

    ad_script_abort
}


ad_proc -public im_rest_get_content {} {
    There's no [ns_conn content] so this is a hack to get the content of the REST request. 
    @return string - the request
    @author Dave Bauer
} {
    # (taken from aol30/modules/tcl/form.tcl)
    # Spool content into a temporary read/write file.
    # ns_openexcl can fail, since tmpnam is known not to
    # be thread/process safe.  Hence spin till success
    set fp ""
    while {$fp eq ""} {
        set filename "[ad_tmpnam][clock clicks -milliseconds].rpc2"
        set fp [ns_openexcl $filename]
    }

    fconfigure $fp -translation binary
    ns_conncptofp $fp
    close $fp

    set fp [open $filename r]
    while {![eof $fp]} {
        append text [read $fp]
    }
    close $fp
    file delete $filename
    # ns_unlink $filename     #; deprecated
    return $text
}

ad_proc -public im_rest_parse_json_content {
    { -format "" }
    { -content "" }
    { -rest_otype "" }
} {
    Parse the JSON content of a POST request with 
    the values of the object to create or update.
    @author Frank Bergmann
} {
    # Parse the HTTP content
    switch $format {
	json {
	    ns_log Notice "im_rest_parse_json_content: going to parse json content=$content"
	    # {"id":8799,"email":"bbigboss@tigerpond.com","first_names":"Ben","last_name":"Bigboss"}
	    array set parsed_json [util::json::parse $content]
	    set json_list $parsed_json(_object_)
	    array set hash_array $json_list

	    # ToDo: Modify the JSON Parser to return NULL values as "" (TCL NULL) instead of "null"
	    foreach var [array names hash_array] {
		set val $hash_array($var)
		if {"null" == $val} { set hash_array($var) "" }
	    }
	}
	default {
	    return [im_rest_error -http_status 406 -message "Unknown format: '$format'. Expected: {json}"]
	}
    }
    return [array get hash_array]
}

ad_proc -public im_rest_normalize_timestamp { date_string } {
    Reformat JavaScript date/timestamp format to suit PostgreSQL 8.4/9.x
    @author Frank Bergmann
} {
    set str $date_string

    # Cut off the GMT+0200... when using long format
    # Wed Jul 23 2014 19:23:26 GMT+0200 (Romance Daylight Time)
    if {[regexp {^(.*?)GMT\+} $str match val]} {
	set str $val
    }

    return $str
}


ad_proc -public im_quotejson { str } {
    Quote a JSON string. In particular this means escaping
    single and double quotes, as well as new lines, tabs etc.
    @author Frank Bergmann
} {
    regsub -all {\\} $str {\\\\} str
    regsub -all {"} $str {\"} str
    regsub -all {\n} $str {\\n} str
    regsub -all {\t} $str {\\t} str
    return $str
}


