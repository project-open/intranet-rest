# /packages/intranet-rest/www/data-source/project-trask-tree-update.tcl
#
# Copyright (C) 2013 ]project-open[

ad_page_contract {
    Recieves a POST request from Sencha for an update
    of in-line editing a TreeGrid
    @param project_id The project
    @author frank.bergmann@project-open.com
} {
    {debug_p 0}
}


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
# ns_log Notice "project-trask-tree-update: json_content=[array get json_hash]"
set json_list $json_hash(_object_);
# ns_log Notice "project-trask-tree-update: json_list=$json_list"
array set json_var_hash $json_list
foreach var [array names json_var_hash] {
    set value $json_var_hash($var)
    set var_hash($var) $value
    ns_log Notice "project-trask-tree-update: $var=$value"
}

# Check that there was a task_id variable
if {![info exists var_hash(task_id)]} {
    doc_return 200 "text/plain" "{success:false, message:'Undefined task_id in URL'}"
    ad_script_abort
}

# ---------------------------------------------------------------
# Security
# ---------------------------------------------------------------

# Check that the current_user_id has write permissions to the project
set current_user_id [ad_maybe_redirect_for_registration]
set task_id $var_hash(task_id)
im_security_alert_check_integer -location "/sencha-task-editor/treegrid-update.tcl: task_id" -value $task_id
im_timesheet_task_permissions $current_user_id $task_id view read write admin
if {!$write} {
    doc_return 200 "text/plain" "{success:false, message: 'No permissions to read task_id=$task_id for user=$current_user_id'}"
    ad_script_abort
}

# ---------------------------------------------------------------
# Perform the update
# ---------------------------------------------------------------



# ---------------------------------------------------------------
# Return a success JSON
# ---------------------------------------------------------------

doc_return 200 "text/plain" "\{success:true, message: 'Successfully updated task'\}"
