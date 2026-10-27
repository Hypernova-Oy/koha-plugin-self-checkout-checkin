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
use C4::Context;

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

# Filename of the bundled KioskBoard virtual keyboard library. It is served
# through a cacheable REST API static route (see static_routes below) instead of
# being injected into the SCOUserJS system preference.
our $KIOSKBOARD_FILE = 'kioskboard-aio-2.3.0.min.js';

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

    # Only extend the self checkout (SCO) and self check-in (SCI) screens. The
    # request URL is available in the PSGI/CGI environment during OPAC rendering.
    my $path = $ENV{'SCRIPT_NAME'} // $ENV{'REQUEST_URI'} // '';
    return '' unless $path =~ m{(?:sco/sco-main\.pl|sci/sci-main\.pl)};

    my $js = '<script src="' . $self->get_plugin_http_path() . '/opac/scc/js/scc.js"></script>';

    # The virtual keyboard is only needed on the SCO login (PIN) screen.
    if ( $path =~ m{sco/sco-main\.pl} && $self->retrieve_data('enable_virtual_keyboard') ) {
        my $kioskboard_url = '/api/v1/contrib/' . $self->api_namespace . '/static/' . $KIOSKBOARD_FILE;
        $js .= "\n" . '<script src="' . $kioskboard_url . '"></script>';
        $js .= "\n" . '<script>' . $self->_kioskboard_binding_js() . '</script>';
    }

    return $js;
}

sub _kioskboard_binding_js {
    my ( $self ) = @_;

    return <<'END_JS';
// Enable KioskBoard numeric keypad for SCO PIN input
if (typeof KioskBoard !== 'undefined') {
    var pinInput = document.querySelector('body#sco_main input#patronpw');
    if (pinInput) {
        pinInput.setAttribute("class","js-kioskboard-input");
        pinInput.setAttribute("data-kioskboard-type","numpad");
        pinInput.setAttribute("data-kioskboard-placement","bottom");
        KioskBoard.init({keysArrayOfObjects: [{"0":"0","1":"1"}]}); // For some reason this must be given, even if using data-* configuration
        KioskBoard.run(pinInput);
    }
}
END_JS
}

sub api_routes {
    my ( $self, $args ) = @_;

    my $spec_str = $self->mbf_read('openapi.json');
    my $spec     = decode_json($spec_str);

    return $spec;
}

sub static_routes {
    my ( $self, $args ) = @_;

    return {
        "/$KIOSKBOARD_FILE" => {
            get => {
                'x-mojo-to' => 'Fi::Hypernova::SelfCheckoutCheckin::Controller#kioskboard',
                operationId => 'kioskboard',
                tags        => ['kioskboard'],
                produces    => ['application/javascript'],
                responses   => {
                    200 => { description => 'KioskBoard virtual keyboard library' },
                },
            },
        },
    };
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

        my $opac_base_url  = C4::Context->preference('OPACBaseURL') || '';
        my $plugin_url     = $opac_base_url . '/api/v1/contrib/' . $self->api_namespace . '/scc';
        my $kioskboard_url = '/api/v1/contrib/' . $self->api_namespace . '/static/' . $KIOSKBOARD_FILE;

        $template->param(
            SelfCheckAllowByIPRanges => C4::Context->preference('SelfCheckAllowByIPRanges'),
            ipallowed                => $self->retrieve_data('ipallowed'),
            scc_sci_username         => $self->retrieve_data('scc_sci_username'),
            scc_sci_password_set     => $self->retrieve_data('scc_sci_password') ? 1 : 0,
            plugin_opac_url          => $plugin_url,
            kioskboard_url           => $kioskboard_url,
            enable_virtual_keyboard  => $self->retrieve_data('enable_virtual_keyboard'),
        );

        $self->output_html( $template->output() );
    }
    else {
        my $enable_virtual_keyboard = $cgi->param('enable_virtual_keyboard') ? 1 : 0;

        my $data = {
            scc_sci_username        => scalar $cgi->param('scc_sci_username'),
            ipallowed               => scalar $cgi->param('ipallowed'),
            enable_virtual_keyboard => $enable_virtual_keyboard,
        };

        # Only overwrite the stored password when a new value is submitted.
        # A value of only asterisks (the masked placeholder) means "keep current".
        my $password = scalar $cgi->param('scc_sci_password');
        $data->{scc_sci_password} = $password
            if defined $password && $password ne '' && $password !~ /^\*+$/;

        $self->store_data($data);
        $self->go_home();
    }
}

sub install {
    my ( $self, $args ) = @_;

    return 1;
}

sub uninstall {
    my ( $self, $args ) = @_;

    return 1;
}

sub upgrade {
    my ( $self, $args ) = @_;

    return 1;
}

1;
