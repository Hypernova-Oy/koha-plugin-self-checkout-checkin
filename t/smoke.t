#!/usr/bin/perl

use Test::More;
use Test::Mojo;

# Koha::Logger reads LOG4PERL_CONF. Point it at a writable, stderr-only config so
# the test neither depends on nor writes to the instance's log files.
my $log_conf = "/tmp/koha-plugin-scc-log4perl-$$.conf";
open my $lfh, '>', $log_conf or die "Cannot write $log_conf: $!";
print {$lfh} join( "\n",
    'log4perl.rootLogger = WARN, SCREEN',
    'log4perl.appender.SCREEN=Log::Log4perl::Appender::Screen',
    'log4perl.appender.SCREEN.stderr=1',
    'log4perl.appender.SCREEN.layout=Log::Log4perl::Layout::PatternLayout',
    'log4perl.appender.SCREEN.layout.ConversionPattern=%m%n',
) . "\n";
close $lfh;
$ENV{LOG4PERL_CONF} = $log_conf;

require Koha::REST::V1;
require C4::Context;

my $plugin_class = 'Koha::Plugin::Fi::Hypernova::SelfCheckoutCheckin';

# Instantiating the plugin auto-runs install(), so only run when it is already
# installed and its routes are registered.
my $installed = C4::Context->dbh->selectrow_array(
    'SELECT COUNT(*) FROM plugin_methods WHERE plugin_class = ?',
    undef, $plugin_class,
);
plan skip_all => "$plugin_class is not installed" unless $installed;

require Koha::Plugin::Fi::Hypernova::SelfCheckoutCheckin;

my $t = Test::Mojo->new('Koha::REST::V1');

subtest 'SCC page loads' => sub {
    # The combined self-checkout/check-in page now relies on Koha's SCO
    # auto-login (AutoSelfCheckAllowed + AutoSelfCheckID/AutoSelfCheckPass) to
    # render when OpacPublic requires authentication. When that is not
    # configured there is nothing to render, so skip rather than dumping the
    # OPAC login page.
    my $auto_allowed = C4::Context->preference('AutoSelfCheckAllowed');
    my $auto_id      = C4::Context->preference('AutoSelfCheckID') // '';
    my $auto_pass    = C4::Context->preference('AutoSelfCheckPass') // '';

    plan skip_all => 'AutoSelfCheckAllowed/AutoSelfCheckID/AutoSelfCheckPass not configured'
        if !$auto_allowed || $auto_id eq '' || $auto_pass eq '';

    $t->get_ok('/api/v1/contrib/hypernova/scc')
        ->status_is(200)
        ->header_like( 'Content-Type' => qr{text/html} )
        ->content_like( qr{start-checkout|start-checkin} );
};

subtest 'SCC page respects SelfCheckAllowByIPRanges' => sub {
    # Mirror sco-main.pl: when SelfCheckAllowByIPRanges is set and the client
    # IP is not in the allowed range, the combined page must redirect away
    # instead of auto-logging in.
    local $ENV{'OVERRIDE_SYSPREF_SelfCheckAllowByIPRanges'} = '192.168.0.0/24';

    $t->get_ok('/api/v1/contrib/hypernova/scc')
        ->status_is(302)
        ->header_is( 'Location' => '/cgi-bin/koha/opac-main.pl' );
};

subtest 'Static KioskBoard library loads' => sub {
    $t->get_ok('/api/v1/contrib/hypernova/static/kioskboard-aio-2.3.0.min.js')
        ->status_is(200)
        ->header_like( 'Content-Type' => qr{application/javascript} )
        ->content_like( qr{KioskBoard} );
};

subtest 'Check-in endpoint redirects' => sub {
    $t->get_ok('/api/v1/contrib/hypernova/redirect/checkin')
        ->status_is(302)
        ->header_is( 'Location' => '/cgi-bin/koha/sci/sci-main.pl' );
};

subtest 'opac_js on the SCO screen' => sub {
    my $plugin = $plugin_class->new( { enable_plugins => 1 } );
    local $ENV{'SCRIPT_NAME'} = '/cgi-bin/koha/sco/sco-main.pl';
    my $js = $plugin->opac_js;
    like( $js, qr{opac/sco/js/scc\.js}, 'loads scc.js from the sco bundle path' );
};

subtest 'Self-service session reload timeout' => sub {
    my $plugin = $plugin_class->new( { enable_plugins => 1 } );

    # With a session timeout configured, the SCO and SCI login views reload at
    # 80% of the timeout so the auto-login refreshes the session before it
    # expires (the timeout preference is in seconds, the interval in ms).
    local $ENV{'OVERRIDE_SYSPREF_timeout'} = '5';

    my $sco = $plugin->_reload_js('sco');
    like( $sco, qr/body#sco_main/, 'SCO reload targets the SCO login screen' );
    like( $sco, qr/location\.reload\(true\);\s*\}, 4000\)/, 'SCO reloads at 80% of the timeout (4000 ms)' );

    my $sci = $plugin->_reload_js('sci');
    like( $sci, qr/body#sci_main/, 'SCI reload targets the SCI login screen' );
    like( $sci, qr/location\.reload\(true\);\s*\}, 4000\)/, 'SCI reloads at 80% of the timeout (4000 ms)' );

    # Without a timeout, no reload script is generated.
    local $ENV{'OVERRIDE_SYSPREF_timeout'} = '';
    my $js = $plugin->_reload_js('sco');
    is( $js, '', 'no reload script when the timeout preference is unset' );
};

subtest 'opac_js on the SCI screen' => sub {
    my $plugin = $plugin_class->new( { enable_plugins => 1 } );
    local $ENV{'SCRIPT_NAME'} = '/cgi-bin/koha/sci/sci-main.pl';
    my $js = $plugin->opac_js;
    like( $js, qr{opac/sco/js/scc\.js}, 'loads scc.js from the sco bundle path' );
    like( $js, qr{sci_append_button}, 'keeps the SCI OK button in sync with the barcode input' );
    like( $js, qr{Itsepalvelupalautus}, 'corrects the Finnish self check-in heading' );
};

subtest 'opac_js is empty elsewhere' => sub {
    my $plugin = $plugin_class->new( { enable_plugins => 1 } );
    local $ENV{'SCRIPT_NAME'} = '/cgi-bin/koha/opac-main.pl';
    my $js = $plugin->opac_js;
    is( $js, '', 'no JS injected on other OPAC pages' );
};

done_testing;
