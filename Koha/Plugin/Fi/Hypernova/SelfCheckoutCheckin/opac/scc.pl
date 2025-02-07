#!/usr/bin/perl
#
# Copyright 2023 Hypernova Oy
#
# This file is not part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use CGI qw ( -utf8 );
use Cwd            qw( abs_path );
use File::Basename qw( dirname );

use C4::Context;
use C4::Output qw( output_html_with_http_headers );
use C4::Auth qw( get_template_and_user );

use Koha::Plugin::Fi::Hypernova::SelfCheckoutCheckin;

my $cgi = new CGI;

my $pluginDir = dirname(abs_path($0));

my $template_name = $pluginDir . '/scc/scc.tt';

my $lang = C4::Languages::getlanguage($cgi) || 'en';
my @lang_split = split /_|-/, $lang;

if (C4::Context->preference('AutoSelfCheckAllowed'))
{
    my $AutoSelfCheckID = C4::Context->preference('AutoSelfCheckID');
    my $AutoSelfCheckPass = C4::Context->preference('AutoSelfCheckPass');
    $cgi->param(-name=>'userid',-values=>[$AutoSelfCheckID]);
    $cgi->param(-name=>'password',-values=>[$AutoSelfCheckPass]);
    $cgi->param(-name=>'koha_login_context',-values=>['sco']);
}
$cgi->param(-name=>'sco_user_login',-values=>[1]);

my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name   => $template_name,
        query           => $cgi,
        type            => "opac",
        flagsrequired   => { self_check => "self_checkout_module" },
        authnotrequired => 1,
        is_plugin       => 1,
    }
);

$template->param(
    lang_dialect => $lang,
    lang_all     => $lang_split[0],
    plugin_dir   => Koha::Plugin::Fi::Hypernova::SelfCheckoutCheckin->new->bundle_path
);

output_html_with_http_headers $cgi, $cookie, $template->output;
