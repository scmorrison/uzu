unit module Uzu::HTTP;

our sub web-server(
    %config
    --> Array
) {
    use HTTP::Server::Tiny:ver<0.0.2>;


    my Promise @servers;

    for %config<themes>.List -> $theme_config {

        push @servers, start {

            my $theme_name = $theme_config.key;
            my %theme      = $theme_config.value;
            my $build_dir  = %theme<build_dir>;
            my $port       = %theme<port>;
            my $ct_json    = 'Content-Type' => 'application/json';
            my $ct_text    = 'Content-Type' => 'text/plain';

            # Use for triggering reload staging when reload is triggered
            my $reload = Channel.new;

            HTTP::Server::Tiny.new(host => %config<host>, :$port).run(sub (%env) {
                
                given %env<PATH_INFO> {
                    # When accessed, sets $reload to True
                    # Routes
                    when  '/reload' {
                        $reload.send(True);
                        say "GET /reload [$theme_name]";
                        return 200, [$ct_json], ['{ "reload": "Staged" }'];
                    }

                    # If $reload is True, return a JSON doc
                    # instructing uzu/js/live.js to reload the
                    # browser.
                    when '/live' {
                        return 200, [$ct_json], ['{ "reload": "True" }'] if $reload.poll;
                        return 200, [$ct_json], ['{ "reload": "False" }'];
                    }

                    # Include live.js that starts polling /live
                    # for reload instructions
                    when '/uzu/js/live.js' {
                        say "GET /uzu/js/live.js [$theme_name]";
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

                        return 200, [$ct_json], [$livejs];
                    }

                    default {

                        my $file = $_;

                        # Trying to access files outside of build path
                        return 400, [$ct_text], ['Invalid path'] if $file.match('..');

                        # Handle HTML without file extension
                        my $index = 'index' ~ (%config<omit_html_ext> ?? '' !! '.html');

                        my IO::Path $path = do given $file {
                            when '/' {
                                $build_dir.IO.child($index)
                            }
                            when so * ~~ / '/' $ / {
                                $build_dir.IO.child($file.split('?')[0].IO.child($index))
                            }
                            default {
                                $build_dir.IO.child($file.split('?')[0])
                            }
                        }

                        given $path {
                        
                            when !*.IO.e {
                                # Invalid path
                                say "GET $file (not found) [$theme_name]";
                                return 400, [$ct_text], ['Invalid path'];
                            }

                            default {
                                # Return any valid paths
                                my Str $type = detect-content-type($path);

                                say "GET $file [$theme_name]";

                                # UTF-8 text
                                return 200, ['Content-Type' => $type ], [slurp($path)] unless $type ~~ / gz|image|ttf|woff|octet\-stream /;

                                # Binary
                                return 201, ['Content-Type' => $type ], [slurp($path, :bin)];
                            }
                        }    
                    }

                    say "uzu serves [http://localhost:{$port}] for theme [$theme_name]";
                }

            }); # /http server
        }
    }

    return @servers;
}

our sub wait-port(
    int $port,
    Str $host   = '0.0.0.0',
        :$sleep = 0.1,
    int :$times = 600
) is export {
    LOOP: for 1..$times {
        try {
            my $sock = IO::Socket::INET.new(:host($host), :port($port));
            $sock.close;

            CATCH { default { sleep $sleep; next LOOP } }
        }
        return True;
    }

    die "$host:$port doesn't open in {$sleep*$times} sec.";
}

our sub inet-request(
    Str $req,
    int $port,
    $host='0.0.0.0'
) is export {
    my $client = IO::Socket::INET.new(:host($host), :port($port));
    my $data   = '';
    try {
        $client.print($req);
        sleep .5;
        while my $d = $client.recv {
            $data ~= $d;
        }
        $client.close;
        CATCH { default {} }
    }
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
        ''       => 'text/html;charset=UTF-8',
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
