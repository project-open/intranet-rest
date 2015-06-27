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



# ---------------------------------------------------------------
# Task-Tree: Create and update tasks based on Procedure to update a task
# ---------------------------------------------------------------

ad_proc im_rest_project_task_tree_action {
    { -action "" }
    -var_hash_list:required
} {
    Create, Update or Delete a task coming from TreeStore
} {
    ns_log Notice "im_rest_project_task_tree_action: var_hash_list=$var_hash_list"
    set current_user_id [ad_get_user_id]
    array set var_hash $var_hash_list

    # Get the project/task_id
    set project_id ""
    if {[info exists var_hash(project_id)] && "" != $var_hash(project_id)} { set project_id $var_hash(project_id) }
    if {[info exists var_hash(task_id)] && "" != $var_hash(task_id)} { set project_id $var_hash(task_id) }
    if {[info exists var_hash(id)] && "" != $var_hash(id)} { set project_id $var_hash(id) }

    switch $action {
	update { im_rest_project_task_tree_update -project_id $project_id -var_hash_list $var_hash_list	}
	create { im_rest_project_task_tree_create -project_id $project_id -var_hash_list $var_hash_list	}
	delete { im_rest_project_task_tree_delete -project_id $project_id -var_hash_list $var_hash_list	}
	default {
	    doc_return 200 "text/plain" "{success:false, message: 'tree_action: found invalid action=$action'}"
	}
    }
    # The calling procedure will return a suitable JSON success message
}

ad_proc im_rest_project_task_tree_update {
    -project_id:required
    -var_hash_list:required
} {
    Update a task coming from TreeStore
} {
    ns_log Notice "im_rest_project_task_tree_update: project_id=$project_id, var_hash_list=$var_hash_list"
    set current_user_id [ad_get_user_id]
    array set var_hash $var_hash_list

    if {"" == $project_id} {
	doc_return 200 "text/plain" "{success:false, message: 'Update failed because we did not find project_id in JSON data: $var_hash_list'}"
	return
    }
    
    # project_id exists - update the existing task
    set object_type [util_memoize [list db_string otype "select object_type from acs_objects where object_id = $project_id"]]
    ${object_type}_permissions $current_user_id $project_id view read write admin
    if {!$write} {
	doc_return 200 "text/plain" "{success:false, message: 'No permissions to write project_id=$project_id for user=$current_user_id'}"
	ad_script_abort
    }

    # Update the main project fields via a generic REST routine
    im_rest_object_type_update_sql \
	-format "json" \
	-rest_otype "im_timesheet_task" \
	-rest_oid $project_id \
	-hash_array $var_hash_list

    # Update assignments
    im_rest_project_task_tree_assignments -project_id $project_id -var_hash_list $var_hash_list
}



ad_proc im_rest_project_task_tree_delete {
    -project_id:required
    -var_hash_list:required
} {
    Delete a task coming from TreeStore
} {
    ns_log Notice "im_rest_project_task_tree_delete: project_id=$project_id, var_hash_list=$var_hash_list"
    set current_user_id [ad_get_user_id]
    array set var_hash $var_hash_list

    if {"" == $project_id} {
	doc_return 200 "text/plain" "{success:false, message: 'Delete failed because we did not find project_id in JSON data: $var_hash_list'}"
	return
    }
    
    # project_id exists - update the existing task
    set object_type [util_memoize [list db_string otype "select object_type from acs_objects where object_id = $project_id"]]
    ${object_type}_permissions $current_user_id $project_id view read write admin
    if {!$admin} {
	doc_return 200 "text/plain" "{success:false, message: 'No permissions to admin project_id=$project_id for user=$current_user_id'}"
	ad_script_abort
    }

    im_rest_delete_object \
	-format "json" \
	-rest_user_id $current_user_id \
	-rest_otype $object_type \
	-rest_oid $project_id \
	-query_hash_pairs $var_hash_list
}



ad_proc im_rest_project_task_tree_create {
    -project_id:required
    -var_hash_list:required
} {
    Create a new task coming from TreeStore
} {
    ns_log Notice "im_rest_project_task_tree_create: project_id=$project_id, var_hash_list=$var_hash_list"
    set current_user_id [ad_get_user_id]
    array set var_hash $var_hash_list

    # No project_id!
    if {"" != $project_id} {
	doc_return 200 "text/plain" "{success:false, message: 'Create failed, object already contains project_id=$project_id in JSON data: $var_hash_list'}"
	return
    }

    set parent_id ""
    if {[info exists var_hash(parent_id)]} { set parent_id $var_hash(parent_id) }
    if {"" == $parent_id} {
	doc_return 200 "text/plain" "{success:false, message: 'Create failed, no parent_id specified for new task in post data: $var_hash_list'}"
	ad_script_abort
    }
    
    set parent_object_type [util_memoize [list db_string otype "select object_type from acs_objects where object_id = $parent_id"]]
    ${parent_object_type}_permissions $current_user_id $parent_id view read write admin
    if {!$write} {
	doc_return 200 "text/plain" "{success:false, message: 'No permissions to write to parent_id=$parent_id for user=$current_user_id'}"
	ad_script_abort
    }

    set project_id [im_rest_post_object_type_im_timesheet_task \
			-format "json" \
			-rest_user_id $current_user_id \
			-rest_otype "im_timesheet_task" \
			-rest_otype_pretty "Timesheet Task" \
			-hash_array_list $var_hash_list]

    # Update assignments
    im_rest_project_task_tree_assignments -project_id $project_id -var_hash_list $var_hash_list
}


ad_proc im_rest_project_task_tree_assignments {
    -project_id:required
    -var_hash_list:required
} {
    Update the resource assignments to the task
} {
    ns_log Notice "im_rest_project_task_tree_assignments: project_id=$project_id, var_hash_list=$var_hash_list"
    array set var_hash $var_hash_list
   
    # Update task assignments
    set assignees $var_hash(assignees)
    ns_log Notice "im_rest_project_task_tree_assignments: assignees=$assignees"
    set assignee_list [lindex $assignees 1]
    foreach assignee_object $assignee_list {
	set object_hash_list [lindex $assignee_object 1]
	ns_log Notice "im_rest_project_task_tree_assignments: object_hash=$object_hash_list"
	array unset object_hash
	array set object_hash $object_hash_list
	set user_id $object_hash(user_id)
	set percent $object_hash(percent)

	# Add the dude to the project and update percentage
	set rel_id [im_biz_object_add_role $user_id $project_id [im_biz_object_role_full_member]]
	db_dml update_assignation "update im_biz_object_members set percentage = :percent where rel_id = :rel_id"
	ns_log Notice "im_rest_project_task_tree_assignments: rel_id=$rel_id"
    }
}


# -------------------------------------------------------
# 
# -------------------------------------------------------

