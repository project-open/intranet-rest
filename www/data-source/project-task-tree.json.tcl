# /packages/sencha-rest/www/project-tree.json.tcl
#
# Copyright (C) 2013 ]project-open[

ad_page_contract {
    Returns a JSON tree structure suitable for batch-loading a project TreeStore
    @param project_id The project
    @author frank.bergmann@project-open.com
    
    @param node Passed by ExtJS to load sub-trees of a tree.
                Normally not used, just in case of error.
} {
    project_id:integer
    {debug_p 0}
    {node ""}
}


set main_project_id $project_id
set root_project_id $project_id
if {"" ne $node && [string is integer $node]} { set root_project_id $node }
ns_log Notice "project-task-tree.json: node=$node, main_project_id=$main_project_id, root_project_id=$root_project_id, query_hash_pairs=$query_hash_pairs"


# --------------------------------------------
# Return an empty tree for project_id == 0 to avoid errors
#
if {0 eq $project_id} {
    set task_json "\]"
    ad_return_template
    return
}

# --------------------------------------------
# Security & Permissions
#
set current_user_id [auth::require_login]
im_project_permissions $current_user_id $main_project_id view read write admin
if {!$read} {
    im_rest_error -format "json" -http_status 403 -message "You (user #$current_user_id) have no permissions to read project #$main_project_id"
    ad_script_abort
}

# 9722 = 'Fixed Work' is the default effort_driven_type
set default_effort_driven_type_id [parameter::get_from_package_key -package_key "intranet-ganttproject" -parameter "DefaultEffortDrivenTypeId" -default "9722"]



# --------------------------------------------
# Task dependencies: Collect before the main loop
# predecessor_hash: The list of predecessors for each task
set default_dependency_type_id [im_timesheet_task_dependency_type_finish_to_start]
set task_dependencies_sql "
	select distinct
		ttd.dependency_id,
		ttd.task_id_one,
		ttd.task_id_two,
		coalesce(ttd.dependency_type_id, :default_dependency_type_id) as dependency_type_id,
		coalesce(ttd.difference_format_id, 9807) as diff_format_id,     -- 9807=Day for formatting lag time
		coalesce(ttd.difference, 0.0) as diff
	from	im_projects main_p,
		im_projects p,
		im_timesheet_task_dependencies ttd
	where	p.tree_sortkey between main_p.tree_sortkey and tree_right(main_p.tree_sortkey) and
		(ttd.task_id_one = p.project_id OR ttd.task_id_two = p.project_id) and
		main_p.project_id = :main_project_id
"
db_foreach task_dependencies $task_dependencies_sql {
    set pred [list]
    if {[info exists predecessor_hash($task_id_one)]} { set pred $predecessor_hash($task_id_one) }
    lappend pred "{id: $dependency_id, pred_id: $task_id_two, succ_id: $task_id_one, type_id: $dependency_type_id, diff: $diff, diff_format_id: $diff_format_id}"
    set predecessor_hash($task_id_one) $pred
}

# ad_return_complaint 1 "<pre>[join [array get predecessor_hash] "<br>"]</pre>


# --------------------------------------------
# Assignees: Collect all before the main loop
#
set assignee_sql "
	select	r.*,
		bom.*,
		coalesce(bom.percentage,0) as percent_pretty,
		im_name_from_user_id(r.object_id_two) as user_name,
		im_email_from_user_id(r.object_id_two) as user_email,
		im_initials_from_user_id(r.object_id_two) as user_initials
	from	im_projects main_p,
		im_projects p,
		acs_rels r,
		im_biz_object_members bom 
	where	r.rel_id = bom.rel_id and
		r.object_id_one = p.project_id and
		main_p.project_id = :main_project_id and
		p.tree_sortkey between main_p.tree_sortkey and tree_right(main_p.tree_sortkey)
	order by
		user_initials
"
db_foreach assignee $assignee_sql {
    set assignees [list]
    if {[info exists assignee_hash($object_id_one)]} { set assignees $assignee_hash($object_id_one) }
    lappend assignees "{id:$rel_id, user_id:$object_id_two, percent:$percent_pretty}"
    set assignee_hash($object_id_one) $assignees
}

# --------------------------------------------
# Invoices: Collect before main loop
#
set invoice_sql "
	select	p.project_id as child_project_id,
		c.*,
		c.effective_date::date as effective_date_date
	from	im_projects main_p,
		im_projects p,
		acs_rels r,
		im_costs c
	where	main_p.project_id = :main_project_id and
		p.tree_sortkey between main_p.tree_sortkey and tree_right(main_p.tree_sortkey) and
		r.object_id_one = p.project_id and
		r.object_id_two = c.cost_id
	order by c.cost_id
"
db_foreach invoice $invoice_sql {
    set invoices [list]
    if {[info exists invoice_hash($child_project_id)]} { set invoices $invoice_hash($child_project_id) }
    lappend invoices "{id:$cost_id, effective_date: '$effective_date_date', cost_name:'[im_quotejson $cost_name]', cost_type_id:$cost_type_id, cost_type:'[im_category_from_id $cost_type_id]'}"
    set invoice_hash($child_project_id) $invoices
}
# ad_return_complaint 1 [array get invoice_hash]


# --------------------------------------------
# Baselines:
#

# Baselines can be installed or not...
if {[im_table_exists im_baselines]} {
    # Get the first active baseline
    array set baseline_hash {}
    set baseline_id [db_string first_baseline "select min(baseline_id) from im_baselines where baseline_project_id = :main_project_id" -default 0]
    set baseline_var_map_list {start_date start end_date end}
    array set baseline_var_map $baseline_var_map_list
    set baseline_vars [array names baseline_var_map]
    array set baseline_hash {}

    set baseline_sql "
    	select	*
	from	im_audits a,
		im_baselines b
	where	a.audit_baseline_id = b.baseline_id and
		b.baseline_project_id = :main_project_id
	order by b.baseline_id, audit_id
    "
    # ad_return_complaint 1 [im_ad_hoc_query -format html $baseline_sql]
    db_foreach baselines $baseline_sql {
	
	# Create a hash with baseline id -> name
	set baseline_hash($baseline_id) $baseline_name

	# Writing audit values into a hash.
	set values [split $audit_value "\n"]
	foreach value $values {
	    set value_parts [split $value "\t"]
	    lassign $value_parts key val
	    if {$key in $baseline_vars} {
		set k "$baseline_id-$audit_object_id-$key"
		set baseline_value_hash($k) $val
	    }
	}
    }
    # ad_return_complaint 1 [join [array get baseline_value_hash] "<br>"]
}

# --------------------------------------------
# Get the list of projects that should not be displayed
# Currently these are projects marked as "deleted".
# We now also want to show "normal projects" / subprojects.
#
set non_display_projects_sql "
	select	distinct sub_p.project_id			-- Select all sup-projects of somehow non-displays
	from	im_projects super_p,
		im_projects sub_p
	where	sub_p.tree_sortkey between super_p.tree_sortkey and tree_right(super_p.tree_sortkey) and
		sub_p.project_id != :main_project_id and
		super_p.project_id in (
			-- The list of projects that should not be displayed
			select	p.project_id
			from	im_projects p,
				acs_objects o,
				im_projects main_p
			where	main_p.project_id = :main_project_id and
				main_p.project_id != p.project_id and
				p.project_id = o.object_id and
				p.tree_sortkey between main_p.tree_sortkey and tree_right(main_p.tree_sortkey) and
				p.project_status_id = [im_project_status_deleted]
		)
"
# set non_display_projects [db_list non_display_projects $non_display_projects_sql]
set non_display_projects [list]
lappend non_display_projects 0

# ad_return_complaint 1 $non_display_projects


# --------------------------------------------
# Get all the variables valid for gantt task
#
set valid_vars [util_memoize [list im_rest_object_type_columns -deref_p 0 -rest_otype "im_timesheet_task"]]
set valid_vars [lsort -unique $valid_vars]


# Get a list of variables containing a date
# We will cut off the time-zone part of the value futher below...
set date_vars [db_list date_vars "
	select	lower(column_name) 
	from	user_tab_columns 
	where	lower(table_name) in ('acs_objects', 'im_biz_objects', 'im_projects', 'im_timesheet_tasks') and 
		lower(data_type) in ('date', 'timestamptz', 'timestamp', 'time_stamp', 'abstime')
	order by column_name
"]


# --------------------------------------------
# Main hierarchical SQL
#
set projects_sql "
	select	o.*,
		bo.*,
		t.*,
		gp.*,
		p.*,					-- p.* needs to come after gp.* in case gp is NULL
		tree_level(p.tree_sortkey) as level,
		(p.end_date - p.start_date)::interval as duration,
		(select count(*) from im_projects child where child.parent_id = p.project_id) as num_children,
		CASE WHEN bts.open_p = 'o' THEN 'true' ELSE 'false' END as expanded,
		p.sort_order,
		round(p.percent_completed * 10.0) / 10.0 as percent_completed,
		coalesce(p.reported_hours_cache, 0.0) as logged_hours
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
	where	main_p.project_id = :root_project_id and
		p.tree_sortkey between main_p.tree_sortkey and tree_right(main_p.tree_sortkey) and
		p.project_id not in ([join $non_display_projects ","])
	order by
		coalesce(p.sort_order, 0)
"

# Read the query into a Multirow, so that we can order
# it according to sort_order within the individual sub-levels.
db_multirow task_multirow task_list $projects_sql {
    # By default keep the main project "open".
    if {"" == $parent_id} { set expanded "true" }

    # Deal with partial data if exactly one of the two start or end dates are set
    if {"" == $start_date && "" != $end_date} { set start_date $end_date }
    if {"" != $start_date && "" == $end_date} {	set end_date $start_date }

    # Workaround for bug in Sencha tree display if cost_center_id is empty
    if {"" == $cost_center_id} { set cost_center_id [im_cost_center_company] }
}

# Sort the tree according to the specified sort order
# "sort_order" is an integer, so we have to tell the sort algorithm to use integer sorting
ns_log Notice "project-tree.json.tcl: Starting to sort multirow"
multirow_sort_tree -integer task_multirow project_id parent_id sort_order
ns_log Notice "project-tree.json.tcl: Finished to sort multirow"

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

    set predecessor_tasks [list]
    set assignees [list]
    set invoices [list]
    if {[info exists predecessor_hash($project_id)]} { set predecessor_tasks $predecessor_hash($project_id) }
    if {[info exists assignee_hash($project_id)]} { set assignees $assignee_hash($project_id) }
    if {[info exists invoice_hash($project_id)]} { set invoices $invoice_hash($project_id) }

    set quoted_char_map {"\n" "\\n" "\r" "\\r" "\"" "\\\"" "\\" "\\\\"}
    set quoted_project_name [string map $quoted_char_map $project_name]

    set type ""
    switch $project_type_id {
	100 { set type "task" }
	101 { set type "ticket" }
	102 - 103 { set type "crm" }
	2502 { set type "sla" }
	2504 { set type "milestone" }
	2510 { set type "program" }
	4597 { set type "release-item" }
	4599 { set type "release" }
    }
    if {[im_category_is_a $project_type_id [im_project_type_gantt]]} { set type "project" }
    if {"t" eq $milestone_p} { set type "milestone" }
    # ToDo: Deal with empty type

    # Fixed Work, fixed duration or Fixed units?
    if {"" eq $effort_driven_type_id} { set effort_driven_type_id $default_effort_driven_type_id }
    
    append task_json "${indent}\{
${indent}\tid:$project_id,
${indent}\ttext:\"$quoted_project_name\",
${indent}\ticonCls:\"icon-$type\",
${indent}\tpredecessors:\[[join $predecessor_tasks ", "]\],
${indent}\tassignees:\[[join $assignees ", "]\],
${indent}\tinvoices:\[[join $invoices ", "]\],
${indent}\tlogged_hours:$logged_hours,
${indent}\texpanded:$expanded,
"
    # Create Baseline structure: baselines {'bid1': {'start_date': "...", 'end_date': "..."}, 'bid2': {...}}
    set b_json_list [list]
    foreach baseline_id [lsort -integer [array names baseline_hash]] {
	# ad_return_complaint 1 $baseline_id
	set json_list [list]
	foreach baseline_var $baseline_vars {
	    set k "$baseline_id-$project_id-$baseline_var"
	    if {[info exists baseline_value_hash($k)]} {
		set val $baseline_value_hash($k)
		lappend json_list "'$baseline_var': '$val'"
	    }
	}
	set b_json "'$baseline_id': {[join $json_list ", "]}"
	lappend b_json_list $b_json
    }
    append task_json "${indent}\tbaselines: {[join $b_json_list ", "]},\n"

    foreach var $valid_vars {
	# Skip xml_* variables (only used by MS-Project)
	if {[regexp {^xml_} $var match]} { continue }

	# Get the value of the local variable containing the database result
	set value [set $var]

	# Cut off the time-zone information for dates, time-stamps etc.
	# So the client will get data without time zone.
	if {$var in $date_vars} { set value [string range $value 0 18] }

	# Append the value to the JSON output
	set quoted_value [string map $quoted_char_map $value]
	append task_json "${indent}\t$var:\"$quoted_value\",\n"
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

