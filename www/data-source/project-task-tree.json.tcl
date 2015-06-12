# /packages/sencha-rest/www/project-tree.json.tcl
#
# Copyright (C) 2013 ]project-open[

ad_page_contract {
    Returns a JSON tree structure suitable for batch-loading a project TreeStore
    @param project_id The project
    @author frank.bergmann@project-open.com
} {
    project_id:integer
    {debug_p 0}
}

# --------------------------------------------
# Security & Permissions
#
set current_user_id [ad_maybe_redirect_for_registration]
im_project_permissions $current_user_id $project_id view read write admin
if {!$read} {
    im_rest_error -format "json" -http_status 403 -message "You (user #$current_user_id) have no permissions to read project #$project_id"
    ad_script_abort
}


# --------------------------------------------
# Task dependencies: Collect before the main loop
# predecessor_hash: The list of predecessors for each task
# successor_task_hash: The list of successors for each task
set task_dependencies_sql "
	select	distinct ttd.*
	from	im_projects main_p,
		im_projects p,
		im_timesheet_task_dependencies ttd
	where	main_p.project_id = :project_id and
		p.tree_sortkey between main_p.tree_sortkey and tree_right(main_p.tree_sortkey) and
		(ttd.task_id_one = p.project_id OR ttd.task_id_two = p.project_id)
"
db_foreach task_dependencies $task_dependencies_sql {
    set predecessor_tasks [list]
    if {[info exists predecessor_hash($task_id_one)]} { set predecessor_tasks $predecessor_hash($task_id_one) }
    lappend predecessor_tasks $task_id_two
    set predecessor_hash($task_id_one) $predecessor_tasks

    set successor_tasks [list]
    if {[info exists successor_hash($task_id_two)]} { set successor_tasks $successor_hash($task_id_two) }
    lappend successor_tasks $task_id_one
    set successor_hash($task_id_two) $successor_tasks
}

# --------------------------------------------
# Assignees: Collect before the main loop
#
set assignee_sql "
	select	r.*,
		bom.*,
		to_char(coalesce(bom.percentage,0), '990.0') as percent_pretty,
		im_name_from_user_id(r.object_id_two) as user_name,
		im_email_from_user_id(r.object_id_two) as user_email,
		im_initials_from_user_id(r.object_id_two) as user_initials
	from	im_projects main_p,
		im_projects p,
		acs_rels r,
		im_biz_object_members bom 
	where	r.rel_id = bom.rel_id and
		r.object_id_one = p.project_id and
		main_p.project_id = :project_id and
		p.tree_sortkey between main_p.tree_sortkey and tree_right(main_p.tree_sortkey)
	order by
		user_initials
"
db_foreach assignee $assignee_sql {
    set assignees [list]
    if {[info exists assignee_hash($object_id_one)]} { set assignees $assignee_hash($object_id_one) }
    lappend assignees "{id:$object_id_two, percent:$percent_pretty, name:'$user_name', email:'$user_email', initials:'$user_initials'}"
    set assignee_hash($object_id_one) $assignees
}

# ad_return_complaint 1 [join [array get assignee_hash] "<br>"]

# --------------------------------------------
# Get all the variables valid for timesheet task
set valid_vars [util_memoize [list im_rest_object_type_columns -deref_p 0 -rest_otype "im_timesheet_task"]]
set valid_vars [lsort -unique $valid_vars]

set projects_sql "
	select	o.*,
		bo.*,
		t.*,
		gp.*,
		p.*,					-- p.* needs to come after gp.* in case gp is NULL
		tree_level(p.tree_sortkey) as level,
		(p.end_date - p.start_date)::interval as duration,
		(select im_name_from_user_id(min(r.object_id_two)) from acs_rels r where r.object_id_one = p.project_id) as assignee,
		(select count(*) from im_projects child where child.parent_id = p.project_id) as num_children,
		CASE WHEN bts.open_p = 'o' THEN 'true' ELSE 'false' END as expanded,
		p.sort_order
	from	im_projects main_p,
		im_projects p
		LEFT OUTER JOIN acs_objects o ON (p.project_id = o.object_id)
		LEFT OUTER JOIN im_biz_objects bo ON (p.project_id = bo.object_id)
		LEFT OUTER JOIN im_timesheet_tasks t ON (p.project_id = t.task_id)
		LEFT OUTER JOIN im_gantt_projects gp ON (p.project_id = gp.project_id)
		LEFT OUTER JOIN im_biz_object_tree_status bts ON (
			p.project_id = bts.object_id and 
			bts.page_url = 'default' and
			bts.user_id = :current_user_id
		)
	where	main_p.project_id = :project_id and
		p.tree_sortkey between main_p.tree_sortkey and tree_right(main_p.tree_sortkey)
	order by
		coalesce(p.sort_order, 0)
"

# Read the query into a Multirow, so that we can order
# it according to sort_order within the individual sub-levels.
db_multirow task_multirow task_list $projects_sql {

    # By default keep the main project "open".
    if {"" == $parent_id} { set expanded "true" }

}

# Sort the tree according to the specified sort order
# "sort_order" is an integer, so we have to tell the sort algorithm to use integer sorting
ns_log Notice "project-tree.json.tcl: starting to sort multirow"

multirow_sort_tree -integer task_multirow project_id parent_id sort_order



set title ""

set task_json ""
set ctr 0
set old_level 1
set indent ""
template::multirow foreach task_multirow {

    ns_log Notice "project-tree.json.tcl: project_id=$project_id, task_id=$task_id"
    if {$debug_p} { append task_json "\n// finish: ctr=$ctr, level=$level, old_level=$old_level\n" }

    # -----------------------------------------
    # Close off the previous entry
    # -----------------------------------------
    
    # This is the first child of the previous item
    # Increasing the level always happens in steps of 1
    if {$level > $old_level} {
	append task_json ",\n${indent}\tchildren:\[\n"
    }

    # A group of children needs to be closed.
    # Please note that this can cascade down to several levels.
    while {$level < $old_level} {
	append task_json "\n${indent}\}\]\n"
	incr old_level -1
	set indent ""
	for {set i 0} {$i < $old_level} {incr i} { append indent "\t" }
    }

    set project_name "$project_name"

    # The current task is on the same level as the previous.
    # This is also executed after reducing the old_level in the previous while loop
    if {$level == $old_level} {
	if {0 != $ctr} { 
	    append task_json "${indent}\n${indent}\},\n"
	}
    }

    if {$debug_p} { append task_json "\n// $project_name: ctr=$ctr, level=$level, old_level=$old_level\n" }

    set indent ""
    for {set i 0} {$i < $level} {incr i} { append indent "\t" }
    
    if {0 == $num_children} { set leaf_json "true" } else { set leaf_json "false" }

    set successor_tasks [list]
    set predecessor_tasks [list]
    set assignees [list]
    if {[info exists successor_hash($project_id)]} { set successor_tasks $successor_hash($project_id) }
    if {[info exists predecessor_hash($project_id)]} { set predecessor_tasks $predecessor_hash($project_id) }
    if {[info exists assignee_hash($project_id)]} { set assignees $assignee_hash($project_id) }

    append task_json "${indent}\{
${indent}\tid:$project_id,
${indent}\ttext:'$project_name',
${indent}\tduration:13.5,
${indent}\tsuccessors:\[[join $successor_tasks ", "]\],
${indent}\tpredecessors:\[[join $predecessor_tasks ", "]\],
${indent}\tassignees:\[[join $assignees ", "]\],
${indent}\tuser:'$assignee',
${indent}\ticonCls:'task-folder',
${indent}\texpanded:$expanded,
"

    foreach var $valid_vars {
	# Skip xml_* variables (only used by MS-Project)
	if {[regexp {^xml_} $var match]} { continue }

	# Append the value to the JSON output
	set value [set $var]
	set mapped_value [string map {"\n" "<br>" "\r" ""} $value]
	append task_json "${indent}\t$var:'$mapped_value',\n"
    }

    append task_json "${indent}\tleaf:$leaf_json"


    incr ctr
    set old_level $level
}

set level 0
while {$level < $old_level} {
    # A group of children needs to be closed.
    # Please note that this can cascade down to several levels.
    append task_json "\n${indent}\}\]\n"
    incr old_level -1
    set indent ""
    for {set i 0} {$i < $old_level} {incr i} { append indent "\t" }
}



doc_return 200 "text/plain" "{'text':'.','children': \[
$task_json
}
"

ad_script_abort
