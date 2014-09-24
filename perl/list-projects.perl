#!/usr/bin/perl -w

# --------------------------------------------------------
# list-projects
#
# (c) 2010-2014 ]project-open[
# Frank Bergmann (frank.bergmann@project-open.com)
#
# Example for accessing the ]po[ REST API V3 using 
# Perl and HTTP basic authentication
# --------------------------------------------------------


# --------------------------------------------------------
# Libraries
#
use strict;
use LWP::UserAgent;
use Data::Dumper;
use JSON;

# --------------------------------------------------------
# Connection parameters: 
#
my $debug = 1;							# Debug: 0=silent, 9=verbose

my $rest_server = "http://demo.project-open.net";		# May include port number, but no trailing "/"
my $rest_email = "bbigboss\@tigerpond.com";			# Email for basic authentication
my $rest_password = "ben";					# Password for basic authentication


#my $rest_server = "http://localhost:8000";			# May include port number


# --------------------------------------------------------
# Request the result
#
print "list-projects.perl: Sending HTTP request to $rest_server/intranet-rest/im_project\n" if ($debug > 0);
print "list-projects.perl: Using email=$rest_email and password=$rest_password\n" if ($debug > 0);

my $ua = LWP::UserAgent->new;
my $url = "$rest_server/intranet-rest/im_project?format=json";
my $req = HTTP::Request->new(GET => $url);
$req->authorization_basic($rest_email, $rest_password);
my $response = $ua->request($req);
my $body =  $response->content;
print "list-projects.perl: HTTP body=$body\n" if ($debug > 8);


# -------------------------------------------------------
# Check and parse JSON results
#
my $return_code = $response->code;
my $json = decode_json($body);
my $success = $json->{'success'};
my $total = $json->{'total'};
my $message = $json->{'message'};

print "list-projects.perl: return_code=$return_code, success=$success, total=$total, message=$message\n";
print Dumper $json if ($debug > 5);


# -------------------------------------------------------
# List projects
#
my @projects = @{$json->{'data'}};
foreach my $p (@projects) {
    print "project_id=" . $p->{'project_id'} . ", project_name=" .  $p->{'project_name'} . "\n";
}

exit 0;

