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
# Creation of Projects, Translation Tasks, Invoices etc.
# -------------------------------------------------------

ad_proc -private im_rest_post_im_project {
    { -format "xml" }
    { -user_id 0 }
    { -content "" }
} {
    Create a new project and returns the project_id.
} {
    ns_log Notice "im_rest_post_im_project: user_id=$user_id"

    # store the key-value pairs into a hash array
    if {[catch {set doc [dom parse $content]} err_msg]} {
	return [im_rest_error -http_status 406 -message "Unable to parse XML: '$err_msg'."]
    }

    set root_node [$doc documentElement]
    foreach child [$root_node childNodes] {
	set nodeName [$child nodeName]
	set nodeText [$child text]
	
	# Store the values
	set hash($nodeName) $nodeText
	set $nodeName $nodeText
    }

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
	return [im_rest_error -http_status 406 -message "Duplicate Project: Your project name or project path already exists for the specified parent_id."]
    }

    if {[catch {
	set rest_oid [project::new \
			-creation_user	    $user_id \
			-context_id	    "" \
			-project_name       $hash(project_name) \
			-project_nr	 $hash(project_nr) \
			-project_path       $hash(project_path) \
			-company_id	 $hash(company_id) \
			-parent_id	  $hash(parent_id) \
			-project_type_id    $hash(project_type_id) \
			-project_status_id  $hash(project_status_id) \
	]
    } err_msg]} {
	return [im_rest_error -http_status 406 -message "Error creating project: '$err_msg'."]
    }

    if {[catch {
	im_rest_object_type_update_sql \
	    -rest_otype "im_project" \
	    -rest_oid $rest_oid \
	    -hash_array [array get hash]

    } err_msg]} {
	return [im_rest_error -http_status 406 -message "Error updating project: '$err_msg'."]
    }
    
    return $rest_oid
}



# --------------------------------------------------------
# Translation Task
# --------------------------------------------------------

ad_proc -private im_rest_post_im_trans_task {
    { -format "xml" }
    { -user_id 0 }
    { -content "" }
} {
    Create a new Translation Task and return the task_id.
} {
    ns_log Notice "im_rest_post_im_trans_task: user_id=$user_id"

    # store the key-value pairs into a hash array
    if {[catch {set doc [dom parse $content]} err_msg]} {
	return [im_rest_error -http_status 406 -message "Unable to parse XML: '$err_msg'."]
    }

    set root_node [$doc documentElement]
    foreach child [$root_node childNodes] {
	set nodeName [$child nodeName]
	set nodeText [$child text]
	
	# Store the values
	set hash($nodeName) $nodeText
	set $nodeName $nodeText
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
	return [im_rest_error -http_status 406 -message "Duplicate Translation Task: Your translation task name already exists for the specified parent_id."]
    }

    if {[catch {
	set rest_oid [db_string new_trans_task "
		select im_trans_task__new (
			null,			-- task_id
			'im_trans_task',	-- object_type
			now(),			-- creation_date
			:user_id,		-- creation_user
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
	return [im_rest_error -http_status 406 -message "Error creating translation task: '$err_msg'."]
    }

    if {[catch {
	im_rest_object_type_update_sql \
	    -rest_otype "im_trans_task" \
	    -rest_oid $rest_oid \
	    -hash_array [array get hash]

    } err_msg]} {
	return [im_rest_error -http_status 406 -message "Error updating translation task: '$err_msg'."]
    }
    
    return $rest_oid
}


# --------------------------------------------------------
# Invoices
# --------------------------------------------------------

ad_proc -private im_rest_post_im_invoice {
    { -format "xml" }
    { -user_id 0 }
    { -content "" }
} {
    Create a new Financial Document and return the task_id.
} {
    ns_log Notice "im_rest_post_im_invoice: user_id=$user_id"

    # store the key-value pairs into a hash array
    if {[catch {set doc [dom parse $content]} err_msg]} {
	return [im_rest_error -http_status 406 -message "Unable to parse XML: '$err_msg'."]
    }

    set note ""

    set root_node [$doc documentElement]
    foreach child [$root_node childNodes] {
	# Store the values
	set nodeName [$child nodeName]
	set nodeText [$child text]
	set hash($nodeName) $nodeText
	set $nodeName $nodeText
    }

    # Check for duplicate
    set dup_sql "
		select  count(*)
		from    im_invoices
		where	invoice_nr = :invoice_nr
    "
    if {[db_string duplicates $dup_sql]} {
	return [im_rest_error -http_status 406 -message "Duplicate Financial Document: Your financial document already exists with the specified invoice_nr='$invoice_nr'."]
    }

    if {[catch {
	set rest_oid [db_string new_invoice "
		select im_invoice__new (
			NULL,			-- invoice_id
			'im_invoice',		-- object_type
			now(),			-- creation_date 
			:user_id,		-- creation_user
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
			0,			-- amount
			:vat,			-- vat
			:tax,			-- tax
			:note			-- note
		)
	"]
    } err_msg]} {
	return [im_rest_error -http_status 406 -message "Error creating financial document: '$err_msg'."]
    }

    if {[catch {
	im_rest_object_type_update_sql \
	    -rest_otype "im_invoice" \
	    -rest_oid $rest_oid \
	    -hash_array [array get hash]

    } err_msg]} {
	return [im_rest_error -http_status 406 -message "Error updating financial document: '$err_msg'."]
    }
    
    return $rest_oid
}


# --------------------------------------------------------
# Invoices
# --------------------------------------------------------

ad_proc -private im_rest_post_im_invoice_item {
    { -format "xml" }
    { -user_id 0 }
    { -content "" }
} {
    Create a new Financial Document line and return the item_id.
} {
    ns_log Notice "im_rest_post_im_invoice_item: user_id=$user_id"

    # store the key-value pairs into a hash array
    if {[catch {set doc [dom parse $content]} err_msg]} {
	return [im_rest_error -http_status 406 -message "Unable to parse XML: '$err_msg'."]
    }

    set root_node [$doc documentElement]
    foreach child [$root_node childNodes] {
	# Store the values
	set nodeName [$child nodeName]
	set nodeText [$child text]
	set hash($nodeName) $nodeText
	set $nodeName $nodeText
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
	return [im_rest_error -http_status 406 -message "Duplicate Financial Document Item: Your item already exists with the specified invoice_name, invoice_id and sort_order."]
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
	return [im_rest_error -http_status 406 -message "Error creating financial document item: '$err_msg'."]
    }

    if {[catch {
	im_rest_object_type_update_sql \
	    -rest_otype "im_invoice_item" \
	    -rest_oid $rest_oid \
	    -hash_array [array get hash]

    } err_msg]} {
	return [im_rest_error -http_status 406 -message "Error updating financial document item: '$err_msg'."]
    }

    # re-calculate the amount of the invoice
    im_invoice_update_rounded_amount -invoice_id $invoice_id 
    
    return $rest_oid
}


# --------------------------------------------------------
# 
# --------------------------------------------------------

