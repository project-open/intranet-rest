# /packages/intranet-rest/www/data-source/project-trask-tree-update.tcl
#
# Copyright (C) 2013 ]project-open[

ad_page_contract {
    Recieves a POST request from Sencha for an update
    of in-line editing a TreeGrid
    @author frank.bergmann@project-open.com
} {
    {debug_p 0}
}



# ---------------------------------------------------------------
# Security
# ---------------------------------------------------------------

# Check that the current_user_id has write permissions to the project
set current_user_id [ad_maybe_redirect_for_registration]


# ---------------------------------------------------------------
# Extract parameters
# Parameters may be send via the URL (project_id=...) or via JSON
# ---------------------------------------------------------------

# Parse the URL line for variables
set query_string [ns_conn query]
set tuple_list [split $query_string "&"]
foreach tuple $tuple_list {
    if {[regexp {^([^=]+)\=(.*)} $tuple match var value]} {
	set var_hash($var) $value
	ns_log Notice "project-trask-tree-update: $var=$value"
    }
}

# Parse the JSON POST data
set post_content [ns_conn content]
array set json_hash [util::json::parse $post_content]
ns_log Notice "project-trask-tree-update: json_hash=[array get json_hash]"

# ---------------------------------------------------------------
# Procedure to update a task
# ---------------------------------------------------------------

ad_proc im_rest_project_task_tree_update {
    -var_hash_list
} {
    Update a single task based on the values from var_hash
} {
    ns_log Notice "project-trask-tree-update: im_rest_project_task_tree_update: var_hash_list=$var_hash_list"
    set current_user_id [ad_get_user_id]
    array set var_hash $var_hash_list
    
    # Get the project/task_id
    set project_id ""
    if {[info exists var_hash(project_id)] && "" != $var_hash(project_id)} { set project_id $var_hash(project_id) }
    if {[info exists var_hash(task_id)] && "" != $var_hash(task_id)} { set project_id $var_hash(task_id) }
    if {[info exists var_hash(id)] && "" != $var_hash(id)} { set project_id $var_hash(id) }
    if {"" == $project_id} {
	doc_return 200 "text/plain" "{success:false, message:'Undefined task_id or roject_id in POST data: [array get var_hash]'}"
	ad_script_abort
    }

    set object_type [util_memoize [list db_string otype "select object_type from acs_objects where object_id = $project_id"]]
    ${object_type}_permissions $current_user_id $project_id view read write admin
    if {!$write} {
	doc_return 200 "text/plain" "{success:false, message: 'No permissions to write project_id=$project_id for user=$current_user_id'}"
	ad_script_abort
    }

    im_rest_object_type_update_sql \
	-format "json" \
	-rest_otype "im_timesheet_task" \
	-rest_oid $project_id \
	-hash_array $var_hash_list
}


# ---------------------------------------------------------------
# Check for single or multiple updates
# ---------------------------------------------------------------

if {[info exists json_hash(_object_)]} {
    set json_list $json_hash(_object_)
    ns_log Notice "project-trask-tree-update: object: json_list=$json_list"
    im_rest_project_task_tree_update -var_hash_list $json_list
}

if {[info exists json_hash(_array_)]} {
    set json_array $json_hash(_array_)
    ns_log Notice "project-trask-tree-update: array=$json_array"
    foreach array_elem $json_array {
	ns_log Notice "project-trask-tree-update: array_elem=$array_elem"
	set obj [lindex $array_elem 0]
	set json_list [lindex $array_elem 1]
	ns_log Notice "project-trask-tree-update: decomposing array_elem: $obj=$json_list"

	im_rest_project_task_tree_update -var_hash_list $json_list
    }
}


# ---------------------------------------------------------------
# Return a success JSON
# ---------------------------------------------------------------

doc_return 200 "text/plain" "\{success:true, message: 'Successfully updated task(s)'\}"
