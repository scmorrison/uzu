use HTTP::Server::Tiny:ver<0.0.2>;

unit module Uzu::HTTP;

our sub web-server(
    %config
    --> Array
) {
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
                                my %ct = detect-content-type($path);

                                say "GET $file [$theme_name]";

                                # HTML
                                if %ct<type> ~~ 'text/html;charset=UTF-8' {
                                    return 200, ['Content-Type' => %ct<type> ], [
                                        process-livereload(
                                            content       => slurp($path),
                                            no_livereload => %config<no_livereload>)];
                                }
                                # UTF8 text
                                return 200, ['Content-Type' => %ct<type> ], [slurp($path)] unless %ct<bin>;
                                # Binary
                                return 201, ['Content-Type' => %ct<type> ], [slurp($path, :bin)];
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

#| Inject livereload JS
our sub process-livereload(
    Str  :$content,
    Bool :$no_livereload
    --> Str
) {
    return '' when !$content.defined;
    unless $no_livereload {
        # Add livejs if live-reload enabled (default)
        my Str $livejs = '<script src="/uzu/js/live.js"></script>';
        if $content ~~ /'</body>'/ {
            return S/'</body>'/$livejs\n<\/body>/ given $content;
        } else {
            return $content ~ "\n$livejs";
        }
    }
    return $content;
}

# From Bailador
sub detect-content-type(
    IO::Path $file
) {
    my %mapping = (
        appcache => %{ bin => False, type => 'text/cache-manifest' },
        atom     => %{ bin => False, type => 'application/atom+xml' },
        bin      => %{ bin => True,  type => 'application/octet-stream' },
        css      => %{ bin => False, type => 'text/css' },
        eot      => %{ bin => True,  type => 'application/vnd.ms-fontobject' },
        gif      => %{ bin => True,  type => 'image/gif' },
        gz       => %{ bin => True,  type => 'application/x-gzip' },
        htm      => %{ bin => False, type => 'text/html' },
        html     => %{ bin => False, type => 'text/html;charset=UTF-8' },
        ''       => %{ bin => False, type => 'text/html;charset=UTF-8' },
        ico      => %{ bin => True,  type => 'image/x-icon' },
        jpeg     => %{ bin => True,  type => 'image/jpeg' },
        jpg      => %{ bin => True,  type => 'image/jpeg' },
        js       => %{ bin => False, type => 'application/javascript' },
        json     => %{ bin => False, type => 'application/json;charset=UTF-8' },
        mp3      => %{ bin => True,  type => 'audio/mpeg' },
        mp4      => %{ bin => True,  type => 'video/mp4' },
        ogg      => %{ bin => True,  type => 'audio/ogg' },
        ogv      => %{ bin => True,  type => 'video/ogg' },
        otf      => %{ bin => True,  type => 'application/x-font-opentype' },
        pdf      => %{ bin => True,  type => 'application/pdf' },
        png      => %{ bin => True,  type => 'image/png' },
        rss      => %{ bin => False, type => 'application/rss+xml' },
        sfnt     => %{ bin => True,  type => 'application/font-sfnt' },
        svg      => %{ bin => True,  type => 'image/svg+xml' },
        ttf      => %{ bin => True,  type => 'application/x-font-truetype' },
        txt      => %{ bin => False, type => 'text/plain;charset=UTF-8' },
        webm     => %{ bin => True,  type => 'video/webm' },
        woff     => %{ bin => True,  type => 'application/font-woff' },
        woff2    => %{ bin => True,  type => 'application/font-woff' },
        xml      => %{ bin => False, type => 'application/xml' },
        zip      => %{ bin => True,  type => 'application/zip' },
        pm       => %{ bin => False, type => 'application/x-perl' },
        pm6      => %{ bin => False, type => 'application/x-perl' },
        pl       => %{ bin => False, type => 'application/x-perl' },
        pl6      => %{ bin => False, type => 'application/x-perl' },
        p6       => %{ bin => False, type => 'application/x-perl' },
    );

    my $ext = $file.extension.lc;
    return %mapping{$ext} if %mapping{$ext}:exists;
    return %mapping<bin>;
}
