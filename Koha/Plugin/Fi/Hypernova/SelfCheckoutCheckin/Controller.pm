package Koha::Plugin::Fi::Hypernova::SelfCheckoutCheckin::Controller;

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

use Mojo::Base 'Mojolicious::Controller';
use Mojo::File;
use Try::Tiny;

use CGI;

use C4::Auth qw( get_template_and_user );
use Koha::Plugin::Fi::Hypernova::SelfCheckoutCheckin;

=head1 Koha::Plugin::Fi::Hypernova::SelfCheckoutCheckin::Controller

A class implementing the controller methods for checking in items

=head2 Class methods

=head3 redirect_checkin

Authenticates the self-check-in user and redirects to sci-main.pl

=cut

sub redirect_checkin {
    my $c = shift->openapi->valid_input or return;

    return try {
        $ENV{'REMOTE_ADDR'} = $c->tx->remote_address;

        my $scc_obj = Koha::Plugin::Fi::Hypernova::SelfCheckoutCheckin->new;
        my $cgi = CGI->new;

        my $ipallowed = $scc_obj->retrieve_data('ipallowed');
        if ( $ipallowed && !C4::Auth::in_iprange($ipallowed) ) {
            $c->app->log->warn('User (' . $ENV{'REMOTE_ADDR'} . ') not allowed to access SCI');
            return $c->redirect_to('/cgi-bin/koha/sci/sci-main.pl');
        }

        $cgi->param(login_userid => $scc_obj->retrieve_data('scc_sci_username'));
        $cgi->param(login_password => $scc_obj->retrieve_data('scc_sci_password'));

        my ($status, $cookie, $sessionid) = C4::Auth::check_api_auth(
            $cgi,
            { self_check => "self_checkin_module" },
        );

        $c->cookie(CGISESSID => $sessionid, { path => "/" });
        return $c->redirect_to('/cgi-bin/koha/sci/sci-main.pl');
    }
    catch {
        $c->unhandled_exception($_);
    };
}

sub template {
    my $c = shift->openapi->valid_input or return;

    return try {
        $ENV{'REMOTE_ADDR'} = $c->tx->remote_address;

        my $scc_obj = Koha::Plugin::Fi::Hypernova::SelfCheckoutCheckin->new;
        my $cgi = CGI->new;

        my $lang = $c->param('language') || $c->cookie('KohaOpacLanguage') || 'fi-FI';
        $lang =~ s/[^a-zA-Z_-]//g;    # sanitize against path traversal
        $lang ||= 'fi-FI';

        my $memory_cache = Koha::Cache::Memory::Lite->get_instance();
        my $cache_key    = "getlanguage";
        $memory_cache->set_in_cache( $cache_key, $lang );
        $cgi->param('language', $lang);
        $scc_obj->{'cgi'} = $cgi;

        my $ipallowed = $scc_obj->retrieve_data('ipallowed');
        if ( $ipallowed && !C4::Auth::in_iprange($ipallowed) ) {
            $c->app->log->warn('User (' . $ENV{'REMOTE_ADDR'} . ') not allowed to access SCC');
            return $c->redirect_to('/cgi-bin/koha/opac-main.pl');
        }

        my ( $template, $loggedinuser, $cookie ) = C4::Auth::get_template_and_user(
            {
                template_name   => $scc_obj->mbf_path('opac/scc/scc.tt'),
                query           => $scc_obj->{'cgi'},
                type            => "opac",
                authnotrequired => 1,
            }
        );
        $template->param(
            PLUGIN_PATH => $scc_obj->get_plugin_http_path(),
            PLUGIN_DIR  => $scc_obj->bundle_path(),
            LANG        => $lang,
        );

        local *STDOUT;
        my $stdout;
        open STDOUT, '>', \$stdout;
        $scc_obj->output_html($template->output);
        close STDOUT;

        unless ($stdout =~ m!^\s*HTTP/(\d\.\d)\s+(\d\d\d)\s*(.+)?$!) {
            # https://docs.mojolicious.org/Mojo/Message/Response.txt
            $stdout = "HTTP/1.1 200 OK\n$stdout";
        }
        $c->res->parse($stdout);
        $c->cookie(CGISESSID => '', { path => "/" });
        $c->cookie(KohaOpacLanguage => $lang, { path => "/" });
        return $c->render( text => $c->res->body );
    }
    catch {
        $c->unhandled_exception($_);
    };
}

sub kioskboard {
    my $c = shift->openapi->valid_input or return;

    my $scc_obj = Koha::Plugin::Fi::Hypernova::SelfCheckoutCheckin->new;
    my $file = $scc_obj->mbf_path( 'opac/js/' . $Koha::Plugin::Fi::Hypernova::SelfCheckoutCheckin::KIOSKBOARD_FILE );

    return $c->render( status => 404, text => 'File not found' ) unless -f $file;

    my $content = Mojo::File->new($file)->slurp;
    $c->res->headers->cache_control('public, max-age=86400');
    $c->res->headers->content_type('application/javascript; charset=UTF-8');
    return $c->render( text => $content );
}

1;
