package Koha::Plugin::Fi::Hypernova::SelfCheckoutCheckin;

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# This program comes with ABSOLUTELY NO WARRANTY;

use Modern::Perl;

use base qw(Koha::Plugins::Base);

use Mojo::JSON qw(decode_json);
use YAML;
use Try::Tiny;

our $VERSION = "24.11.02";

our $metadata = {
    name            => 'Self Checkout & Check-in without login',
    author          => 'Lari Taskula',
    date_authored   => '2023-08-04',
    date_updated    => "2025-11-26",
    minimum_version => '24.05.01.000',
    maximum_version => undef,
    version         => $VERSION,
    description     => 'This plugin adds combined self checkout and check-in view to OPAC. Check-in in this plugin requires no login.',
};

sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual $self
    my $self = $class->SUPER::new($args);

    return $self;
}

sub opac_js {
    my ( $self ) = @_;

    return '<script src="'.$self->get_plugin_http_path().'/opac/scc/js/scc.js"></script>';
}

sub api_routes {
    my ( $self, $args ) = @_;

    my $spec_str = $self->mbf_read('openapi.json');
    my $spec     = decode_json($spec_str);

    return $spec;
}

sub api_namespace {
    my ( $self ) = @_;
    
    return 'hypernova';
}

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('save') ) {
        my $template = $self->get_template( { file => 'configure.tt' } );

        ## Grab the values we already have for our settings, if any exist
        $template->param(
            SelfCheckAllowByIPRanges => C4::Context->preference('SelfCheckAllowByIPRanges'),
            ipallowed => $self->retrieve_data('ipallowed'),
            scc_sci_username => $self->retrieve_data('scc_sci_username'),
            scc_sci_password => $self->retrieve_data('scc_sci_password'),
        );

        $self->output_html( $template->output() );
    }
    else {
        $self->store_data(
            {
                scc_sci_username => scalar $cgi->param('scc_sci_username'),
                scc_sci_password => scalar $cgi->param('scc_sci_password'),
                ipallowed => scalar $cgi->param('ipallowed'),
            }
        );
        $self->go_home();
    }
}

sub install {
    return 1;
}

sub uninstall {}

1;
