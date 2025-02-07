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

use Koha::DateUtils;
use Koha::Libraries;

use C4::Circulation;
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
            print $c->redirect_to('/cgi-bin/koha/sci/sci-main.pl');
            return;
        }

        $cgi->param(login_userid => $scc_obj->retrieve_data('scc_sci_username'));
        $cgi->param(login_password => $scc_obj->retrieve_data('scc_sci_password'));
        my ($status, $cookie, $sessionid) = C4::Auth::check_api_auth(
            $cgi,
            { self_check => "self_checkout_module" },
        );

        $c->cookie(CGISESSID => $sessionid, { path => "/" });
        $c->redirect_to('/cgi-bin/koha/sci/sci-main.pl');
    }
    catch {
        $c->unhandled_exception($_);
    };
}


1;
