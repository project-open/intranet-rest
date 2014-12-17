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
use Getopt::Long;

# BEGIN {push @INC, '../../intranet-rest/perl'}
use ProjectOpen;

# --------------------------------------------------------
# Parameters: 
#
my $debug = 1;							# Debug: 0=silent, 9=verbose

my $rest_host = "demo.project-open.net";			# May include port number, but no trailing "/"
my $rest_email = "sysadmin\@tigerpond.com";			# Email for basic auth, needs to be Admin
my $rest_password = "system";					# Password for basic authentication
$rest_host = "localhost:8000";

my $result = GetOptions (
    "debug=i"    => \$debug,
    "host=s"     => \$rest_host,
    "email=s"    => \$rest_email,
    "password=s" => \$rest_password
) or die "Usage:\n\ntest-update.perl --debug 1 --host localhost:8000 --email bbigboss\@tigerpond.com --password ben\n\n";


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
my $url = "http://$rest_host/intranet-rest/index?format=json";
my $req = HTTP::Request->new(GET => $url);
$req->authorization_basic($rest_email, $rest_password);
my $response = $ua->request($req);
my $body =  $response->content;
print STDERR "test-update.perl: HTTP body=$body\n" if ($debug > 8);


# -------------------------------------------------------
# Check and parse the list of object type
#
my $return_code = $response->code;
if (200 != $return_code) {
    print "test-update.perl:	update all object types	0	$url	return_code=$return_code, message=$body\n";
    exit 1;
}

my $json;
eval { $json = decode_json($body); };
if ($@) {
    print "test-update.perl:	update all object types	0	$url	Failed to parse JSON, json=$body\n";
    exit 1;
}

my $success = $json->{'success'};
my $total = $json->{'total'};
if (!defined $total) { $total = 0; }
my $successfull_p = ($return_code eq "200") && ($success eq "true" || $success eq "1") && ($total > 50);
my $message = $json->{'message'};
if (!$successfull_p || $debug > 1) {
    print "test-update.perl:	list all object types	'$successfull_p'	$url	return_code=$return_code, success=$success, total=$total, message=$message\n";
}

if (!$successfull_p) {
    die "test-update.perl:\tError getting the list of objects - aborting\n";
}


# --------------------------------------------------------
# Create a generic access object to query the ]po[ HTTP server
#
ProjectOpen->new (
    host	=> $rest_host,
    email	=> $rest_email,
    password	=> $rest_password,
    debug	=> 0
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
#    next if ($object_type ne "im_cost_center");
#    next if (!($object_type =~ /^im_/));
    
    # ----------------------------------------
    # Get the list of objects for the object type
    # and check return codes
    $url = "http://$rest_host/intranet-rest/$object_type?format=json";
    print STDERR "test-update.perl: $object_type\n" if ($debug > 1);
    print STDERR "test-update.perl: $object_type\n" if ($debug > 1);
    print STDERR "test-update.perl: $object_type: Getting list of $object_type from $url\n" if ($debug > 1);
    my $object_json = ProjectOpen->get_object_list($object_type);
    if (ref($object_json) ne "HASH") {
	print "test-update.perl:	update $object_type	0	$url	Internal error in get_object_update\n";
	next;
    }
    my $success = $object_json->{'success'};
    my $message = $object_json->{'message'};
    $message =~ tr/\n\t/  /;
    my $short_msg = substr($message, 0, 40);
    if ("true" ne $success && "1" ne $success) {
	print "test-update.perl:	list $object_type	0	$url	$short_msg\n";
	next;
    }
    $total = $object_json->{'total'};
    if (0 == $total) {
	# No objects found of the specific type
	print STDERR "test-update.perl: $object_type: Didn't find any objects of this type\n" if ($debug > 1);
	next;
    }
   
    my @object_list_json = @{$object_json->{'data'}};
    print STDERR "test-update.perl: $object_type: List of objects of type $object_type: " . Dumper(@object_list_json) . "\n" if ($debug > 8);
    my $first_object_json = $object_list_json[0];
    print STDERR "test-update.perl: $object_type: JSON of first object of type $object_type: " . Dumper($first_object_json) . "\n" if ($debug > 8);
    my $oid = $first_object_json->{'id'};					# Every REST results includes a generic 'id'
    if (!defined $oid) {
	print "test-update.perl:	list $object_type	0	$url	Didn't find 'id' property of first object\n";
	next;
    }

    print "test-update.perl:	list $object_type	1	$url	$short_msg\n" if ($debug > 0);

    
    # -------------------------------
    # Test the single object GET request
    #
    print STDERR "test-update.perl: $object_type: Getting single object with OID=$oid\n" if ($debug > 1);
    my $get_object_json = ProjectOpen->get_object($object_type, $oid);
    my $object_data_json = $get_object_json->{'data'}[0];
    print STDERR "test-update.perl: $object_type: get_object($object_type,$oid): " . Dumper($object_data_json) . "\n" if ($debug > 6);

    $success = $get_object_json->{'success'};
    $message = $get_object_json->{'message'};
    $message =~ tr/\n\t/  /;
    $short_msg = substr($message, 0, 40);
    if ("true" ne $success && "1" ne $success) {
	$url = "http://$rest_host/intranet-rest/$object_type/$oid?format=json";
	print "test-update.perl:	get $oid	0	$url	$short_msg\n";
	next;
    }
    
    # -------------------------------
    # Update object using REST with exactly the same data.
    # This tests that there is no error message during update.
    #
    print STDERR "test-update.perl: $object_type: Updating object OID=$oid with identical data:\n" if ($debug > 1);
    my $update_result = ProjectOpen->post_object($object_type, $oid, $object_data_json);
    print STDERR "test-update.perl: $object_type: post_object: result=" . Dumper($update_result) . "\n" if ($debug > 4);
    # ToDo: Write out error message in case of failure


    # -------------------------------
    # Check if we know the name field of the object type
    #
    my $name_field = "";
    if (exists $object_type_name_field_hash->{$object_type}) {
	$name_field = $object_type_name_field_hash->{$object_type};
	print STDERR "test-update.perl: $object_type: name_field=" . $name_field . " for object_type=" . $object_type . "\n" if ($debug > 4);
    } else {
	print STDERR "test-update.perl: $object_type: no name_field exists for object_type=" . $object_type . "\n" if ($debug > 4);
	next;
    }

    
    # -------------------------------
    # We know the name field of the object type.
    # Let's append a "%" at the end of the name and
    # check that the object was updated correctly.
    #
    print STDERR "test-update.perl: $object_type: Appended a '%' to name_field=$name_field of object #$oid\n" if ($debug > 1);
    my $object_name = $object_data_json->{$name_field};
    if (!defined $object_name) {
	print "test-update.perl:	get object_name for $object_type	0	unknown url	Didn't find '$name_field' property in object_data_json of #$oid\n";
	next;
    }
    $object_data_json->{$name_field} = $object_name . "%";

    print STDERR "test-update.perl: $object_type: post_object: data=" . Dumper($object_data_json) . "\n" if ($debug > 8);
    $update_result = ProjectOpen->post_object($object_type, $oid, $object_data_json);
    print STDERR "test-update.perl: $object_type: post_object: result=" . Dumper($update_result) . "\n" if ($debug > 6);
    # ToDo: Write out error message in case of failure

    # -------------------------------
    # Get the updated data
    #
    print STDERR "test-update.perl: $object_type: Get the object #$oid ('$object_name') and check if the '%' was successfully written\n" if ($debug > 1);
    $get_object_json = ProjectOpen->get_object($object_type, $oid);
    $object_data_json = $get_object_json->{'data'}[0];
    $success = $get_object_json->{'success'};
    $message = $get_object_json->{'message'};
    $message =~ tr/\n\t/  /;
    $short_msg = substr($message, 0, 40);
    if ("true" ne $success && "1" ne $success) {
	print "test-update.perl:	get $oid	0	$url	$short_msg\n";
	next;
    }
    
    # Compare the new name of the object
    my $new_object_name = $object_data_json->{$name_field};
    if ($new_object_name ne $object_name . "%") {
	print "test-update.perl:	get updated name of $oid	0	$url	update of object name failed: org=$object_name, new=$new_object_name\n";
    }


    # -------------------------------
    # Restore the original data
    #
    print STDERR "test-update.perl: $object_type: Restore the original values of object #$oid\n" if ($debug > 1);
    $object_data_json->{$name_field} = $object_name;
    $update_result = ProjectOpen->post_object($object_type, $oid, $object_data_json);
    print STDERR "test-update.perl: $object_type: post_object: result=" . Dumper($update_result) . "\n" if ($debug > 6);
    # ToDo: Write out error message in case of failure

}

exit 0;

