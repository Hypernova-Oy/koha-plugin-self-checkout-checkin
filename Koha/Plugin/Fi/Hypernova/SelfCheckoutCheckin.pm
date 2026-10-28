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
use C4::Auth;
use Koha::Patrons;

our $VERSION = "24.11.02"; #PLACEHOLDER
our $DATE_UPDATED = "2025-11-26"; #PLACEHOLDER

our $metadata = {
    name            => 'Self Checkout & Check-in without login',
    author          => 'Lari Taskula',
    date_authored   => '2023-08-04',
    date_updated    => $DATE_UPDATED,
    minimum_version => '24.05.01.000',
    maximum_version => undef,
    version         => $VERSION,
    description     => 'This plugin adds combined self checkout and check-in view to OPAC. Check-in in this plugin requires no login.',
};

# Filename of the bundled KioskBoard virtual keyboard library. It is served
# through a cacheable REST API static route (see static_routes below) instead of
# being injected into the SCOUserJS system preference.
our $KIOSKBOARD_FILE = 'kioskboard-aio-2.3.0.min.js';

# Default key rows (English QWERTY) used when the administrator has not entered
# a custom "Custom keys" JSON. Matches KioskBoard's own English layout.
our $KIOSKBOARD_DEFAULT_KEYS = '[{"0":"Q","1":"W","2":"E","3":"R","4":"T","5":"Y","6":"U","7":"I","8":"O","9":"P"},{"0":"A","1":"S","2":"D","3":"F","4":"G","5":"H","6":"J","7":"K","8":"L"},{"0":"Z","1":"X","2":"C","3":"V","4":"B","5":"N","6":"M"}]';

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

    my $js = '<script src="' . $self->get_plugin_http_path() . '/opac/sco/js/scc.js"></script>';

    if ( $path =~ m{sco/sco-main\.pl} ) {
        # Periodically reload the SCO login screen: the AutoSelfCheckAllowed
        # session is not refreshed after the 'timeout' system preference.
        my $reload_js = $self->_sco_reload_js();
        $js .= "\n" . '<script>' . $reload_js . '</script>' if $reload_js;
    }

    # The KioskBoard virtual keyboard is available on both the SCO and SCI screens.
    if ( $self->retrieve_data('enable_virtual_keyboard') ) {
        my $page = $path =~ m{sci/sci-main\.pl} ? 'sci' : 'sco';
        my $kioskboard_js = $self->_kioskboard_js($page);
        if ($kioskboard_js) {
            my $kioskboard_url = '/api/v1/contrib/' . $self->api_namespace . '/static/' . $KIOSKBOARD_FILE;
            $js .= "\n" . '<script src="' . $kioskboard_url . '"></script>';
            $js .= "\n" . '<script>' . $kioskboard_js . '</script>';
        }
    }

    return $js;
}

sub _sco_reload_js {
    my ( $self ) = @_;

    my $timeout_seconds = C4::Context->preference('timeout') || 0;
    my $reload_ms = $timeout_seconds > 0 ? int( $timeout_seconds * 1000 / 3 ) : 0;
    return '' unless $reload_ms > 0;

    return <<"END_JS";
// Reload the SCO login screen periodically, because the 'AutoSelfCheckAllowed'
// system preference fails to refresh the session after the 'timeout' preference.
if (document.querySelector('body#sco_main')) {
    var sccReloadTimeout = setTimeout(function () { location.reload(true); }, $reload_ms);
}
END_JS
}

sub _kioskboard_js {
    my ( $self, $page ) = @_;

    my @selectors;
    if ( $page eq 'sco' ) {
        push @selectors, 'body#sco_main input#patronid'    if $self->retrieve_data('kioskboard_field_patronid');
        push @selectors, 'body#sco_main input#patronlogin' if $self->retrieve_data('kioskboard_field_patronlogin');
        push @selectors, 'body#sco_main input#patronpw'    if $self->retrieve_data('kioskboard_field_patronpw') // 1;
    }
    else {
        push @selectors, 'body#sci_main input#barcode_input' if $self->retrieve_data('kioskboard_field_barcode') // 1;
    }
    return '' unless @selectors;

    my %valid_themes  = map { $_ => 1 } qw( light dark flat material oldschool );
    my %valid_layouts = map { $_ => 1 } qw( all keyboard numpad );

    my $theme = $self->retrieve_data('kioskboard_theme');
    $theme = 'light' unless $valid_themes{$theme};

    my $layout = $self->retrieve_data('kioskboard_layout');
    $layout = 'numpad' unless $valid_layouts{$layout};

    my $keys_json  = $self->retrieve_data('kioskboard_keys_json') || '';
    my $keys_array = $KIOSKBOARD_DEFAULT_KEYS;
    if ( $keys_json =~ /\S/ ) {
        my $decoded = eval { decode_json($keys_json) };
        $keys_array = $keys_json if $decoded && ref($decoded) eq 'ARRAY';
    }

    # Action-key visibility (Caps/Shift, Space, Backspace, Enter). KioskBoard's
    # own CSS is scoped to the "#KioskBoard-VirtualKeyboard" ID, which beats
    # plain class selectors, so our overrides repeat that ID and use !important.
    my $show_space     = $self->retrieve_data('kioskboard_key_space') // 0;
    my $show_caps      = $self->retrieve_data('kioskboard_key_caps')  // 0;
    my $show_backspace = $self->retrieve_data('kioskboard_key_backspace') // 0;
    my $show_enter     = $self->retrieve_data('kioskboard_key_enter') // 1;

    my @css_rules;
    push @css_rules, '#KioskBoard-VirtualKeyboard .kioskboard-key-space { display: none !important; }'     unless $show_space;
    push @css_rules, '#KioskBoard-VirtualKeyboard .kioskboard-key-capslock { display: none !important; }'  unless $show_caps;
    push @css_rules, '#KioskBoard-VirtualKeyboard .kioskboard-key-backspace { display: none !important; }' unless $show_backspace;
    push @css_rules, '#KioskBoard-VirtualKeyboard .kioskboard-key-enter { flex-grow: 2 !important; }'      if $show_enter;

    my $css_injection = '';
    if (@css_rules) {
        my $css_text = join ' ', @css_rules;
        $css_injection =
            "        var sccStyle = document.createElement('style');\n" .
            "        sccStyle.textContent = '$css_text';\n" .
            "        document.head.appendChild(sccStyle);\n";
    }

    my $selector_list = join ', ', @selectors;

    return <<"END_JS";
if (typeof KioskBoard !== 'undefined') {
    var sccInputs = document.querySelectorAll('$selector_list');
    if (sccInputs.length) {
        [].forEach.call(sccInputs, function (input) {
            input.classList.add('js-kioskboard-input');
            input.setAttribute('data-kioskboard-type', '$layout');
            input.setAttribute('data-kioskboard-placement', 'bottom');
        });
        var sccCurrentInput = null;
        document.addEventListener('focusin', function (e) {
            if (e.target && e.target.classList && e.target.classList.contains('js-kioskboard-input')) {
                sccCurrentInput = e.target;
            }
        });
$css_injection        KioskBoard.init({
            theme: '$theme',
            keysArrayOfObjects: $keys_array,
            keysEnterCallback: function () {
                if (sccCurrentInput && sccCurrentInput.form) {
                    if (typeof sccCurrentInput.form.requestSubmit === 'function') {
                        sccCurrentInput.form.requestSubmit();
                    } else {
                        sccCurrentInput.form.submit();
                    }
                }
            }
        });
        KioskBoard.run('$selector_list');
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
            ipallowed                  => $self->retrieve_data('ipallowed'),
            scc_sci_username           => $self->retrieve_data('scc_sci_username'),
            scc_sci_password_set       => $self->retrieve_data('scc_sci_password') ? 1 : 0,
            plugin_opac_url            => $plugin_url,
            kioskboard_url             => $kioskboard_url,
            enable_virtual_keyboard    => $self->retrieve_data('enable_virtual_keyboard'),
            kioskboard_theme           => $self->retrieve_data('kioskboard_theme') || 'light',
            kioskboard_layout          => $self->retrieve_data('kioskboard_layout') || 'numpad',
            kioskboard_keys_json       => $self->retrieve_data('kioskboard_keys_json') || '',
            kioskboard_default_keys    => $KIOSKBOARD_DEFAULT_KEYS,
            kioskboard_key_space       => $self->retrieve_data('kioskboard_key_space') // 0,
            kioskboard_key_caps        => $self->retrieve_data('kioskboard_key_caps')  // 0,
            kioskboard_key_backspace   => $self->retrieve_data('kioskboard_key_backspace') // 0,
            kioskboard_key_enter       => $self->retrieve_data('kioskboard_key_enter') // 1,
            kioskboard_field_patronid  => $self->retrieve_data('kioskboard_field_patronid') ? 1 : 0,
            kioskboard_field_patronlogin => $self->retrieve_data('kioskboard_field_patronlogin') ? 1 : 0,
            kioskboard_field_patronpw  => $self->retrieve_data('kioskboard_field_patronpw') // 1,
            kioskboard_field_barcode   => $self->retrieve_data('kioskboard_field_barcode') // 1,
            diagnostics                => $self->_run_diagnostics(),
        );

        $self->output_html( $template->output() );
    }
    else {
        my $enable_virtual_keyboard = $cgi->param('enable_virtual_keyboard') ? 1 : 0;

        my $data = {
            scc_sci_username           => scalar $cgi->param('scc_sci_username'),
            ipallowed                  => scalar $cgi->param('ipallowed'),
            enable_virtual_keyboard    => $enable_virtual_keyboard,
            kioskboard_theme           => scalar $cgi->param('kioskboard_theme') || 'light',
            kioskboard_layout          => scalar $cgi->param('kioskboard_layout') || 'numpad',
            kioskboard_keys_json       => scalar $cgi->param('kioskboard_keys_json') || '',
            kioskboard_key_space       => $cgi->param('kioskboard_key_space') ? 1 : 0,
            kioskboard_key_caps        => $cgi->param('kioskboard_key_caps') ? 1 : 0,
            kioskboard_key_backspace   => $cgi->param('kioskboard_key_backspace') ? 1 : 0,
            kioskboard_key_enter       => $cgi->param('kioskboard_key_enter') ? 1 : 0,
            kioskboard_field_patronid  => $cgi->param('kioskboard_field_patronid') ? 1 : 0,
            kioskboard_field_patronlogin => $cgi->param('kioskboard_field_patronlogin') ? 1 : 0,
            kioskboard_field_patronpw  => $cgi->param('kioskboard_field_patronpw') ? 1 : 0,
            kioskboard_field_barcode   => $cgi->param('kioskboard_field_barcode') ? 1 : 0,
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

sub _run_diagnostics {
    my ( $self ) = @_;

    return {
        sci => $self->_diagnose_module('sci'),
        sco => $self->_diagnose_module('sco'),
    };
}

sub _diagnose_module {
    my ( $self, $module ) = @_;

    my ( $username, $password, $permission, $iprange, $enabling_ok, $sysprefs );

    if ( $module eq 'sci' ) {
        $username    = $self->retrieve_data('scc_sci_username') // '';
        $password    = $self->retrieve_data('scc_sci_password') // '';
        $permission  = 'self_checkin_module';
        $iprange     = $self->retrieve_data('ipallowed') // '';
        $enabling_ok = C4::Context->preference('SelfCheckInModule') ? 1 : 0;
        $sysprefs    = [
            {
                name    => 'SelfCheckInModule',
                display => $enabling_ok ? 'Enabled' : 'Disabled',
                ok      => $enabling_ok,
                hint    => 'Enables the self check-in module',
                url     => $self->_pref_url('SelfCheckInModule'),
            },
        ];
    }
    else {
        $username    = C4::Context->preference('AutoSelfCheckID') // '';
        $password    = C4::Context->preference('AutoSelfCheckPass') // '';
        $permission  = 'self_checkout_module';
        $iprange     = C4::Context->preference('SelfCheckAllowByIPRanges') // '';
        $enabling_ok = C4::Context->preference('WebBasedSelfCheck') ? 1 : 0;
        $sysprefs    = [
            {
                name    => 'WebBasedSelfCheck',
                display => $enabling_ok ? 'Enabled' : 'Disabled',
                ok      => $enabling_ok,
                hint    => 'Enables web-based self checkout',
                url     => $self->_pref_url('WebBasedSelfCheck'),
            },
            {
                name    => 'AutoSelfCheckAllowed',
                display => C4::Context->preference('AutoSelfCheckAllowed') ? 'Enabled' : 'Disabled',
                ok      => C4::Context->preference('AutoSelfCheckAllowed') ? 1 : 0,
                hint    => 'Automatically logs in to self checkout',
                url     => $self->_pref_url('AutoSelfCheckAllowed'),
            },
            {
                name    => 'AutoSelfCheckID',
                display => $username ne '' ? $username : '(not set)',
                ok      => $username ne '' ? 1 : 0,
                hint    => 'Username used for automatic self checkout login',
                url     => $self->_pref_url('AutoSelfCheckID'),
            },
            {
                name    => 'AutoSelfCheckPass',
                display => $password ne '' ? 'Set' : 'Not set',
                ok      => $password ne '' ? 1 : 0,
                hint    => 'Password used for automatic self checkout login',
                url     => $self->_pref_url('AutoSelfCheckPass'),
            },
            {
                name    => 'SelfCheckAllowByIPRanges',
                display => $iprange ne '' ? $iprange : '(not set)',
                ok      => 1,
                hint    => 'Optional IP restriction for self checkout',
                url     => $self->_pref_url('SelfCheckAllowByIPRanges'),
            },
        ];
    }

    my $tests = {
        credentials => $self->_test_credentials( $username, $password ),
        permissions => $self->_test_permissions( $username, $permission ),
        ip          => $self->_test_ip( $iprange ),
    };

    my $ready = $enabling_ok
        && $tests->{credentials}{ok}
        && $tests->{permissions}{ok}
        && $tests->{ip}{ok} ? 1 : 0;

    return {
        sysprefs => $sysprefs,
        tests    => $tests,
        ready    => $ready,
    };
}

sub _test_credentials {
    my ( $self, $username, $password ) = @_;

    return { ok => 0, message => 'No username configured' }
        unless defined $username && $username ne '';
    return { ok => 0, message => 'No password configured' }
        unless defined $password && $password ne '';

    my ($retval) = C4::Auth::checkpw( $username, $password, $self->{'cgi'}, 'intranet', 1 );

    return { ok => 1, message => 'Credentials are valid' } if $retval;

    my $patron = Koha::Patrons->find( { userid => $username } )
        || Koha::Patrons->find( { cardnumber => $username } );

    return { ok => 0, message => 'User not found' } unless $patron;
    return { ok => 0, message => 'Wrong password' };
}

sub _test_permissions {
    my ( $self, $username, $permission ) = @_;

    return { ok => 0, message => 'No username configured' }
        unless defined $username && $username ne '';

    my $patron = Koha::Patrons->find( { userid => $username } )
        || Koha::Patrons->find( { cardnumber => $username } );

    return { ok => 0, message => 'User not found' } unless $patron;

    my %labels = (
        self_checkin_module  => 'self check-in',
        self_checkout_module => 'self check-out',
    );
    my $label = $labels{$permission} || $permission;

    my $ok = C4::Auth::haspermission( $patron->userid, { self_check => $permission } );
    return $ok
        ? { ok => 1, message => "Has the $label permission" }
        : { ok => 0, message => "Missing the $label permission" };
}

sub _test_ip {
    my ( $self, $iprange ) = @_;

    my $ip = $ENV{'REMOTE_ADDR'} // '';
    $ip ||= $self->{'cgi'}->remote_addr() if $self->{'cgi'};

    if ( !defined $iprange || $iprange eq '' ) {
        return { ok => 1, message => "No IP restriction set. Your current IP is $ip", ip => $ip };
    }

    my $in_range = C4::Auth::in_iprange($iprange);
    return $in_range
        ? { ok => 1, message => "Your IP ($ip) is within the allowed range", ip => $ip }
        : { ok => 0, message => "Your IP ($ip) is NOT within the allowed range", ip => $ip };
}

sub _pref_url {
    my ( $self, $name ) = @_;

    return '/cgi-bin/koha/admin/preferences.pl?tab=&op=search&searchfield=' . $name;
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


