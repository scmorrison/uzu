use v6;

use IO::Notification::Recursive;
use File::Find;
use YAMLish;
use Terminal::ANSIColor;

unit module Uzu:ver<0.1.0>:auth<gitlab:samcns>;

# Utils
sub path-exists(Str :$path) returns Bool {
  return $path.IO ~~ :f|:d;
}

sub find-dirs (Str:D $p) returns Slip {
  state $seen = {};
  return slip ($p.IO, slip find :dir($p), :type<dir>).grep: { !$seen{$_}++ };
}

sub templates(Str :@exts, Str :$dir) returns Seq {
  return $dir.IO.dir(:test(/:i '.' @exts $/));
}

sub build-context(Str :$i18n_dir, Str :$language) returns Hash {
  my Str %context;
  %context<language> = $language;

  my Str $i18n_file = "$i18n_dir/$language.yml";
  if path-exists(path => $i18n_file) {
    try {
      CATCH {
        default {
          note "Invalid i18n yaml file [$i18n_file]";
        }
      }
      %context.append: load-yaml slurp($i18n_file);
    }
  }
  return %context;
}

sub write-generated-files(Hash $content, Str :$build_dir) {
  # IO write to disk
  my @p;
  for $content.keys -> $path {
    push @p, start {
      spurt "$build_dir/$path.html", $content{$path}
    }
  }
  await @p;
}

sub prepare-html-output(Hash  $context,
                        Str   :@template_dirs,
                        Str   :$default_language,
                        Str   :$language, 
                        Hash  :$pages,
                        Bool  :$no_livereload) returns Hash {
  use Template6;
  my $t6 = Template6.new;

  @template_dirs.map( -> $dir { $t6.add-path: $dir } );
  my %generated_pages = Hash;

  my @p;
  $pages.keys.map( -> $page_name {
    push @p, start {
      # Render the page content
      my Str $page_content = $t6.process($page_name, |$context);

      # Append page content to $context
      $context<content> = $page_content;

      my Str $layout_content = $t6.process('layout', |$context );

      unless $no_livereload {
        # Add livejs if live-reload enabled (default)
        my Str $livejs = '<script src="uzu/js/live.js"></script>';
        $layout_content = $layout_content.subst('</body>', "{$livejs}\n</body>");
      };

      # Default file_name without prefix
      my Str $file_name = $page_name;
      if $language !~~ $default_language {
        $file_name = "{$page_name}-{$language}";
      }

      # Capture generated HTML
      %generated_pages{$file_name} = $layout_content;
    }
  });

  await @p;
  return %generated_pages;
};

our sub build(Hash $config,
               Bool :$no_livereload = False) {
  # Set up logger
  $config ==> logger();
  $config ==> render(no_livereload => $no_livereload);
  exit;
}

our sub render(Hash $config,
           Bool :$no_livereload = False) {

  my Str $themes_dir = $config<themes_dir>;
  my Str $layout_dir = $config<layout_dir>;
  my Str $assets_dir = $config<assets_dir>;
  my Str $build_dir  = $config<build_dir>;

  # All available pages
  my Str %pages;
  my Str @exts = |$config<template_extensions>;
  my IO::Path @page_templates = templates(exts => @exts,
                                           dir => $config<pages_dir>);
  @page_templates.map( -> $page { 
    my Str $page_name = IO::Path.new($page).basename.Str.split('.')[0]; 
    %pages{$page_name} = slurp($page, :r);
  });

  # Clear out build
  $config<logger>.emit("Clear old files");
  run(«rm "-rf" "$build_dir"»);

  # Create build dir
  if !path-exists(path => $build_dir) { 
    $config<logger>.emit("Create build directory");
    mkdir $build_dir;
  }

  # Copy assets
  $config<logger>.emit("Copy asset files");
  run(«cp "-rf" "$assets_dir/." "$build_dir/"»);

  # Setup compile specific variables
  my Str $default_language = $config<language>[0];
  my Str @template_dirs = |$config<template_dirs>;

  # One per language
  my @p;
  $config<language>.map( -> $language { 
    push @p, start {
      $config<logger>.emit("Compile templates [$language]");
      # Build %context hash
      build-context(
        i18n_dir         => $config<i18n_dir>,
        language         => $language)
      # Render HTML
      ==> prepare-html-output(
        template_dirs    => @template_dirs, 
        default_language => $default_language,
        language         => $language,
        pages            => %pages,
        no_livereload    => $no_livereload)
      # Write HTML to build/
      ==> write-generated-files(
        build_dir        => $build_dir);
    }
  });

  # Wait for compiling
  await @p;
  $config<logger>.emit("Compile complete");
}

our sub serve(Str :$config_file) returns Proc::Async {
  my Proc::Async $p;
  my @args = ("--config={$config_file}", "webserver");

  # Use the library path if running from test
  if path-exists(path => "bin/uzu") {
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

our sub web-server(Hash $config) {
  use Bailador;
  use Bailador::App;
  my Bailador::ContentTypes $content-types = Bailador::ContentTypes.new;
  my $build_dir = $config<build_dir>;

  # Use for triggering reload staging when reload is triggered
  my Bool $reload = False;
  
  # When accessed, sets $reload to True
  get '/reload' => sub () {
    $reload = True;
    header("Content-Type", "application/json");
    return [ '{ "reload": "Staged" }' ];
  }

  # If $reload is True, return a JSON doc
  # instructing uzu/js/live.js to reload the
  # browser.
  get '/live' => sub () {
    my Str $response;
    if $reload {
      $reload = False;
      $response = '{ "reload": "True" }';
    } else {
      $response = '{ "reload": "False" }';
    }
    header("Content-Type", "application/json");
    return [ $response ];
  }

  # Include live.js that starts polling /live
  # for reload instructions
  get '/uzu/js/live.js' => sub () {
    my Str $livejs = q:to/EOS/; 
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
    EOS

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
    return slurp $path if !$type.grep: / image|ttf|woff|octet\-stream /;
    # Binary
    return slurp $path, :bin;
  }    

  # Start bailador
  baile($config<port>||3000);
}

# Watchers
sub watch-it(Str $p) returns Tap {
  whenever IO::Notification.watch-path($p) -> $e {
    if $e.event ~~ FileRenamed && $e.path.IO ~~ :d {
      watch-it($_) for find-dirs($e.path);
    }
    emit($e);
  }
}

sub watch-dirs(Str @dirs) returns Supply {
  run("stty", "sane");
  supply {
    watch-it(~$_) for |@dirs.map: { find-dirs($_) };
  }
}

sub keybinding() {
  use Term::termios;
  my $fd = $*IN.native-descriptor();
  # Save the previous attrs
  my $saved_termios := Term::termios.new(fd => $fd ).getattr;
  # Get the existing attrs in order to modify them
  my $termios := Term::termios.new(fd => $fd ).getattr;
  # Set the tty to raw mode
  $termios.makeraw;
  # Set the modified atributes, delayed until the buffer is emptied
  $termios.setattr(:DRAIN);
  # Loop on characters from STDIN
  supply {
    # Listen for keyboard input
    loop {
      my $c = $*IN.getc;
      # Respond to `r+enter`: Rebuild
      emit 'rebuild' if $c.ord == 114;
    }
    # Restore the saved, previous attributes before exit
    $saved_termios.setattr(:DRAIN);
  };
}

sub logger(Hash $config) {
  my $logger = Thread.start({
    react {
      whenever $config<logger>.Supply -> $e { 
        say $e;
      }
    }
  });
  return $logger;
}

our sub watch(Hash $config, Bool :$no_livereload = False) returns Tap {
  use HTTP::Tinyish;

  unless 'partials'.IO.e {
    note "No project files available";
    exit(1);
  }

  sub build() {
    $config  ==> render(no_livereload => $no_livereload);
  }

  sub reload-browser() {
    unless $no_livereload {
      HTTP::Tinyish.new().get("http://{$config<host>}:{$config<port>}/reload");
    }
  }

  sub build-and-reload() {
    build();
    reload-browser();
  }

  # Set up logger
  $config ==> logger();

  # Initialize build
  $config<logger>.emit("Initial build");
  build();
  
  # Track time delta between FileChange events. 
  # Some editors trigger more than one event per
  # edit. 
  my Instant $last;
  my Str @exts = |$config<template_extensions>;
  my Str @dirs = |$config<template_dirs>.grep: *.IO.e;
  @dirs.map: -> $dir {
    $config<logger>.emit("Starting watch on {$dir.subst("{$*CWD}/", '')}");
  }

  # Start server
  my Proc::Async $app = serve(config_file => $config<path>);

  # Spawn thread to watch directories for modifications
  my $thread_watch_dirs = Thread.start({
    react {
      whenever watch-dirs(@dirs) -> $e {
        # Make sure the file change is a known extension; don't re-render too fast
        if $e.path.grep: /'.' @exts $/ and (!$last.defined or now - $last > 4) {
          $last = now;
          $config<logger>.emit("Change detected [{$e.path()}].");
          build-and-reload();
        }
      }
    }
  });

  # Listen for keyboard input
  $config<logger>.emit(colored("Press `r enter` to [rebuild]", "bold green on_blue"));
  keybinding().tap( -> $e { 
    if $e ~~ 'rebuild' {
      $config<logger>.emit(colored("Rebuild triggered", "bold green on_blue"));
      build-and-reload();
    }
  });
}

# Config
sub parse-config(Str :$config_file) returns Hash {
  if path-exists(path => $config_file) {
    my %config = load-yaml slurp($config_file);
    # Make sure language is always a list
    if %config<language> ~~ Str {
      %config<language> = [%config<language>];
    }
    return %config;
  } else {
    return {error => "Config file [$config_file] not found. Please run uzu init to generate."};
  }
}

sub uzu-config(Str :$config_file = 'config.yml') returns Hash is export {

  # Parse yaml config
  my %config = parse-config(config_file => $config_file);
  # Set configuration
  %config<logger>               = Supplier.new;
  %config<host>                 = "{%config<host>||'0.0.0.0'}";
  %config<port>                 = %config<port>||3000;
  my $project_root              = %config<project_root>||$*CWD;
  %config<project_root>         = $project_root;
  %config<path>                 = $config_file;
  %config<build_dir>            = "{$project_root}/build";
  %config<themes_dir>           = "{$project_root}/themes";
  %config<assets_dir>           = "{$project_root}/themes/{%config<defaults><theme>||'default'}/assets";
  %config<layout_dir>           = "{$project_root}/themes/{%config<defaults><theme>||'default'}/layout";
  %config<pages_dir>            = "{$project_root}/pages";
  %config<partials_dir>         = "{$project_root}/partials";
  %config<i18n_dir>             = "{$project_root}/i18n";
  %config<template_dirs>        = [%config<layout_dir>, %config<partials_dir>, %config<pages_dir>, %config<i18n_dir>];
  %config<template_extensions>  = ['tt', 'html', 'yml'];

  %config.kv.map( -> $k, $v { 
    # Replace ~ with full home path if applicable:
    if %config{$k} ~~ Str {
      %config{$k} = $v.subst('~', $*HOME);
    }
  });

  # We want to stop everything if the project root ~~ $*HOME or
  # the build dir ~~ project root. This would have bad side-effects
  if %config<build_dir>.IO ~~ $*HOME.IO|%config<project_root>.IO {
    return { error => "Build directory [{%config<build_dir>}] cannot be {$*HOME} or project root [{%config<project_root>}]."}
  }
  return %config;
}

our sub init( Str   :$config_file  = 'config.yml', 
              Str   :$project_name = 'New Uzu Project',
              Str   :$url          = 'http://example.com',
              Str   :$language     = 'en',
              Str   :$theme        = 'default') returns Bool {

  my Hash %config;
  %config<name>     = $project_name;
  %config<url>      = $url;
  %config<language> = [$language];
  %config<theme>    = $theme;

  # Write config file
  my Str $config_yaml = save-yaml(%config).subst('...', '');
  return spurt $config_file.subst('~', $*HOME), $config_yaml;
}

=begin pod

=head1 NAME

Uzu - Static site generator with built-in web server, file modification watcher, i18n, themes, and multi-page support.

=head1 SYNOPSIS

        use Uzu;

        # Start development web server
        uzu-config(config_file => $config)
        ==> Uzu::web-server();

        # Render all templates to ./build/
        uzu-config(config_file => $config)
        ==> Uzu::render();

        # Watch template files for modification
        # and spawn development web server for testing
        uzu-config(config_file => $config)
        ==> Uzu::watch();

        # Create a new project
        Uzu::init(  config_file  => $config,
                    project_name => $project_name,
                    url          => $url,
                    language     => $language,
                    theme        => $theme );

=head1 DESCRIPTION

Uzu is a static site generator with built-in web server,
file modification watcher, i18n, themes, and multi-page
support.

=head3 C<render(Hash %config)>

Render all template files to ./build. This is destructive and replaces
all content in ./build with the new rendered content.

=head3 C<web-server(Hash %config)>

Start a development web server on port 3000 that serves the contents
of ./build. Web server port can be overriden in config.yml

=head3 C<watch(Hash %config, Bool :no_livereload = False)>

Render all template files to ./build. This is destructive and replaces
all content in ./build with the new rendered content. Then start
a new development web server and watch template files for modification.
On file modification, re-render template content to ./build for testing.

By default, `uzu watch` will inject a JavaScript block into the generated
HTML build/ output. The JavaScript will make an XMLHttpRequest to the dev
server every second (e.g. http://0.0.0.0/3000/live). When a new file
modification is detected the build/ HTML will be regenerated and a reload
flag will be set on the server. The next XMLHttpRequest from the client 
will receive a JSON doc, { "reload" : "True"}, triggering a browser 
reload (document.location.reload).

Passing :no_livereload = True will disable livereload.

=head2 C<uzu-config(Str :config_file = 'config.yml')>

Loads and parses config file. If config_file is unspecified then
the default, ./config.yml, will be used if exists.

=head3 C<init(Str :config_file,
              Str :project_name,
              Str :url,
              Str :language,
              Str :theme)>

Initialize a new project. This will create a new ./config.yml file
and populate it with the values passed for each named argument. If
:config_file is specified, init will create the config yml file 
using that value as file name.

=head2 C<License>

This module is licensed under the same license as Perl6 itself. 
Artistic License 2.0.
Copyright 2016 Sam Morrison.

=end pod

# vim: ft=perl6
