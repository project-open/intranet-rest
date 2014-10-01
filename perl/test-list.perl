#!/usr/bin/perl -w

# --------------------------------------------------------
# test-list.perl
#
# (c) 2014 ]project-open[
# Frank Bergmann (frank.bergmann@project-open.com)
#
# Tests the REST "list" operation for all object types
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
my $debug = 0;							# Debug: 0=silent, 9=verbose

my $rest_server = "demo.project-open.net";			# May include port number, but no trailing "/"
my $rest_email = "bbigboss\@tigerpond.com";			# Email for basic authentication
my $rest_password = "ben";					# Password for basic authentication

$rest_server = "localhost:8000";



# --------------------------------------------------------
# Request the result
#
my $ua = LWP::UserAgent->new;
my $url = "http://$rest_server/intranet-rest/index?format=json";
my $req = HTTP::Request->new(GET => $url);
$req->authorization_basic($rest_email, $rest_password);
my $response = $ua->request($req);
my $body =  $response->content;
print "test-list.perl: HTTP body=$body\n" if ($debug > 8);


# -------------------------------------------------------
# Check and parse JSON results
#
my $return_code = $response->code;
if (200 != $return_code) {
    print "test-list.perl:	list all object types	0	$url	return_code=$return_code, message=$body\n";
    exit 1;
}

my $json;
eval {
    $json = decode_json($body);
};
if ($@) {
    print "test-list.perl:	list all object types	0	$url	Failed to parse JSON, json=$body\n";
    exit 1;
}




my $success = $json->{'success'};
my $total = $json->{'total'};
my $message = $json->{'message'};

my $successfull_p = ($return_code eq "200") && ($success eq "true") && ($total > 100);
if (!$successfull_p || $debug > 0) {
    print "test-list.perl:	list all object types	$successfull_p	$url	return_code=$return_code, success=$success, total=$total, message=$message\n";
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
# List object_types
#
my @object_types = @{$json->{'data'}};
foreach my $ot (@object_types) {

    my $object_type = $ot->{'object_type'};
    my $pretty_name = $ot->{'pretty_name'};
    next if ($object_type =~ /::/);
#    next if ($object_type =~ /acs_message_revision/);        # throws hard error in client

    $url = "http://$rest_server/intranet-rest/$object_type?format=json";
    print STDERR "test-list.perl: getting objects of type $object_type from $url\n" if ($debug > 0);

    my $object_json = ProjectOpen->get_object_list($object_type);
    my $success = $object_json->{'success'};
    my $message = $object_json->{'message'};
    $message =~ tr/\n\t/  /;
    my $short_msg = substr($message, 0, 40);
    if ("true" ne $success) {
	print "test-list.perl:	list $object_type	0	$url	$short_msg\n";
	next;
    }
    
    my $total = $object_json->{'total'};
    my @object_list = @{$object_json->{'data'}};

    $successfull_p = ($success eq "true");
    if (!$successfull_p || $debug > 0) {
	print "test-list.perl:	list $object_type	$successfull_p	$url	success=$success, total=$total, message=$short_msg\n";
    }
}

exit 0;
