[% META type = 'text' %]
/* http://www.dustindiaz.com/rock-solid-addevent/ */

function addEvent( obj, type, fn ) {
    if (obj.addEventListener) {
        obj.addEventListener( type, fn, false );
        EventCache.add(obj, type, fn);
    }
    else if (obj.attachEvent) {
        obj["e"+type+fn] = fn;
        obj[type+fn] = function() { obj["e"+type+fn]( window.event ); }
        obj.attachEvent( "on"+type, obj[type+fn] );
        EventCache.add(obj, type, fn);
    }
    else {
        obj["on"+type] = obj["e"+type+fn];
    }
}

var EventCache = function(){
    var listEvents = [];
    return {
        listEvents : listEvents,
        add : function(node, sEventName, fHandler){
            listEvents.push(arguments);
        },
        flush : function(){
            var i, item;
            for(i = listEvents.length - 1; i >= 0; i = i - 1){
                item = listEvents[i];
                if(item[0].removeEventListener){
                    item[0].removeEventListener(item[1], item[2], item[3]);
                };
                if(item[1].substring(0, 2) != "on"){
                    item[1] = "on" + item[1];
                };
                if(item[0].detachEvent){
                    item[0].detachEvent(item[1], item[2]);
                };
                item[0][item[1]] = null;
            };
        }
    };
}();

addEvent(window,'unload', EventCache.flush);


function stopEvent( e ) {
    if ( !e ) e = window.event;
    if ( e.preventDefault ) {
        e.preventDefault();
        e.stopPropagation();
    } else {
        e.returnValue   = false;
        e.cancelBubble = true;
    }
}

/* Hide/Display the advanced form */

if ( document.getElementById ) {


    var show_advanced = function() {
        document.getElementById( 'showform' ).style.display = 'none';
        document.getElementById( 'hideform' ).style.display = 'inline';
        document.getElementById( 'advflag').value = 1;


        var advanced_form = document.getElementById( 'advancedform' );

        if ( advanced_form.parentNode.nodeName != 'FORM' )
            document.getElementById('searchform').appendChild( advanced_form );

        advanced_form.style.display = 'block';

        return false;
    };

    var hide_advanced = function() {
        document.getElementById( 'showform' ).style.display = 'inline';
        document.getElementById( 'hideform' ).style.display = 'none';
        document.getElementById( 'advflag').value = 0;

        var advanced_form = document.getElementById( 'advancedform' );

        if ( advanced_form.parentNode.nodeName == 'FORM' )
            document.getElementById('hidingplace').appendChild( advanced_form );

        advanced_form.style.display = 'none';

        return false;
    };

    var load_event = function() {
        var advanced_form = document.getElementById( 'advancedform' );
        var simple_form   = document.getElementById( 'simpleform' );

        if ( advanced_form && simple_form ) {

            var adv_flag = document.getElementById( 'advflag');




            /* Add links */
            var show_button = document.createElement('span');
            var hide_button = document.createElement('span');
            show_button.id  = 'showform';
            hide_button.id  = 'hideform';
            show_button.style.display = 'none';
            hide_button.style.display = 'none';

            show_button.appendChild( document.createTextNode('advanced search'));
            hide_button.appendChild( document.createTextNode('basic search'));

            simple_form.appendChild( show_button );
            simple_form.appendChild( hide_button );


            /* Hide the advanced form, unless advanced is in use */
            if ( !adv_flag || adv_flag.value == 0 ) {
                hide_advanced();

            } else {
                show_advanced();
            }

            /* add events to links */
            addEvent(show_button, 'click', show_advanced );
            addEvent(hide_button, 'click', hide_advanced );

        }
    };

    addEvent(window, 'load', load_event );

}









