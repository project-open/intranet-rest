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
    { -pass 0}
    { -action "" }
    -var_hash_list:required
} {
    Create, Update or Delete a task coming from TreeStore
    @param pass: 0:all actions, 1: create/update only, 2: dependencies only
    @return 0 if everything OK, 1 if we need to repeat
} {
    ns_log Notice "im_rest_project_task_tree_action: pass=$pass, var_hash_list=$var_hash_list"
    set current_user_id [ad_conn user_id]
    array set var_hash $var_hash_list

    # Handle issues with "true" or "false" in milestone_p breaking the DB char(1) data-type
    if {[info exists var_hash(milestone_p)]} { set var_hash(milestone_p) [string range $var_hash(milestone_p) 0 0] }

    # Ignore the root of the tree that might be send by the Sencha side
    set id ""
    if {[info exists var_hash(id)]} { set id $var_hash(id) }
    if {"root" == $id} { return; }

    # Check the project_id/task_id
    set project_id ""
    if {[info exists var_hash(project_id)] && "" != $var_hash(project_id)} { set project_id $var_hash(project_id) }
    if {[info exists var_hash(task_id)] && "" != $var_hash(task_id)} { set project_id $var_hash(task_id) }
    if {[info exists var_hash(id)] && "" != $var_hash(id)} { set project_id $var_hash(id) }

    # Check if parent_id exists. All tasks should have a parent_id. Otherwise it's the main project.
    set parent_id ""
    if {[info exists var_hash(parent_id)]} { set parent_id $var_hash(parent_id) }
    set parent_id_exists_p [db_string parent_exists "select count(*) from im_projects where project_id = :parent_id"]
    ns_log Notice "im_rest_project_task_tree_action: parent_id=$parent_id, exists=$parent_id_exists_p, pass=$pass, var_hash_list=$var_hash_list"
    if {"" ne $parent_id && !$parent_id_exists_p} { 
	ns_log Notice "im_rest_project_task_tree_action: parent_id=$parent_id does not yet exist in the DB, looping:\npass=$pass, var_hash_list=$var_hash_list"
	return 1
    }

    switch $action {
	update { im_rest_project_task_tree_update -pass $pass -project_id $project_id -var_hash_list [array get var_hash] }
	create { im_rest_project_task_tree_create -pass $pass -project_id $project_id -var_hash_list [array get var_hash] }
	delete { im_rest_project_task_tree_delete -pass $pass -project_id $project_id -var_hash_list [array get var_hash] }
	default {
	    doc_return 200 "text/plain" "{success:false, message: 'tree_action: found invalid action=[im_quotejson $action]'}"
	    return
	}
    }
    # The calling procedure will return a suitable JSON success message
}

ad_proc im_rest_project_task_tree_update {
    {-pass 0}
    -project_id:required
    -var_hash_list:required
} {
    Update a task coming from TreeStore
    @param pass: 0:all actions, 1: create/update only, 2: dependencies only
} {
    ns_log Notice "im_rest_project_task_tree_update: pass=$pass, project_id=$project_id, var_hash_list=$var_hash_list"
    set current_user_id [ad_conn user_id]
    array set var_hash $var_hash_list

    if {"" == $project_id} {
	doc_return 200 "text/plain" "{success:false, message: 'Did not find project_id in JSON data: [im_quotejson $var_hash_list]'}"
	return
    }

    # project_id exists - update the existing task
    set object_type [db_string otype "select object_type from acs_objects where object_id = $project_id" -default ""]
    if {"" == $object_type} {
	# task doesn't exist yet - so this is a "create" instead of an "update" action
	ns_log Notice "im_rest_project_task_tree_update: pass=$pass, project_id=$project_id: Didn't find project - redirecting to 'create' action"
	set result [im_rest_project_task_tree_create -pass $pass -project_id $project_id -var_hash_list $var_hash_list]
	return $result
    }

    ${object_type}_permissions $current_user_id $project_id view read write admin
    if {!$write} {
	doc_return 200 "text/plain" "{success:false, message: 'User #$current_user_id ([im_name_from_user_id $current_user_id]) has not enough permissions<br>
        to modify task or project #$project_id ([acs_object_name $project_id])'}"
	return
    }

    # Update the main project fields via a generic REST routine
    if {0 eq $pass || 1 eq $pass} {
	im_rest_object_type_update_sql \
	    -format "json" \
	    -rest_otype "im_timesheet_task" \
	    -rest_oid $project_id \
	    -hash_array $var_hash_list
    }
    
    # Update assignees
    im_rest_project_task_tree_assignees -project_id $project_id -var_hash_list $var_hash_list

    # Update predecessors
    if {0 eq $pass || 2 eq $pass} {
	if {[info exists var_hash(predecessors)]} {
	    im_rest_project_task_tree_predecessors -project_id $project_id -var_hash_list $var_hash_list
	}
    }

}



ad_proc im_rest_project_task_tree_delete {
    {-pass 0}
    -project_id:required
    -var_hash_list:required
} {
    Delete a task coming from TreeStore
} {
    ns_log Notice "im_rest_project_task_tree_delete: pass=$pass, project_id=$project_id, var_hash_list=$var_hash_list"
    set current_user_id [ad_conn user_id]
    array set var_hash $var_hash_list

    if {"" == $project_id} {
	doc_return 200 "text/plain" "{success:false, message: \"Delete failed because we did not find project_id in JSON data: [im_quotejson $var_hash_list]\"}"
	return
    }
    
    # project_id exists - update the existing task
    set object_type [util_memoize [list db_string otype "select object_type from acs_objects where object_id = $project_id" -default ""]]
    if {"" eq $object_type} { return }; # Delete object before it really was created. Kind of OK...
    ${object_type}_permissions $current_user_id $project_id view read write admin
    if {!$admin} {
	doc_return 200 "text/plain" "{success:false, message: \"No permissions to admin project_id=$project_id for user=$current_user_id\"}"
	return
    }

    if {2 eq $pass} {

	set parent_id [db_string task_parent_id "select parent_id from im_projects where project_id = :project_id" -default ""]
	# Found the main project. We don't want to delete this project.
	if {"" == $parent_id} { continue }
	# Nuke including timesheet costs logged, task dependencies etc
	ns_log Notice "im_rest_project_task_tree_delete: before 'im_project_nuke $project_id'"
	set err_msg [im_project_nuke $project_id]

	if {"" ne $err_msg} {
	    doc_return 200 "text/plain" "{success:false, message: \"[im_quotejson $err_msg]\"}"
	    return
	}

    }
}



ad_proc im_rest_project_task_tree_create {
    {-pass 0}
    -project_id:required
    -var_hash_list:required
} {
    Create a new task coming from TreeStore
    @param pass: 0:all actions, 1: create/update only, 2: dependencies only
} {
    ns_log Notice "im_rest_project_task_tree_create: pass=$pass, project_id=$project_id, var_hash_list=$var_hash_list"
    set current_user_id [ad_conn user_id]
    array set var_hash $var_hash_list

    # No project_id!
    if {"" != $project_id && [db_string exists_p "select count(*) from im_projects where project_id=:project_id"]} {
	doc_return 200 "text/plain" "{success:false, message: 'Create failed, project_id=$project_id already exists. JSON data: [im_quotejson $var_hash_list]'}"
	return
    }

    set parent_id ""
    if {[info exists var_hash(parent_id)]} { set parent_id $var_hash(parent_id) }
    if {"" == $parent_id} {
	doc_return 200 "text/plain" "{success:false, message: 'Create failed, no parent_id specified for new task in post data: [im_quotejson $var_hash_list]'}"
	return
    }
    
    set parent_object_type [util_memoize [list db_string otype "select object_type from acs_objects where object_id = $parent_id"]]
    ${parent_object_type}_permissions $current_user_id $parent_id view read write admin
    if {!$write} {
	doc_return 200 "text/plain" "{success:false, message: 'No permissions to write to parent_id=$parent_id for user=$current_user_id'}"
	return
    }

    # ToDo: What does this call return, do we need to check the result?
    if {0 eq $pass || 1 eq $pass} {
	im_rest_post_object_type_im_timesheet_task \
			-format "json" \
			-rest_user_id $current_user_id \
			-rest_oid $project_id \
			-rest_otype "im_timesheet_task" \
			-rest_otype_pretty "Gantt Task" \
			-hash_array_list $var_hash_list
    }

    # Update assignees
    if {[info exists var_hash(assignees)]} {
	im_rest_project_task_tree_assignees -project_id $project_id -var_hash_list $var_hash_list
    }

    # Update predecessors on passes 0 or 2
    if {0 eq $pass || 2 eq $pass} {
	if {[info exists var_hash(predecessors)]} {
	    im_rest_project_task_tree_predecessors -project_id $project_id -var_hash_list $var_hash_list
	}
    }
}


# -------------------------------------------------------
# Update/Store assignees and predecessors
# -------------------------------------------------------


ad_proc im_rest_project_task_tree_assignees {
    -project_id:required
    -var_hash_list:required
} {
    Update the resource assignees to the task
} {
    ns_log Notice "im_rest_project_task_tree_assignees: project_id=$project_id, var_hash_list=$var_hash_list"
    array set var_hash $var_hash_list
   
    # Update task assignees
    set assignees $var_hash(assignees)
    ns_log Notice "im_rest_project_task_tree_assignees: assignees=$assignees"
    set assignee_list [lindex $assignees 1]
    set assignee_user_ids [list]
    foreach assignee_object $assignee_list {
	set object_hash_list [lindex $assignee_object 1]
	ns_log Notice "im_rest_project_task_tree_assignees: object_hash=$object_hash_list"
	array unset object_hash
	array set object_hash $object_hash_list
	set user_id $object_hash(user_id)
	set percent $object_hash(percent)
	lappend assignee_user_ids $user_id

	# Add the dude to the project and update percentage
	set rel_id [im_biz_object_add_role $user_id $project_id [im_biz_object_role_full_member]]
	db_dml update_assignation "update im_biz_object_members set percentage = :percent where rel_id = :rel_id"
	ns_log Notice "im_rest_project_task_tree_assignees: rel_id=$rel_id"
    }

    # Delete assignees that are not in the list anymore
    set db_assigned_user_ids [db_list db_assig "select object_id_two from acs_rels where rel_type = 'im_biz_object_member' and object_id_one = :project_id"]
    ns_log Notice "im_rest_project_task_tree_assignees: db_assigned_user_ids=$db_assigned_user_ids"
    foreach db_uid $db_assigned_user_ids {
	if {[lsearch $assignee_user_ids $db_uid] < 0} {
	    # The db_uid is still available in the DB, but not in the new data: delete it!
	    ns_log Notice "im_rest_project_task_tree_assignees: found user_id=$db_uid assigned in the DB, but not in the new data - deleting"
	    db_string del_rel "select im_biz_object_member__delete(:project_id, :db_uid) from dual"
	}
    }
}



# ToDo: Delete dependencies!?!

ad_proc im_rest_project_task_tree_predecessors {
    -project_id:required
    -var_hash_list:required
} {
    Update the resource predecessors to the task
} {
    ns_log Notice "im_rest_project_task_tree_predecessors: project_id=$project_id, var_hash_list=$var_hash_list"
    array set var_hash $var_hash_list

    # Update task predecessors
    set pred_list [list 0]
    set predecessors $var_hash(predecessors)
    ns_log Notice "im_rest_project_task_tree_predecessors: predecessors=$predecessors"
    set predecessor_list [lindex $predecessors 1]
    foreach predecessor_object $predecessor_list {
	set object_hash_list [lindex $predecessor_object 1]
	ns_log Notice "im_rest_project_task_tree_predecessors: object_hash=$object_hash_list"
	array unset object_hash
	array set object_hash $object_hash_list
	set pred_id $object_hash(pred_id)
	set succ_id $object_hash(succ_id)
	set type_id $object_hash(type_id)
	set diff $object_hash(diff)

	# Create a list of all predecessor tasks
	lappend pred_list $pred_id

	# Check if the dependency already exists
	set dependency_id [db_string dep_id "
		select	dependency_id
		from	im_timesheet_task_dependencies
		where	task_id_two = :pred_id and
			task_id_one = :succ_id
	" -default ""]

	if {"" eq $dependency_id} {
	    ns_log Notice "im_rest_project_task_tree_predecessors: dependency_id does not exist - create new dependency"
	    # Add the dude
	    set insert_sql "
		insert into im_timesheet_task_dependencies (
			task_id_two, task_id_one, dependency_type_id, difference
		) values (
			:pred_id, :succ_id, :type_id, :diff
		)
	    "
	    db_dml dep_insert $insert_sql
	} else {
	    ns_log Notice "im_rest_project_task_tree_predecessors: dependency_id=$dependency_id already exists - updating"
	    # Update the dude
	    set update_sql "
		update im_timesheet_task_dependencies set
			difference = :diff,
			dependency_type_id = :type_id
		where	task_id_two = :pred_id and
			task_id_one = :succ_id
	    "
	    db_dml dep_update $update_sql
	}
    }

    # Get the list of all predecessors in the DB that are not preds anymore
    set preds_to_delete [db_list pred_list "
	select	dependency_id
	from	im_timesheet_task_dependencies ttd
	where	ttd.task_id_one = :project_id and
		ttd.task_id_two not in ([join $pred_list ","])
    "]
    ns_log Notice "im_rest_project_task_tree_predecessors: the following preds need to be deleted: $preds_to_delete"

    foreach pred_dep_id $preds_to_delete {
	db_dml del_pred "delete from im_timesheet_task_dependencies where dependency_id = :pred_dep_id"
    }
}


