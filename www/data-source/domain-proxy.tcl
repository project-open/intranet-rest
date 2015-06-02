# /packages/sencha-rest/www/data-source/domain-proxy.tcl
#
# Copyright (C) 2015 ]project-open[

ad_page_contract {
    Fetches a page from www.project-open.org
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


# --------------------------------------------
# Fetch and return the page
#

if {[catch {
    set json [ns_httpget $url]
} err_msg]} {
    ad_return_complaint 1 "Domain-proxy: Error retreiving url:<br><pre>[ns_quotehtml $err_msg]</pre>"
    ad_script_abort    
}



doc_return 200 "application/json" $json
