use v6.c;

unit module Uzu::HTTP;

our sub serve(
    IO::Path :$config_file
    --> Proc::Async
) {
    my @args = "--config={$config_file}", "webserver";

    # Use the library path if running from test
    my $p = "bin/uzu".IO.f
            ?? Proc::Async.new: $*EXECUTABLE, "-I{$?FILE.IO.parent.parent}",
               $?FILE.IO.parent.parent.parent.child('bin').child('uzu'), @args
            !! Proc::Async.new: "uzu", @args;

    my Promise $server_up .= new;
    $p.stdout.tap: -> $v {
        # Wait until server started
        $server_up.keep when $server_up.status ~~ Planned && $v ~~ / 'uzu serves' /;
        $*OUT.print: $v; 
    }
    $p.stderr.tap: -> $v { $*ERR.print: $v }

    # Start web server
    $p.start;

    # Wait for server to come online
    await $server_up;
    return $p;
}

our sub web-server(
    Map $config
#    --> Bool
) {
    use HTTP::Server::Async;
    use HTTP::Server::Router;

    my HTTP::Server::Async $server .=new: port => $config<port>||3000;
    serve $server;

    my $build_dir = $config<build_dir>;

    # Use for triggering reload staging when reload is triggered
    my $channel = Channel.new;

    # When accessed, sets $reload to True
    # Routes
    route '/reload', -> $req, $res {
        $channel.send(True);
        say "GET /reload";
        $res.headers<Content-Type> = 'application/json';
        $res.close( '{ "reload": "Staged" }' );
    }

    # If $reload is True, return a JSON doc
    # instructing uzu/js/live.js to reload the
    # browser.
    route '/live', -> $req, $res {
        $res.headers<Content-Type> = 'application/json';
        $res.close( '{ "reload": "True" }' ) if $channel.poll;
        $res.close( '{ "reload": "False" }' );
    }

    # Include live.js that starts polling /live
    # for reload instructions
    route '/uzu/js/live.js', -> $req, $res {
        say "GET /uzu/js/live.js";
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
            xhttp.open("GET", "/live", true);
            xhttp.send();
            setTimeout(live, 1000);
        }
        setTimeout(live, 1000);
        END

        $res.headers<Content-Type> = 'application/javascript';
        $res.close( $livejs );
    }

    route / .+ /, -> $req, $res {

        my $file = $req.uri;

        # Trying to access files outside of build path
        $res.status = 404;
        $res.headers<Content-Type> = 'text/plain';
        $res.close("Invalid path") if $file.match('..');

        my IO::Path $path =
            $file ~~ '/'
            ?? $build_dir.IO.child('index.html')
            !! $build_dir.IO.child($file.split('?')[0]);

        given $path {
        
            when !*.IO.e {
                # Invalid path
                say "GET $file (not found)";
                $res.close("Invalid path: $path");
            }

            default {
                # Return any valid paths
                $res.status  = 200;
                my Str $type = detect-content-type($path);
                $res.headers<Content-Type> = $type;

                say "GET $file";

                # UTF-8 text
                $res.close( slurp $path ) unless $type ~~ / image|ttf|woff|octet\-stream /;

                # Binary
                $res.close( slurp $path, :bin );
            }
        }    
    }

    say 'uzu serves';
    $server.listen(True);
}

our sub wait-port(int $port, Str $host='0.0.0.0', :$sleep=0.1, int :$times=600) is export {
    LOOP: for 1..$times {
        try {
            my $sock = IO::Socket::INET.new(:host($host), :port($port));
            $sock.close;

            CATCH { default { sleep $sleep; next LOOP } }
        }
        return;
    }

    die "$host:$port doesn't open in {$sleep*$times} sec.";
}

our sub inet-request(Str $req, $port, $host='0.0.0.0') is export {
    my $client = IO::Socket::INET.new(:host($host), :port($port));
    my $data   = '';
    $client.print($req);
    sleep .5;
    while my $d = $client.recv {
        $data ~= $d;
    }
    CATCH { default { "CAUGHT {$_}".say; } }
    try { $client.close; CATCH { default { } } }
    return $data;
}

# From Bailador
sub detect-content-type(
    IO::Path $file
) returns Str {
    my Str %mapping = (
        appcache => 'text/cache-manifest',
        atom     => 'application/atom+xml',
        bin      => 'application/octet-stream',
        css      => 'text/css',
        gif      => 'image/gif',
        gz       => 'application/x-gzip',
        htm      => 'text/html',
        html     => 'text/html;charset=UTF-8',
        ico      => 'image/x-icon',
        jpeg     => 'image/jpeg',
        jpg      => 'image/jpeg',
        js       => 'application/javascript',
        json     => 'application/json;charset=UTF-8',
        mp3      => 'audio/mpeg',
        mp4      => 'video/mp4',
        ogg      => 'audio/ogg',
        ogv      => 'video/ogg',
        pdf      => 'application/pdf',
        png      => 'image/png',
        rss      => 'application/rss+xml',
        svg      => 'image/svg+xml',
        txt      => 'text/plain;charset=UTF-8',
        webm     => 'video/webm',
        woff     => 'application/font-woff',
        xml      => 'application/xml',
        zip      => 'application/zip',
        pm       => 'application/x-perl',
        pm6      => 'application/x-perl',
        pl       => 'application/x-perl',
        pl6      => 'application/x-perl',
        p6       => 'application/x-perl',
    );

    my $ext = $file.extension.lc;
    return %mapping{$ext} if %mapping{$ext}:exists;
    return 'application/octet-stream';
}
