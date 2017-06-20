use v6;

unit module Uzu::HTTP;

our sub serve(
    IO::Path :$config_file
    --> Proc::Async
) {
    my @args = "--config={$config_file}", "webserver";

    # Use the library path if running from test
    my $p = do given "bin/uzu".IO {
        when *.f {
            Proc::Async.new: $*EXECUTABLE, "-I{$?FILE.IO.parent.parent}",
            $?FILE.IO.parent.parent.parent.child('bin').child('uzu'), @args;
        }
        default {
            Proc::Async.new: "uzu", @args;
        }
    }

    my Promise $server_up .= new;
    $p.stdout.tap: -> $v { $*OUT.print: $v; }
    $p.stderr.tap: -> $v {
        # Wait until server started
        if $server_up.status ~~ Planned && $v.contains('Started HTTP server') {
            $server_up.keep; 
        }
        # Filter out livereload requests
        if !$v.contains('GET /live') { $*ERR.print: $v }
    }

    # Start web server
    $p.start;

    # Wait for server to come online
    await $server_up;
    return $p;
}

#
# Config
#
our sub web-server(
    Map $config
    --> Bool
) {
    use Bailador;
    use Bailador::App;
    my Bailador::ContentTypes $content-types = Bailador::ContentTypes.new;
    my $build_dir = $config<build_dir>;

    # Use for triggering reload staging when reload is triggered
    my $channel = Channel.new;

    # When accessed, sets $reload to True
    get '/reload' => sub () {
        $channel.send(True);
        header("Content-Type", "application/json");
        return [ '{ "reload": "Staged" }' ];
    }

    # If $reload is True, return a JSON doc
    # instructing uzu/js/live.js to reload the
    # browser.
    get '/live' => sub () {
        header("Content-Type", "application/json");
        return ['{ "reload": "True"  }'] if $channel.poll;
        return ['{ "reload": "False" }'];
    }

    # Include live.js that starts polling /live
    # for reload instructions
    get '/uzu/js/live.js' => sub () {
        my Str $livejs = q:to|END|; 
        // Uzu live-reload
        function live() {
            var xhttp = new XMLHttpRequest();
            xhttp.onreadystatechange = function() {
                if (xhttp.readyState == 4 && xhttp.status == 200) {
                    var resp = JSON.parse(xhttp.responseText);
                    if (resp.reload == 'True') {
                        document.location.reload();
                    };
                };
            };
            xhttp.open("GET", "live", true);
            xhttp.send();
            setTimeout(live, 1000);
        }
        setTimeout(live, 1000);
        END

        header("Content-Type", "application/javascript");
        return [ $livejs ];
    }

    get /(.+)/ => sub ($file) {
        # Trying to access files outside of build path
        return "Invalid path" if $file.match('..');

        my IO::Path $path;
        if $file ~~ '/' {
            # Serve index.html on /
            $path = $build_dir.IO.child('index.html');
        } else {
            # Strip query string for now
            $path = $build_dir.IO.child($file.split('?')[0]);
        }

        # Invalid path
        return "Invalid path: file does not exists" if !$path.IO.e;

        # Return any valid paths
        my Str $type = $content-types.detect-type($path);
        header("Content-Type", $type);
        # UTF-8 text
        return slurp $path unless $type ~~ / image|ttf|woff|octet\-stream /;
        # Binary
        return slurp $path, :bin;
    }    

    # Start bailador
    set( 'port', $config<port>||3000 );
    baile;
}
