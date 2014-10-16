#!/usr/bin/perl -w

# --------------------------------------------------------
# test-update.perl
#
# (c) 2014 ]project-open[
# Frank Bergmann (frank.bergmann@project-open.com)
#
# Tests the REST "update" operation for all object types
# --------------------------------------------------------


# --------------------------------------------------------
# Libraries
#
use strict;
use LWP::UserAgent;
use Data::Dumper;
use JSON;

# BEGIN {push @INC, '../../intranet-rest/perl'}
use ProjectOpen;

# --------------------------------------------------------
# Connection parameters: 
#
my $debug = 6;							# Debug: 0=silent, 9=verbose

my $rest_server = "demo.project-open.net";			# May include port number, but no trailing "/"
my $rest_email = "sysadmin\@tigerpond.com";			# Email for basic auth, needs to be Admin
my $rest_password = "system";					# Password for basic authentication

$rest_server = "localhost:8000";


# --------------------------------------------------------
# Map of object types into their name fields
#

my $object_type_name_field_hash = {
    "im_category" => "category",
    "im_company" => "company_name",
    "im_conf_item" => "conf_item_name",
    "im_cost" => "cost_name",
    "im_cost_center" => "cost_center_name",
    "im_dynfield_attribute" => "attribute_name",
    "im_dynfield_widget" => "widget_name",
    "im_expense" => "cost_name",
    "im_expense_bundle" => "cost_name",
    "im_forum_topic" => "topic_name",
    "im_fs_file" => "filename",
    "im_hour" => "note",
    "im_indicator" => "report_name",
    "im_invoice" => "cost_name",
    "im_invoice_item" => "item_name",
    "im_material" => "material_name",
    "im_menu" => "name",
    "im_note" => "note",
    "im_office" => "office_name",
    "im_project" => "project_name",
    "im_report" => "report_name",
    "im_risk" => "risk_name",
    "im_ticket" => "project_name",
    "im_ticket_queue" => "group_name",
    "im_timesheet_conf_object" => "comment",
    "im_timesheet_invoice" => "cost_name",
    "im_timesheet_task" => "project_name",
    "im_user_absence" => "absence_name"
    };


# --------------------------------------------------------
# Request the result
#
my $ua = LWP::UserAgent->new;
my $url = "http://$rest_server/intranet-rest/index?format=json";
my $req = HTTP::Request->new(GET => $url);
$req->authorization_basic($rest_email, $rest_password);
my $response = $ua->request($req);
my $body =  $response->content;
print "test-update.perl: HTTP body=$body\n" if ($debug > 8);


# -------------------------------------------------------
# Check and parse the list of object type
#
my $return_code = $response->code;
if (200 != $return_code) {
    print "test-update.perl:	update all object types	0	$url	return_code=$return_code, message=$body\n";
    exit 1;
}

my $json;
eval {
    $json = decode_json($body);
};
if ($@) {
    print "test-update.perl:	update all object types	0	$url	Failed to parse JSON, json=$body\n";
    exit 1;
}

my $success = $json->{'success'};
my $total = $json->{'total'};
my $message = $json->{'message'};

my $successfull_p = ($return_code eq "200") && ($success eq "true") && ($total > 50);
if (!$successfull_p || $debug > 0) {
    print "test-update.perl:	list all object types	$successfull_p	$url	return_code=$return_code, success=$success, total=$total, message=$message\n";
}


# --------------------------------------------------------
# Create a generic access object to query the ]po[ HTTP server
#
ProjectOpen->new (
    host	=> $rest_server,
    email	=> $rest_email,
    password	=> $rest_password,
    debug	=> $debug
);


# -------------------------------------------------------
# Loop for all object types
#
my @object_types = @{$json->{'data'}};
foreach my $ot (@object_types) {

    my $object_type = $ot->{'object_type'};
    my $pretty_name = $ot->{'pretty_name'};
    next if ($object_type =~ /::/);

#    next if ($object_type =~ /acs_message_revision/);        # throws hard error in client
    next if ($object_type ne "im_cost_center");
    
    $url = "http://$rest_server/intranet-rest/$object_type?format=json";
    print STDERR "test-update.perl: getting objects of type $object_type from $url\n" if ($debug > 0);

    my $object_json = ProjectOpen->get_object_list($object_type);
    if (ref($object_json) ne "HASH") {
	print "test-update.perl:	update $object_type	0	$url	Internal error in get_object_update\n";
	next;
    }
    
    my $success = $object_json->{'success'};
    my $message = $object_json->{'message'};
    $message =~ tr/\n\t/  /;
    my $short_msg = substr($message, 0, 40);
    if ("true" ne $success) {
	print "test-update.perl:	list $object_type	0	$url	$short_msg\n";
	next;
    }
    
    my $total = $object_json->{'total'};
    if (!defined $total) {
	print "test-update.perl:	list $object_type	0	$url	Result does not contain 'total' property\n";
	next;
    }

    my @object_list_json = @{$object_json->{'data'}};
    print "test-update.perl: " . Dumper(@object_list_json) . "\n" if ($debug >= 9);
    my $first_object_json = $object_list_json[0];
    print "test-update.perl: first_object_json: " . Dumper($first_object_json) . "\n" if ($debug > 4);


    # -------------------------------
    # Get the data of a single object
    my $oid = $first_object_json->{'id'};					# Every REST results includes generic 'id'
    my $get_object_json = ProjectOpen->get_object($object_type, $oid);
    my $get_data_json = $get_object_json->{'data'}[0];
    print "test-update.perl: get_object($object_type,$oid): " . Dumper($first_object_json) . "\n" if ($debug > 4);

    $success = $get_object_json->{'success'};
    $message = $get_object_json->{'message'};
    $message =~ tr/\n\t/  /;
    $short_msg = substr($message, 0, 40);
    if ("true" ne $success) {
	print "test-update.perl:	get $oid	0	$url	$short_msg\n";
	next;
    }

    print "test-update.perl: array=" . Dumper($object_type_name_field_hash) . "\n";
    
    if (exists $object_type_name_field_hash->{$object_type}) {
	my $name_field = $object_type_name_field_hash->{$object_type};
	print "test-update.perl: name_field=" . $name_field . " for object_type=" . $object_type . "\n" if ($debug > 4);
    } else {
	print "test-update.perl: no name_field exists for object_type=" . $object_type . "\n" if ($debug > 4);
	next;
    }


    # !!!
    # Add a "$" to the name field, so that the modified field is written to the server.

    
    # -------------------------------
    # Update object using REST with exactly the same data
    ProjectOpen->post_object($object_type, $oid, $get_data_json);

}

exit 0;

