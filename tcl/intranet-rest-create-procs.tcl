# /packages/intranet-rest/tcl/intranet-rest-create-procs.tcl
#
# Copyright (C) 2009-2010 ]project-open[
#
# All rights reserved. Please check
# http://www.project-open.com/license/ for details.

ad_library {
    REST Web Service Component Library
    @author frank.bergmann@project-open.com

    This file contains object creation scripts for a number
    of object types.
}

# -------------------------------------------------------
# Index
#
#	Project
#	Ticket
#	Timesheet Task
#	Translation Task
#	Company
#	User Absence
#	User
#	Invoice
#	Invoice Item (fake object)
#	Hour (fake object, create + update)
# -------------------------------------------------------


# -------------------------------------------------------
# Project
# -------------------------------------------------------

ad_proc -private im_rest_post_object_type_im_project {
    { -format "json" }
    { -rest_user_id 0 }
    { -content "" }
    { -rest_otype "im_project" }
    { -rest_otype_pretty "Project" }
} {
    Create a new object and return the object_id.
} {
    ns_log Notice "im_rest_post_object_type_$rest_otype: rest_user_id=$rest_user_id"

    # Permissions
    set add_projects_p [im_permission $rest_user_id "add_projects"]
    if {!$add_projects_p} {
	return [im_rest_error -format $format -http_status 403 -message "User #$rest_user_id does not have the right to create projects"] 
    }
    
    # Extract a key-value list of variables from JSON POST request
    array set hash_array [im_rest_parse_json_content -rest_otype $rest_otype -format $format -content $content]

    # Check that all required variables are there
    set required_vars {project_name project_nr}
    foreach var $required_vars {
	if {![info exists hash_array($var)]} { 
	    return [im_rest_error -format $format -http_status 406 -message "Variable '$var' not specified. The following variables are required: $required_vars"] 
	}
    }

    # Default values for not required vars
    if {![info exists hash_array(project_path)]} { set hash_array(project_path) $hash_array(project_nr) }
    if {![info exists hash_array(company_id)]} { set hash_array(company_id) [im_company_internal] }
    if {![info exists hash_array(parent_id)]} { set hash_array(parent_id) "" }
    if {![info exists hash_array(project_status_id)]} { set hash_array(project_status_id) [im_project_status_open] }
    if {![info exists hash_array(project_type_id)]} { set hash_array(project_type_id) [im_project_type_gantt] }
    if {![info exists hash_array(start_date)]} { set hash_array(start_date) [util_memoize [list db_string y "select to_char(now(), 'YYYY-01-01')"]] }
    if {![info exists hash_array(end_date)]} { set hash_array(end_date) [util_memoize [list db_string y "select to_char(now(), 'YYYY-12-31')"]] }

    set project_name $hash_array(project_name)
    set project_nr $hash_array(project_nr)
    set project_path $hash_array(project_path)
    set parent_id $hash_array(parent_id)
    
    # Check for duplicate
    set parent_sql "parent_id = :parent_id"
    if {"" == $parent_id} { set parent_sql "parent_id is NULL" }
    set dup_sql "
		select  count(*)
		from    im_projects
		where   $parent_sql and
			(       upper(trim(project_name)) = upper(trim(:project_name)) OR
				upper(trim(project_nr)) = upper(trim(:project_nr)) OR
				upper(trim(project_path)) = upper(trim(:project_path))
			)
    "
    if {[db_string duplicates $dup_sql]} {
	return [im_rest_error -format $format -http_status 406 -message "Duplicate $rest_otype_pretty: Your project_name, project_nr or project_path already exists for the specified parent_id."]
    }

    if {[catch {
	set rest_oid [im_project::new \
			-creation_user		$rest_user_id \
			-context_id		"" \
			-project_name		$hash_array(project_name) \
			-project_nr		$hash_array(project_nr) \
			-project_path       	$hash_array(project_path) \
			-company_id	 	$hash_array(company_id) \
			-parent_id	  	$hash_array(parent_id) \
			-project_type_id    	$hash_array(project_type_id) \
			-project_status_id  	$hash_array(project_status_id) \
	]
    } err_msg]} {
	return [im_rest_error -format $format -http_status 406 -message "Error creating $rest_otype_pretty: '$err_msg'."]
    }

    if {[catch {
	im_rest_object_type_update_sql \
	    -rest_otype $rest_otype \
	    -rest_oid $rest_oid \
	    -hash_array [array get hash_array]
    } err_msg]} {
	return [im_rest_error -format $format -http_status 406 -message "Error updating $rest_otype_pretty: '$err_msg'."]
    }

    # Write Audit Trail
    im_project_audit -project_id $rest_oid -action after_create  

    # Add the creating user as a member, so that he's got the right to modify the project if he is not a privileged user
    im_biz_object_add_role $rest_user_id $rest_oid [im_biz_object_role_project_manager]
    
    set hash_array(rest_oid) $rest_oid
    return [array get hash_array]
}


# -------------------------------------------------------
# Ticket
# -------------------------------------------------------

ad_proc -private im_rest_post_object_type_im_ticket {
    { -format "json" }
    { -rest_user_id 0 }
    { -content "" }
    { -rest_otype "im_ticket" }
    { -rest_otype_pretty "Ticket" }
} {
    Create a new object and return its object_id
} {
    ns_log Notice "im_rest_post_object_type_$rest_otype: rest_user_id=$rest_user_id"

    # Permissions
    set add_tickets_p [im_permission $rest_user_id "add_tickets"]
    if {!$add_tickets_p} {
	return [im_rest_error -format $format -http_status 403 -message "User #$rest_user_id does not have the right to create tickets"] 
    }

    # Extract a key-value list of variables from JSON POST request
    array set hash_array [im_rest_parse_json_content -rest_otype $rest_otype -format $format -content $content]

    # write hash values as local variables
    foreach key [array names hash_array] {
	set value $hash_array($key)
	ns_log Notice "im_rest_post_object_type_$rest_otype: key=$key, value=$value"
	set $key $value
    }
    ns_log Notice "im_rest_post_object_type_$rest_otype: hash_array=[array get hash_array]"

    # write hash values as local variables
    foreach key [array names hash_array] {
	set value $hash_array($key)
	ns_log Notice "im_rest_post_object_type_$rest_otype: key=$key, value=$value"
	set $key $value
    }

    # Create optional variables if they haven't been specified in the request
    if {![info exists project_nr]} { 
	set project_nr [db_nextval "im_ticket_seq"] 
	set hash_array(project_nr) $project_nr
    }
    if {![info exists ticket_customer_contact_id]} { 
	set ticket_customer_contact_id "" 
	set hash_array(ticket_customer_contact_id) $ticket_customer_contact_id
    }
    if {![info exists ticket_start_date]} { 
	set ticket_start_date "" 
	set hash_array(ticket_start_date) $ticket_start_date
    }
    if {![info exists ticket_end_date]} { 
	set ticket_end_date "" 
	set hash_array(ticket_end_date) $ticket_end_date
    }
    if {![info exists ticket_note]} { 
	set ticket_note "" 
	set hash_array(ticket_note) $ticket_note
    }
    if {![info exists ticket_status_id]} { 
	set ticket_status_id 30000
	set hash_array(ticket_status_id) $ticket_status_id
    }
    if {![info exists ticket_type_id]} { 
	set ticket_type_id 30110
	set hash_array(ticket_type_id) $ticket_type_id
    }

    # Check that all required variables are there
    set required_vars {project_name parent_id}
    foreach var $required_vars {
	if {![info exists $var]} { 
	    return [im_rest_error -format $format -http_status 406 -message "Variable '$var' not specified. The following variables are required: $required_vars"] 
	}
    }

    # Check for duplicates
    set parent_sql "parent_id = :parent_id"
    if {"" == $parent_id} { set parent_sql "parent_id is NULL" }
    set dup_sql "
		select	count(*)
		from	im_tickets t,
			im_projects p
		where	t.ticket_id = p.project_id and
			$parent_sql and
			(upper(trim(p.project_name)) = upper(trim(:project_name)) OR
			 upper(trim(p.project_nr)) = upper(trim(:project_nr)))
    "
    if {[db_string duplicates $dup_sql]} {
	return [im_rest_error -format $format -http_status 406 -message "Duplicate $rest_otype_pretty: Your ticket_name or project_nr already exists."]
    }

    # Check for valid parent_id
    set company_id [db_string ticket_company "select company_id from im_projects where project_id = :parent_id" -default ""]
    if {"" == $company_id} {
	return [im_rest_error -format $format -http_status 406 -message "Invalid $rest_otype_pretty field 'parent_id': parent_id should represent an 'open' project of type 'Service Level Agreement'. This SLA will become the container for the ticket."]
    }

    if {[catch {
	db_transaction {

	    set rest_oid [im_ticket::new \
			      -ticket_sla_id $parent_id \
			      -ticket_name $project_name \
			      -ticket_nr $project_nr \
			      -ticket_customer_contact_id $ticket_customer_contact_id \
			      -ticket_type_id $ticket_type_id \
			      -ticket_status_id $ticket_status_id \
			      -ticket_start_date $ticket_start_date \
			      -ticket_end_date $ticket_end_date \
			      -ticket_note $ticket_note \
			     ]

	}
    } err_msg]} {
	ns_log Notice "im_rest_post_object_type_im_ticket: Error creating $rest_otype_pretty: '$err_msg'"
	return [im_rest_error -format $format -http_status 406 -message "Error creating $rest_otype_pretty: '$err_msg'."]
    }

    if {[catch {
	im_rest_object_type_update_sql \
	    -rest_otype $rest_otype \
	    -rest_oid $rest_oid \
	    -hash_array [array get hash_array]

    } err_msg]} {
	ns_log Notice "im_rest_post_object_type_im_ticket: Error creating $rest_otype_pretty during update: '$err_msg'"
	return [im_rest_error -format $format -http_status 406 -message "Error updating $rest_otype_pretty: '$err_msg'."]
    }

    # Write Audit Trail
    im_project_audit -project_id $rest_oid -action after_create
    
    ns_log Notice "im_rest_post_object_type_im_ticket: Successfully created object with object_id=$rest_oid"
    set hash_array(rest_oid) $rest_oid
    set hash_array(ticket_id) $rest_oid
    return [array get hash_array]
}


# -------------------------------------------------------
# Timesheet Task
# -------------------------------------------------------

ad_proc -private im_rest_post_object_type_im_timesheet_task {
    { -format "json" }
    { -rest_user_id 0 }
    { -content "" }
    { -hash_array_list ""}
    { -rest_oid "" }
    { -rest_otype "im_timesheet_task" }
    { -rest_otype_pretty "Timesheet Task" }
} {
    Create a new object and return its object_id
} {
    ns_log Notice "im_rest_post_object_type_$rest_otype: rest_user_id=$rest_user_id"

    # Permissions
    set add_p [im_permission $rest_user_id "add_timesheet_tasks"]
    if {!$add_p} {
	return [im_rest_error -format $format -http_status 403 -message "User #$rest_user_id does not have the right to create projects"] 
    }
    
    # Store the values into local variables
    set project_nr ""
    set project_status_id [im_project_status_open]
    set project_type_id [im_project_type_task]
    set planned_units ""
    set billable_units ""
    set percent_completed 0
    set cost_center_id ""
    set material_id ""
    set invoice_id ""
    set priority ""
    set sort_order ""
    set gantt_project_id ""
    set note ""
   
    # Extract a key-value list of variables from JSON POST request
    if {"" != $hash_array_list} {
	array set hash_array $hash_array_list
    } else {
	array set hash_array [im_rest_parse_json_content -rest_otype $rest_otype -format $format -content $content]
    }
   
    # write hash values as local variables
    foreach key [array names hash_array] {
	set value $hash_array($key)
	ns_log Notice "im_rest_post_object_type_$rest_otype: key=$key, value=$value"
	set $key $value
    }

    # Create default values if not yet set
    if {"" == $material_id} {
	set material_id [im_material_default_material_id]
	set hash_array(material_id) $material_id
    }
    if {"" == $uom_id} {
	set uom_id 320
	set hash_array(uom_id) $uom_id
    }
    if {"" == $project_nr} {
	set nr_prefix "task_"
        set nr_digits 4
	set project_nr [db_string oid "select nextval('t_acs_object_id_seq') + 1"]
	while {[string length $project_nr] < $nr_digits} { set project_nr "0$project_nr" }
        set project_nr "$nr_prefix$project_nr"
	set hash_array(project_nr) $project_nr
    }

    # Check that all required variables are there
    set required_vars {project_name project_nr parent_id project_status_id project_type_id uom_id material_id}
    foreach var $required_vars {
	if {![info exists $var]} { 
	    return [im_rest_error -format $format -http_status 406 -message "Variable '$var' not specified. The following variables are required: $required_vars"] 
	}
    }

    # More checks
    if {"" == $parent_id} {
	return [im_rest_error -format $format -http_status 406 -message "Variable 'parent_id' is not a valid project_id."]
    }

    # Check if the user has write permissions on the parent_id project
    im_project_permissions $rest_user_id $parent_id view_p read_p write_p admin_p
    if {!$write_p} {
	return [im_rest_error -format $format -http_status 406 -message "User #$rest_user_id does not have write permissions on parent project #$parent_id."]
    }

    # Check for duplicates
    set dup_sql "
		select	count(*)
		from	im_timesheet_tasks t,
			im_projects p
		where	t.task_id = p.project_id and
			p.parent_id = :parent_id and
			(upper(trim(p.project_name)) = upper(trim(:project_name)) OR
			 upper(trim(p.project_nr)) = upper(trim(:project_nr)))
    "
    if {[db_string duplicates $dup_sql]} {
	return [im_rest_error -format $format -http_status 406 -message "Duplicate $rest_otype_pretty: Your project_name='$project_name' or project_nr='$project_nr' already exists below parent_id=$parent_id."]
    }

    if {[catch {
	db_transaction {
	    set rest_oid [db_string new_task "
		SELECT im_timesheet_task__new (
			:rest_oid,		-- p_task_id
			'im_timesheet_task',	-- object_type
			now(),			-- creation_date
			:rest_user_id,		-- creation_user
			'[ad_conn peeraddr]',	-- creation_ip
			null,			-- context_id
	
			:project_nr,
			:project_name,
			:parent_id,
			:material_id,
			:cost_center_id,
			:uom_id,
			:project_type_id,
			:project_status_id,
			:note
		)
	    "]
	}
    } err_msg]} {
	ns_log Notice "im_rest_post_object_type_$rest_otype: Error creating $rest_otype_pretty: '$err_msg'"
	return [im_rest_error -format $format -http_status 406 -message "Error creating $rest_otype_pretty: '$err_msg'."]
    }


    if {[catch {
	im_rest_object_type_update_sql \
	    -rest_otype $rest_otype \
	    -rest_oid $rest_oid \
	    -hash_array [array get hash_array]

    } err_msg]} {
	return [im_rest_error -format $format -http_status 406 -message "Error updating $rest_otype_pretty: '$err_msg'."]
    }
    
    im_audit -user_id $rest_user_id -object_type $rest_otype -object_id $rest_oid -action after_create

    set hash_array(rest_oid) $rest_oid
    set hash_array(task_id) $rest_oid
    return [array get hash_array]
}


# --------------------------------------------------------
# Translation Task
# --------------------------------------------------------

ad_proc -private im_rest_post_object_type_im_trans_task {
    { -format "json" }
    { -rest_user_id 0 }
    { -content "" }
    { -rest_otype "im_trans_task" }
    { -rest_otype_pretty "Translation Task" }
} {
    Create a new object and return the object_id.
} {
    ns_log Notice "im_rest_post_object_type_$rest_otype: rest_user_id=$rest_user_id"

    # Permissions:
    # No specific permission required to create translation tasks.
    # Just write permissions on the project
    
    # Extract a key-value list of variables from JSON POST request
    array set hash_array [im_rest_parse_json_content -rest_otype $rest_otype -format $format -content $content]

    # write hash values as local variables
    foreach key [array names hash_array] {
	set value $hash_array($key)
	ns_log Notice "im_rest_post_object_type_$rest_otype: key=$key, value=$value"
	set $key $value
    }

    # Check that all required variables are there
    set required_vars {task_name project_id task_type_id task_status_id source_language_id target_language_id task_uom_id}
    foreach var $required_vars {
	if {![info exists $var]} { 
	    return [im_rest_error -format $format -http_status 406 -message "Variable '$var' not specified. The following variables are required: $required_vars"] 
	}
    }

    # Check if the user has write permissions on the parent_id project
    im_project_permissions $rest_user_id $project_id view_p read_p write_p admin_p
    if {!$write_p} {
	return [im_rest_error -format $format -http_status 406 -message "User #$rest_user_id does not have write permissions on parent project #$project_id."]
    }

    # Check for duplicate
    set dup_sql "
		select  count(*)
		from    im_trans_tasks
		where   project_id = :project_id and
			task_name = :task_name and
			target_language_id = :target_language_id
    "
    if {[db_string duplicates $dup_sql]} {
	return [im_rest_error -format $format -http_status 406 -message "Duplicate $rest_otype_pretty: Your task_name and target_language_id already exists for the specified parent_id."]
    }

    if {[catch {
	set rest_oid [db_string new_trans_task "
		select im_trans_task__new (
			null,			-- task_id
			'im_trans_task',	-- object_type
			now(),			-- creation_date
			:rest_user_id,		-- creation_user
			'[ns_conn peeraddr]',	-- creation_ip	
			null,			-- context_id	

			:project_id,		-- project_id	
			:task_type_id,		-- task_type_id	
			:task_status_id,	-- task_status_id
			:source_language_id,	-- source_language_id
			:target_language_id,	-- target_language_id
			:task_uom_id		-- task_uom_id
		)
	"]
    } err_msg]} {
	return [im_rest_error -format $format -http_status 406 -message "Error creating $rest_otype_pretty: '$err_msg'."]
    }

    if {[catch {
	im_rest_object_type_update_sql \
	    -rest_otype $rest_otype \
	    -rest_oid $rest_oid \
	    -hash_array [array get hash_array]

    } err_msg]} {
	return [im_rest_error -format $format -http_status 406 -message "Error updating $rest_otype_pretty: '$err_msg'."]
    }

    im_audit -user_id $rest_user_id -object_type $rest_otype -object_id $rest_oid -action after_create
    
    set hash_array(rest_oid) $rest_oid
    set hash_array(task_id) $rest_oid
    return [array get hash_array]
}


# --------------------------------------------------------
# Company
# --------------------------------------------------------

ad_proc -private im_rest_post_object_type_im_company {
    { -format "json" }
    { -rest_user_id 0 }
    { -content "" }
    { -rest_otype "im_company" }
    { -rest_otype_pretty "Company" }
} {
    Create a new Company and return the company_id.
} {
    ns_log Notice "im_rest_post_object_type_$rest_otype: rest_user_id=$rest_user_id"

    # Permissions
    set add_p [im_permission $rest_user_id "add_companies"]
    if {!$add_p} {
	return [im_rest_error -format $format -http_status 403 -message "User #$rest_user_id does not have the right to create companies"] 
    }

    # Extract a key-value list of variables from JSON POST request
    array set hash_array [im_rest_parse_json_content -rest_otype $rest_otype -format $format -content $content]

    # write hash values as local variables
    foreach key [array names hash_array] {
	set value $hash_array($key)
	ns_log Notice "im_rest_post_object_type_$rest_otype: key=$key, value=$value"
	set $key $value
    }

    # --------------------------------------------
    # Check that all required variables are there
    set required_vars {company_name}
    foreach var $required_vars {
	if {![info exists $var]} { 
	    return [im_rest_error -format $format -http_status 406 -message "Variable '$var' not specified. The following variables are required: $required_vars"] 
	}
    }

    # --------------------------------------------
    # Make sure the variable "company_path" exists.
    if {![info exists company_path] || "" == $company_path} {
	# Take company_name, make it lower and replace any strange chars with "_"
	set company_path [string tolower $company_name]
	regsub -all {[^a-z0-9]} $company_path "_" company_path
	set hash_array(company_path) $company_path
    }

    ns_log Notice "im_rest_post_object_type_$rest_otype: hash_array=[array get hash_array]"


    # --------------------------------------------
    # Check for duplicate
    set dup_sql "
	select	count(*)
	from	im_companies
	where	(lower(company_path) = lower(:company_path) OR
		lower(company_name) = lower(:company_name))
    "
    if {[db_string duplicates $dup_sql]} {
	return [im_rest_error -format $format -http_status 406 -message "Duplicate $rest_otype_pretty: Your company_name or company_path already exists."]
    }


    # Special case: The direction of a company is stored in it's "Office".
    # So let's create a new office if the variable "main_office_id" isn't
    # defined.
    ns_log Notice "im_rest_post_object_type_$rest_otype: Before new main_office_id for company"
    if {![info exists main_office_id] || "" == $main_office_id || 0 == $main_office_id} {

	ns_log Notice "im_rest_post_object_type_$rest_otype: Create new main_office_id for company"

	# Make sure all important fields are somehow defined
	if {![info exists office_name] || "" == $office_name} { set office_name "[im_opt_val company_name] Main Office" }
	if {![info exists office_path] || "" == $office_path} { 
	    # Take company_name, make it lower and replace any strange chars with "_"
	    set office_path [string tolower [im_opt_val company_name]]
	    regsub -all {[^a-z0-9]} $office_path "_" office_path
	}
	if {![info exists office_status_id] || "" == $office_status_id} { set office_status_id [im_office_status_active] }
	if {![info exists office_type_id] || "" == $office_type_id} { set office_type_id [im_office_type_main] }

	set main_office_id [db_string office_exists "select office_id from im_offices where office_name = :office_name" -default ""]
	
	if {"" == $main_office_id} {
	    set main_office_id [im_office::new \
				    -office_name $office_name \
				    -office_path $office_path \
				    -office_type_id $office_type_id \
				    -office_status_id $office_status_id
			       ]
	}

	if {[catch {
	    im_rest_object_type_update_sql \
		-rest_otype "im_office" \
		-rest_oid $main_office_id \
		-hash_array [array get hash_array]
	    
	} err_msg]} {
	    return [im_rest_error -format $format -http_status 406 -message "Error updating im_office: '$err_msg'."]
	}

	set hash_array(main_office_id) $main_office_id
    }

    # Create some default parameters in order to reduce the number of parameters necessary
    if {![info exists company_status_id] || "" == $company_status_id} { 
	# By default make the company "active"
	set company_status_id [im_company_status_active]
	set hash_array(company_status_id) $company_status_id
    }

    if {![info exists company_type_id] || "" == $company_type_id} { 
	# By default create a "customer" (should be more frequent then "provider"...)
	set company_type_id [im_company_type_customer]
	set hash_array(company_type_id) $company_type_id
    }


    if {[catch {
	set rest_oid [db_string new_company "
		select im_company__new (
			null,			-- task_id
			'im_company',		-- object_type
			now(),			-- creation_date
			:rest_user_id,		-- creation_user
			'[ns_conn peeraddr]',	-- creation_ip	
			null,			-- context_id	
			:company_name,
			:company_path,
			:main_office_id,
			:company_type_id,
			:company_status_id
		)
	"]
    } err_msg]} {
	return [im_rest_error -format $format -http_status 406 -message "Error creating $rest_otype_pretty: '$err_msg'."]
    }

    if {[catch {
	im_rest_object_type_update_sql \
	    -rest_otype $rest_otype \
	    -rest_oid $rest_oid \
	    -hash_array [array get hash_array]

    } err_msg]} {
	return [im_rest_error -format $format -http_status 406 -message "Error updating $rest_otype_pretty: '$err_msg'."]
    }

    im_audit -user_id $rest_user_id -object_type $rest_otype -object_id $rest_oid -action after_create
    
    set hash_array(rest_oid) $rest_oid
    set hash_array(company_id) $rest_oid
    return [array get hash_array]
}


# --------------------------------------------------------
# Absence
# --------------------------------------------------------

ad_proc -private im_rest_post_object_type_im_user_absence {
    { -format "json" }
    { -rest_user_id 0 }
    { -content "" }
    { -rest_otype "im_user_absence" }
    { -rest_otype_pretty "User Absence" }
} {
    Create a new User Absence and return the company_id.
} {
    ns_log Notice "im_rest_post_object_type_$rest_otype: rest_user_id=$rest_user_id"

    # Permissions
    set add_p [im_permission $rest_user_id "add_absences"]
    set add_all_p [im_permission $rest_user_id "add_absences_all"]
    set add_direct_reports_p [im_permission $rest_user_id "add_absences_direct_reports"]
    if {!$add_p} {
	return [im_rest_error -format $format -http_status 403 -message "User #$rest_user_id does not have the right to create absences"] 
    }

    # Extract a key-value list of variables from JSON POST request
    array set hash_array [im_rest_parse_json_content -rest_otype $rest_otype -format $format -content $content]
    ns_log Notice "im_rest_post_object_type_$rest_otype: hash_array=[array get hash_array]"

    # write hash values as local variables
    set contact_info ""
    set group_id ""
    foreach key [array names hash_array] {
	set value $hash_array($key)
	ns_log Notice "im_rest_post_object_type_$rest_otype: key=$key, value=$value"
	set $key $value
    }

    # Check that all required variables are there
    set required_vars { absence_name owner_id duration_days absence_type_id absence_status_id start_date end_date description }
    foreach var $required_vars {
	if {![info exists $var]} { 
	    return [im_rest_error -format $format -http_status 406 -message "Variable '$var' not specified. The following variables are required: $required_vars"] 
	}
    }

    # Advanced permissions are necessary to log absences for others
    if {$rest_user_id != $owner_id} {
	if {!$add_all_p} {
	    return [im_rest_error -format $format -http_status 403 -message "User #$rest_user_id does not have the right to create absences for users other than himself"]
	}
	# ToDo: Deal with privilesges add_absences_direct_reports and add_absences_all
    }  

    # Check for duplicate
    set dup_sql "
	select	count(*)
	from	im_user_absences
	where	owner_id = :owner_id and
		absence_type_id = :absence_type_id and
		start_date = :start_date
    "
    if {[db_string duplicates $dup_sql]} {
	return [im_rest_error -format $format -http_status 406 -message "Duplicate $rest_otype_pretty: Your combination of owner_id=$owner_id, start_date=$start_date and absence_type_id=$absence_type_id already exists."]
    }

    if {[catch {

	set start_date_sql [template::util::date get_property sql_timestamp $start_date]
	set end_date_sql [template::util::date get_property sql_timestamp $end_date]

	set rest_oid [db_string new_absence "
		SELECT im_user_absence__new(
			null,
			'im_user_absence',
			now(),
			:rest_user_id,
			'[ns_conn peeraddr]',
			null,

			:absence_name,
			:owner_id,
			$start_date_sql,
			$end_date_sql,

			:absence_status_id,
			:absence_type_id,
			:description,
			:contact_info
		)
	"]

	db_dml update_absence "
		update im_user_absences	set
			duration_days = :duration_days,
			group_id = :group_id
		where absence_id = :rest_oid
	"

	db_dml update_object "
		update acs_objects set
			last_modified = now()
		where object_id = :rest_oid
	"
    } err_msg]} {
	return [im_rest_error -format $format -http_status 406 -message "Error creating $rest_otype_pretty: '$err_msg'."]
    }

    if {[catch {
	im_rest_object_type_update_sql \
	    -rest_otype $rest_otype \
	    -rest_oid $rest_oid \
	    -hash_array [array get hash_array]

    } err_msg]} {
	return [im_rest_error -format $format -http_status 406 -message "Error updating $rest_otype_pretty: '$err_msg'."]
    }

    im_audit -user_id $rest_user_id -object_type $rest_otype -object_id $rest_oid -action after_create
    
    set hash_array(rest_oid) $rest_oid
    set hash_array(absence_id) $rest_oid
    return [array get hash_array]
}

# --------------------------------------------------------
# User
# --------------------------------------------------------

ad_proc -private im_rest_post_object_type_user {
    { -format "json" }
    { -rest_user_id 0 }
    { -content "" }
    { -rest_otype "user" }
    { -rest_otype_pretty "User" }
} {
    Create a new User object return the user_id.
} {
    ns_log Notice "im_rest_post_object_type_$rest_otype: Started"

    # Permissions
    set add_p [im_permission $rest_user_id "add_users"]
    if {!$add_p} {
	return [im_rest_error -format $format -http_status 403 -message "User #$rest_user_id does not have the right to create users"] 
    }

    # Extract a key-value list of variables from JSON POST request
    array set hash_array [im_rest_parse_json_content -rest_otype $rest_otype -format $format -content $content]
    ns_log Notice "im_rest_post_object_type_$rest_otype: hash_array=[array get hash_array]"

    # write hash values as local variables
    foreach key [array names hash_array] {
	set value $hash_array($key)
	ns_log Notice "im_rest_post_object_type_$rest_otype: key=$key, value=$value"
	set $key $value
    }

    # Check that all required variables are there
    set required_vars {first_names last_name}
    foreach var $required_vars {
	if {![info exists $var]} { 
	    return [im_rest_error -format $format -http_status 406 -message "Variable '$var' not specified. The following variables are required: $required_vars"] 
	}
    }

    # Fake the following required variables
    if {![info exists username] || "" == $username} { 
	set username "$first_names $last_name"
	set hash_array(username) $username
	ns_log Notice "im_rest_post_object_type_$rest_otype: Set username=$username"
    }
    if {![info exists screen_name] || "" == $screen_name} { 
	set screen_name $username 
	set hash_array(screen_name) $screen_name
	ns_log Notice "im_rest_post_object_type_$rest_otype: Set screen_name=$screen_name"
    }
    if {![info exists email] || "" == $email} { 
	set email "${first_names}.${last_name}@nowhere.com"
	set email [string tolower $email]
	regsub -all {[^a-zA-Z0-9_\-@]} $email "." email
	set hash_array(email) $email
	ns_log Notice "im_rest_post_object_type_$rest_otype: Set email=$email"
    }
    if {![info exists password] || "" == $password} { 
	set password [ad_generate_random_string] 
	set hash_array(password) $password
	ns_log Notice "im_rest_post_object_type_$rest_otype: Set password=$password"
    }
    if {![info exists url] || "" == $url} { 
	set url "" 
	set hash_array(url) $url
	ns_log Notice "im_rest_post_object_type_$rest_otype: Set url=$url"
    }

    # Check for duplicate
    set dup_sql "
		select  count(*)
		from    users u,
			persons pe,
			parties pa
		where	u.user_id = pe.person_id and
			u.user_id = pa.party_id and
			(	lower(u.username) = lower(:username) OR
				lower(pa.email) = lower(:email)
			)
    "
    if {[db_string duplicates $dup_sql]} {
	return [im_rest_error -format $format -http_status 406 -message "Duplicate $rest_otype_pretty: Your username or email already exist."]
    }

    if {[catch {
	ns_log Notice "im_rest_post_object_type_user: before auth::create_user -username $username -email $email -first_names $first_names -last_name $last_name -screen_name $screen_name -password $password -url $url"

	array set creation_info [auth::create_user \
				     -username $username \
				     -email $email \
				     -first_names $first_names \
				     -last_name $last_name \
				     -screen_name $screen_name \
				     -password $password \
				     -url $url \
				    ]
	ns_log Notice "im_rest_post_object_type_user: after auth::create_user"
	if { "ok" != $creation_info(creation_status) || "ok" != $creation_info(account_status)} {
	    ns_log Notice "im_rest_post_object_type_user: User creation unsuccessfull: [array get creation_status]"
	    return [im_rest_error -format $format -http_status 406 -message "User creation unsuccessfull: [array get creation_status]"]
	}
	set new_user_id $creation_info(user_id)
	
	# Update creation user to allow the creator to admin the user
	db_dml update_creation_user_id "
		update acs_objects
		set creation_user = :rest_user_id
		where object_id = :new_user_id
	"
    
	ns_log Notice "im_rest_post_object_type_user: person::update -person_id=$new_user_id -first_names=$first_names -last_name=$last_name"
	person::update \
		-person_id $new_user_id \
		-first_names $first_names \
		-last_name $last_name
	    
	    ns_log Notice "im_rest_post_object_type_user: party::update -party_id=$new_user_id -url=$url -email=$email"
	    party::update \
		-party_id $new_user_id \
		-url $url \
		-email $email
	    
	    ns_log Notice "im_rest_post_object_type_user: acs_user::update -rest_user_id=$new_user_id -screen_name=$screen_name"
	    acs_user::update \
		-rest_user_id $new_user_id \
		-screen_name $screen_name \
		-username $username


        # Add the user to the "Registered Users" group, because
        # (s)he would get strange problems otherwise
        # Use a non-cached version here to avoid issues!
        set registered_users [im_registered_users_group_id]
        set reg_users_rel_exists_p [db_string member_of_reg_users "
		select	count(*) 
		from	group_member_map m, membership_rels mr
		where	m.member_id = :new_user_id
			and m.group_id = :registered_users
			and m.rel_id = mr.rel_id 
			and m.container_id = m.group_id 
			and m.rel_type::text = 'membership_rel'::text
	"]
	if {!$reg_users_rel_exists_p} {
	    relation_add -member_state "approved" "membership_rel" $registered_users $new_user_id
	}

    
	# Add a im_employees record to the user since the 3.0 PostgreSQL
	# port, because we have dropped the outer join with it...
	if {[im_table_exists im_employees]} {
	    
	    # Simply add the record to all users, even it they are not employees...
	    set im_employees_exist [db_string im_employees_exist "select count(*) from im_employees where employee_id = :new_user_id"]
	    if {!$im_employees_exist} {
		db_dml add_im_employees "insert into im_employees (employee_id) values (:new_user_id)"
	    }
	}
	
	
	# Add a im_freelancers record to the user since the 3.0 PostgreSQL
	# port, because we have dropped the outer join with it...
	if {[im_table_exists im_freelancers]} {
	    
	    # Simply add the record to all users, even it they are not freelancers...
	    set im_freelancers_exist [db_string im_freelancers_exist "select count(*) from im_freelancers where user_id = :new_user_id"]
	    if {!$im_freelancers_exist} {
		db_dml add_im_freelancers "insert into im_freelancers (user_id) values (:new_user_id)"
	    }
	}

    } err_msg]} {
	return [im_rest_error -format $format -http_status 406 -message "Error creating $rest_otype_pretty: '$err_msg'."]
    }

    if {[catch {
	im_rest_object_type_update_sql \
	    -rest_otype $rest_otype \
	    -rest_oid $new_user_id \
	    -hash_array [array get hash_array]
    } err_msg]} {
	return [im_rest_error -format $format -http_status 406 -message "Error updating $rest_otype_pretty: '$err_msg'."]
    }

    im_audit -user_id $rest_user_id -object_type $rest_otype -object_id $new_user_id -action after_create

    set rest_oid $new_user_id

    set hash_array(rest_oid) $rest_oid
    set hash_array(user_id) $rest_oid
    return [array get hash_array]
}


# --------------------------------------------------------
# Invoices
# --------------------------------------------------------

ad_proc -private im_rest_post_object_type_im_invoice {
    { -format "json" }
    { -rest_user_id 0 }
    { -content "" }
    { -rest_otype "im_invoice" }
    { -rest_otype_pretty "Financial Document" }
} {
    Create a new Financial Document and return the task_id.
} {
    ns_log Notice "im_rest_post_object_type_$rest_otype: rest_user_id=$rest_user_id"

    # Permissions
    set add_p [im_permission $rest_user_id "add_invoices"]
    if {!$add_p} {
	return [im_rest_error -format $format -http_status 403 -message "User #$rest_user_id does not have the right to create invoices"] 
    }

    # Store the key-value pairs into local variables
    set note ""
    set amount 0
    set currency "EUR"
    set vat ""
    set tax ""
    set payment_days 0
    set payment_method_id ""
    set template_id ""
    set company_contact_id ""
    set effective_date [db_string effdate "select now()::date"]


    # Extract a key-value list of variables from JSON POST request
    array set hash_array [im_rest_parse_json_content -rest_otype $rest_otype -format $format -content $content]
    ns_log Notice "im_rest_post_object_type_$rest_otype: hash_array=[array get hash_array]"

    # write hash values as local variables
    foreach key [array names hash_array] {
	set value $hash_array($key)
	ns_log Notice "im_rest_post_object_type_$rest_otype: key=$key, value=$value"
	set $key $value
    }

    # Check that all required variables are there
    set required_vars { invoice_nr customer_id provider_id cost_status_id cost_type_id}
    foreach var $required_vars {
	if {![info exists $var]} { 
	    return [im_rest_error -format $format -http_status 406 -message "Variable '$var' not specified. The following variables are required: $required_vars"] 
	}
    }

    # Check for duplicate
    set dup_sql "
		select  count(*)
		from    im_invoices
		where	invoice_nr = :invoice_nr
    "
    if {[db_string duplicates $dup_sql]} {
	return [im_rest_error -format $format -http_status 406 -message "Duplicate $rest_otype_pretty: Your specified invoice_nr='$invoice_nr' already exists."]
    }

    if {[catch {
	set rest_oid [db_string new_invoice "
		select im_invoice__new (
			NULL,			-- invoice_id
			'im_invoice',		-- object_type
			now(),			-- creation_date 
			:rest_user_id,		-- creation_user
			'[ad_conn peeraddr]',	-- creation_ip
			null,			-- context_id

			:invoice_nr,		-- invoice_nr
			:customer_id,		-- customer_id
			:provider_id,		-- provider_id
			:company_contact_id,	-- company_contact_id
			:effective_date,	-- effective_date
			:currency,		-- currency
			:template_id,		-- template_id
			:cost_status_id,	-- cost_status_id
			:cost_type_id,		-- cost_type_id
			:payment_method_id,	-- payment_method_id
			:payment_days,		-- payment_days
			:amount,		-- amount
			:vat,			-- vat
			:tax,			-- tax
			:note			-- note
		)
	"]
    } err_msg]} {
	return [im_rest_error -format $format -http_status 406 -message "Error creating $rest_otype_pretty: '$err_msg'."]
    }

    if {[catch {
	im_rest_object_type_update_sql \
	    -rest_otype $rest_otype \
	    -rest_oid $rest_oid \
	    -hash_array [array get hash_array]

    } err_msg]} {
	return [im_rest_error -format $format -http_status 406 -message "Error updating $rest_otype_pretty: '$err_msg'."]
    }

    im_audit -user_id $rest_user_id -object_type $rest_otype -object_id $rest_oid -action after_create
    
    set hash_array(rest_oid) $rest_oid
    set hash_array(invoice_id) $rest_oid
    return [array get hash_array]
}


ad_proc -private im_rest_post_object_type_im_trans_invoice {
    { -format "json" }
    { -rest_user_id 0 }
    { -content "" }
    { -rest_otype "im_trans_invoice" }
    { -rest_otype_pretty "Translation Financial Document" }
} {
    Create a new object and return the object_id
} {
    ns_log Notice "im_rest_post_object_type_$rest_otype: rest_user_id=$rest_user_id"

    # Permissions
    set add_p [im_permission $rest_user_id "add_invoices"]
    if {!$add_p} {
	return [im_rest_error -format $format -http_status 403 -message "User #$rest_user_id does not have the right to create translation invoices"] 
    }
    
    set rest_oid [ \
		       im_rest_post_object_type_im_trans_invoice \
			-format $format \
    			-rest_user_id $rest_user_id \
			-content $content \
			-rest_otype $rest_otype \
			-rest_otype_pretty $rest_otype_pretty \
    ]
    db_dml insert_trans_invoice "
	insert into im_trans_invoices (invoice_id) values (:rest_oid)
    "
    db_dml update_trans_invoice "
	update	acs_objects
	set	object_type = 'im_trans_invoice'
	where	object_id = :rest_oid
    "

    im_audit -user_id $rest_user_id -object_type $rest_otype -object_id $rest_oid -action after_create

    set hash_array(rest_oid) $rest_oid
    set hash_array(invoice_id) $rest_oid
    return [array get hash_array]
}


# --------------------------------------------------------
# Invoice Items - It's not really an object type,
# so we have to fake it here.
# --------------------------------------------------------

ad_proc -private im_rest_post_object_type_im_invoice_item {
    { -format "json" }
    { -rest_user_id 0 }
    { -content "" }
    { -rest_otype "im_invoice_item" }
    { -rest_otype_pretty "Financial Document Item" }
} {
    Create a new Financial Document line and return the item_id.
} {
    ns_log Notice "im_rest_post_object_type_$rest_otype: rest_user_id=$rest_user_id"

    # Permissions
    set add_p [im_permission $rest_user_id "add_invoices"]
    if {!$add_p} {
	return [im_rest_error -format $format -http_status 403 -message "User #$rest_user_id does not have the right to create invoice items"] 
    }

    # store the key-value pairs into a hash array
    set description ""
    set item_material_id ""
    set item_type_id ""
    set item_status_id ""
    set invoice_id ""
    set project_id ""


    # Extract a key-value list of variables from JSON POST request
    array set hash_array [im_rest_parse_json_content -rest_otype $rest_otype -format $format -content $content]
    ns_log Notice "im_rest_post_object_type_$rest_otype: hash_array=[array get hash_array]"

    # write hash values as local variables
    foreach key [array names hash_array] {
	set value $hash_array($key)
	ns_log Notice "im_rest_post_object_type_$rest_otype: key=$key, value=$value"
	set $key $value
    }

    # Check that all required variables are there
    set required_vars { item_name invoice_id sort_order item_uom_id item_units price_per_unit currency }
    foreach var $required_vars {
	if {![info exists $var]} { 
	    return [im_rest_error -format $format -http_status 406 -message "Variable '$var' not specified. The following variables are required: $required_vars"] 
	}
    }

    # Check for duplicate
    set dup_sql "
		select  count(*)
		from    im_invoice_items
		where	item_name = :item_name and
			invoice_id = :invoice_id and
			sort_order = :sort_order
    "
    if {[db_string duplicates $dup_sql]} {
	return [im_rest_error -format $format -http_status 406 -message "Duplicate $rest_otype_pretty: Your item already exists with the specified invoice_name, invoice_id and sort_order."]
    }

    if {[catch {
	set rest_oid [db_string item_id "select nextval('im_invoice_items_seq')"]
	db_dml new_invoice_item "
		insert into im_invoice_items (
			item_id,
			item_name,
			invoice_id,
			item_uom_id,
			sort_order
		) values (
			:rest_oid,
			:item_name,
			:invoice_id,
			:item_uom_id,
			:sort_order
		)
	"
    } err_msg]} {
	return [im_rest_error -format $format -http_status 406 -message "Error creating $rest_otype_pretty: '$err_msg'."]
    }

    if {[catch {
	im_rest_object_type_update_sql \
	    -rest_otype $rest_otype \
	    -rest_oid $rest_oid \
	    -hash_array [array get hash_array]

    } err_msg]} {
	return [im_rest_error -format $format -http_status 406 -message "Error updating $rest_otype_pretty: '$err_msg'."]
    }

    # re-calculate the amount of the invoice
    im_invoice_update_rounded_amount -invoice_id $invoice_id 

    # No audit here, invoice_item is not a real object
    # im_audit -user_id $rest_user_id -object_type $rest_otype -object_id $rest_oid -action after_create

    set hash_array(rest_oid) $rest_oid
    set hash_array(item_id) $rest_oid
    return [array get hash_array]
}


# --------------------------------------------------------
# im_hour
# Not an object type really, so we have to fake it here.
# --------------------------------------------------------


ad_proc -private im_rest_post_object_type_im_hour {
    { -format "json" }
    { -rest_user_id 0 }
    { -content "" }
    { -rest_otype "im_hour" }
    { -rest_otype_pretty "Timesheet Hour" }
} {
    Create a new Timesheet Hour line and return the item_id.
} {
    ns_log Notice "im_rest_post_object_type_$rest_otype: rest_user_id=$rest_user_id"

    # Permissions
    set add_p [im_permission $rest_user_id "add_hours"]
    set add_all_p [im_permission $rest_user_id "add_hours_all"]
    if {!$add_p} {
	return [im_rest_error -format $format -http_status 403 -message "User #$rest_user_id does not have the right to create hours"] 
    }

    # Extract a key-value list of variables from JSON POST request
    array set hash_array [im_rest_parse_json_content -rest_otype $rest_otype -format $format -content $content]
    ns_log Notice "im_rest_post_object_type_$rest_otype: hash_array=[array get hash_array]"

    # write hash values as local variables
    foreach key [array names hash_array] {
	set value $hash_array($key)
	ns_log Notice "im_rest_post_object_type_$rest_otype: key=$key, value=$value"
	set $key $value
    }

    # Check that all required variables are there
    set required_vars { user_id project_id day hours note }
    foreach var $required_vars {
	if {![info exists $var]} { 
	    return [im_rest_error -format $format -http_status 406 -message "Variable '$var' not specified. The following variables are required: $required_vars"] 
	}
    }

    # Hour permissions
    if {$user_id != $rest_user_id} {
	if {!$add_all_p} {
	    return [im_rest_error -format $format -http_status 403 -message "User #$rest_user_id does not have the right to create hours for others than himself"] 
	}
    }
    
    # Check for duplicate
    set dup_sql "
		select  count(*)
		from    im_hours
		where	user_id = :user_id and
			project_id = :project_id and
			day = :day
    "
    if {[db_string duplicates $dup_sql]} {
	return [im_rest_error -format $format -http_status 406 -message "Duplicate $rest_otype_pretty: Your item already exists with the specified user, project and day."]
    }

    if {[catch {
	set rest_oid [db_string item_id "select nextval('im_hours_seq')"]
	db_dml new_im_hour "
		insert into im_hours (
			hour_id,
			user_id,
			project_id,
			day,
			hours,
			note
		) values (
			:rest_oid,
			:user_id,
			:project_id,
			:day,
			:hours,
			:note
		)
	"
    } err_msg]} {
	return [im_rest_error -format $format -http_status 406 -message "Error creating $rest_otype_pretty: '$err_msg'."]
    }

    if {[catch {
	im_rest_object_type_update_sql \
	    -rest_otype $rest_otype \
	    -rest_oid $rest_oid \
	    -hash_array [array get hash_array]

    } err_msg]} {
	return [im_rest_error -format $format -http_status 406 -message "Error updating $rest_otype_pretty: '$err_msg'."]
    }

    # Not a real object, so no audit!
    # im_audit -user_id $rest_user_id -object_type $rest_otype -object_id $rest_oid -action after_create

    set hash_array(rest_oid) $rest_oid
    set hash_array(hour_id) $rest_oid
    return [array get hash_array]
}


# --------------------------------------------------------
# im_hour_interval
# Not an object type really, so we have to fake it here.
# --------------------------------------------------------


ad_proc -private im_rest_post_object_type_im_hour_interval {
    { -format "json" }
    { -rest_user_id 0 }
    { -content "" }
    { -rest_otype "im_hour_interval" }
    { -rest_otype_pretty "Timesheet Interval" }
} {
    Create a new Timesheet Hour line and return the item_id.
} {
    ns_log Notice "im_rest_post_object_type_$rest_otype: rest_user_id=$rest_user_id"

    # Permissions
    set add_p [im_permission $rest_user_id "add_hours"]
    set add_all_p [im_permission $rest_user_id "add_hours_all"]
    if {!$add_p} {
	return [im_rest_error -format $format -http_status 403 -message "User #$rest_user_id does not have the right to add hours"] 
    }

    # Extract a key-value list of variables from JSON POST request
    array set hash_array [im_rest_parse_json_content -rest_otype $rest_otype -format $format -content $content]
    ns_log Notice "im_rest_post_object_type_$rest_otype: hash_array=[array get hash_array]"

    # write hash values as local variables
    foreach key [array names hash_array] {
	set value $hash_array($key)
	ns_log Notice "im_rest_post_object_type_$rest_otype: key=$key, value=$value"
	set $key $value
    }

    # Check that all required variables are there
    set required_vars { user_id project_id interval_start interval_end note }
    foreach var $required_vars {
	if {![info exists $var]} { 
	    return [im_rest_error -format $format -http_status 406 -message "Variable '$var' not specified. The following variables are required: $required_vars"] 
	}
	
	# Fix timestamp format between JavaScript and PostgreSQL 8.4/9.x
	# Wed Jul 23 2014 19:23:26 GMT+0200 (Romance Daylight Time)
	switch $var {
	    interval_start - interval_end {
		set val [im_rest_normalize_timestamp [im_opt_val $var]]
		set $var $val
		set hash_array($var) $val
	    }
	}

    }

    # Permission Check: Only log hours for yourself
    if {$user_id != $rest_user_id} { 
	return [im_rest_error -format $format -http_status 403 -message "You can log hours only for yourself."] 
    }

    # Check for duplicate
    set dup_sql "
		select  count(*)
		from    im_hour_intervals
		where	user_id = :user_id and
			project_id = :project_id and
			interval_start = :interval_start
    "
    if {[db_string duplicates $dup_sql]} {
	return [im_rest_error -format $format -http_status 406 -message "Duplicate $rest_otype_pretty: Your item already exists with the specified user, project and interval_start."]
    }

    # Create the new object
    if {[catch {
	set rest_oid [db_string item_id "select nextval('im_hour_intervals_seq')"]
	db_dml new_im_hour_interval "
		insert into im_hour_intervals (
			interval_id,
			user_id,
			project_id,
			interval_start,
			interval_end,
			note
		) values (
			:rest_oid,
			:user_id,
			:project_id,
			:interval_start,
			:interval_end,
			:note
		)
	"
    } err_msg]} {
	return [im_rest_error -format $format -http_status 406 -message "Error creating $rest_otype_pretty: '$err_msg'."]
    }

    if {[catch {
	im_rest_object_type_update_sql \
	    -rest_otype $rest_otype \
	    -rest_oid $rest_oid \
	    -hash_array [array get hash_array]
    } err_msg]} {
	return [im_rest_error -format $format -http_status 406 -message "Error updating $rest_otype_pretty: '$err_msg'."]
    }

    # Not a real object, so no audit!
    # im_audit -user_id $rest_user_id -object_type $rest_otype -object_id $rest_oid -action after_create

    set hash_array(rest_oid) $rest_oid
    set hash_array(interval_id) $rest_oid
    return [array get hash_array]
}





# --------------------------------------------------------
# Task Dependencies - It's not really an object type,
# so we have to fake it here.
# --------------------------------------------------------

ad_proc -private im_rest_post_object_type_im_timesheet_task_dependency {
    { -format "json" }
    { -rest_user_id 0 }
    { -content "" }
    { -rest_otype "im_timesheet_task_dependency" }
    { -rest_otype_pretty "Timesheet Task Dependency" }
} {
    Create a new task dependency and return the id.
} {
    ns_log Notice "im_rest_post_object_type_$rest_otype: rest_user_id=$rest_user_id"

    # Permissions
    set add_p [im_permission $rest_user_id "add_timesheet_tasks"]
    if {!$add_p} {
	return [im_rest_error -format $format -http_status 403 -message "User #$rest_user_id does not have the right to create timesheet task dependencies"] 
    }

    # Extract a key-value list of variables from JSON POST request
    array set hash_array [im_rest_parse_json_content -rest_otype $rest_otype -format $format -content $content]
    ns_log Notice "im_rest_post_object_type_$rest_otype: hash_array=[array get hash_array]"

    # Set default variables
    if {![info exists hash_array(dependency_status_id)] || "" == $hash_array(dependency_status_id) } { set hash_array(dependency_status_id) 9740 }
    if {![info exists hash_array(dependency_type_id)] || "" == $hash_array(dependency_type_id) } { set hash_array(dependency_type_id) 9650 }
    if {![info exists hash_array(difference)] || "" == $hash_array(difference) } { set hash_array(difference) 0 }
    if {![info exists hash_array(hardness_type_id)]} { set hash_array(hardness_type_id) "" }

    # write hash values as local variables
    foreach key [array names hash_array] {
	set value $hash_array($key)
	ns_log Notice "im_rest_post_object_type_$rest_otype: key=$key, value=$value"
	set $key $value
    }

    # Check that all required variables are there
    set required_vars {task_id_one task_id_two dependency_type_id}
    foreach var $required_vars {
	if {![info exists $var]} { 
	    return [im_rest_error -format $format -http_status 406 -message "Variable '$var' not specified. The following variables are required: $required_vars"] 
	}
    }

    # Check for duplicate
    set dup_sql "
		select  dependency_id
		from    im_timesheet_task_dependencies
		where	task_id_one = :task_id_one and
			task_id_two = :task_id_two
    "
    set rest_oid [db_string duplicate $dup_sql -default ""]
    if {"" != $rest_oid} {
	ns_log Warning "im_rest_post_object_type_$rest_otype: duplicate dependency: task_id_one=$task_id_one, task_id_two=$task_id_two"
	set hash_array(rest_oid) $rest_oid
	set hash_array(dependency_id) $rest_oid
	return [array get hash_array]
	# return [im_rest_error -format $format -http_status 406 -message "Duplicate $rest_otype_pretty: Your objectalready exists with the specified task_id_one and task_id_two."]
    }

    if {[catch {
	set rest_oid [db_string item_id "select nextval('im_timesheet_task_dependency_seq')"]
	db_dml new_timesheet_task_dependency "
		insert into im_timesheet_task_dependencies (
			dependency_id,
			task_id_one,
			task_id_two,
			dependency_type_id,
			dependency_status_id,
			difference,
			hardness_type_id
		) values (
			:rest_oid,
			:task_id_one,
			:task_id_two,
			:dependency_type_id,
			:dependency_status_id,
			:difference,
			:hardness_type_id
		)
	"
    } err_msg]} {
	return [im_rest_error -format $format -http_status 406 -message "Error creating $rest_otype_pretty: '$err_msg'."]
    }

    if {[catch {
	im_rest_object_type_update_sql \
	    -rest_otype $rest_otype \
	    -rest_oid $rest_oid \
	    -hash_array [array get hash_array]
    } err_msg]} {
	return [im_rest_error -format $format -http_status 406 -message "Error updating $rest_otype_pretty: '$err_msg'."]
    }

    set hash_array(rest_oid) $rest_oid
    set hash_array(dependency_id) $rest_oid
    return [array get hash_array]
}

# --------------------------------------------------------
# im_note
#

ad_proc -private im_rest_post_object_type_im_note {
    { -format "json" }
    { -rest_user_id 0 }
    { -rest_otype "" }
    { -rest_otype_pretty "Note" }
    { -rest_oid "" }
    { -content "" }
    { -debug 0 }
} {
    Handler for POST calls on particular im_note objects.
    im_note is not a real object type and performs a "delete" 
    operation specifying hours=0 or hours="".
} {
    ns_log Notice "im_rest_post_object_im_note: rest_oid=$rest_oid"

    # Permissions
    set add_p [im_permission $rest_user_id "add_projects"]
    if {!$add_p} {
	return [im_rest_error -format $format -http_status 403 -message "User #$rest_user_id does not have the right to create projects"] 
    }

    set creation_user $rest_user_id
    set creation_ip [ad_conn peeraddr]


    # Extract a key-value list of variables from JSON POST request
    array set hash_array [im_rest_parse_json_content -rest_otype $rest_otype -format $format -content $content]
    ns_log Notice "im_rest_post_object_type_$rest_otype: hash_array=[array get hash_array]"

    # write hash values as local variables
    foreach key [array names hash_array] {
	set value $hash_array($key)
	ns_log Notice "im_rest_post_object_type_$rest_otype: key=$key, value=$value"
	set $key $value
    }

    # Check that all required variables are there
    set required_vars {note note_status_id note_type_id object_id}
    foreach var $required_vars {
	if {![info exists $var]} { 
	    return [im_rest_error -format $format -http_status 406 -message "Variable '$var' not specified. The following variables are required: $required_vars"] 
	}
    }

    # Check for duplicate
    set dup_sql "
	select	count(*)
	from	im_notes
	where	note = :note and
		object_id = :object_id
    "
    if {[db_string duplicates $dup_sql]} {
	return [im_rest_error -format $format -http_status 406 -message "Duplicate $rest_otype_pretty: The note already exists for the specified object."]
    }

    if {[catch {
	set rest_oid [db_string new_im_note "
		select im_note__new (
			null,			-- note_id
			:rest_otype,		-- object_type
			now(),			-- creation_date
			:creation_user,
			:creation_ip,
			null,			-- context_id

			:note,
			:object_id,
			:note_type_id,
			:note_status_id
		)
	"]
    } err_msg]} {
	return [im_rest_error -format $format -http_status 406 -message "Error creating $rest_otype_pretty: '$err_msg'."]
    }
   
    im_audit -user_id $rest_user_id -object_type $rest_otype -object_id $rest_oid -status_id $note_status_id -type_id $note_type_id -action after_create

    set hash_array(rest_oid) $rest_oid
    set hash_array(rel_id) $rest_oid
    return [array get hash_array]
}



# --------------------------------------------------------
# Membership Relationshiop
# --------------------------------------------------------

ad_proc -private im_rest_post_object_type_membership_rel {
    { -format "json" }
    { -rest_user_id 0 }
    { -content "" }
    { -rest_otype "membership_rel" }
    { -rest_otype_pretty "Membership Relationship" }
} {
    Create a new object and return the object_id.
} {
    ns_log Notice "im_rest_post_object_type_$rest_otype: rest_user_id=$rest_user_id"

    # Permissions
    set add_p [im_permission $rest_user_id "add_projects"]
    if {!$add_p} {
	return [im_rest_error -format $format -http_status 403 -message "User #$rest_user_id does not have the right to create projects"] 
    }



    # Store values into local variables
    set rel_type "membership_rel"
    set member_state "appoved"
    set creation_user $rest_user_id
    set creation_ip [ad_conn peeraddr]


    # Extract a key-value list of variables from JSON POST request
    array set hash_array [im_rest_parse_json_content -rest_otype $rest_otype -format $format -content $content]
    ns_log Notice "im_rest_post_object_type_$rest_otype: hash_array=[array get hash_array]"

    # write hash values as local variables
    foreach key [array names hash_array] {
	set value $hash_array($key)
	ns_log Notice "im_rest_post_object_type_$rest_otype: key=$key, value=$value"
	set $key $value
    }

    # Check that all required variables are there
    set required_vars {object_id_one object_id_two}
    foreach var $required_vars {
	if {![info exists $var]} { 
	    return [im_rest_error -format $format -http_status 406 -message "Variable '$var' not specified. The following variables are required: $required_vars"] 
	}
    }

    # Check for duplicate
    set dup_sql "
	select	count(*)
	from	acs_rels
	where	rel_type = :rest_otype and
		object_id_one = :object_id_one and
		object_id_two = :object_id_two
    "
    if {[db_string duplicates $dup_sql]} {
	return [im_rest_error -format $format -http_status 406 -message "Duplicate $rest_otype_pretty: Your company_name or company_path already exists."]
    }

    if {[catch {
	set rest_oid [db_string new_membership_rel "
		select membership_rel__new (
			null,			-- task_id
			:rest_otype,		-- object_type
			:object_id_one,
			:object_id_two,
			:member_state,
			:rest_user_id,		-- creation_user
			'[ns_conn peeraddr]'
		)
	"]
    } err_msg]} {
	return [im_rest_error -format $format -http_status 406 -message "Error creating $rest_otype_pretty: '$err_msg'."]
    }
   
    im_audit -user_id $rest_user_id -object_type $rest_otype -object_id $rest_oid -action after_create

    set hash_array(rest_oid) $rest_oid
    set hash_array(rel_id) $rest_oid
    return [array get hash_array]
}


# --------------------------------------------------------
# Business Object Membership
# --------------------------------------------------------

ad_proc -private im_rest_post_object_type_im_biz_object_member {
    { -format "json" }
    { -rest_user_id 0 }
    { -content "" }
    { -rest_otype "im_biz_object_member" }
    { -rest_otype_pretty "Biz Object Relationship" }
} {
    Create a new object and return the object_id.
} {
    ns_log Notice "im_rest_post_object_type_$rest_otype: rest_user_id=$rest_user_id"

    # Permissions
    set add_p [im_permission $rest_user_id "add_projects"]
    if {!$add_p} {
	return [im_rest_error -format $format -http_status 403 -message "User #$rest_user_id does not have the right to create projects"] 
    }


    # Store values into local variables
    set rel_type $rest_otype
    set creation_ip [ad_conn peeraddr]
    set sort_order ""

    # Extract a key-value list of variables from JSON POST request
	ns_log Notice "im_rest_post_object_type_$rest_otype: Now parsing json content ..."
    array set hash_array [im_rest_parse_json_content -rest_otype $rest_otype -format $format -content $content]
    ns_log Notice "im_rest_post_object_type_$rest_otype: hash_array=[array get hash_array]"

    # write hash values as local variables
    foreach key [array names hash_array] {
	set value $hash_array($key)
	ns_log Notice "im_rest_post_object_type_$rest_otype: key=$key, value=$value"
	set $key $value
    }

    # Check that all required variables are there
    set required_vars {object_id_one object_id_two}
    foreach var $required_vars {
	if {![info exists $var]} { 
	    ns_log Notice "im_rest_post_object_type_$rest_otype: Variable '$var' not specified. The following variables are required: $required_vars"	
	    return [im_rest_error -format $format -http_status 406 -message "Variable '$var' not specified. The following variables are required: $required_vars"] 
	}
    }

	ns_log Notice "im_rest_post_object_type_$rest_otype: Found all necessary var's" 

    if {![info exists percentage]} { set percentage "" }
    if {![info exists object_role_id]} { set object_role_id [im_biz_object_role_full_member] }

    # Check for duplicate
    set dup_sql "
	select	min(rel_id)
	from	acs_rels
	where	rel_type = :rest_otype and
		object_id_one = :object_id_one and
		object_id_two = :object_id_two
    "
    set rest_oid [db_string duplicates $dup_sql -default ""]

    if {"" == $rest_oid} {
	# Add the new relationship only if it doesn't exist yet
	# Gracefully handle duplicates
	if {[catch {
	    ns_log Notice "im_rest_post_object_type_$rest_otype: Now calling im_biz_object_member__new ..."
	    set rest_oid [db_string new_im_biz_object_member "
				select im_biz_object_member__new (
					null,			-- rel_id
					:rest_otype,		-- rel_type
					:object_id_one,
					:object_id_two,
					:object_role_id,	-- full member, project manager, key account manger, ...
					:percentage,		-- percentage of assignment
					:rest_user_id,		-- Creation user
					'[ns_conn peeraddr]'	-- Connection IP address for audit
				)
	    "]
	} err_msg]} {
	    ns_log Notice "im_rest_post_object_type_$rest_otype: Error creating $rest_otype_pretty: '$err_msg'."
	    return [im_rest_error -format $format -http_status 406 -message "Error creating $rest_otype_pretty: '$err_msg'."]
	}
   
	im_audit -user_id $rest_user_id -object_type $rest_otype -object_id $rest_oid -action after_create
    } else {
	ns_log Notice "im_rest_post_object_type_$rest_otype: im_biz_object_member__new skipped, found rest_oid: $rest_oid"
    }

    set hash_array(rest_oid) $rest_oid
    set hash_array(rel_id) $rest_oid
    return [array get hash_array]
}



# --------------------------------------------------------
# Ticket-Ticket Relationshiop
# --------------------------------------------------------

ad_proc -private im_rest_post_object_type_im_ticket_ticket_rel {
    { -format "json" }
    { -rest_user_id 0 }
    { -content "" }
    { -rest_otype "im_ticket_ticket_rel" }
    { -rest_otype_pretty "Ticket-Ticket Relationship" }
} {
    Create a new object and return the object_id.
} {
    ns_log Notice "im_rest_post_object_type_$rest_otype: rest_user_id=$rest_user_id"

    # Permissions
    set add_p [im_permission $rest_user_id "add_projects"]
    if {!$add_p} {
	return [im_rest_error -format $format -http_status 403 -message "User #$rest_user_id does not have the right to create projects"] 
    }

    # Store values into local variables
    set rel_type $rest_otype
    set creation_ip [ad_conn peeraddr]
    set sort_order ""


    # Extract a key-value list of variables from JSON POST request
    array set hash_array [im_rest_parse_json_content -rest_otype $rest_otype -format $format -content $content]
    ns_log Notice "im_rest_post_object_type_$rest_otype: hash_array=[array get hash_array]"

    # write hash values as local variables
    foreach key [array names hash_array] {
	set value $hash_array($key)
	ns_log Notice "im_rest_post_object_type_$rest_otype: key=$key, value=$value"
	set $key $value
    }


    # Check that all required variables are there
    set required_vars {object_id_one object_id_two}
    foreach var $required_vars {
	if {![info exists $var]} { 
	    return [im_rest_error -format $format -http_status 406 -message "Variable '$var' not specified. The following variables are required: $required_vars"] 
	}
    }

    # Check for duplicate
    set dup_sql "
	select	count(*)
	from	acs_rels
	where	rel_type = :rest_otype and
		object_id_one = :object_id_one and
		object_id_two = :object_id_two
    "
    if {[db_string duplicates $dup_sql]} {
	return [im_rest_error -format $format -http_status 406 -message "Duplicate $rest_otype_pretty: Your company_name or company_path already exists."]
    }

    if {[catch {
	set rest_oid [db_string new_im_ticket_ticket_rel "
		select im_ticket_ticket_rel__new (
			null,			-- task_id
			:rest_otype,		-- object_type
			:object_id_one,
			:object_id_two,
			null,			-- context_id
			:rest_user_id,
			'[ns_conn peeraddr]'
		)
	"]
    } err_msg]} {
	return [im_rest_error -format $format -http_status 406 -message "Error creating $rest_otype_pretty: '$err_msg'."]
    }
   
    im_audit -user_id $rest_user_id -object_type $rest_otype -object_id $rest_oid -action after_create

    set hash_array(rest_oid) $rest_oid
    set hash_array(rel_id) $rest_oid
    return [array get hash_array]
}


# --------------------------------------------------------
# Key-Account Relationship
# --------------------------------------------------------

ad_proc -private im_rest_post_object_type_im_key_account_rel {
    { -format "json" }
    { -rest_user_id 0 }
    { -content "" }
    { -rest_otype "im_key_account_rel" }
    { -rest_otype_pretty "Key Account Relationship" }
} {
    Create a new object and return the object_id.
} {
    ns_log Notice "im_rest_post_object_type_$rest_otype: rest_user_id=$rest_user_id"

    # Permissions
    set add_p [im_permission $rest_user_id "add_projects"]
    if {!$add_p} {
	return [im_rest_error -format $format -http_status 403 -message "User #$rest_user_id does not have the right to create projects"] 
    }

    
    # Store values into local variables
    set rel_type $rest_otype
    set creation_ip [ad_conn peeraddr]
    set sort_order ""


    # Extract a key-value list of variables from JSON POST request
    array set hash_array [im_rest_parse_json_content -rest_otype $rest_otype -format $format -content $content]
    ns_log Notice "im_rest_post_object_type_$rest_otype: hash_array=[array get hash_array]"

    # write hash values as local variables
    foreach key [array names hash_array] {
	set value $hash_array($key)
	ns_log Notice "im_rest_post_object_type_$rest_otype: key=$key, value=$value"
	set $key $value
    }


    # Check that all required variables are there
    set required_vars {object_id_one object_id_two}
    foreach var $required_vars {
	if {![info exists $var]} { 
	    return [im_rest_error -format $format -http_status 406 -message "Variable '$var' not specified. The following variables are required: $required_vars"] 
	}
    }

    # Check for duplicate
    set dup_sql "
	select	count(*)
	from	acs_rels
	where	rel_type = :rest_otype and
		object_id_one = :object_id_one and
		object_id_two = :object_id_two
    "
    if {[db_string duplicates $dup_sql]} {
	return [im_rest_error -format $format -http_status 406 -message "Duplicate $rest_otype_pretty: Your company_name or company_path already exists."]
    }

    if {[catch {
	set rest_oid [db_string new_im_key_account_rel "
		select im_key_account_rel__new (
			null,			-- task_id
			:rest_otype,		-- object_type
			:object_id_one,
			:object_id_two,
			null,			-- context_id
			:rest_user_id,
			'[ns_conn peeraddr]'
		)
	"]
    } err_msg]} {
	return [im_rest_error -format $format -http_status 406 -message "Error creating $rest_otype_pretty: '$err_msg'."]
    }

    im_audit -user_id $rest_user_id -object_type $rest_otype -object_id $rest_oid -action after_create
   
    set hash_array(rest_oid) $rest_oid
    set hash_array(rel_id) $rest_oid
    return [array get hash_array]
}


# --------------------------------------------------------
# Company-Employee Relationship
# --------------------------------------------------------

ad_proc -private im_rest_post_object_type_im_company_employee_rel {
    { -format "json" }
    { -rest_user_id 0 }
    { -content "" }
    { -rest_otype "im_company_employee_rel" }
    { -rest_otype_pretty "Company Employee Relationship" }
} {
    Create a new object and return the object_id.
} {
    ns_log Notice "im_rest_post_object_type_$rest_otype: rest_user_id=$rest_user_id"

    # Permissions
    set add_p [im_permission $rest_user_id "add_projects"]
    if {!$add_p} {
	return [im_rest_error -format $format -http_status 403 -message "User #$rest_user_id does not have the right to create projects"] 
    }


    # Store values into local variables
    set rel_type $rest_otype
    set creation_ip [ad_conn peeraddr]
    set sort_order ""


    # Extract a key-value list of variables from JSON POST request
    array set hash_array [im_rest_parse_json_content -rest_otype $rest_otype -format $format -content $content]
    ns_log Notice "im_rest_post_object_type_$rest_otype: hash_array=[array get hash_array]"

    # write hash values as local variables
    foreach key [array names hash_array] {
	set value $hash_array($key)
	ns_log Notice "im_rest_post_object_type_$rest_otype: key=$key, value=$value"
	set $key $value
    }

    # Check that all required variables are there
    set required_vars {object_id_one object_id_two}
    foreach var $required_vars {
	if {![info exists $var]} { 
	    return [im_rest_error -format $format -http_status 406 -message "Variable '$var' not specified. The following variables are required: $required_vars"] 
	}
    }

    # Check for duplicate
    set dup_sql "
	select	count(*)
	from	acs_rels
	where	rel_type = :rest_otype and
		object_id_one = :object_id_one and
		object_id_two = :object_id_two
    "
    if {[db_string duplicates $dup_sql]} {
	return [im_rest_error -format $format -http_status 406 -message "Duplicate $rest_otype_pretty: Your company_name or company_path already exists."]
    }

    if {[catch {
	set rest_oid [db_string new_im_company_employee_rel "
		select im_company_employee_rel__new (
			null,			-- task_id
			:rest_otype,		-- object_type
			:object_id_one,
			:object_id_two,
			null,			-- context_id
			:rest_user_id,
			'[ns_conn peeraddr]'
		)
	"]
    } err_msg]} {
	return [im_rest_error -format $format -http_status 406 -message "Error creating $rest_otype_pretty: '$err_msg'."]
    }

    im_audit -user_id $rest_user_id -object_type $rest_otype -object_id $rest_oid -action after_create
   
    set hash_array(rest_oid) $rest_oid
    set hash_array(rel_id) $rest_oid
    return [array get hash_array]
}


# --------------------------------------------------------
# im_sencha_preference
#

ad_proc -private im_rest_post_object_type_im_sencha_preference {
    { -format "json" }
    { -rest_user_id 0 }
    { -rest_otype "" }
    { -rest_otype_pretty "Sencha Preference" }
    { -rest_oid "" }
    { -content "" }
    { -debug 0 }
} {
    Handler for POST calls on particular im_sencha_preference objects.
} {
    ns_log Notice "im_rest_post_object_im_sencha_preference: rest_oid=$rest_oid"
    set creation_user $rest_user_id
    set creation_ip [ad_conn peeraddr]

    # Extract a key-value list of variables from JSON POST request
    array set hash_array [im_rest_parse_json_content -rest_otype $rest_otype -format $format -content $content]
    ns_log Notice "im_rest_post_object_type_$rest_otype: hash_array=[array get hash_array]"

    # Default values for not required vars
    if {![info exists hash_array(preference_status_id)] || "" == $hash_array(preference_status_id)} { set hash_array(preference_status_id) [im_sencha_preference_status_active] }
    if {![info exists hash_array(preference_type_id)] || "" == $hash_array(preference_type_id)} { set hash_array(preference_type_id) [im_sencha_preference_type_default] }
    if {![info exists hash_array(preference_object_id)] || "" == $hash_array(preference_object_id)} { set hash_array(preference_object_id) $rest_user_id }


    # Permissions
    # No permissions are necessary if the user changes preferences for preference_object_id = current_user_id
    set preference_object_id $hash_array(preference_object_id)
    if {$rest_user_id != $preference_object_id} {
	set object_type [util_memoize [list db_string object_type "select object_type from acs_objects where object_id = $preference_object_id" -default ""]]
	if {"" == $object_type} {
	    return [im_rest_error -format $format -http_status 403 -message "Could not find preference_object_id=$preference_object_id."] 
	}
	set perm_cmd "${object_type}_permissions \$user_id \$object_id view_p read_p write_p admin_p"
	eval $perm_cmd
	if {!$write_p} {
	    return [im_rest_error -format $format -http_status 403 -message "You don not have write permissions on object_id=$preference_object_id"] 
	}
    }

    # write hash values as local variables
    foreach key [array names hash_array] {
	set value $hash_array($key)
	set $key $value
    }

    # Check that all required variables are there
    set required_vars {preference_url preference_key preference_value}
    foreach var $required_vars {
	if {![info exists $var]} { 
	    return [im_rest_error -format $format -http_status 406 -message "Variable '$var' not specified. The following variables are required: $required_vars"] 
	}
    }

    # Check for duplicate
    set dup_sql "
	select	preference_id
	from	im_sencha_preferences
	where	preference_object_id = :preference_object_id and
		preference_url = :preference_url and
		preference_key = :preference_key
    "
    set rest_oid [db_string duplicates $dup_sql -default 0]
    if {$rest_oid} {
	# Exception: Just update the preference.
	db_dml update_preference "
		update im_sencha_preferences set
			preference_value = :preference_value
		where	preference_id = :rest_oid
        "
	im_audit -user_id $rest_user_id -object_type $rest_otype -object_id $rest_oid -status_id $preference_status_id -type_id $preference_type_id -action after_update
    } else {
	# Create a new preference
	if {[catch {
	    set rest_oid [db_string new_im_sencha_preference "
		select im_sencha_preference__new (
			null,			-- preference_id
			:rest_otype,		-- object_type
			now(),			-- creation_date
			:creation_user,
			:creation_ip,
			null,			-- context_id

			:preference_type_id,
			:preference_status_id,
			:preference_object_id,
			:preference_url,
			:preference_key,
			:preference_value
		)
	    "]
	} err_msg]} {
	    return [im_rest_error -format $format -http_status 406 -message "Error creating $rest_otype_pretty: '$err_msg'."]
	}

	im_audit -user_id $rest_user_id -object_type $rest_otype -object_id $rest_oid -status_id $preference_status_id -type_id $preference_type_id -action after_create
    }
   
    set hash_array(rest_oid) $rest_oid
    return [array get hash_array]
}

# --------------------------------------------------------
# im_sencha_column_config
#

ad_proc -private im_rest_post_object_type_im_sencha_column_config {
    { -format "json" }
    { -rest_user_id 0 }
    { -rest_otype "" }
    { -rest_otype_pretty "Sencha Column Config" }
    { -rest_oid "" }
    { -content "" }
    { -debug 0 }
} {
    Handler for POST calls on particular im_sencha_column_config objects.
} {
    ns_log Notice "im_rest_post_object_im_sencha_column_config: rest_oid=$rest_oid"
    set creation_user $rest_user_id
    set creation_ip [ad_conn peeraddr]

    # Extract a key-value list of variables from JSON POST request
    array set hash_array [im_rest_parse_json_content -rest_otype $rest_otype -format $format -content $content]
    ns_log Notice "im_rest_post_object_type_$rest_otype: hash_array=[array get hash_array]"

    # Default values for not required vars
    if {![info exists hash_array(column_config_status_id)] || "" == $hash_array(column_config_status_id)} { set hash_array(column_config_status_id) [im_sencha_column_config_status_active] }
    if {![info exists hash_array(column_config_type_id)] || "" == $hash_array(column_config_type_id)} { set hash_array(column_config_type_id) [im_sencha_column_config_type_default] }
    if {![info exists hash_array(column_config_object_id)] || "" == $hash_array(column_config_object_id)} { set hash_array(column_config_object_id) $rest_user_id }


    # Permissions
    # No permissions are necessary if the user changes column_configs for column_config_object_id = current_user_id
    set column_config_object_id $hash_array(column_config_object_id)
    if {$rest_user_id != $column_config_object_id} {
	set object_type [util_memoize [list db_string object_type "select object_type from acs_objects where object_id = $column_config_object_id" -default ""]]
	if {"" == $object_type} {
	    return [im_rest_error -format $format -http_status 403 -message "Could not find column_config_object_id=$column_config_object_id."] 
	}
	set perm_cmd "${object_type}_permissions \$user_id \$object_id view_p read_p write_p admin_p"
	eval $perm_cmd
	if {!$write_p} {
	    return [im_rest_error -format $format -http_status 403 -message "You don not have write permissions on object_id=$column_config_object_id"] 
	}
    }

    # write hash values as local variables
    foreach key [array names hash_array] {
	set value $hash_array($key)
	set $key $value
    }

    # Check that all required variables are there
    set required_vars {column_config_url column_config_name}
    foreach var $required_vars {
	if {![info exists $var]} { 
	    return [im_rest_error -format $format -http_status 406 -message "Variable '$var' not specified. The following variables are required: $required_vars"] 
	}
    }

    # Check for duplicate
    set dup_sql "
	select	column_config_id
	from	im_sencha_column_configs
	where	column_config_object_id = :column_config_object_id and
		column_config_url = :column_config_url and
		column_config_name = :column_config_name
    "
    set rest_oid [db_string duplicates $dup_sql -default 0]
    if {0 == $rest_oid} {
	# Create a new column_config
	if {[catch {
	    set rest_oid [db_string new_im_sencha_column_config "
		select im_sencha_column_config__new (
			null,			-- column_config_id
			:rest_otype,		-- object_type
			now(),			-- creation_date
			:creation_user,
			:creation_ip,
			null,			-- context_id

			:column_config_type_id,
			:column_config_status_id,
			:column_config_object_id,
			:column_config_url,
			:column_config_name
		)
	    "]
	} err_msg]} {
	    return [im_rest_error -format $format -http_status 406 -message "Error creating $rest_otype_pretty: '$err_msg'."]
	}
    }

    if {[catch {
	im_rest_object_type_update_sql \
	    -rest_otype $rest_otype \
	    -rest_oid $rest_oid \
	    -hash_array [array get hash_array]
    } err_msg]} {
	return [im_rest_error -format $format -http_status 406 -message "Error updating $rest_otype_pretty: '$err_msg'."]
    }

    im_audit -user_id $rest_user_id -object_type $rest_otype -object_id $rest_oid -status_id $column_config_status_id -type_id $column_config_type_id -action after_create
   
    set hash_array(rest_oid) $rest_oid
    return [array get hash_array]
}

