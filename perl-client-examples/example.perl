# --------------------------------------------------------
# Access the ]project-open[ REST Web-Service
# Example
# (c) 2010 ]project-open[
# Author: Frank Bergmann
# --------------------------------------------------------

use ProjectOpen;
use Data::Dumper;

# --------------------------------------------------------
# Connection parameters:

# Debug: 0=silent, 9=very verbose
$debug = 1;

# benbigboss/ben is a default user @ demo.project-open.net...
#
$rest_server = "http://demo.project-open.net";          # May include port number
$rest_url = "/intranet-rest/im_conf_item";
$rest_email = "bbigboss\@tigerpond.com";
$rest_password = "ben";


# Create a generic access object to query the ]po[ HTTP server
#
ProjectOpen->new (
	server	=> $rest_server,
	email	=> $rest_email,
	password => $rest_password,
	debug => $debug
);


# HTTP request with specific URL. You can use this if you know
# which page to retreive in ]po[.
#
my $conf_item_list = ProjectOpen->get_object_list("im_conf_item");
print Dumper($conf_item_list) if ($debug > 5);


# -------------------------------------------------------
# Get the list of IDs of the Conf Items
#
my $list = $conf_item_list->{object_id};
for my $object_id (keys %$list) {
    
    print "example.perl: Found conf_item_id=$object_id\n" if ($debug > 5);
    my $conf_item = ProjectOpen->get_object("im_conf_item", $object_id);
    print Dumper($conf_item) if ($debug > 5);

    my $conf_item_name = $conf_item->{conf_item_name};
    my $conf_item_status_id = $conf_item->{conf_item_status_id}->{content};
    my $conf_item_type_id = $conf_item->{conf_item_type_id}->{content};

    my $conf_item_status = ProjectOpen->get_category($conf_item_status_id);
    my $conf_item_type = ProjectOpen->get_category($conf_item_type_id);

    print "example.perl: name=$conf_item_name, status=$conf_item_status, type=$conf_item_type\n" if ($debug);

}

