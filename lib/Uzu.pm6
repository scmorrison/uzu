use v6;

use IO::Notification::Recursive;
use File::Find;
use YAMLish;

unit module Uzu:ver<0.0.8>:auth<gitlab:samcns>;

# Utils
sub path-exists(Str :$path) returns Bool {
  return $path.IO ~~ :f|:d;
}

sub find-dirs (Str:D $p) returns Slip {
  state $seen = {};
  return slip ($p.IO, slip find :dir($p), :type<dir>).grep: { !$seen{$_}++ };
}

sub templates(:@exts, Str :$dir) returns Seq {
   return $dir.IO.dir(:test(/:i '.' @exts $/));
}

sub file-with-extension(:@exts, Str :$path) returns Str {
  for @exts -> $ext {
    my $file_name = "$path.$ext";
    return $file_name if $file_name.IO ~~ :e and $file_name.IO ~~ :f;
  }
}

sub build-context(Str :$i18n_dir, Str :$language) returns Hash {
  my %context;
  %context<language> = $language;

  my $i18n_file = "$i18n_dir/$language.yml";
  if path-exists(path => $i18n_file) {
    try {
      CATCH {
        default {
          note "Invalid i18n yaml file [$i18n_file]";
        }
      }
      my %yaml = load-yaml slurp($i18n_file);
      %context.append: %yaml;
    }
  }
  return %context;
}

our sub render(:%config,
               Bool :$no_livereload = False) {

  use Template6;
  my $t6 = Template6.new;
  for |%config<template_dirs> -> $dir { $t6.add-path: $dir }

  my $themes_dir = %config<themes_dir>;
  my $layout_dir = %config<layout_dir>;
  my $assets_dir = %config<assets_dir>;
  my $build_dir  = %config<build_dir>;

  # All available pages
  my %pages;
  my @exts = |%config<template_extensions>;
  my @page_templates = templates(exts => @exts, dir => %config<pages_dir>);
  for @page_templates -> $page { 
    my $page_name = IO::Path.new($page).basename.Str.split('.')[0]; 
    %pages{$page_name} = slurp($page, :r);
  }

  # Clear out build
  say "Clear old files";
  run(«rm "-rf" "$build_dir"»);

  # Create build dir
  if !path-exists(path => $build_dir) { say "Creating build directory"; mkdir $build_dir }

  # Copy assets
  say "Copying asset files";
  run(«cp "-rf" "$assets_dir/." "$build_dir/"»);

  for |%config<language> -> $language {
    # Build %context hash
    my %context = build-context(i18n_dir => %config<i18n_dir>,
                                language => $language);

    # Write to build
    say "Compiling template to HTML";
    for %pages.kv -> $page_name, $content {

      # Render the page content
      my $page_content = $t6.process($page_name, |%context);
      
      # Append page content to %context
      %context<content> = $page_content;
      
      my $layout_content = $t6.process('layout', |%context );

      unless $no_livereload {
        # Add livejs if live-reload enabled (default)
        my $livejs = '<script src="uzu/js/live.js"></script>';
        $layout_content = $layout_content.subst('</body>', "{$livejs}\n</body>");
      };

      my $file_name = $page_name;
      if $language !~~ %config<language>[0] {
        $file_name = "{$page_name}_{$language}";
      }

      spurt "$build_dir/$file_name.html", $layout_content;
    }
  }
  say "Compile complete";
}

our sub serve(Str :$config_file) returns Proc::Async {
  my Proc::Async $p;
  my @args = ("--config={$config_file}", "webserver");
  # Use the library path if running from test
  if path-exists(path => "bin/uzu") {
    my $lib_path = $?FILE.IO.parent;
    $p .= new: "perl6", "-I{$lib_path}", "bin/uzu", @args;
  } else {
    # Use uzu from PATH otherwise
    $p .= new: "uzu", @args;
  }
  $p.stdout.tap: -> $v { $*OUT.print: $v }
  $p.stderr.tap: -> $v { 
    # Filter out livereload requests
    if !$v.contains('GET /live') { $*ERR.print: $v }
  }
  $p.start;
  return $p;
}

our sub web-server(:%config) {
  use Bailador;
  use Bailador::App;
  my Bailador::ContentTypes $content-types = Bailador::ContentTypes.new;
  my $build_dir = %config<build_dir>;

  # Use for triggering reload staging when reload is triggered
  my $reload = False;
  
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
    my $response;
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
    my $livejs = q:to/EOS/; 
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

    # Catch / => index.html
    my $path;
    my @exts = |%config<template_extensions>;
    if $file ~~ '/' {
      $path = IO::Path.new(file-with-extension(exts => @exts, path => "$build_dir/index"));
    } else {
      $path = IO::Path.new($build_dir ~ $file.split('?')[0]);
    }

    # Invalid path
    return "Invalid path: file does not exists" if !$path.IO.e;

    # Return any valid paths
    my $type = $content-types.detect-type($path);
    header("Content-Type", $type);
    return $path.slurp if !$type.grep: / image|ttf|woff /;
    return $path.slurp(:bin);
  }    

  # Start bailador
  baile(%config<port>||3000);
}

# Watchers
sub watch-it($p) returns Tap {
    say "Starting watch on {$p.subst("{$*CWD}/", '')}";
    whenever IO::Notification.watch-path($p) -> $e {
        if $e.event ~~ FileRenamed && $e.path.IO ~~ :d {
            watch-it($_) for find-dirs($e.path);
        }
        emit($e);
    }
}

sub watch-dirs(@dirs) returns Supply {
  supply {
    watch-it(~$_) for |@dirs.map: { find-dirs($_) };
  }
}

our sub watch(:%config, Bool :$no_livereload = False) returns Tap {
  use HTTP::Tinyish;

  unless 'partials'.IO.e {
    note "No project files available";
    exit(1);
  }

  # Initialize build
  render(config => %config, no_livereload => $no_livereload);

  # Start server
  my $app = serve(config_file => %config<path>);
  
  # Track time delta between FileChange events. 
  # Some editors trigger more than one event per
  # edit. 
  my Instant $last;
  my @exts = |%config<template_extensions>;
  my @dirs = |%config<template_dirs>;
  react {
    whenever watch-dirs(@dirs.grep: *.IO.e) -> $e {
      if $e.path().grep: / '.' @exts $/ and (!$last.defined or now - $last > 2) {
        $last = now;
        say "Change detected [$e.path(), $e.event()].";
        render(config => %config, no_livereload => $no_livereload);
        unless $no_livereload {
          HTTP::Tinyish.new(agent => "Mozilla/4.0").get("http://{%config<host>}:{%config<port>}/reload");
        }
      }
    }
  }
}

our sub wait-server(Str :$host, int :$port, :$sleep=0.1, int :$times=100) is export {
    LOOP: for 1..$times {
        try {

            my $sock = IO::Socket::INET.new(host => $host, port => $port);
            $sock.close;

            CATCH { default {
                sleep $sleep;
                next LOOP;
            } }
        }
        return;
    }

    die "http://{$host}:{$port} did not open within {$sleep*$times} seconds.";
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
  %config<host>                   = "{%config<host>||'0.0.0.0'}";
  %config<port>                   = %config<port>||3000;
  my $project_root                = %config<project_root>||$*CWD;
  %config<project_root>           = $project_root;
  %config<path>                   = $config_file;
  %config<build_dir>              = "{$project_root}/build";
  %config<themes_dir>             = "{$project_root}/themes";
  %config<assets_dir>             = "{$project_root}/themes/{%config<defaults><theme>||'default'}/assets";
  %config<layout_dir>             = "{$project_root}/themes/{%config<defaults><theme>||'default'}/layout";
  %config<pages_dir>              = "{$project_root}/pages";
  %config<partials_dir>           = "{$project_root}/partials";
  %config<i18n_dir>               = "{$project_root}/i18n";
  %config<template_dirs>          = [%config<layout_dir>, %config<partials_dir>, %config<pages_dir>, %config<i18n_dir>];
  %config<template_extensions>    = ['tt', 'html', 'yml'];

  for %config.kv -> $k, $v {
    # Replace ~ with full home path if applicable:
    if %config{$k} ~~ Str {
      %config{$k} = $v.subst('~', $*HOME);
    }
  }

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

  my %config;
  %config<name>     = $project_name;
  %config<url>      = $url;
  %config<language> = [$language];
  %config<theme>    = $theme;

  # Write config file
  my $config_yaml = save-yaml(%config).subst('...', '');
  return spurt $config_file.subst('~', $*HOME), $config_yaml;
}

=begin pod

=head1 NAME

Uzu - Static site generator with built-in web server, file modification watcher, i18n, themes, and multi-page support.

=head1 SYNOPSIS

        use Uzu;

        # Start development web server
        Uzu::config(config_file => $config);
        Uzu::web-server();

        # Render all templates to ./build/
        Uzu::config(config_file => $config);
        Uzu::render();

        # Watch template files for modification
        # and spawn development web server for testing
        Uzu::config(config_file => $config);
        Uzu::watch();

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

=head3 C<render>

Render all template files to ./build. This is destructive and replaces
all content in ./build with the new rendered content.

=head3 C<web-server>

Start a development web server on port 3000 that serves the contents
of ./build. Web server port can be overriden in config.yml

=head3 C<watch(Bool :no_livereload = False)>

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

=head2 C<config(Str :config_file = 'config.yml')>

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
