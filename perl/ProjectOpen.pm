#----------------------------------------------------------------
# ]project-open[ REST Interface
#
# (c) Frank Bergmann, 2014-09-24
# Version 3
# Released under GPL V2.0 or higher
#
# $Id$
#
#----------------------------------------------------------------

package ProjectOpen;

use strict;
use warnings;
use Carp qw/carp croak/;
use HTTP::Request;
use LWP::UserAgent;
use Data::Dumper;
use JSON;
use Try::Tiny;

use Class::Data::Inheritable;

require Class::Data::Inheritable;
require Class::Accessor;
use base qw/Class::Data::Inheritable Class::Accessor/;

# Define class variables:
#
__PACKAGE__->mk_classdata("host");		# domain name of ]po[ REST host
__PACKAGE__->mk_classdata("email");		# email of the user accessing
__PACKAGE__->mk_classdata("password");		# password for email
__PACKAGE__->mk_classdata("debug");		# 0=silent, 9=very verbose
__PACKAGE__->mk_classdata("category_cache");	# Cache for category values
__PACKAGE__->mk_classdata("object_cache");	# Cache for category values

# Default variable values. demo.project-open.net will continue to 
# provide a user bbigboss/ben with access to most REST objects.
# 
use constant DEFAULT_ARGS => (
	"host" => "demo.project-open.net",
        "email" => "bbigboss\@tigerpond.com",
	"password" => "ben",
	"debug" => 1
);


# Get arguments. This private method is used in the constructor 
# to get it's arguments.
#
sub _get_args {
    my $proto = shift;
    
    my %args;
    if (scalar(@_) > 1) {
	if (@_ % 2) {croak "odd number of parameters";}
	%args = @_;
    } elsif (ref $_[0]) {
	unless (eval {local $SIG{'__DIE__'}; %{$_[0]} || 1}) {
	    croak "not a hashref in args";
	}
	%args = %{$_[0]};
    } else {
	%args = ('q' => shift);
    }
    return {$proto->DEFAULT_ARGS, %args};
}

# Constructor. Takes an optional var => value list and stores in
# class variables.
#
sub new {
    my $class = shift;
    my $args = $class->_get_args(@_);

    # Write arguments into class variables
    $class->host($args->{host});
    $class->email($args->{email});
    $class->password($args->{password});
    $class->debug($args->{debug});

    # Initialize caches for objects and categories
    $class->object_cache({});
    $class->category_cache({});

    # Print out some debug information
    my $debug = $class->debug;
    print STDERR sprintf "ProjectOpen: new: host=%s, email=%s, pwd=%s\n", $class->host, $class->email, $class->password if ($debug > 0);

    return $class;
}


# Low-level HTTP request to retrieve an XML page from ]project-open[.
# Higher-level procedures will use this procecure to retreive specific
# objects.
# Example: _http_request("/intranet-rest/im_conf_item");
# Parameters:
#	self:	reference to ProjectOpen class
#	path:	the path to the resource ('/intranet-rest/')
#
sub _http_request {
    my $self = shift;
    my $uri = shift;

    # Show some debug messages
    my $debug = ProjectOpen->debug;
    print STDERR sprintf "ProjectOpen: request: uri=%s using email=%s, pwd=%s\n", 
        $uri, ProjectOpen->email, ProjectOpen->password if ($debug > 3);

    # Perform the HTTP request. The request is authenticated using Basic Auth.
    my $ua = LWP::UserAgent->new;
    my $req = HTTP::Request->new(GET => $uri);
    $req->authorization_basic(ProjectOpen->email, ProjectOpen->password);
    my $res = $ua->request($req);
    carp sprintf "ProjectOpen: request: HTTP request failed: %s", 
        $res->status_line unless $res->is_success;

    print STDERR sprintf "ProjectOpen: content=%s", $res->content if ($debug > 5);

    # Parse the returned data and return the result
    my $json;
    eval {
	$json = decode_json($res->content);
    };

    if ($@) {
	my $json_error = "{\"success\": false, \"message\": \"Error parsing JSON\"}";
	$json = decode_json($json_error);
    }
    
    return $json;
}


# Retreive a list of objects of a certain type.
# Example: get_object_list("im_conf_item");
# Parameters:
#	object_type:	]po[ object type ('im_project', 'im_conf_item', ...)
#	sql_query:	A SQL query selecting out only objects that satisfy
#			some condition. Ex: 'project_status_id=76' for 
#			selecting only projects with status 'open'.
#
sub get_object_list {
    my $self = shift;
    my $object_type = shift;
    my $sql_query = shift;

    my $host = ProjectOpen->host;
    my $uri = URI->new("http://$host/intranet-rest/$object_type");

    if (defined $sql_query) { 
	$uri->query_form("query" => $sql_query, "format" => "json"); 
    } else {
	$uri->query_form("format" => "json"); 
    }
    my $res = ProjectOpen->_http_request($uri);
    return $res;
}


# Retreive a single object.
# Example: get_object(624); # should return info about user "System Administrator"
# Parameters:
#	object_type:	]po[ object type ('im_project', 'im_conf_item', ...)
#	object_id:	The ID of the object. Every object in ]po[ has a
#			unique ID.
#
sub get_object {
    my $self = shift;
    my $object_type = shift;
    my $object_id = shift;

    # Check if we already got the value for this object_id
    # or get the value from the REST server
    my $o_cache = ProjectOpen->object_cache;
    my $o_json;

    if (defined $o_cache->{$object_id}) { 
 	$o_json = $o_cache->{$object_id}; 
    } else {
	# Get the object from the REST server
	my $host = ProjectOpen->host;
	my $uri = URI->new("http://$host/intranet-rest/$object_type/$object_id?format=json");
	$uri->query_form("format" => "json"); 
	$o_json = ProjectOpen->_http_request($uri);

	# Store in cache
	$o_cache->{$object_id} = $o_json;
    }

    return $o_json;
}

# Get the string value of a category. Categories are a kind of constants in ]po[.
# This procedure thakes the ID of a category and will return the pretty name.
# Parameters:
#	category_id:	A category_id value
#
sub get_category {
    my $self = shift;
    my $category_id = shift;

    # Check if we already got the value for this category_id
    # or get the value from the REST server
    my $debug = ProjectOpen->debug;
    my $cat_cache = ProjectOpen->category_cache;
    my $cat_hash;
    if (defined $cat_cache->{$category_id}) { 
 	$cat_hash = $cat_cache->{$category_id}; 
    } else {
	# Get the category from the REST server
	my $uri = URI->new("/intranet-rest/im_category/$category_id?format=json");
	$cat_hash = ProjectOpen->_http_request($uri);

	# Store in cache
	$cat_cache->{$category_id} = $cat_hash;
	print STDERR Dumper($cat_cache) if ($debug > 5);
    }

    my $category = $cat_hash->{category};
    return $category;
}



# Get group memberships for a specific user.
# The procedure returns an array of group_id -> $value hashs
# Parameters:
#	object_id:	ID of a ]po[ user
#
sub get_group_memberships {
    my $self = shift;
    my $object_id = shift;

    # Don't cache this. These results are unlikely to be used again.
    my $host = ProjectOpen->host;
    my $uri = URI->new("http://$host/intranet-reporting/view?format=json");
    $uri->query_form(
		     "report_code" => "rest_group_membership", 
		     "object_id" => $object_id,
		     "format" => "json"
    );
    my $membership_json = ProjectOpen->_http_request($uri);
    my $list = $membership_json->{data};
    
    return $list;
}


1;

