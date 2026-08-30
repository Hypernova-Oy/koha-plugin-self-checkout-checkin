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
use Try::Tiny;
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

sub _get_kioskboard_content {
    my ( $self ) = @_;
    
    my $kioskboard_file = $self->mbf_path('opac/js/kioskboard-aio-2.3.0.min.js');
    open my $fh, '<', $kioskboard_file or return '';
    local $/;
    my $content = <$fh>;
    close $fh;
    
    return $content;
}

sub _get_kioskboard_version {
    my ( $self ) = @_;
    
    return '2.3.0';
}

sub _get_kioskboard_binding_js {
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

sub _install_kioskboard_to_sco_user_js {
    my ( $self, $force ) = @_;
    
    my $enable_virtual_keyboard = $self->retrieve_data('enable_virtual_keyboard');
    
    unless ( $enable_virtual_keyboard || $force ) {
        return 1;
    }
    
    my $kioskboard_version = $self->_get_kioskboard_version();
    my $kioskboard_content = $self->_get_kioskboard_content();
    my $kioskboard_binding_js = $self->_get_kioskboard_binding_js();
    
    return unless $kioskboard_content && $kioskboard_binding_js;
    
    my $sco_user_js = C4::Context->preference('SCOUserJS') || '';
    
    my $version_regex = qr/\/\* KioskBoard - Virtual Keyboard \(https:\/\/github\.com\/furcan\/KioskBoard\) - Version: (\d+\.\d+\.\d+)/;
    
    if ( $sco_user_js =~ /$version_regex/ ) {
        my $existing_version = $1;
        
        if ( $existing_version eq $kioskboard_version ) {
            return 1;
        }
        
        $sco_user_js =~ s/\/\/ KioskBoard - Added by Self Checkout & Check-in plugin \(Version: \d+\.\d+\.\d+\).*?\n\n.*?\n//gs;
    }
    
    my $new_content = "// KioskBoard - Added by Self Checkout & Check-in plugin (Version: $kioskboard_version)\n" . $kioskboard_content . "\n" . $kioskboard_binding_js . "\n\n" . $sco_user_js;
    
    C4::Context->set_preference('SCOUserJS', $new_content);
    
    return 1;
}

sub _check_kioskboard_in_sco_user_js {
    my ( $self ) = @_;
    
    my $sco_user_js = C4::Context->preference('SCOUserJS') || '';
    my $version_regex = qr/\/\* KioskBoard - Virtual Keyboard \(https:\/\/github\.com\/furcan\/KioskBoard\) - Version: (\d+\.\d+\.\d+)/;
    
    if ( $sco_user_js =~ /$version_regex/ ) {
        return $1;
    }
    
    return '';
}

sub _remove_kioskboard_from_sco_user_js {
    my ( $self ) = @_;
    
    my $sco_user_js = C4::Context->preference('SCOUserJS') || '';
    
    $sco_user_js =~ s/\/\/ KioskBoard - Added by Self Checkout & Check-in plugin \(Version: \d+\.\d+\.\d+\).*?\n\n.*?\n//gs;
    
    C4::Context->set_preference('SCOUserJS', $sco_user_js);
    
    return 1;
}

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('save') ) {
        my $template = $self->get_template( { file => 'configure.tt' } );

        my $opac_base_url = C4::Context->preference('OPACBaseURL') || '';
        my $plugin_url = $opac_base_url . '/api/v1/contrib/' . $self->api_namespace . '/scc';
        
        my $kioskboard_version = $self->_check_kioskboard_in_sco_user_js();
        my $enable_virtual_keyboard = $self->retrieve_data('enable_virtual_keyboard');

        ## Grab the values we already have for our settings, if any exist
        $template->param(
            SelfCheckAllowByIPRanges => C4::Context->preference('SelfCheckAllowByIPRanges'),
            ipallowed => $self->retrieve_data('ipallowed'),
            scc_sci_username => $self->retrieve_data('scc_sci_username'),
            scc_sci_password => $self->retrieve_data('scc_sci_password'),
            plugin_opac_url => $plugin_url,
            kioskboard_deployed => $kioskboard_version ? 1 : 0,
            kioskboard_version => $kioskboard_version || '',
            enable_virtual_keyboard => $enable_virtual_keyboard,
        );

        $self->output_html( $template->output() );
    }
    else {
        my $enable_virtual_keyboard = $cgi->param('enable_virtual_keyboard') ? 1 : 0;
        
        $self->store_data(
            {
                scc_sci_username => scalar $cgi->param('scc_sci_username'),
                scc_sci_password => scalar $cgi->param('scc_sci_password'),
                ipallowed => scalar $cgi->param('ipallowed'),
                enable_virtual_keyboard => $enable_virtual_keyboard,
            }
        );
        $self->_install_kioskboard_to_sco_user_js();
        $self->go_home();
    }
}

sub install {
    my ( $self, $args ) = @_;
    
    $self->_install_kioskboard_to_sco_user_js(1);
    
    return 1;
}

sub uninstall {
    my ( $self, $args ) = @_;
    
    $self->_remove_kioskboard_from_sco_user_js();
    
    return 1;
}

sub upgrade {
    my ( $self, $args ) = @_;
    
    $self->_install_kioskboard_to_sco_user_js(1);
    
    return 1;
}

1;
