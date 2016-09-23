# /packages/intranet-reste/www/version.tcl
#
# Copyright (C) 2010 ]project-open[
#

# ---------------------------------------------------------
# Returns a version string.
# Changes in the major number of the version 
# indicate incompatibilites, while changes in
# the minor number mean upgrades.
#
# Please see www.project-open.com/en/rest-version-history


set version [im_rest_version]
if {![info exists format]} { set format "json" }
set rest_url "[im_rest_system_url]/intranet-rest"

# Got a user already authenticated by Basic HTTP auth or auto-login
switch $format {
    json {
	set json_p 1
	set json "{\"success\": true, \"version\": \"$version\"}"
    }
    default {
	set json_p 0
	set page_title [lang::message::lookup "" intranet-rest "REST Version"]
	set context_bar ""
    }
}
	
