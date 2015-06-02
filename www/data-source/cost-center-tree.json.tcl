# /packages/sencha-rest/www/cost-center-tree.json.tcl
#
# Copyright (C) 2013 ]project-open[

ad_page_contract {
    Returns a JSON tree structure suitable for batch-loading a cost center TreeStore
    @param cost_center_id The top cost center
    @author frank.bergmann@cost_center-open.com
} {
    {cost_center_id:integer 0}
    {debug_p 0}
}

# --------------------------------------------
# Security & Permissions
#
set current_user_id [ad_maybe_redirect_for_registration]
if {"" == $cost_center_id || 0 == $cost_center_id} {
    # Use the topmost cost center as the base
    set cost_center_id [im_cost_center_company]
}

im_cost_center_permissions $current_user_id $cost_center_id view read write admin
if {!$read} {
    im_rest_error -format "json" -http_status 403 -message "You (user #$current_user_id) have no permissions to read cost_center #$cost_center_id"
    ad_script_abort
}

set top_cc_id $cost_center_id
set top_cc_code [util_memoize [list db_string top_cc_code "select im_cost_center_code_from_id($top_cc_id) from dual"]]
set top_cc_code_len [string length $top_cc_code]
set top_cc_level [expr ($top_cc_code_len / 2) - 1]


# Get all the variables valid for timesheet cost_center
set valid_vars [util_memoize [list im_rest_object_type_columns -deref_p 0 -rest_otype "im_cost_center"]]
set valid_vars [lsort -unique $valid_vars]

set cost_centers_sql "
	select	cc.*,
		o.*,
		length(cc.cost_center_code) / 2 - :top_cc_level as level,
		CASE WHEN bts.open_p = 'o' THEN 'true' ELSE 'false' END as expanded,
		(select count(*) from im_cost_centers child where child.parent_id = cc.cost_center_id) as num_children
	from	acs_objects o,
		im_cost_centers cc
		LEFT OUTER JOIN im_biz_object_tree_status bts ON (
			cc.cost_center_id = bts.object_id and 
			bts.page_url = 'default' and
			bts.user_id = :current_user_id
		)
	where	cc.cost_center_id = o.object_id and
		substring(cc.cost_center_code for :top_cc_code_len) = :top_cc_code
	order by cc.cost_center_code
"

# Read the query into a Multirow, so that we can order
# it according to sort_order within the individual sub-levels.
db_multirow cost_center_multirow cost_center_list $cost_centers_sql {
    # By default keep the main project "open".
    if {"" == $parent_id} { set expanded "true" }
}


set title ""
set cost_center_json ""
set ctr 0
set old_level 1
set indent ""
template::multirow foreach cost_center_multirow {

    ns_log Notice "cost-center-tree.json.tcl: cost_center_id=$cost_center_id"
    if {$debug_p} { append cost_center_json "\n// finish: ctr=$ctr, level=$level, old_level=$old_level\n" }

    # -----------------------------------------
    # Close off the previous entry
    # -----------------------------------------
    
    # This is the first child of the previous item
    # Increasing the level always happens in steps of 1
    if {$level > $old_level} {
	append cost_center_json ",\n${indent}\tchildren:\[\n"
    }

    # A group of children needs to be closed.
    # Please note that this can cascade down to several levels.
    while {$level < $old_level} {
	append cost_center_json "\n${indent}\}\]\n"
	incr old_level -1
	set indent ""
	for {set i 0} {$i < $old_level} {incr i} { append indent "\t" }
    }

    set cost_center_name "$cost_center_code - $cost_center_name"

    # The current cost_center is on the same level as the previous.
    # This is also executed after reducing the old_level in the previous while loop
    if {$level == $old_level} {
	if {0 != $ctr} { 
	    append cost_center_json "${indent}\n${indent}\},\n"
	}
    }

    if {$debug_p} { append cost_center_json "\n// $cost_center_name: ctr=$ctr, level=$level, old_level=$old_level\n" }

    set indent ""
    for {set i 0} {$i < $level} {incr i} { append indent "\t" }
    
    if {0 == $num_children} { set leaf_json "true" } else { set leaf_json "false" }

    set successor_cost_centers [list]
    set predecessor_cost_centers [list]
    if {[info exists successor_hash($cost_center_id)]} { set successor_cost_centers $successor_hash($cost_center_id) }
    if {[info exists predecessor_hash($cost_center_id)]} { set predecessor_cost_centers $predecessor_hash($cost_center_id) }

    append cost_center_json "${indent}\{
${indent}\tid:$cost_center_id,
${indent}\ttext:'$cost_center_name',
${indent}\tduration:13.5,
${indent}\tsuccessors:\[[join $successor_cost_centers ","]\],
${indent}\tpredecessors:\[[join $predecessor_cost_centers ","]\],
${indent}\ticonCls:'cost_center-folder',
${indent}\texpanded:$expanded,
"

    foreach var $valid_vars {
	continue
	# Skip xml_* variables (only used by MS-Cost_Center)
	if {[regexp {^xml_} $var match]} { continue }

	# Append the value to the JSON output
	set value [set $var]
	set mapped_value [string map {"\n" "<br>" "\r" ""} $value]
	append cost_center_json "${indent}\t$var:'$mapped_value',\n"
    }

    append cost_center_json "${indent}\tleaf:$leaf_json"
    incr ctr
    set old_level $level
}

set level 0
while {$level < $old_level} {
    # A group of children needs to be closed.
    # Please note that this can cascade down to several levels.
    append cost_center_json "\n${indent}\}\]\n"
    incr old_level -1
    set indent ""
    for {set i 0} {$i < $old_level} {incr i} { append indent "\t" }
}



doc_return 200 "text/plain" "{'text':'.','children': \[
$cost_center_json
}
"

ad_script_abort
