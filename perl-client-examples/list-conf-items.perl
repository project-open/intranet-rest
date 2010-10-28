#!/usr/bin/perl -w

# --------------------------------------------------------
# list-conf_items
# (c) 2010 ]project-open[
# Frank Bergmann (frank.bergmann@project-open.com)


# --------------------------------------------------------
# Libraries

use XML::Parser;
use LWP::UserAgent;

# --------------------------------------------------------
# Connection parameters: 

# Debug: 0=silent, 9=verbose
$debug = 1;

# benbigboss/ben is a default user @ demo.project-open.net...
#
$rest_server = "http://demo.project-open.net";		# May include port number
$rest_email = "bbigboss\@tigerpond.com";
$rest_password = "ben";

# Work with local virtual machine
#
$rest_server = "http://192.168.21.128:30086";		# May include port number


# --------------------------------------------------------
# Request the XML result

print "list-conf_items.perl: Sending HTTP request to $rest_server/intranet-rest/im_conf_item\n" if ($debug > 0);
print "list-conf_items.perl: Using email=$rest_email and password=$rest_password\n" if ($debug > 0);

$ua = LWP::UserAgent->new;
$req = HTTP::Request->new(GET => "$rest_server/intranet-rest/im_conf_item");
$req->authorization_basic($rest_email, $rest_password);
$response = $ua->request($req);

# Extract return_code (200, ...), headers and body from the response
print $response->as_string if ($debug > 8);
$code = $response->code if ($debug > 0);
print "list-conf_items.perl: HTTP return_code=$code\n" if ($debug > 0);
$headers = $response->headers_as_string;
print "list-conf_items.perl: HTTP headers=$headers\n" if ($debug > 7);
$body =  $response->content;
print "list-conf_items.perl: HTTP body=$body\n" if ($debug > 8);


# -------------------------------------------------------
# Creates a XML parser object with a number of event handlers

my $parser = new XML::Parser ( Handlers => {
                              Start   => \&hdl_start,
                              End     => \&hdl_end,
                              Char    => \&hdl_char,
                              Default => \&hdl_def,
			  });

my $message;			# Hashref containing infos on a message
$parser->parse($body);		# Parse the message



# -------------------------------------------------------
# Define Event Handlers for event based XML parsing

# Handle the start of a tag.
# Store the tag's attributes into "message".
# Create a reserved field "_str" which will contain the strings of the tag.
sub hdl_start{
    my ($p, $elt, %atts) = @_;
    return unless $elt eq 'object_id';  # We're only interrested in what's said
    $atts{'_str'} = '';
    $message = \%atts; 
}

# Handle the end of a tag.
# Just print out the tag
sub hdl_end{
    my ($p, $elt) = @_;
    process_conf_item($message) if $elt eq 'object_id' && $message && $message->{'_str'} =~ /\S/;
}

# Handle characters: Append them to the "_str" field
sub hdl_char {
    my ($p, $str) = @_;
    $message->{'_str'} .= $str;
}

# Default handler: Just ignore everything else
sub hdl_def { }



# -------------------------------------------------------
# Deal with a single configuration item returned from the list

sub process_conf_item {
    my $atts = shift;
    $atts->{'_str'} =~ s/\n//g;

    $conf_item_name = $atts->{'_str'};
    $conf_item_id = $atts->{'id'};
    print "list-conf_items.perl: conf_item_id=$conf_item_id, conf_item_name=$conf_item_name\n";

    # Show the other fields returned by the REST answer
    # while ( my ($key, $value) = each(%$atts) ) { print "$key => $value\n";  }

    undef $message;
}


exit 0;

