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

our $VERSION = "23.05.01.1";

our $metadata = {
    name            => 'Self Checkout & Check-in without login',
    author          => 'Lari Taskula',
    date_authored   => '2023-08-04',
    date_updated    => "2023-08-04",
    minimum_version => '23.05.01.000',
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

    my $opac_js = "<script>\n";
    $opac_js = $opac_js . 'var SCC_SCRIPT_LOCATION = "'. ($self->retrieve_data('scc_location') ? $self->retrieve_data('scc_location') : '/custom/cgi-bin/koha/scc/scc.pl') ."\";\n";
    $opac_js = $opac_js . q%
            $(document).ready(function(){
                if (new RegExp('(sco/sco-main.pl)$')
                      .exec(window.location.pathname) && new RegExp('^([\?&]op=logout)$').exec(window.location.search)) {
                    $("body#sco_main").html("");
                    window.location.href = SCC_SCRIPT_LOCATION;
                }
                if (new RegExp('(sci/sci-main.pl)$')
                      .exec(window.location.pathname) && $("form#auth").length > 0) {
                   $("body#opac-login-page").html("");
                   window.location.href = SCC_SCRIPT_LOCATION;
                }

                if (new RegExp('(sco/sco-main.pl)$').exec(window.location.pathname) || new RegExp('(sci/sci-main.pl)$').exec(window.location.pathname)) {
                    if (typeof SCC_HOME_BUTTON_TEXT === "undefined") {
                        SCC_HOME_BUTTON_TEXT = '<<';
                    }

                    $("div#wrapper div.main div.container-fluid").first().before(
    %;
    $opac_js = $opac_js . <<'END_JS';
    "<div class=\"container-fluid\">"+
                        "<div class=\"row\">"+
                        "<style type=\"text/css\">"+
                        "h2.scc-exit-button {"+
                          "display:table;"+
                          "border:solid 1px #000;"+
                          "text-align:center;"+
                          "vertical-align:middle;"+
                          "height:20vh;"+
                          "width:100%;"+
                          "background:#80b3ff;"+
                          "color:#fff;"+
                          "text-shadow:1px 1px 0 #444;"+
                          "margin-bottom:10vh;"+
                        "}"+
                        "h2.scc-exit-button:active {"+
                          "background:#4DA6FF;"+
                          "color:#eee;"+
                        "}"+
                        "h2.scc-exit-button a {"+
                          "display:table-cell;"+
                          "vertical-align:middle;"+
                          "width:100%;"+
                          "height:100%;"+
                          "text-decoration:none;"+
                          "color:#fff;"+
                        "}"+
                        ".lds-dual-ring {"+
                          "display:none;"+
                          "width:80px;"+
                          "height:80px;"+
                        "}"+
                        ".lds-dual-ring:after {"+
                          "content:\" \";"+
                          "display:block;"+
                          "width:64px;"+
                          "height:64px;"+
                          "margin:8px;"+
                          "border-radius:50%;"+
                          "border:6px solid #fff;"+
                          "border-color:#fff transparent #fff transparent;"+
                          "animation:lds-dual-ring 1.2s linear infinite;"+
                        "}"+
                        "@keyframes lds-dual-ring {"+
                          "0% {"+
                            "transform:rotate(0deg);"+
                          "}"+
                          "100% {"+
                            "transform:rotate(360deg);"+
                          "}"+
                        "}"+
                        "</style>"+
                        "<h2 class=\"scc-exit-button\"><a id=\"scc-exit-button-a\" href=\""+SCC_SCRIPT_LOCATION+"\">"+SCC_HOME_BUTTON_TEXT+"</a><div class=\"lds-dual-ring\"></div></h2>"+
                        "</div>"+
                        "</div>"
END_JS
    $opac_js = $opac_js . q%
                        
                    );
                    $("body").on("click", "a#scc-exit-button-a", function() {
                      $(this).css("display", "none");
                      $(this).siblings("div.lds-dual-ring").css("display", "inline-block");
                    });
                }
            });
         </script>
     %;
     return $opac_js;
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
            scc_location => $self->retrieve_data('scc_location'),
            scc_sci_username => $self->retrieve_data('scc_sci_username'),
            scc_sci_password => $self->retrieve_data('scc_sci_password'),
        );

        $self->output_html( $template->output() );
    }
    else {
        $self->store_data(
            {
                scc_location => $cgi->param('scc_location'),
                scc_sci_username => $cgi->param('scc_sci_username'),
                scc_sci_password => $cgi->param('scc_sci_password'),
                ipallowed => $cgi->param('ipallowed'),
            }
        );
        $self->go_home();
    }
}

sub uninstall {}

1;
