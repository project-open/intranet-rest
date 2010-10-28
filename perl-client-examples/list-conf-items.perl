#!/usr/bin/perl -w

# --------------------------------------------------------
# list-conf_items
# (c) 2010 ]project-open[
# Frank Bergmann (frank.bergmann@project-open.com)
#
# This Perl script will:
#	1. Create a connection to the REST server
#	2. Retreive the list of all ConfItems in the system
#	3. For every ConfItem:
#		3.1. Create a connection to the REST server
#		3.2. Retreive all fields of the ConfItem
#		3.3. Store the conf item values into a Hash of Hashes
#	4. End Loop
#

# --------------------------------------------------------
# Libraries

use XML::Parser;
use LWP::UserAgent;

# --------------------------------------------------------
# Connection parameters: 

# Debug: 0=silent, 9=very verbose
$debug = 1;

# benbigboss/ben is a default user @ demo.project-open.net...
#
$rest_server = "http://demo.project-open.net";		# May include port number
$rest_email = "bbigboss\@tigerpond.com";
$rest_password = "ben";

# Work with local virtual machine
#
$rest_server = "http://192.168.21.128:30086";		# May include port number


# Global vars for keeping the current ID of the conf item and the list of conf items
my $conf_item_id;
my %list_conf_items = ();

# --------------------------------------------------------
# Request the list of configuration items

print "list-conf_items.perl: Sending HTTP request to $rest_server/intranet-rest/im_conf_item\n" if ($debug > 0);
print "list-conf_items.perl: Using email=$rest_email and password=$rest_password\n" if ($debug > 0);

$list_ua = LWP::UserAgent->new;
$list_req = HTTP::Request->new(GET => "$rest_server/intranet-rest/im_conf_item");
$list_req->authorization_basic($rest_email, $rest_password);
$list_response = $list_ua->request($list_req);

# Extract return_code (200, ...), headers and body from the response
print $list_response->as_string if ($debug > 8);
$code = $list_response->code if ($debug > 0);
print "list-conf_items.perl: HTTP return_code=$code\n" if ($debug > 0);
$headers = $list_response->headers_as_string;
print "list-conf_items.perl: HTTP headers=$headers\n" if ($debug > 7);
$body =  $list_response->content;
print "list-conf_items.perl: HTTP body=$body\n" if ($debug > 8);


# -------------------------------------------------------
# Creates a XML parser object with a number of event handlers
# in order to parse the list of configuration items

my $list_parser = new XML::Parser ( Handlers => {
    Start   => \&list_hdl_start,
    End     => \&list_hdl_end,
    Char    => \&list_hdl_char,
    Default => \&hdl_default,
});

my $list_message;			# Hashref containing infos on a message


# Parse the message
# The parser will execute the list_hdl_xxx procedures which will
# continue the execution
$list_parser->parse($body);		# Parse the message





# -------------------------------------------------------
# Define Event Handlers for handling the LIST of configuration items
# -------------------------------------------------------

# Default handler: Just ignore everything else
sub hdl_default { }


# Handle the start of a tag.
# Store the tag's attributes into "message".
# Create a reserved field "_str" which will contain the strings of the tag.
sub list_hdl_start{
    my ($p, $elt, %list_atts) = @_;
    return unless $elt eq 'object_id';  # We're only interrested in what's said
    $list_atts{'_str'} = '';
    $list_message = \%list_atts; 
}

# Handle the end of a tag.
# Just print out the tag
sub list_hdl_end{
    my ($p, $elt) = @_;
    list_process_conf_item($list_message) if $elt eq 'object_id' && $list_message && $list_message->{'_str'} =~ /\S/;
}

# Handle characters: Append them to the "_str" field
sub list_hdl_char {
    my ($p, $str) = @_;
    $list_message->{'_str'} .= $str;
}



# -------------------------------------------------------
# Deal with a single configuration item returned from the list
# This procedure is called from the list_hdl_end when encountering
# an end-tag
# -------------------------------------------------------

sub list_process_conf_item {
    my $list_atts = shift;
    $list_atts->{'_str'} =~ s/\n//g;

    $conf_item_name = $list_atts->{'_str'};
    $conf_item_id = $list_atts->{'id'};
    print "list-conf_items.perl: conf_item_id=$conf_item_id, conf_item_name=$conf_item_name\n";

    # Show the other fields returned by the REST answer
    # while ( my ($key, $value) = each(%$list_atts) ) { print "$key => $value\n";  }


    # Get the XML for the project
    $item_ua = LWP::UserAgent->new;
    $item_req = HTTP::Request->new(GET => "$rest_server/intranet-rest/im_conf_item/$conf_item_id");
    $item_req->authorization_basic($rest_email, $rest_password);
    $item_response = $item_ua->request($item_req);

    # Extract return_code (200, ...), headers and body from the response
    print $item_response->as_string if ($debug > 8);
    $code = $item_response->code if ($debug > 0);
    print "list-conf-items.perl: HTTP return_code=$code\n" if ($debug > 0);
    $headers = $item_response->headers_as_string;
    print "list-conf-items.perl: HTTP headers=$headers\n" if ($debug > 7);
    $body =  $item_response->content;
    print "list-conf-items.perl: HTTP body=$body\n" if ($debug > 8);

    # Write the body into an XML file
    open(F,"> $conf_item_id.xml");
    print F $body;
    close(F);

    # -------------------------------------------------------
    # Creates a XML parser object with a number of event handlers

    my $item_parser = new XML::Parser ( Handlers => {
	Start   => \&item_hdl_start,
	End     => \&item_hdl_end,
	Char    => \&item_hdl_char,
	Default => \&hdl_default,
    });


    my $item_message;			# Hashref containing infos on a message
    $item_parser->parse($body);		# Parse the message
    undef $item_message;
}


# Handle the start of a tag.
# Store the tag's attributes into "message".
# Create a reserved field "_str" which will contain the strings of the tag.
sub item_hdl_start{
    my ($p, $elt, %item_atts) = @_;
    # return unless $elt eq 'object_id';  # We're only interrested in what's said
    $item_atts{'var'} = $elt;
    $item_atts{'_str'} = '';
    $item_message = \%item_atts; 
}

# Handle characters: Append them to the "_str" field
sub item_hdl_char {
    my ($p, $str) = @_;
    $item_message->{'_str'} .= $str;
}

# Handle the end of a tag.
# Store the value into the $conf_item hash ref
sub item_hdl_end{
    my ($p, $elt) = @_;

    $item_message->{'_str'} =~ s/\n//g;
    if (!exists $item_message->{'_str'}) { return; }
    if (!exists $item_message->{'var'}) { return; }

    $str = $item_message->{'_str'};
    $var = $item_message->{'var'};

    # Store the value into the $conf_item hash ref
    print "list-conf-items.perl: id=$conf_item_id, $var=$str\n" if ($debug > 1);

    if ("" ne $str) {
	$list_conf_items{$conf_item_id}{$var} = $str;
    }

    undef $item_message;
}


# -------------------------------------------------------
# Print the list of configuration items
# -------------------------------------------------------

# Print out the "list_conf_items" Hash of Hashes
sub print_conf_items {
    for $cid (keys %list_conf_items) {
	print "conf_item_id=$cid: \n";
	for $attrib (keys %{$list_conf_items{$cid}}) {
	    print "\t$attrib	=  $list_conf_items{$cid}{$attrib} \n";
	}
	print "\n";
    }
}

print_conf_items();

exit 0;

