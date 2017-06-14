# /packages/sencha-rest/www/data-source/domain-proxy.tcl
#
# Copyright (C) 2015 ]project-open[

ad_page_contract {
    Fetches a page from www.project-open.net
    @param project_id The project
    @author frank.bergmann@project-open.com
} {
    {url ""}
}

# --------------------------------------------
# Security & Permissions
#

if {![regexp {^http://www\.project-open\.[a-z]+} $url match]} {
    ad_return_complaint 1 "Domain-proxy: This proxy can relay information only from project-open.* domains"
    ad_script_abort
}

ns_log Notice "/intranet-rest/data-source/domain-proxy.tcl: url=$url"


# --------------------------------------------
# Fetch and return the page
#
if {[catch {
    set json [im_httpget $url]
} err_msg]} {
    set json "{'success': false, 'message': 'Error message: $err_msg'}"
}
