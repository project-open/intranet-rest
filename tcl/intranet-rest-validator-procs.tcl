# /packages/intranet-rest/tcl/intranet-rest-validator-procs.tcl
#
# Copyright (C) 2014 ]project-open[
#
# All rights reserved. Please check
# http://www.project-open.com/license/ for details.

ad_library {
    REST Web Service Validator
    @author frank.bergmann@project-open.com
}

# -------------------------------------------------------
#
# -------------------------------------------------------


ad_proc -private im_rest_validate_call {
    { -rest_url "http://localhost:8000/intranet-rest" }
    { -rest_user_id 8799 }
} {
    Performs a REST call and returns the results.
} {
    # Get the list of projects
    set expiry_date ""
    set auth_token [im_generate_auto_login -user_id $rest_user_id -expiry_date $expiry_date]

    append rest_url "/im_project"
    set url [export_vars -base $rest_url {auth_token {user_id $rest_user_id}}]
    set data "{\"project_name\": \"New Project\", \"project_nr\": \"12345\"}"

    # ---------------------------------
    
    set rqset [ns_set new rqset]
    ns_set put $rqset "Accept" "*/*"
    ns_set put $rqset "User-Agent" "[ns_info name]-Tcl/[ns_info version]"
    ns_set put $rqset "Content-type" "application/x-www-form-urlencoded"
    ns_set put $rqset "Content-length" [string length $data]
    set timeout 15
    set connInfo [ns_httpopen POST $url $rqset $timeout $data]

    
    foreach {rfd wfd headers} $connInfo break
    close $wfd
    set length [ns_set iget $headers content-length]
    if {$length eq ""} {
	set length -1
    }
    set page ""
    set err [catch {
	# Read the content.
	while {1} {
	    set buf [_ns_http_read $timeout $rfd $length]
	    append page $buf
	    if {$buf eq ""} {
		break
	    }
	    if {$length > 0} {
		incr length -[string length $buf]
		if {$length <= 0} {
		    break
		}
	    }
	}
    } errMsg]
    ns_set free $headers
    close $rfd
    if {$err} {
	return -code error -errorinfo $::errorInfo $errMsg
    }
    return $page

}


ad_proc -private im_rest_validate_list {
    { -rest_url "http://localhost:8000/intranet-rest" }
    { -rest_user_id 8799 }
} {
    Checks permissions to "list" on all object types
} {
    set auth_token [im_generate_auto_login -user_id $rest_user_id -expiry_date ""]

    set not_in_object_type "
				'acs_activity',
				'acs_event',
				'acs_mail_body',
				'acs_mail_gc_object',
				'acs_mail_link',
				'acs_mail_multipart',
				'acs_mail_queue_message',
				'acs_message',
				'acs_message_revision',
				'acs_named_object',
				'acs_object',
				'acs_reference_repository',
				'acs_sc_contract',
				'acs_sc_implementation',
				'acs_sc_msg_type',
				'acs_sc_operation',
				'admin_rel',
				'ams_object_revision',
				'apm_application',
				'apm_package',
				'apm_package_version',
				'apm_parameter',
				'apm_parameter_value',
				'apm_service',
				'application_group',
				'authority',
				'bt_bug',
				'bt_bug_revision',
				'bt_patch',
				'calendar',
				'cal_item',
				'composition_rel',
				'content_extlink',
				'content_folder',
				'content_item',
				'content_keyword',
				'content_module',
				'content_revision',
				'content_symlink',
				'content_template',
				'cr_item_child_rel',
				'cr_item_rel',
				'dynamic_group_type',
				'etp_page_revision',
				'image',
				'im_biz_object',
				'im_component_plugin',
				'im_cost',
				'im_gantt_person',
				'im_gantt_project',
				'im_indicator',
				'im_investment',
				'im_menu',
				'im_note',
				'im_repeating_cost',
				'im_report',
				'journal_article',
				'journal_entry',
				'journal_issue',
				'news_item',
				'notification',
				'notification_delivery_method',
				'notification_interval',
				'notification_reply',
				'notification_request',
				'notification_type',
				'person',
				'party',
				'postal_address',
				'rel_segment',
				'rel_constraint',
				'site_node',
				'user_blob_response_rel',
				'user_portrait_rel',
				'workflow',
				'workflow_lite',
				'workflow_case_log_entry'
    "

    set otypes_sql "
		select
			ot.object_type,
			ot.pretty_name,
			ot.object_type_gif,
			rot.object_type_id,
			im_object_permission_p(rot.object_type_id, :rest_user_id, 'read') as rest_user_read_p
		from
			acs_object_types ot,
			im_rest_object_types rot
		where
			ot.object_type = rot.object_type and
			ot.object_type not in ($not_in_object_type)
			and ot.object_type not like '%wf'
		order by
			ot.object_type
    "
    set debug_html ""
    db_foreach otypes $otypes_sql {
	set operation "list"
	set url [export_vars -base "$rest_url/$object_type" {auth_token {user_id $rest_user_id} {format json} }]
	ns_log Notice "im_rest_validate_list: $object_type: Before im_httpget $url"
	set result [im_httpget $url]
	ns_log Notice "im_rest_validate_list: $object_type: After im_httpget $url"
	set parsed_result [util::json::parse $result]
	array unset result_hash
	array set result_hash [lindex $parsed_result 1]
	
	set total ""
	set success ""
	set data ""
	set message ""
	if {[info exists result_hash(total)]} { set total $result_hash(total) }
	if {[info exists result_hash(success)]} { set success $result_hash(success) }
	if {[info exists result_hash(message)]} { set message $result_hash(message) }
	if {[info exists result_hash(data)]} { set data [lindex [lindex $result_hash(data) 1] 0 1] }
	set data_len [llength $data]
	set link "<a href=$url>url</a>"
	
	set color "white"
	if {$should_read_p && ($total == 0 || $data_len == 0 || $success != "true")} { set color "#FFAAFF" }
	if {!$should_read_p && ($total > 0 || $data_len > 0 || $success != "false")} { set color "#FFAAAA" }
	append debug_html "<tr bgcolor=$color><td>$project_id</td><td>$project_name</td><td>$operation</td><td>$should_read_p</td><td>$total</td><td>$success</td><td>$message</td><td>$data_len</td><td>$link</td></tr>\n"
	
    }

    set debug_header "<tr><td>oid</td><td>oname</td><td>operation</td><td>access_p</td><td>total</td><td>success</td><td>message</td><td>data</td><td>url</td></tr>\n"
    ad_return_complaint 1 "<table border=0>$debug_header $debug_html</table>"
}




ad_proc -private im_rest_validate_projects {
    { -rest_url "http://localhost:8000/intranet-rest" }
    { -rest_user_id 8799 }
} {
    Checks permissions on ]po[ projects
} {
    set auth_token [im_generate_auto_login -user_id $rest_user_id -expiry_date ""]
    
    # Get the list of projects together with permissions for the rest_user_id
    set add_projects [im_permission $rest_user_id "add_projects"]
    set view_projects_all [im_permission $rest_user_id "view_projects_all"]
    set view_projects_history [im_permission $rest_user_id "view_projects_history"]
    set edit_projects_all [im_permission $rest_user_id "edit_projects_all"]
    set edit_project_basedata [im_permission $rest_user_id "edit_project_basedata"]
    set edit_project_status [im_permission $rest_user_id "edit_project_status"]

    set validate_read_p 0
    set validate_list_p 0
    set validate_update_p 1
    set validate_create_p 0
    set validate_delete_p 0

    # ------------------------------------------------------------------------
    # Create a new Project
    # ------------------------------------------------------------------------

    if {$validate_create_p} {
	set operation "create"
	set url [export_vars -base "$rest_url/im_project" {auth_token {user_id $rest_user_id} project_id {format json} }]
	ns_log Notice "im_rest_validate_projects - create: Before im_httppost $url"
	set result [im_httppost $url]
	ns_log Notice "im_rest_validate_projects - create: After im_httppost $url"
	set parsed_result [util::json::parse $result]
	array unset result_hash
	array set result_hash [lindex $parsed_result 1]
	
	set total ""
	set success ""
	set data ""
	set message ""
	if {[info exists result_hash(total)]} { set total $result_hash(total) }
	if {[info exists result_hash(success)]} { set success $result_hash(success) }
	if {[info exists result_hash(message)]} { set message $result_hash(message) }
	if {[info exists result_hash(data)]} { set data [lindex [lindex $result_hash(data) 1] 0 1] }
	set data_len [llength $data]
	set link "<a href=$url>url</a>"
    }

    # ------------------------------------------------------------------------
    # Check a number of projects for read/list permissions
    # ------------------------------------------------------------------------
    set sql "
	select	sub_p.project_id,
		sub_p.project_name,
		sub_p.project_status_id,
		sub_p.project_type_id,
		(select	max(bom.object_role_id) 
		from	acs_rels r, im_biz_object_members bom 
		where	r.rel_id = bom.rel_id and
			r.object_id_one = sub_p.project_id and
			r.object_id_two in (
				select :rest_user_id UNION 
				select group_id from group_distinct_member_map where member_id = :rest_user_id
			)
		) as member_role_id
	from	im_projects main_p,
		im_projects sub_p
	where	main_p.parent_id is null and
		sub_p.tree_sortkey between main_p.tree_sortkey and tree_right(main_p.tree_sortkey)
	order by sub_p.tree_sortkey
	LIMIT 20
    "
    set lol [db_list_of_lists validate_projects $sql]
    
    set debug_html ""
    foreach l $lol {
	
	set project_id [lindex $l 0]
	set project_name [lindex $l 1]
	set project_status_id [lindex $l 2]
	set project_type_id [lindex $l 3]
	set member_role_id [lindex $l 4]

	switch $member_role_id {
	    "" {
		set should_read_p 0
		set should_write_p 0
	    }
	    1300 {
		# Full Member - may read
		set should_read_p 1
		set should_write_p 0
	    }
	    1301 {
		# Project Manager - may read and write
		set should_read_p 1
		set should_write_p 1
	    }
	    default {
		ad_return_complaint 1 "im_rest_validate_projects: Unknown role '$member_role_id'"
	    }
	}

	if {$project_type_id == [im_project_type_task]} {
	    # special permissions for timesheet tasks
	    im_timesheet_task_permissions $rest_user_id $project_id view should_read_p should_write_p admin
	}

	# Get the project using the multi-project call
	if {$validate_list_p} {
	    set operation "list"
	    set url [export_vars -base "$rest_url/im_project" {auth_token {user_id $rest_user_id} project_id {format json} }]
	    ns_log Notice "im_rest_validate_projects - list: Before im_httpget $url"
	    set result [im_httpget $url]
	    ns_log Notice "im_rest_validate_projects - list: After im_httpget $url"
	    set parsed_result [util::json::parse $result]
	    array unset result_hash
	    array set result_hash [lindex $parsed_result 1]
	    
	    set total ""
	    set success ""
	    set data ""
	    set message ""
	    if {[info exists result_hash(total)]} { set total $result_hash(total) }
	    if {[info exists result_hash(success)]} { set success $result_hash(success) }
	    if {[info exists result_hash(message)]} { set message $result_hash(message) }
	    if {[info exists result_hash(data)]} { set data [lindex [lindex $result_hash(data) 1] 0 1] }
	    set data_len [llength $data]
	    set link "<a href=$url>url</a>"
	    
	    set color "white"
	    if {$should_read_p && ($total == 0 || $data_len == 0 || $success != "true")} { set color "#FFAAFF" }
	    if {!$should_read_p && ($total > 0 || $data_len > 0 || $success != "false")} { set color "#FFAAAA" }
	    append debug_html "<tr bgcolor=$color><td>$project_id</td><td>$project_name</td><td>$operation</td><td>$should_read_p</td><td>$total</td><td>$success</td><td>$message</td><td>$data_len</td><td>$link</td></tr>\n"
	}

	# Get the project using the multi-project call
	if {$validate_read_p} {
	    set operation "read"
	    set url [export_vars -base "$rest_url/im_project/$project_id" {auth_token {user_id $rest_user_id} {format json} }]
	    ns_log Notice "im_rest_validate_projects: Before im_httpget $url"
	    set result [im_httpget $url]
	    ns_log Notice "im_rest_validate_projects: After im_httpget $url"
	    set parsed_result [util::json::parse $result]
	    array unset result_hash
	    array set result_hash [lindex $parsed_result 1]
	    
	    set total ""
	    set success ""
	    set data ""
	    set message ""
	    if {[info exists result_hash(total)]} { set total $result_hash(total) }
	    if {[info exists result_hash(success)]} { set success $result_hash(success) }
	    if {[info exists result_hash(message)]} { set message $result_hash(message) }
	    if {[info exists result_hash(data)]} { set data [lindex [lindex $result_hash(data) 1] 0 1] }
	    set link "<a href=$url>url</a>"
	    
	    set color "white"
	    if {$should_read_p && ($total == 0 || $data_len == 0 || $success != "true")} { set color "#FFAAFF" }
	    if {!$should_read_p && ($total > 0 || $data_len > 0 || $success != "false")} { set color "#FFAAAA" }
	    append debug_html "<tr bgcolor=$color><td>$project_id</td><td>$project_name</td><td>$operation</td><td>$should_read_p</td><td>$total</td><td>$success</td><td>$message</td><td>[llength $data]</td><td>$link</td></tr>\n"
	}



	# Get the project using the multi-project call
	if {$validate_update_p} {
	    set operation "update"
	    set form_vars [export_vars {auth_token {user_id $rest_user_id} {format json}}]

	    set prob [expr {round(rand() * 100.0 * 10000.0) / 10000.0}]
	    set form [ns_set new]
	    ns_set put $form presales_probability $prob

	    set url "$rest_url/im_project/$project_id"
	    set url [export_vars -base "$rest_url/im_project/$project_id" {auth_token {user_id $rest_user_id} {format json} }]
	    
	    ns_log Notice "im_rest_validate_projects: Before im_httppost $url"
	    set result [im_httppost $url "" ""]
	    ns_log Notice "im_rest_validate_projects: After im_httppost $url"
	    ad_return_complaint 1 "<pre>$result</pre>"
	    set parsed_result [util::json::parse $result]
	    array unset result_hash
	    array set result_hash [lindex $parsed_result 1]
	    
	    set total ""
	    set success ""
	    set data ""
	    set message ""
	    if {[info exists result_hash(total)]} { set total $result_hash(total) }
	    if {[info exists result_hash(success)]} { set success $result_hash(success) }
	    if {[info exists result_hash(message)]} { set message $result_hash(message) }
	    if {[info exists result_hash(data)]} { set data [lindex [lindex $result_hash(data) 1] 0 1] }
	    set link "<a href=$url>url</a>"

	    set color "white"
	    if {$should_write_p && ($total == 0 || $data_len == 0 || $success != "true")} { set color "#FFAAFF" }
	    if {!$should_write_p && ($total > 0 || $data_len > 0 || $success != "false")} { set color "#FFAAAA" }
	    append debug_html "<tr bgcolor=$color><td>$project_id</td><td>$project_name</td><td>$operation</td><td>$should_write_p</td><td>$total</td><td>$success</td><td>$message</td><td>[llength $data]</td><td>$link</td></tr>\n"
	}


    }

    set debug_header "<tr><td>oid</td><td>oname</td><td>operation</td><td>access_p</td><td>total</td><td>success</td><td>message</td><td>data</td><td>url</td></tr>\n"

    ad_return_complaint 1 "<table border=0>$debug_header $debug_html</table>"
}

