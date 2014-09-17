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

    ns_log Notice "im_rest_validate_call: Before ns_httpget $url"
    set result [ns_httpget $url]
    ns_log Notice "im_rest_validate_call: After ns_httpget $url"
    ad_return_complaint 1 "<pre>$url<br>[ad_quotehtml $result]</pre>"
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
    set sql "
	select	sub_p.project_id,
		sub_p.project_name,
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
		sub_p.parent_id is null and
		sub_p.tree_sortkey between main_p.tree_sortkey and tree_right(main_p.tree_sortkey)
	order by sub_p.tree_sortkey
    "
    set lol [db_list_of_lists validate_projects $sql]
    
    set validate_read_p 1
    set validate_list_p 1
    set debug_html ""
    foreach l $lol {
	
	set project_id [lindex $l 0]
	set project_name [lindex $l 1]
	set member_role_id [lindex $l 2]

	# Get the project using the multi-project call
	if {$validate_list_p} {
	    set operation "list"
	    set url [export_vars -base "$rest_url/im_project" {auth_token {user_id $rest_user_id} project_id {format json} }]
	    ns_log Notice "im_rest_validate_projects - list: Before ns_httpget $url"
	    set result [ns_httpget $url]
	    ns_log Notice "im_rest_validate_projects - list: After ns_httpget $url"
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
	    if {[info exists result_hash(data)]} { set data [lindex [lindex [lindex $result_hash(data) 1] 0] 1] }
	    set link "<a href=$url>url</a>"
	    
	    # append debug_html "<li><pre>$url</pre><br>[ad_quotehtml [array get result_hash]]\n"
	    append debug_html "<tr><td>$project_id</td><td>$project_name</td><td>$operation</td><td>$member_role_id</td><td>$total</td><td>$success</td><td>$message</td><td>[llength $data]</td><td>$link</td></tr>\n"
	}

	# Get the project using the multi-project call
	if {$validate_read_p} {
	    set operation "read"
	    set url [export_vars -base "$rest_url/im_project/$project_id" {auth_token {user_id $rest_user_id} {format json} }]
	    ns_log Notice "im_rest_validate_projects: Before ns_httpget $url"
	    set result [ns_httpget $url]
	    ns_log Notice "im_rest_validate_projects: After ns_httpget $url"
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
	    if {[info exists result_hash(data)]} { set data [lindex [lindex [lindex $result_hash(data) 1] 0] 1] }
	    set link "<a href=$url>url</a>"
	    
	    # append debug_html "<li><pre>$url</pre><br>[ad_quotehtml [array get result_hash]]\n"
	    append debug_html "<tr><td>$project_id</td><td>$project_name</td><td>$operation</td><td>$member_role_id</td><td>$total</td><td>$success</td><td>$message</td><td>[llength $data]</td><td>$link</td></tr>\n"
	}
    }

    set debug_header "<tr><td>oid</td><td>oname</td><td>operation</td><td>member<br>role_id</td><td>total</td><td>success</td><td>message</td><td>data</td><td>url</td></tr>\n"

    ad_return_complaint 1 "<table border=0>$debug_header $debug_html</table>"
}

