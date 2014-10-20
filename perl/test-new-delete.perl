#!/usr/bin/perl -w

# --------------------------------------------------------
# test-new-delete.perl
#
# (c) 2014 ]project-open[
# Frank Bergmann (frank.bergmann@project-open.com)
#
# Tests creation and destruction of certain objects
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
my $debug = 4;							# Debug: 0=silent, 9=verbose

my $rest_host = "demo.project-open.net";			# May include port number, but no trailing "/"
my $rest_email = "bbigboss\@tigerpond.com";			# Email for basic auth, needs to be Admin
my $rest_password = "ben";					# Password for basic authentication
$rest_host = "localhost:8000";

my $result = GetOptions (
    "debug=i"    => \$debug,
    "host=s"     => \$rest_host,
    "email=s"    => \$rest_email,
    "password=s" => \$rest_password
) or die "Usage:\n\ntest-new-delete.perl --debug 1 --host localhost:8000 --email bbigboss\@tigerpond.com --password ben\n\n";


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
    print "test-new-delete.perl:	update all object types	0	$url	return_code=$return_code, message=$body\n";
    exit 1;
}

my $json;
eval { $json = decode_json($body); };
if ($@) {
    print "test-new-delete.perl:	update all object types	0	$url	Failed to parse JSON, json=$body\n";
    exit 1;
}

my $success = $json->{'success'};
my $total = $json->{'total'};
my $message = $json->{'message'};
my $successfull_p = ($return_code eq "200") && ($success eq "true") && ($total > 50);
if (!$successfull_p || $debug > 1) {
    print "test-new-delete.perl:	list all object types	$successfull_p	$url	return_code=$return_code, success=$success, total=$total, message=$message\n";
}


# --------------------------------------------------------
# Create a generic access object to query the ]po[ HTTP server
#
ProjectOpen->new (
    host	=> $rest_host,
    email	=> $rest_email,
    password	=> $rest_password,
    debug	=> $debug
);



# -------------------------------------------------------
# Create a new Project
#

my $r = int(1000000000.0 * rand() * 1000000000.0);
my $random_project_name = "New Project #" . $r;
my $project_hash = { 
    "project_name" => "New Project #$r",
    "project_nr" => "new_project_$r",
    "project_status_id" => 76,
    "project_type_id" => 2501
};


$url = "http://$rest_host/intranet-rest/im_project";
$result = ProjectOpen->_http_post_request($url, $project_hash);

$success = $result->{'success'};
$message = $result->{'message'};
my $project_id = $result->{'data'}[0];

# print Dumper($project_id). "\n";    

$successfull_p = ($success eq "true");
if (!$successfull_p || $debug > 0) {
    print "test-new-delete.perl:	create new im_project	$successfull_p	$url	success=$success, message=$message\n";
}


exit 0;

