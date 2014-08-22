# /packages/intranet-rest/tcl/intranet-rest-sql-parser.tcl
#
# Copyright (C) 2009 ]project-open[
#
# All rights reserved. Please check
# http://www.project-open.com/license/ for details.

ad_library {
    REST Web Service Library
    Utility functions
    @author frank.bergmann@project-open.com
}

# ----------------------------------------------------------------------
# SQL Parser
# ----------------------------------------------------------------------

ad_proc -public sql_select {str} {
    ns_log Notice "sql_select: $str"
    set str_org $str
    if {"select" != [lindex $str 0]} { return [list "" $str_org "Not a select - 'select' expected as first literal"] }
    set str [lrange $str 1 end]

    # [ DISTINCT | ALL ]
    set s0 [lindex $str 0]
    if {"distinct" == $s0 || "all" == $s0} {
	set str [lrange $str 1 end]
    }

    # ( '*' | functions | value_litteral { ',' value_litteral } )
    set continue 1
    set select_cols [list]
    while {$continue} {
	set s0 [sql_exact $str "*"]
	if {"" == [lindex $s0 0]} { set s0 [sql_functions $str] }
	if {"" == [lindex $s0 0]} { set s0 [sql_value_litteral $str] }
	if {"" == [lindex $s0 0]} { return [list "" $str_org "Select - expecting '*', function or literal"] }
	lappend select_cols [lindex s0 0]
	set str [lindex $s0 1]

	set komma [sql_exact $str ","]
	set str [lindex $komma 1]
	if {"," != [lindex $komma 0]} { set continue 0 }
    }

    # 'from' from_table_reference { ',', from_table_reference}
    set from [sql_exact $str "from"]
    if {"" == [lindex $from 0]} { return [list "" $str_org "Select - expecting 'from'"] }
    set str [lindex $from 1]

    set t0 [sql_from_table_reference $str]
    if {"" == [lindex $t0 0]} { return [list "" $str_org "Select - expecting table reference after 'from'"] }
    set table_references [list $t0]
    
    set komma [sql_exact $str ","]
    while {"," == [lindex $komma 0]} {
	set str [lrange $str 1 end]
	set t1 [sql_from_table_reference $str]
	if {"" == [lindex $t1 0]} { return [list "" $str_org "Select - expecting table reference after ','"] }
	set str [lindex $t1 1]
	lappend table_references $t1
	set komma [sql_exact $str ","]
    }

    # [ 'where' search_condition ]
    set where [sql_exact $str "where"]
    if {"" == [lindex $where 0]} { 
	set str [lindex $where 1]
	set search_condition [sql_search_condition $str]
	if {"" == [lindex $search_condition 0]} { return [list "" $str_org "Select - expecting search_condition after 'where'"] }
	set str [lindex $search_condition 1]
    }

    return [list [list select ] $str ""]

}

# search_condition = search_value { ( 'or' | 'and' ) search_condition }.
ad_proc -public sql_search_condition {str} {
    ns_log Notice "sql_search_condition: $str"

    set conditions [list]
    set continue 1
    while {$continue} {
	set s0 [sql_search_value $str]
	if {"" == [lindex $s0 0]} { return [list "" $str "Not a search_condition - expecting a search_value"] }
	set str [lindex $s0 1]
	lappend conditions [lindex $s0 0]

	set conj [sql_exact $str "and"]
	if {"" == [lindex $conj 0]} { set conj [sql_exact $str "or"] }
	set str [lindex $conj 1]
	
	if {"" == [lindex $conj 0]} { set continue 0 }
    }
    
    return [list $conditions $str ""]
}


# search_value = 
# 	value_litteral [ 'not' ] ( between | like | in | compare | containing | starting ) |
#	'is' [ 'not' ] 'null' |
#	('all' | 'some' | 'any') '(' select_column_list ')' |
#	'exists' '(' select_expression ')' |
#	'singular' '(' select_expression ')' | 
#	'(' search_condition ')' | 
#	'not' search_condition.
ad_proc -public sql_search_value {str} {
    ns_log Notice "sql_search_value: $str"
    set str_org $str

    # value_litteral [ 'not' ] ( between | like | in | compare | containing | starting ) |
    set v0 [sql_value_litteral $str]
    if {"" != [lindex $v0 0]} {
	set str [lindex $v0 1]

	# Optional 'not' - simply ignore error of sql_exact
	set not [sql_exact $str "not"]
	set str [lindex $not 1]

	set cont [list ""]
	if {"" == [lindex $cont 0]} { set cont [sql_between $str] }
	if {"" == [lindex $cont 0]} { set cont [sql_like $str] }
	if {"" == [lindex $cont 0]} { set cont [sql_in $str] }
	if {"" == [lindex $cont 0]} { set cont [sql_compare $str] }
	if {"" == [lindex $cont 0]} { set cont [sql_containing $str] }
	if {"" == [lindex $cont 0]} { set cont [sql_starting $str] }
	if {"" == [lindex $cont 0]} { return [list "" $str_org "Not a search value - expecting between, like, in, compare, containing or starting after value_litteral"] }
	set str [lindex $cont 1]

	return [list $v0 [lindex $cont 0]  $str ""]
    }

    # 'is' [ 'not' ] 'null' |
    set is [sql_exact $str "is"]
    if {"" != [lindex $is 0]} {
	set str [lindex $is 1]

	# Optional 'not' - simply ignore error of sql_exact
	set not [sql_exact $str "not"]
	set str [lindex $not 1]

	set null [sql_exact $str "null"]
	if {"" == [lindex $null 0]} { return [list "" $str_org "Not a search value - expecting 'null' after 'is'"] }
	set str [lindex $null 1]

	return [list "is [lindex $not 0] null" $str ""]
    }

ad_return_complaint 1 $v0

    
    # '(' search_condition ')'
    set par [sql_exact $str "("]
    if {"" != [lindex $par 0]} {
	set str [lindex $par 1]

	set s0 [sql_search_condition $str]
	if {"" == [lindex $s0 0]} { return [list "" $str_org "Not a search value - expecting search_condition after '('"] }
	set str [lindex $s0 1]

	set par [sql_exact $str ")"]
	if {"" == [lindex $par 0]} { return [list "" $str_org "Not a search value - expecting ')' after search_condition"] }
	set str [lindex $par 1]

	return [ [lindex $s0 0] $str ""]
    }

    # 'not' search_condition
    set not [sql_exact $str "not"]
    if {"" != [lindex $not 0]} {
	set str [lindex $not 1]
	set s0 [sql_search_condition $str]
	if {"" == [lindex $s0 0]} { return [list "" $str_org "Not a search value - expecting search_condition after 'not'"] }
	set str [lindex $s0 1]
	return [[list "not" [lindex $s0 0]] $str ""]
    }

    return ["" $str "Not a search value - found none of the options"]
}




# between = 'between' value_litteral 'and' value_litteral.
ad_proc -public sql_between {str} {
    ns_log Notice "sql_between: $str"
    if {"between" != [lindex $str 0]} { return [list "" $str "Not a between - 'between' expected as first literal"] }
    set str [lrange $str 1 end]
    set b1 [sql_value_litteral $str]
    if {"" == [lindex $b1 0]} { return [list "" $str "Not a between - literal expected as 2nd literal"] }
    set str [lindex $b1 1]
    if {"and" != [lindex $str 0]} { return [list "" $str "Not a between - 'and' expected as 3rd literal"] }
    set str [lrange $str 1 end]
    set b2 [sql_value_litteral $str]
    if {"" == [lindex $b2 0]} { return [list "" $str "Not a between - literal expected as 4th literal"] }
    set str [lindex $b2 1]
    
    return [list [list between [lindex $b1 0] and [lindex $b2 0]] $str ""]
}

# from_table_reference = name procedure_end | joined_table.
ad_proc -public sql_from_table_reference {str} {
    ns_log Notice "sql_from_table_reference: $str"

    set name [sql_name $str]
    if {"" == [lindex $name 0]} { return [list "" $str "Not a from_table_reference - expecting a name as first literal"] }
    set str [lindex $name 1]

    set procedure_end [sql_procedure_end $str]
    if {"" == [lindex $procedure_end 0]} { return $name }

    set str [lindex $procedure_end 1]
    return [list [list [lindex $name 0] [lindex $procedure_end 0]] $str ""]
}

#  procedure_end= [ '(' value_litteral { ',' value_litteral } ')' ] [ alias_name ] .
ad_proc -public sql_procedure_end {str} {
    ns_log Notice "sql_procedure_end: $str"
    set str_org $str

    set par_open [sql_exact $str "("]
    if {"" == [lindex $par_open 0]} { return [list "" $str_org "Not a procedure_end - expecting '(' as first literal"] }
    set str [lrange $str 1 end]

    set v0 [sql_value_litteral $str]
    set values [list [lindex $v0 0]]
    if {"" == [lindex $v0 0]} { return [list "" $str_org "Not a procedure_end - expecting literal after '('"] }
    set str [lindex $v0 1]

    set komma [sql_exact $str ","]
    while {"," == [lindex $komma 0]} {
        set str [lindex $komma 1]
        set v1 [sql_value_litteral $str]
        if {"" == [lindex $v1 0]} { return [list "" $str_org "Not a procedure_end - found non-literal between '(' and ')'"] }
        set str [lindex $v1 1]
        lappend values [lindex $v1 0]
        set komma [sql_exact $str ","]
    }
    set str [lindex $komma 1]

    set par_close [sql_exact $str ")"]
    if {"" == [lindex $par_close 0]} { return [list "" $str_org "Not a procedure_end - expecting ')' as last literal"] }
    set str [lindex $par_close 1]

    set alias [sql_name $str]
    if {"" != [lindex $alias 0]} { lappend values "([lindex $alias 0])" }
    set str [lindex $alias 1]

    return [list $values $str ""]
}

ad_proc -public sql_value_litteral {str} {
    ns_log Notice "sql_value_litteral: $str"
    set int [sql_integer $str]
    if {"" != [lindex $int 0]} { return $int }
    set name [sql_name $str]
    if {"" != [lindex $name 0]} { return $name }
    return [list "" $str]
}

ad_proc -public sql_exact {str exact} {
    ns_log Notice "sql_exact: $str '$exact'"
    if {$exact == [lindex $str 0]} { return [list $exact [lrange $str 1 end] ""] }
    return [list "" $str "Not an exact($exact)"]
}

ad_proc -public sql_name {str} {
    ns_log Notice "sql_name: $str"

    set keyword [sql_keyword $str]
    if {"" != [lindex $keyword 0]} {
	# Found a keywork - so this is NOT a name...
	return [list "" $str "Not a name - is a keyword"]
    }

    set name [lindex $str 0]
    if {[regexp {^[[:alnum:]_]+$} $name match]} { return [list $name [lrange $str 1 end] ""] }
    return [list "" $str "Not a name - contains non-name characters"]
}

ad_proc -public sql_integer {str} {
    ns_log Notice "sql_integer: $str"
    set int [lindex $str 0]
    if {[regexp {^[0-9]+$} $int match]} { return [list $int [lrange $str 1 end] ""] }
    return [list "" $str "Not an integer - contains non-integer characters"]
}

ad_proc -public sql_keyword {str} {
    ns_log Notice "sql_keyword: $str"

    set s0 [lindex $str 0]
    set keywords {all and any asc ascending avg between by collate containing count desc descending distinct escape exists from full group having in is inner insert into join left like lower max min not null or order outer right set singular some starting sum table union update upper values where with}
    set found_keyword ""
    foreach keyword $keywords {
	if {$s0 == $keyword} { return [list $keyword [lrange $str 1 end] ""] }
    }
    return [list "" $str "Not a keyword"]
}



# ----------------------------------------------------------------------
# SQL Parser Test Cases
# ----------------------------------------------------------------------


ad_proc -public sql_assert { 
    type str
} {
    Checks that the string str is of sql type "type".
} {
    set cmd [list $type $str]
    set result [eval $cmd]

    if {"" == [lindex $result 0] || "" != [lindex $result 1] || "" != [lindex $result 2]} {
	ns_log Error "sql_assert: $str is $type: failed with message: '[lindex $result 2]' and unparsed: '[lindex $result 1]'"
    } else {
	ns_log Notice "sql_assert: $str is $type: OK"
    }
    return $result
}

ad_proc -public sql_non_assert { 
    type str
} {
    Checks that the string str is NOT of sql type "type".
} {
    set cmd [list $type $str]
    set result [eval $cmd]

    if {"" == [lindex $result 0] || "" != [lindex $result 1] || "" != [lindex $result 2]} {
	return [list "" $str ""]
    } else {
	return [list "" $str "sql_assert: $str is $type: mistakenly passed"]
    }
    return $result
}


ad_proc -public sql_test {

} {
    Executes a number of checks
} {
    set e [list]

    # keyword
    lappend e [sql_assert sql_keyword "and"]
    lappend e [sql_assert sql_keyword "where"]
    lappend e [sql_assert sql_keyword "between"]

    # integer
    lappend e [sql_assert sql_integer "1234"]
    lappend e [sql_non_assert sql_integer "1234x"]

    # name
    lappend e [sql_assert sql_name "asf"]
    lappend e [sql_assert sql_name "a6sf2"]
    lappend e [sql_non_assert sql_name "as&f"]
    lappend e [sql_non_assert sql_name "from"]

    # from_table_reference
    lappend e [sql_assert sql_from_table_reference "func ( a , b ) alias"]

    # select
    lappend e [sql_assert sql_select "select * from test1"]
    lappend e [sql_assert sql_select "select * from test1 , test2"]
    lappend e [sql_assert sql_select "select * from test1 , test2 where 1 = 2"]

    # sql_search_value
    lappend e [sql_assert sql_search_value "var is not null"]
    lappend e [sql_assert sql_search_value "var < 10"]
    lappend e [sql_assert sql_search_value "( var > 20 )"]
    lappend e [sql_assert sql_search_value "not (var != 30)"]
    lappend e [sql_assert sql_search_value "var like '%asdf%'"]
    lappend e [sql_assert sql_search_value "exists (select * from users)"]
	       
    # -------------------------
    set cnt 0
    set errors [list]
    foreach entry $e {
	incr cnt
	if {"" != [lindex $entry 2]} {
	    lappend errors $entry
	}
    }
    lappend errors [list "" "" "$cnt tests executed"]
    return $errors
}

