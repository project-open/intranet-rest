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
# SQL Validator
# ----------------------------------------------------------------------

ad_proc -public im_rest_valid_sql {
    -string:required
    {-variables {} }
    {-debug 1}
} {
    Returns 1 if "where_clause" is a valid where_clause or 0 otherwise.
    ToDo:
    <ul>
    <li>Single quote quoting: Does not handle correctly 
    </ul>
} {
    # An empty string is a valid SQL...
    if {"" == $string} { return 1 }

    # ------------------------------------------------------
    # Massage the string so that it suits the rule engine.
    # Reduce all characters to lower case
    set string [string tolower $string]
    # Add spaces around the string
    set string " $string "
    # Add an extra space between all "comparison" strings in the where clause
    regsub -all {([\>\<\=\!]+)} $string { \1 } string
    # Add an extra space around parentesis
    regsub -all {([\(\)])} $string { \1 } string
    # Add an extra space around kommas
    regsub -all {(,)} $string { \1 } string
    # Replace multiple spaces by a single one
    regsub -all {\s+} $string { } string
    # Eliminate leading space
    if {" " == [string range $string 0 0]} { set string [string range $string 1 end] }

    set result [sql_search_condition $string]
    set parsed_term [lindex $result 0]
    set remaining_string [string trim [lindex $result 1]]
    set error_message [lindex $result 2]

    # ad_return_complaint 1 "<pre>parsed=$parsed_term\nrem=$remaining_string\nerr=$error_message"

    if {"" == $remaining_string} {
	# Nothing remaining - everything is parsed correctly
	return 1
    } else {
	# Something is left - error
	return 0
    }
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
	if {"" == [lindex $s0 0]} { set s0 [sql_function_count $str] }
	if {"" == [lindex $s0 0]} { set s0 [sql_function $str] }
	if {"" == [lindex $s0 0]} { set s0 [sql_value_litteral $str] }
	if {"" == [lindex $s0 0]} { return [list "" $str_org "Select - expecting '*', function or literal"] }
	lappend select_cols [lindex $s0 0]
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
    set str [lindex $t0 1]
    if {"" == [lindex $t0 0]} { return [list "" $str_org "Select - expecting table reference after 'from'"] }
    set table_references [list [lindex $t0 0]]
    
    set komma [sql_exact $str ","]
    set str [lindex $komma 1]
    while {"," == [lindex $komma 0]} {
	set t1 [sql_from_table_reference $str]
	if {"" == [lindex $t1 0]} { return [list "" $str_org "Select - expecting table reference after ','"] }
	set str [lindex $t1 1]
	lappend table_references $t1
	set komma [sql_exact $str ","]
	set str [lindex $komma 1]
    }

    # [ 'where' search_condition ]
    set where [sql_exact $str "where"]
    set str [lindex $where 1]
    set search_condition ""
    if {"" != [lindex $where 0]} { 
	set search_condition [sql_search_condition $str]
	if {"" == [lindex $search_condition 0]} { return [list "" $str_org "Select - expecting search_condition after 'where'"] }
	set str [lindex $search_condition 1]
    }

    return [list [list select $select_cols $table_references [lindex $search_condition 0]] $str ""]

}

# search_condition = search_value { ( 'or' | 'and' ) search_condition }.
ad_proc -public sql_search_condition {str} {
    ns_log Notice "sql_search_condition: '$str'"

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

    # Search for simple keyword to start with 
    set kw [lindex $str 0]
    switch $kw {
	"(" {
	    # '(' search_condition ')'
	    set str [lrange $str 1 end]
	    set s0 [sql_search_condition $str]
	    if {"" == [lindex $s0 0]} { return [list "" $str_org "Not a search value - expecting search_condition after '('"] }
	    set str [lindex $s0 1]
	    
	    set par [sql_exact $str ")"]
	    if {"" == [lindex $par 0]} { return [list "" $str_org "Not a search value - expecting ')' after search_condition"] }
	    set str [lindex $par 1]
	    
	    return [list [lindex $s0 0] $str ""]
	}
	"not" {
	    # 'not' search_condition
	    set str [lrange $str 1 end]
	    set s0 [sql_search_condition $str]
	    if {"" == [lindex $s0 0]} { return [list "" $str_org "Not a search value - expecting search_condition after 'not'"] }
	    set str [lindex $s0 1]
	    return [list [list "not" [lindex $s0 0]] $str ""]
	}
	"is" {
	    # 'is' [ 'not' ] 'null' |
	    set str [lrange $str 1 end]
	    # Optional 'not' - simply ignore error of sql_exact
	    set not [sql_exact $str "not"]
	    set str [lindex $not 1]
	    
	    set null [sql_exact $str "null"]
	    if {"" == [lindex $null 0]} { return [list "" $str_org "Not a search value - expecting 'null' after 'is'"] }
	    set str [lindex $null 1]
	    
	    return [list "is [lindex $not 0] null" $str ""]
	}
    }

    # value_litteral [ 'not' ] ( between | like | in | compare | containing | starting ) |
    set v0 [sql_value_litteral $str]
    if {"" != [lindex $v0 0]} {
	set str [lindex $v0 1]

	# Optional 'not' - simply ignore error of sql_exact
	set not [sql_exact $str "not"]
	set str [lindex $not 1]

	set cont [list ""]
	set kw [lindex $str 0]
	set op [sql_operator $str]
	if {"" != [lindex $op 0]} { set kw "compare" }
	switch $kw {
	    "between" {
		set cont [sql_between $str]
		if {"" == [lindex $cont 0]} { return [list "" $str_org "Not a search_value - invalid 'between' clause"] }
	    }
	    "compare" {
		set cont [sql_compare $str]
		if {"" == [lindex $cont 0]} { return [list "" $str_org "Not a search_value - invalid 'compare' clause"] }
	    }
	    "containing" {
		set cont [sql_containing $str]
		if {"" == [lindex $cont 0]} { return [list "" $str_org "Not a search_value - invalid 'containing' clause"] }
	    }
	    "in" {
		set cont [sql_in $str]
		if {"" == [lindex $cont 0]} { return [list "" $str_org "Not a search_value - invalid 'in' clause"] }
	    }
	    "is" {
		# 'is' [ 'not' ] 'null' |
		set str [lrange $str 1 end]
		    
		# Optional 'not' - simply ignore error of sql_exact
		set not [sql_exact $str "not"]
		set str [lindex $not 1]
		
		set null [sql_exact $str "null"]
		if {"" == [lindex $null 0]} { return [list "" $str_org "Not a search value - expecting 'null' after 'is'"] }
		set str [lindex $null 1]
		
		return [list "is [lindex $not 0] null" $str ""]
	    }
	    "like" {
		set cont [sql_like $str]
		if {"" == [lindex $cont 0]} { return [list "" $str_org "Not a search_value - invalid 'like' clause"] }
	    }
	    "starting" {
		set cont [sql_starting $str]
		if {"" == [lindex $cont 0]} { return [list "" $str_org "Not a search_value - invalid 'starting' clause"] }
	    }
	    default {
		return [list "" $str_org "Not a search_value - expecting between, like, in, compare, containing or starting after value_litteral, found '$kw'"]
	    }
	}
	set str [lindex $cont 1]
	return [list [list litteral [lindex $v0 0] not [lindex $not 0] $kw [lindex $cont 0]] $str ""]
    }

    return [list "" $str "Not a search value - found none of the options"]
}




# like = 'like' value_litteral [ ESCAPE value_litteral ].
ad_proc -public sql_like {str} {
    ns_log Notice "sql_like: $str"
    set str_org $str

    set like [sql_exact $str "like"]
    if {"" == [lindex $like 0]} { return [list "" $str_org "Not a like - 'like' expected as first literal"] }
    set str [lindex $like 1]

    set val [sql_value_litteral $str]
    if {"" == [lindex $val 0]} { return [list "" $str_org "Not a like - value_litteral expected after 'like'"] }
    set str [lindex $val 1]

    return [list [list like [lindex $val 0]] $str ""]
}


# containing = 'containing' value_litteral .
ad_proc -public sql_containing {str} {
    ns_log Notice "sql_containing: $str"
    set str_org $str

    set containing [sql_exact $str "containing"]
    if {"" == [lindex $containing 0]} { return [list "" $str_org "Not a containing - 'containing' expected as first literal"] }
    set str [lindex $containing 1]

    set val [sql_value_litteral $str]
    if {"" == [lindex $val 0]} { return [list "" $str_org "Not a containing - value_litteral expected after 'containing'"] }
    set str [lindex $val 1]

    return [list [list containing [lindex $val 0]] $str ""]
}


# starting = 'starting' value_litteral .
ad_proc -public sql_starting {str} {
    ns_log Notice "sql_starting: $str"
    set str_org $str

    set starting [sql_exact $str "starting"]
    if {"" == [lindex $starting 0]} { return [list "" $str_org "Not a starting - 'starting' expected as first literal"] }
    set str [lindex $starting 1]

    set val [sql_value_litteral $str]
    if {"" == [lindex $val 0]} { return [list "" $str_org "Not a starting - value_litteral expected after 'starting'"] }
    set str [lindex $val 1]

    return [list [list starting [lindex $val 0]] $str ""]
}


# in = 'in' '(' value_litteral { ',' value_litteral } | select_column_list ')'.
ad_proc -public sql_in {str} {
    ns_log Notice "sql_in: $str"
    set str_org $str

    set in [sql_exact $str "in"]
    if {"" == [lindex $in 0]} { return [list "" $str_org "Not a in - 'in' expected as first literal"] }
    set str [lindex $in 1]

    set par [sql_exact $str "("]
    if {"" == [lindex $par 0]} { return [list "" $str_org "Not a in - '(' expected as second literal"] }
    set str [lindex $par 1]

    set kw [lindex $str 0]
    switch $kw {
	"select" {
	    # Check for select_column_list
	    set collist [sql_select $str]
	    set str [lindex $collist 1]
	    if {"" == [lindex $collist 0]} { return [list "" $str_org "Not a in - valid select statement expected after 'in' '(' 'select'"] }
	    set result [list in_collist [lindex $collist 0]]
	}
	default {
	    # Check for list of value_litterals
	    set continue 1
	    set values [list]
	    while {$continue} {
		set val [sql_value_litteral $str]
		if {"" == [lindex $val 0]} { return [list "" $str_org "Not a in - invalid value_litteral in list of values"] }
		lappend values [lindex $val 0]
		set str [lindex $val 1]

		set komma [sql_exact $str ","]
		set str [lindex $komma 1]
		if {"," != [lindex $komma 0]} { set continue 0 }
	    }
	    set result [list in_valuelist $values]
	}
    }

    set par [sql_exact $str ")"]
    if {"" == [lindex $par 0]} { return [list "" $str_org "Not a in - ')' expected after last value_litteral"] }
    set str [lindex $par 1]

    return [list $result $str ""]
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

# from_table_reference = name [ procedure_end ] [ alias_name ] | joined_table.
ad_proc -public sql_from_table_reference {str} {
    ns_log Notice "sql_from_table_reference: $str"

    set name [sql_name $str]
    if {"" == [lindex $name 0]} { return [list "" $str "Not a from_table_reference - expecting a name as first literal"] }
    set str [lindex $name 1]

    set procedure_end [sql_procedure_end $str]
    set str [lindex $procedure_end 1]

    # Optional alias
    set alias [sql_name $str]
    set str [lindex $alias 1]

    return [list [list name [lindex $name 0] procedure_end [lindex $procedure_end 0] alias [lindex $alias 0]] $str ""]
}

#  procedure_end= '(' value_litteral { ',' value_litteral } ')' .
ad_proc -public sql_procedure_end {str} {
    # ns_log Notice "sql_procedure_end: $str"
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

    return [list $values $str ""]
}



# compare = operator ( value_litteral | '(' select_one_column ')' ) .
ad_proc -public sql_compare {str} {
    ns_log Notice "sql_compare: $str"
    set str_org $str

    set op [sql_operator $str]
    if {"" == [lindex $op 0]} { return [list "" $str_org "Compare - expecting operator as first token"] }
    set str [lindex $op 1]

    # Try value_litteral after operator
    set val [sql_value_litteral $str]
    set str [lindex $val 1]
    if {"" != [lindex $val 0]} {
	return [list [list operator [lindex $op 0] value [lindex $val 0]] $str ""]
    }

    # Otherwise go for select
    set par [sql_exact $str "("]
    set str [lindex $par 1]
    if {"" == [lindex $par 0]} { return [list "" $str_org "Compare - expecting '(' or value_litteral after operator"] }
    
    set sel [sql_select $str]
    set str [lindex $sel 1]
    if {"" == [lindex $sel 0]} { return [list "" $str_org "Compare - expecting select after '('"] }

    return [list [list operator [lindex $op 0] select [lindex $sel 0]] $str ""]
}


# function_count = count ( * )
ad_proc -public sql_function_count {str} {
    ns_log Notice "sql_function_count: $str"

    set name [sql_name $str]
    if {"count" != [lindex $name 0]} { return [list "" $str "Not a count function - expecting 'count' as first literal"] }
    set str [lindex $name 1]

    set par_open [sql_exact $str "("]
    if {"" == [lindex $par_open 0]} { return [list "" $str "Not a count function - expecting '(' after 'count'"] }
    set str [lrange $str 1 end]

    set asterisk [sql_exact $str "*"]
    if {"*" != [lindex $asterisk 0]} { return [list "" $str "Not a count function - expecting '*' after 'count(' "] }
    set str [lrange $str 1 end]

    set par_close [sql_exact $str ")"]
    if {"" == [lindex $par_close 0]} { return [list "" $str "Not a procedure_end - expecting ')' as last literal"] }
    set str [lindex $par_close 1]

    return [list [list function [lindex $name 0] procedure_end "*"] $str ""]
}

# function = name procedure_end
ad_proc -public sql_function {str} {
    ns_log Notice "sql_function: $str"

    set name [sql_name $str]
    if {"" == [lindex $name 0]} { return [list "" $str "Not a function - expecting a name as first literal"] }
    set str [lindex $name 1]

    set procedure_end [sql_procedure_end $str]
    if {"" == [lindex $procedure_end 0]} { return [list "" $str "Not a function - expecting a procedure_end after name"] }
    set str [lindex $procedure_end 1]

    return [list [list function [lindex $name 0] procedure_end [lindex $procedure_end 0]] $str ""]
}


ad_proc -public sql_value_litteral {str} {
    ns_log Notice "sql_value_litteral: $str"
    set str_org $str

    set first_char [string range $str 0 0]
    if {[string is integer $first_char]} { set first_char "integer" }
    if {"-" == $first_char} {
	# Deal with negative integers - ugly/inconsistent?
	set str [string range $str 1 end]
	set first_char "integer"
    }
    if {[string is alpha $first_char]} { set first_char "alpha" }
    switch $first_char {
	"'" {
	    # Search for ending tick
	    set lit ""
	    set str [string range $str 1 end]
	    set char [string range $str 0 0]
	    set cnt 0
	    while {$cnt < 1000 && "'" != $char && $str ne ""} {
		append lit $char
		set str [string range $str 1 end]
		set char [string range $str 0 0]
		incr cnt
	    }

	    if {"'" != $char} { return [list "" $str "Value litteral - found invalid value litteral"] }
	    set str [string range $str 1 end]
	
	    # Skip whitespaces after tick
	    set cnt 0
	    set char [string range $str 0 0]
	    while {$cnt < 1000 && " " == $char && $str ne ""} {
		set str [string range $str 1 end]
		set char [string range $str 0 0]
		incr cnt
	    }
            return [list $lit $str ""]
	}
	"integer" {
	    set int [sql_integer $str]
	    if {"" == [lindex $int 0]} { return [list "" $str_org "Value litteral - found bad integer"] }
	    return $int
	}
	"alpha" {
	    set alpha [sql_name $str]
	    if {"" == [lindex $alpha 0]} { return [list "" $str_org "Value litteral - found bad name"] }
	    set str [lindex $alpha 1]
	    set procedure_end [sql_procedure_end $str]
	    set str [lindex $procedure_end 1]
	    if {"" == [lindex $procedure_end 0]} {
		return $alpha
	    } else {
		return [list [list function [lindex $alpha 0] [lindex $procedure_end 0]] $str ""]
	    }
	}
	default {
	    return [list "" $str_org "Value litteral - found invalid value litteral"]
	}
    }
}

ad_proc -public sql_exact {str exact} {
    # ns_log Notice "sql_exact: $str '$exact'"
    if {$exact == [lindex $str 0]} { return [list $exact [lrange $str 1 end] ""] }
    return [list "" $str "Not an exact($exact)"]
}

ad_proc -public sql_name {str} {
    # ns_log Notice "sql_name: $str"

    set keyword [sql_keyword $str]
    if {"" != [lindex $keyword 0]} {
	# Found a keywork - so this is NOT a name...
	return [list "" $str "Not a name - is a keyword"]
    }

    set name [lindex $str 0]
    if {[regexp {^[[:alnum:]_\.]+$} $name match]} { return [list $name [lrange $str 1 end] ""] }
    return [list "" $str "Not a name - contains non-name characters"]
}

ad_proc -public sql_integer {str} {
    # ns_log Notice "sql_integer: $str"
    set int [lindex $str 0]
    if {[regexp {^[0-9]+$} $int match]} { return [list $int [lrange $str 1 end] ""] }
    return [list "" $str "Not an integer - contains non-integer characters"]
}

ad_proc -public sql_keyword {str} {
    # ns_log Notice "sql_keyword: $str"

    set s0 [lindex $str 0]
    set keywords {all and any asc ascending avg between by collate containing desc descending distinct escape exists from full group having in is inner insert into join left like not null or order outer right set singular some starting table union update values where with}    
    set found_keyword ""
    foreach keyword $keywords {
	if {$s0 == $keyword} { return [list $keyword [lrange $str 1 end] ""] }
    }
    return [list "" $str "Not a keyword"]
}

# operator= '=' | '<' | '>' | '<=' | '>=' | '<>'.
ad_proc -public sql_operator {str} {
    # ns_log Notice "sql_operator: $str"

    set s0 [lindex $str 0]
    set operators {"=" " != " "<" ">" "<=" ">=" "<>"}
    set found_operator ""
    foreach operator $operators {
	if {$s0 == $operator} { return [list $operator [lrange $str 1 end] ""] }
    }
    return [list "" $str "Not a operator"]
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

    lappend result $type
    lappend result $str
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

    # search_value
    lappend e [sql_assert sql_search_value "project_id = 46896"]
    # lappend e [sql_assert sql_search_value "project_id = 46896+1"]  # ToDo
    lappend e [sql_assert sql_search_value "var between 1 and 10"]
    lappend e [sql_assert sql_search_value "var is not null"]
    lappend e [sql_assert sql_search_value "var != 30"]
    lappend e [sql_assert sql_search_value "var < 10"]
    lappend e [sql_assert sql_search_value "( var > 20 )"]
    lappend e [sql_assert sql_search_value "not ( var != 30 )"]
    lappend e [sql_assert sql_search_value "var like '%asdf%'"]
    lappend e [sql_assert sql_search_value "exists ( select * from users )"]

    # search_condition
    lappend e [sql_assert sql_search_condition "p.project_id = 46896"]
    lappend e [sql_assert sql_search_condition "p.project_id = 46896 and u.user_id = p.user_id"]

    # select
    lappend e [sql_assert sql_select "select * from test1"]
    lappend e [sql_assert sql_select "select * from test1 , test2"]
    lappend e [sql_assert sql_select "select * from test1 , test2 where 1 = 2"]
    lappend e [sql_assert sql_select "select * from users where user_id in ( 1 , 2 , 3 )"]
    lappend e [sql_assert sql_select "select p.project_id from im_projects p , im_projects main_p where main_p.project_id = 43373 and p.tree_sortkey between main_p.tree_sortkey and tree_right ( main_p.tree_sortkey )"]

    # -------------------------
    set cnt 0
    set errors [list]
    foreach entry $e {
	set test_result [lindex $entry 0]
	set test_unparsed_str [lindex $entry 1]
	set test_errmsg [lindex $entry 2]
	set test_type [lindex $entry 3]
	set test_str [lindex $entry 4]

	incr cnt
	if {"" != [lindex $entry 2]} {
	    return [list $test_type $test_str $test_errmsg $test_unparsed_str]
	    lappend errors $entry
	}
    }
    lappend errors [list "" "" "$cnt tests executed"]
    return $errors
}


set bnf {
select_expression = select.
select_one_column = select.
select_column_list = select.
select = SELECT [ DISTINCT | ALL ] ( '*' | functions | value_litteral { ',' value_litteral } )
	FROM from_table_reference { ',' from_table_reference }
	[ WHERE search_condition ]
	[ GROUP BY column_name
	[ COLLATE collation_name ] { ',' column_name [ COLLATE collation_name ] } ]
	[ HAVING search_condition ]
	[ UNION select_expression [ ALL ] ]
	[ ORDER BY order_list ].


search_condition = search_value { ( OR | AND ) search_condition }.
search_value = 
	value_litteral ( [ NOT ] ( between | like | in | compare | containing | starting ) | 
	IS [ NOT ] NULL ) |
	( ALL | SOME | ANY ) '(' select_column_list ')' |
	EXISTS '(' select_expression ')' |
	SINGULAR '(' select_expression ')' |
	'(' search_condition ')' |
	NOT search_condition.


between = BETWEEN value_litteral AND value_litteral.
like = LIKE value_litteral [ ESCAPE value_litteral ].
in = IN '(' value_litteral { ',' value_litteral } | select_column_list ')'.
compare = operator ( value_litteral | '(' select_one_column ')' ).
containing = CONTAINING value_litteral.
starting = STARTING [ WITH ] value_litteral.


from_table_reference = NAME procedure_end | joined_table.
procedure_end = [ '(' value_litteral { ',' value_litteral } ')' ] [ alias_name ].
joined_table = ( name_view_procedure join_on | '(' joined_table ')' ) { join_on }.
join_on = join_type ( joined_table | name_view_procedure ) ON search_condition.
join_type = ( [ INNER | { LEFT | RIGHT | FULL } [OUTER] ] ) JOIN.
order_list = ( column_name | integer_litteral ) [ COLLATE collation_name ] [ ascending_or_descending ] { ',' order_list }.
ascending_or_descending = ASC | ASCENDING | DESC | DESCENDING.


functions = average | count | max | min | sum | upper.
	average = AVG '(' [ ALL | DISTINCT ] value_litteral ')'.
	count = COUNT '(' '*' | [ ALL | DISTINCT ] value_litteral ')'.
	max = MAX '(' [ ALL | DISTINCT ] value_litteral ')'.
	min = MIN '(' [ ALL | DISTINCT ] value_litteral ')'.
	sum = SUM '(' [ ALL | DISTINCT ] value_litteral ')'.
	upper = UPPER '(' value_litteral ')'.

value_litteral = VALUE_LITTERAL | NAME.
integer_litteral = INTEGER.
table_or_view_name = NAME.
name_view_procedure = NAME.
column_name = NAME.
collation_name = NAME.
alias_name = NAME.
operator = ' = ' | '<' | '>' | '< = ' | '> = ' | '<>'.



sql = insert | select | update.
insert = INSERT INTO table_or_view_name [ '(' column_name { ',' column_name } ')' ] ( VALUES '(' value_litteral { ',' value_litteral } ')' | select_expression ).
update = UPDATE table_or_view_name SET column_name ' = ' value_litteral { ',' column_name ' = ' value_litteral } [ WHERE search_condition ].
}

