# /packages/intranet-rest/www/data-source/project-trask-tree-action.tcl
#
# Copyright (C) 2013 ]project-open[


#ad_page_contract {
#    Recieves a POST request from Sencha for an update
#    of in-line editing a TreeGrid
#    @author frank.bergmann@project-open.com
#} {
#    {debug_p 0}
#}

set debug_p 0

# ---------------------------------------------------------------
# 
# ---------------------------------------------------------------

# Check that the user is logged in
set current_user_id [auth::require_login]
ns_log Notice "project-task-tree-action: query_hash_pairs=$query_hash_pairs"

array set var_hash $query_hash_pairs
set action $var_hash(action)

# Default values for JSON return message
set success "true"
set message "Successfully performed action=$action"

if {[catch {

    # Parse the JSON POST data
    set post_content [ns_conn content]
    array set json_hash [util::json::parse $post_content]
    ns_log Notice "project-task-tree-action: json_hash=[array get json_hash]"
    
    # ---------------------------------------------------------------
    # Check for single update
    # ---------------------------------------------------------------
    
    if {[info exists json_hash(_object_)]} {
	set json_list $json_hash(_object_)
	ns_log Notice "project-task-tree-action: object: json_list=$json_list"
	im_rest_project_task_tree_action -pass 1 -action $action -var_hash_list $json_list
	im_rest_project_task_tree_action -pass 2 -action $action -var_hash_list $json_list
    }

    # ---------------------------------------------------------------
    # Check for multiple updates
    # ---------------------------------------------------------------
    
    if {[info exists json_hash(_array_)]} {
	set json_array $json_hash(_array_)
	
	ns_log Notice "project-task-tree-action: pass=1, array=$json_array"
	foreach array_elem $json_array {
	    ns_log Notice "project-task-tree-action: pass=1, array_elem=$array_elem"
	    set obj [lindex $array_elem 0]
	    set json_list [lindex $array_elem 1]
	    ns_log Notice "project-task-tree-action: pass=1, decomposing array_elem: $obj=$json_list"
	    im_rest_project_task_tree_action -pass 1 -action $action -var_hash_list $json_list
	}
	
	ns_log Notice "project-task-tree-action: pass=2, array=$json_array"
	foreach array_elem $json_array {
	    ns_log Notice "project-task-tree-action: pass=2, array_elem=$array_elem"
	    set obj [lindex $array_elem 0]
	    set json_list [lindex $array_elem 1]
	    ns_log Notice "project-task-tree-action: pass=2, decomposing array_elem: $obj=$json_list"
	    im_rest_project_task_tree_action -pass 2 -action $action -var_hash_list $json_list
	}
    }

} err_msg]} {

    ns_log Error "project-task-tree-action: Reporting back error: [ad_print_stack_trace]"
    set success "false"
    set message [im_rest_error -format json -http_status 404 -message "Internal Error: [ad_print_stack_trace]"]

}
