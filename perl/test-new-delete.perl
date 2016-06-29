#!/usr/bin/perl -w

# --------------------------------------------------------
# test-new-delete.perl
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
my $debug = 0;							# Debug: 0=silent, 9=verbose

my $rest_host = "demo.project-open.net";			# May include port number, but no trailing "/"
my $rest_email = "sysadmin\@tigerpond.com";			# Email for basic auth, needs to be Admin
my $rest_password = "system";					# Password for basic authentication
$rest_host = "localhost:8000";

my $result = GetOptions (
    "debug=i"    => \$debug,
    "host=s"     => \$rest_host,
    "email=s"    => \$rest_email,
    "password=s" => \$rest_password
) or die "Usage:\n\ntest-new-delete.perl --debug 1 --host localhost:8000 --email bbigboss\@tigerpond.com --password ben\n\n";


# --------------------------------------------------------
# Create a generic access object to query the ]po[ HTTP server
#
ProjectOpen->new (
    host	=> $rest_host,
    email	=> $rest_email,
    password	=> $rest_password,
    debug	=> $debug
);


# --------------------------------------------------------
# Map of object types into their name fields
#

# A random name for the new object
my $r = "" . int(1000000000.0 * rand() * 1000000000.0);

# The ID of the SysAdmin - he's the first user in the system after 0=Guest
my $sysadmin_hash = ProjectOpen->get_object_list("user", "user_id in (select min(user_id) from users where user_id > 0)");
my $sysadmin_id = $sysadmin_hash->{'data'}[0]{'user_id'};

# The ID of a customer and a provider company
my $customer_hash = ProjectOpen->get_object_list("im_company", "company_type_id = 57");
my $customer_id = $customer_hash->{'data'}[0]{'user_id'};
my $provider_hash = ProjectOpen->get_object_list("im_company", "company_type_id = 57");
my $provider_id = $provider_hash->{'data'}[0]{'user_id'};

# A container for creating tickets
my $sla_hash = ProjectOpen->get_object_list("im_project", "project_type_id = 2502");
my $sla_id = $sla_hash->{'data'}[0]{'project_id'};


    
my $constructors_hash = {
    "im_company" => {"company_name" => $r, "company_path" => $r, "company_status_id" => 46, 
		     "company_type_id" => 57},
    "im_project" => {"project_name" => "Project #$r", "project_nr" => "project_$r", 
		     "project_status_id" => 76, "project_type_id" => 2501},
    "im_office" => {"office_name" => $r, "office_path" => $r, "office_status_id" => 160, 
		    "office_type_id" => 160},
    "im_ticket" => {"project_name" => "Ticket #$r", "parent_id" => $sla_id},
    "im_user_absence" => {"absence_name" => "Absence #$r", "duration_days" => 2, "owner_id" => $sysadmin_id,
			  "start_date" => "2014-11-01", "end_date" => "2014-11-05",
			  "description" => "Halloween", "absence_type_id" => 5000, "absence_status_id" => 16000},
    "im_hour" => {"user_id" => $sysadmin_id, "project_id" => $sla_id, "day" => "2014-11-01", 
		  "hours" => "1.23", "note" => $r},
    "im_note" => {"note" => $r, "object_id" => $sla_id, "note_status_id" => 11400, 
		  "note_type_id" => 11400},
    "im_expense" => {"cost_name" => "Expense #$r", "cost_nr=" => "cost_$r", "customer_id" => $customer_id, 
		     "provider_id" => $provider_id, "cost_status_id" => 3802, "cost_type_id" => 3720, 
		     "effective_date" => "2014-11-11", "amount" => "123.45", "currency" => "EUR", 
		     "external_company_name" => "External Company #$r"}
};

    
my $ttt = {
    "im_expense_bundle" => "cost_name",
    "im_hour_interval" => "note",
    "im_forum_topic" => "topic_name",
    "im_fs_file" => "filename",
    "im_indicator" => "report_name",
    "im_invoice" => "cost_name",
    "im_invoice_item" => "item_name",
    "im_risk" => "risk_name",
    "im_timesheet_conf_object" => "comment",
    "im_timesheet_task" => "project_name",
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
print STDERR "test-new-delete.perl: HTTP body=$body\n" if ($debug > 8);
my $return_code = $response->code;
if (200 != $return_code) {
    print "test-new-delete.perl:	list all object types	0	$url	return_code=$return_code, message=$body\n";
    exit 1;
}
my $json;
eval { $json = decode_json($body); };
if ($@) {
    print "test-new-delete.perl:	list all object types	0	$url	Failed to parse JSON, json=$body\n";
    exit 1;
}

my $success = $json->{'success'};
my $total = $json->{'total'};
my $message = $json->{'message'};
my $successfull_p = ($return_code eq "200") && ($success eq "true") && ($total > 50);
if (!$successfull_p || $debug > 1) {
    print "test-new-delete.perl:	list all object types	$successfull_p	$url	return_code=$return_code, success=$success, total=$total, message=$message\n";
}


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
#    next if (!($object_type =~ /^im_ticket$/));

    
    # -------------------------------
    # Check if we have defined a constructor
    #
    my $constructor_hash;
    if (exists $constructors_hash->{$object_type}) {
	$constructor_hash = $constructors_hash->{$object_type};
	print STDERR "test-new-delete.perl: $object_type: constructor=" . Dumper($constructor_hash) . "\n" if ($debug > 0);
    } else {
	print STDERR "test-new-delete.perl: $object_type: no constructor defined - skipping\n" if ($debug > 4);
	next;
    }

    
    # -------------------------------------------------------
    # Create a new object
    #
    my $url = "http://$rest_host/intranet-rest/$object_type";
    print STDERR "test-new-delete.perl: $object_type: Creating a new object\n" if ($debug > 1);
    my $result_hash = ProjectOpen->_http_post_request($url, $constructor_hash);
    $success = $result_hash->{'success'};
    $message = $result_hash->{'message'};
    my $object_hash = $result_hash->{'data'}[0];
    my $oid = $object_hash->{'object_id'};

    if (($success eq "true") && ($oid eq int($oid))) { $successfull_p = 1 } else { $successfull_p = 0; }
    if (!$successfull_p || $debug > 0) {
	print STDERR "test-new-delete.perl: ID of new object: " . Dumper($oid). "\n" if ($debug > 6);
	print "test-new-delete.perl:	create new $object_type	$successfull_p	$url	success=$success, message=$message\n";
    }
    next if (!$successfull_p);

    
    # -------------------------------------------------------
    # Get the object that we've just created
    #
    print STDERR "test-new-delete.perl: $object_type: Getting single object with OID=$oid\n" if ($debug > 1);
    $result_hash = ProjectOpen->get_object($object_type, $oid);
    $success = $result_hash->{'success'};
    $message = $result_hash->{'message'};
    $object_hash = $result_hash->{'data'}[0];
    if ($success eq "true") { $successfull_p = 1 } else { $successfull_p = 0; }
    if (!$successfull_p || $debug > 0) {
	print "test-new-delete.perl:	check for newly created $object_type	$successfull_p	$url	success=$success, message=$message\n";
    }
   

    # -------------------------------------------------------
    # Delete the object that we've just created
    #
    $url = "http://$rest_host/intranet-rest/$object_type/$oid";
    print STDERR "test-new-delete.perl: $object_type: Deleting $object_type: #".$oid."\n" if ($debug > 1);
    $result_hash = ProjectOpen->_http_delete_request($url);
    $success = $result_hash->{'success'};
    $message = $result_hash->{'message'};
    if ($success eq "true") { $successfull_p = 1 } else { $successfull_p = 0; }
    if (!$successfull_p || $debug > 0) {
	print "test-new-delete.perl:	delete $object_type	$successfull_p	$url	success=$success, message=$message\n";
    }
    next if (!$successfull_p);

}

exit 0;

