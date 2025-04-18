# Koha plugin - Self Checkout & Check-in combined

Provides access to both self checkout and check-in from a single screen.

Allows you to configure a Koha account that is used for self check-ins.

Allows you to restrict access to SCI by IP address.

## Examples

Self Checkout & Check-in main screen

![Self Checkout & Check-in main](assets/images/scc.png)

Self Checkout login

![Self Checkout login](assets/images/sco_main.png)

Self Check-in main screen

![Self Check-in main](assets/images/sci_main.png)

Video (in Finnish)

![Self Checkout & Check-in video](assets/images/scc.webm)


## Install

Download the latest _.kpz_ file from the _Project / Releases_ page

## Configuration

1. Go to staff client /cgi-bin/koha/plugins/plugins-home.pl
2. Click Actions -> Configure

### System preferences

1. Enable `SelfCheckInModule`
2. Enable `AutoSelfCheckAllowed`, set `AutoSelfCheckID` and `AutoSelfCheckPass`

## Set up Apache2 routing

Modify file `/etc/apache2/sites-available/your_koha_instance.conf`

Add the following under OPAC's VirtualHost:

```
ScriptAlias /custom/cgi-bin/koha/scc/scc.pl "/var/lib/koha/your_koha_instance/plugins/Koha/Plugin/Fi/Hypernova/SelfCheckoutCheckin/opac/scc.pl"
```

Restart Apache2:

`systemctl restart apache2`

## Usage

After installation and configuration, navigate to

`https://yourkoha/custom/cgi-bin/koha/scc/scc.pl`

## Possibly useful system preferences

### SelfCheckInUserJS: Make SCI finish button navigate to start screen

```
$("#sci_finish_button").on('click', function(e) {
  window.location.href = SCC_SCRIPT_LOCATION;
  e.preventDefault();
});
```

### SelfCheckInUserJS: Custom timeouts

```
function timerIncrement() {
  if ( $("#sci_finish_button").is(":visible") || $("#sci_refresh_button").is(":visible") ) {
    // checkin status screen timeout
    idleTime = idleTime + 1;
    idleTimeout = 20;
    if (idleTime >= idleTimeout ) {
      location.href = SCC_SCRIPT_LOCATION;
      idleTime = 0;
    }
  }
  if ( $("#barcode_input").is(":visible") ) {
    // checkin barcode read screen timeout
    idleTime = idleTime + 1;
    idleTimeout = 60;
    if (idleTime >= idleTimeout ) {
      location.href = SCC_SCRIPT_LOCATION;
      idleTime = 0;
    }
  }
}
```

### SCOUserJS: Custom timeouts

```
$(document).ready(function () {
  //Increment the idle time counter every second
  var idleInterval = setInterval(timerIncrement, 1000);
  var idleTime = 0;
  //Zero the idle timer on mouse movement.
  $(this).mousemove(function (e) {
    idleTime = 0;
  });
  $(this).keypress(function (e) {
     idleTime = 0;
   });

  function timerIncrement() {
  if ( $("#patronpw").is(":visible") && $("div.sco_entry").is(":visible") ) {
    idleTime = idleTime + 1;
    idleTimeout = 60;
    if (idleTime >= idleTimeout ) {
      location.href = SCC_SCRIPT_LOCATION;
      idleTime = 0;
    }
  }
}
});
```

### SelfCheckInUserJS & SCOUserJS: Translate return button

```
if (new RegExp("fi-FI").exec($("html").attr("lang"))) {
  SCC_HOME_BUTTON_TEXT = "PAINA TÄSTÄ PALATAKSESI TAKAISIN";
} else {
  SCC_HOME_BUTTON_TEXT = "GO BACK";
}
```

### SelfCheckInUserJS: Rename check-in statuses

```
$.each($("#sci_bcheckins_table").find('td'), function() { if (new RegExp('Kirja ei ole tällä hetkellä lainassa').exec($(this).html())) { $(this).html("Palautettu"); } });
```
