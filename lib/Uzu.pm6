use v6;

use IO::Notification::Recursive;
use File::Find;
use YAMLish;
use Terminal::ANSIColor;

unit module Uzu:ver<0.1.5>:auth<gitlab:samcns>;

#
# HTML Rendering
#

sub templates(
    List :$exts!,
    Str :$dir! --> Seq
) {
    return $dir.IO.dir(:test(/:i ^ \w+ '.' |$exts $/));
}

sub build-context(
    Str :$i18n_dir,
    Str :$language --> Hash
) {
    my Str $i18n_file = "$i18n_dir/$language.yml";
    if $i18n_file.IO.f {
        try {
            CATCH {
                default {
                    note "Invalid i18n yaml file [$i18n_file]";
                }
            }
            return %( %(language => $language), load-yaml slurp($i18n_file) );
        }
    }
    return %( error => "i18n yaml file [$i18n_file] could not be loaded" );
}

sub write-generated-files(
    Hash $content,
    Str :$build_dir --> Bool
) {
    # IO write to disk
    for $content.keys -> $path {
        spurt "$build_dir/$path.html", $content{$path}
    };
}

sub html-file-name(
    Str :$page_name,
    Str :$default_language,
    Str :$language --> Str
) {
    return "{$page_name}-{$language}" if $language !~~ $default_language;
    return $page_name;
}

sub process-livereload(
    Str :$content,
    Bool :$no_livereload --> Str
) {
    unless $no_livereload {
        # Add livejs if live-reload enabled (default)
        my Str $livejs = '<script src="uzu/js/live.js"></script>';
        return $content.subst('</body>', "{$livejs}\n</body>");
    }
    return $content;
}

sub prepare-html-output(
    Hash  $context,
    List  :$template_dirs,
    Str   :$default_language,
    Str   :$language, 
    Hash  :$pages,
    Bool  :$no_livereload --> Hash
) {
    use Template6;
    my $t6 = Template6.new;
    $template_dirs.map( -> $dir { $t6.add-path: $dir } );

    return $pages.keys.map( -> $page_name {

        # Render the page content
        my Str $page_content = $t6.process($page_name, |$context);

        # Append page content to $context
        my %layout_context = %( |$context, %( content => $page_content ) );
        my Str $layout_content = $t6.process('layout', |%layout_context );

        # Default file_name without prefix
        my Str $file_name = 
            html-file-name(
                page_name        => $page_name,
                default_language => $default_language, 
                language         => $language);

        # Return processed HTML
        my Str $processed_html =
            process-livereload(
                content          => $layout_content,
                no_livereload    => $no_livereload);

        %( $file_name => $processed_html );

    }).Hash;
};

our sub render(
    Map      $config,
    Bool     :$no_livereload = False,
    Supplier :$log = Supplier.new --> Bool
) {
    my Str $themes_dir = $config<themes_dir>;
    my Str $layout_dir = $config<layout_dir>;
    my Str $assets_dir = $config<assets_dir>;
    my Str $build_dir  = $config<build_dir>;

    # All available pages
    my List $exts = $config<extensions>;
    my IO::Path @page_templates =
    templates(
        exts => $exts,
        dir => $config<pages_dir>);

    my Str %pages = (@page_templates
                     ==> map( -> $page { 
                         my Str $page_name = ( split '.', IO::Path.new($page).basename )[0]; 
                         %( $page_name => slurp $page, :r );
                     }));

    # Clear out build
    $log.emit: "Clear old files";
    qqx{ rm -rf $build_dir };

    # Create build dir
    if !$build_dir.IO.d { 
        $log.emit: "Create build directory";
        mkdir $build_dir;
    }

    # Copy assets
    $log.emit: "Copy asset files";
    qqx{ cp -rf $assets_dir/. $build_dir/ };

    # Setup compile specific variables
    my Str  $default_language = $config<language>[0];
    my List $template_dirs    = $config<template_dirs>;
    my List $languages        = $config<language>;

    # One per language
    await $languages.map( -> $language { 
        start {
            $log.emit: "Compile templates [$language]";
            # Build %context hash
            build-context(
                i18n_dir         => $config<i18n_dir>,
                language         => $language)
                # Render HTML
            ==> prepare-html-output(
                template_dirs    => $template_dirs, 
                default_language => $default_language,
                language         => $language,
                pages            => %pages,
                no_livereload    => $no_livereload)
                # Write HTML to build/
            ==> write-generated-files(
                build_dir        => $build_dir);
        }
    });

    $log.emit: "Compile complete";
}

our sub build(
    Map  $config,
    Bool :$no_livereload = False --> Bool
) {
    # Create a new logger
    my $log = Supplier.new;

    # Start logger
    logger $log;

    render $config, no_livereload => $no_livereload, log => $log;
}

#
# Web Server
#

our sub serve(
    Str :$config_file --> Proc::Async
) {
    my Proc::Async $p;
    my @args = ("--config={$config_file}", "webserver");

    # Use the library path if running from test
    if "bin/uzu".IO.f {
        my IO::Path $lib_path = $?FILE.IO.parent;
        $p .= new: "perl6", "-I{$lib_path}", "bin/uzu", @args;
    } else {
        # Use uzu from PATH otherwise
        $p .= new: "uzu", @args;
    }

    my Promise $server-up .= new;
    $p.stdout.tap: -> $v { $*OUT.print: $v; }
    $p.stderr.tap: -> $v { 
        # Wait until server started
        if $server-up.status ~~ Planned {
            $server-up.keep if $v.contains('Started HTTP server');
        }
        # Filter out livereload requests
        if !$v.contains('GET /live') { $*ERR.print: $v }
    }

    # Start web server
    $p.start;

    # Wait for server to come online
    await $server-up;
    return $p;
}

our sub web-server(
    Map $config --> Bool
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
        my Str $livejs = q:to/END/; 
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
        #'

        header("Content-Type", "application/javascript");
        return [ $livejs ];
    }

    get /(.+)/ => sub ($file) {
        # Trying to access files outside of build path
        return "Invalid path" if $file.match('..');

        my IO::Path $path;
        if $file ~~ '/' {
            # Serve index.html on /
            $path = IO::Path.new("{$build_dir}/index.html");
        } else {
            # Strip query string for now
            $path = IO::Path.new("{$build_dir}{$file.split('?')[0]}");
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
    baile($config<port>||3000);
}

#
# Event triggers
#

sub find-dirs (
    Str:D $p --> Slip
) {
    state $seen = {};
    return slip ($p.IO, slip find :dir($p), :type<dir>)
           ==> grep({ !$seen{$_}++ });
}

sub watch-it(
    Str $p --> Tap
) {
    whenever IO::Notification.watch-path($p) -> $e {
        if $e.event ~~ FileRenamed && $e.path.IO ~~ :d {
            watch-it($_) for find-dirs($e.path);
        }
        emit $e;
    }
}

sub watch-dirs(
    List $dirs --> Supply
) {
    run("stty", "sane");
    supply {
        watch-it(~$_) for $dirs.map: { find-dirs($_) };
    }
}

sub keybinding(
    --> Supply
) {
    use Term::termios;
    my $fd = $*IN.native-descriptor();
    my $saved_termios = Term::termios.new(fd => $fd ).getattr;
    my $termios = Term::termios.new(fd => $fd ).getattr;
    $termios.makeraw;
    $termios.setattr(:DRAIN);
    supply {
        loop {
            my $c = $*IN.getc;
            emit 'rebuild' if $c.ord == 114;
        }
        $saved_termios.setattr(:DRAIN);
    };
}

sub logger(
    Supplier $log --> Promise
) {
    start {
        react {
            whenever $log.Supply { say $_ }
        }
    }
}

our sub watch(
    Map  $config,
    Bool :$no_livereload = False --> Tap
) {
    # Create a new logger
    my Supplier $log = Supplier.new;

    # Start logger
    logger($log);
    
    sub trigger-build() {
      render($config, no_livereload => $no_livereload, log => $log);
    }

    sub reload-browser() {
      unless $no_livereload {
        use HTTP::Tinyish;
        HTTP::Tinyish.new().get("http://{$config<host>}:{$config<port>}/reload");
      }
    }

    sub build-and-reload() {
      trigger-build();
      reload-browser();
    }

    # Initialize build
    $log.emit: "Initial build";
    trigger-build();
    
    # Track time delta between FileChange events. 
    # Some editors trigger more than one event per
    # edit. 
    my List $exts = $config<extensions>;
    my List $dirs = $config<template_dirs>.grep(*.IO.e).List;
    $dirs.map: -> $dir {
      $log.emit: "Starting watch on {$dir.subst("{$*CWD}/", '')}";
    }

    # Start server
    my Proc::Async $app = serve config_file => $config<path>;

    # Keep track of the last render timestamp
    my Instant $last_run = now;

    # Watch directories for modifications
    start {
        react {
            whenever watch-dirs($dirs) -> $e {
                # Make sure the file change is a 
                # known extension; don't re-render too fast
                if so $e.path.IO.extension ∈ $exts and (now - $last_run) > 2 {
                    $log.emit: 
                        colored "Change detected [{$e.path()}]", "bold green on_blue";
                    build-and-reload();
                    $last_run = now;
                }
            }
        }
    }

    # Listen for keyboard input
    $log.emit: 
        colored "Press `r enter` to [rebuild]", "bold green on_blue";
    keybinding().tap( -> $e { 
        if $e ~~ 'rebuild' {
            $log.emit:
                colored "Rebuild triggered", "bold green on_blue";
            build-and-reload();
        }
    });
}

#
# Config
#

sub valid-project-folder-structure(
    @template_dirs --> Bool()
) {
    @template_dirs
    ==> grep({ !$_.IO.e })
    ==> &{
        unless elems $_ > 0 {
            note "Project directory missing: \n * {join "\n * ", $_}";
            exit 1;
        }
    }();
}

sub parse-config(
    Str :$config_file --> Map()
) {
    return load-yaml(slurp($config_file)).Map when $config_file.IO.f;
    note "Config file [$config_file] not found. Please run uzu init to generate.";
    exit 1;
}

sub uzu-config(
    Str :$config_file = 'config.yml' --> Map
) is export {

    # Parse yaml config
    my Map $config          = parse-config(config_file => $config_file);
    my List $language       = [$config<language>];

    # Network
    my Str  $host           = $config<host>||'0.0.0.0';
    my Int  $port           = $config<port>||3000;

    # Paths
    my Str  $project_root   = "{$config<project_root>||$*CWD}".subst('~', $*HOME);
    my Str  $build_dir      = "{$project_root}/build";
    my Str  $themes_dir     = "{$project_root}/themes";
    my Str  $assets_dir     = "{$project_root}/themes/{$config<defaults><theme>||'default'}/assets";
    my Str  $layout_dir     = "{$project_root}/themes/{$config<defaults><theme>||'default'}/layout";
    my Str  $pages_dir      = "{$project_root}/pages";
    my Str  $partials_dir   = "{$project_root}/partials";
    my Str  $i18n_dir       = "{$project_root}/i18n";
    my List $template_dirs  = [$layout_dir, $pages_dir, $partials_dir, $i18n_dir];
    my List $extensions     = ['tt', 'html', 'yml'];

    # Confirm all template directories exist
    # before continuing.
    valid-project-folder-structure($template_dirs);

    my Map $config_plus = (
        :host($host),
        :port($port),
        :language($language),
        :project_root($project_root),
        :path($config_file),
        :build_dir($build_dir),
        :themes_dir($themes_dir),
        :assets_dir($assets_dir),
        :layout_dir($layout_dir),
        :pages_dir($pages_dir),
        :partials_dir($partials_dir),
        :i18n_dir($i18n_dir),
        :template_dirs($template_dirs),
        :extensions($extensions)
    ).Map;

    # We want to stop everything if the project root ~~ $*HOME or
    # the build dir ~~ project root. This would have bad side-effects
    if $build_dir.IO ~~ $*HOME.IO|$project_root.IO {
        note "Build directory [{$build_dir}] cannot be {$*HOME} or project root [{$project_root}].";
        exit(1);
    }

    # Merged config as output
    return Map.new($config.pairs, $config_plus.pairs);
}

#
# Init
#

our sub init(
    Str  :$config_file  = 'config.yml', 
    Str  :$project_name = 'New Uzu Project',
    Str  :$url          = 'http://example.com',
    Str  :$language     = 'en',
    Str  :$theme        = 'default' --> Bool
) {
    my Map $config = (
        :name($project_name),
        :url($url),
        :language($language),
        :theme($theme)
    ).Map;

    my Str $theme_dir      = "themes/$theme";
    my List $template_dirs = (
        "i18n", 
        "pages",
        "partials",
        "$theme_dir/layout",
        "$theme_dir/assets"
    );

    # Create project directories
    $template_dirs
    ==> map( -> $dir { mkdir $dir });

    # Write config file
    my Str $config_yaml = S:g /'...'// given save-yaml($config);
    my Str $config_out  = S:g /'~'/$*HOME/ given $config_file;
    return spurt $config_out, $config_yaml;
}

# License
# 
# This module is licensed under the same license as Perl6 itself. 
# Artistic License 2.0.
#
# Copyright 2017 Sam Morrison.

# vim: ft=perl6
