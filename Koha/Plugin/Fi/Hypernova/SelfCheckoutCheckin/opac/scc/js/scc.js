var SCC_SCRIPT_LOCATION = "/api/v1/contrib/hypernova/scc";

$(document).ready(function () {
    if (new RegExp('(sco/sco-main\.pl)$')
        .exec(window.location.pathname) && new RegExp('^([\?&]op=logout)$').exec(window.location.search)) {
        $("body#sco_main").html("");
        window.location.href = SCC_SCRIPT_LOCATION;
    }
    if (new RegExp('(sci/sci-main\.pl)$')
        .exec(window.location.pathname) && $("form#auth").length > 0) {
        $("body#opac-login-page").html("");
        window.location.href = SCC_SCRIPT_LOCATION;
    }

    if (new RegExp('(sco/sco-main\.pl)$').exec(window.location.pathname) || new RegExp('(sci/sci-main\.pl)$').exec(window.location.pathname)) {
        if (typeof SCC_HOME_BUTTON_TEXT === "undefined") {
            SCC_HOME_BUTTON_TEXT = '<<';
        }

        $(".main div.container-fluid").first().before(

            "<div class=\"container-fluid\">" +
            "<div class=\"row\">" +
            "<style type=\"text/css\">" +
            "h2.scc-exit-button {" +
            "display:table;" +
            "border:solid 1px #000;" +
            "text-align:center;" +
            "vertical-align:middle;" +
            "height:20vh;" +
            "width:100%;" +
            "background:#80b3ff;" +
            "color:#fff;" +
            "text-shadow:1px 1px 0 #444;" +
            "margin-bottom:10vh;" +
            "}" +
            "h2.scc-exit-button:active {" +
            "background:#4DA6FF;" +
            "color:#eee;" +
            "}" +
            "h2.scc-exit-button a {" +
            "display:table-cell;" +
            "vertical-align:middle;" +
            "width:100%;" +
            "height:100%;" +
            "text-decoration:none;" +
            "color:#fff;" +
            "}" +
            ".lds-dual-ring {" +
            "display:none;" +
            "width:80px;" +
            "height:80px;" +
            "}" +
            ".lds-dual-ring:after {" +
            "content:\" \";" +
            "display:block;" +
            "width:64px;" +
            "height:64px;" +
            "margin:8px;" +
            "border-radius:50%;" +
            "border:6px solid #fff;" +
            "border-color:#fff transparent #fff transparent;" +
            "animation:lds-dual-ring 1.2s linear infinite;" +
            "}" +
            "@keyframes lds-dual-ring {" +
            "0% {" +
            "transform:rotate(0deg);" +
            "}" +
            "100% {" +
            "transform:rotate(360deg);" +
            "}" +
            "}" +
            "</style>" +
            "<h2 class=\"scc-exit-button\"><a id=\"scc-exit-button-a\" href=\"/cgi-bin/koha/sco/sco-main.pl?op=logout\">" + SCC_HOME_BUTTON_TEXT + "</a><div class=\"lds-dual-ring\"></div></h2>" +
            "</div>" +
            "</div>"
        );
        $("body").on("click", "a#scc-exit-button-a", function () {
            $(this).css("display", "none");
            $(this).siblings("div.lds-dual-ring").css("display", "inline-block");
        });
    }
});