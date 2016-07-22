use v6;

use IO::Notification::Recursive;
use File::Find;
use YAMLish;

unit module Uzu:ver<0.0.6>:auth<gitlab:samcns>;

# Globals
my %config;

# Utils
sub path-exists(Str $path) returns Bool {
  return $path.IO ~~ :f|:d;
}

sub find-dirs (Str:D $p) returns Slip {
  state $seen = {};
  return slip ($p.IO, slip find :dir($p), :type<dir>).grep: { !$seen{$_}++ };
}

sub templates(Str :$dir) returns Seq {
   my @exts = |%config<template_extensions>;
   return $dir.IO.dir(:test(/:i '.' @exts $/));
}

sub file-with-extension(Str $path) returns Str {
  my @exts = |%config<template_extensions>;
  for @exts -> $ext {
    my $file_name = "$path.$ext";
    return $file_name if $file_name.IO ~~ :e and $file_name.IO ~~ :f;
  }
}

sub included-partials(Str :$content) returns Hash {
  my %partials;
  # Find matching mustache partial include declarations
  my @include_partials = $content.comb: / '{{>' ~ '}}' [\s*? <(\w+)> \s*?] /;
  for @include_partials -> $partial {
    my $partial_name = $partial;
    my $partial_path = file-with-extension("{%config<partials_dir>}/{$partial_name}");
    my $partial_content = slurp($partial_path, :r);
    %partials{$partial_name} = $partial_content;
  }
  return %partials;
}

sub build-context returns Hash {
  my %context;
  my $lang = %config<defaults><language>;
  %context<language> = $lang;

  my $i18n_file = "%config<i18n_dir>/$lang.yml";
  if path-exists($i18n_file) {
    for $i18n_file.IO.lines -> $line {
      next if $line ~~ '---'|''|/^\#.+$/;
      for load-yaml($line).kv -> $key, $val {
        %context{$key} = $val if $key !~~ '';
      }
    }
  }
  return %context;
}

our sub render() {
  use Template6;
  my $t6 = Template6.new;
  for |%config<template_dirs> -> $dir { $t6.add-path: $dir }

  my $themes_dir = %config<themes_dir>;
  my $layout_dir = %config<layout_dir>;
  my $assets_dir = %config<assets_dir>;
  my $build_dir = %config<build_dir>;

  # All available pages
  my %pages;
  my @page_templates = templates(dir => %config<pages_dir>);
  for @page_templates -> $page { 
    my $page_name = IO::Path.new($page).basename.Str.split('.')[0]; 
    %pages{$page_name} = slurp($page, :r);
  }

  # Clear out build
  say "Clear old files";
  run(«rm "-rf" "$build_dir"»);

  # Create build dir
  if !path-exists($build_dir) { say "Creating build directory"; mkdir $build_dir }

  # Copy assets
  say "Copying asset files";
  run(«cp "-rf" "$assets_dir/." "$build_dir/"»);

  # Build %context hash
  my %context = build-context();

  # Write to build
  say "Compiling template to HTML";
  for %pages.kv -> $page_name, $content {

		CATCH {
				when X { .resume }
		}

		# Render the page content
		my $page_content = $t6.process($page_name, |%context);
		
		# Append page content to %context
		%context<content> = $page_content;
		
		my $layout_content = $t6.process('layout', |%context );
		spurt "$build_dir/$page_name.html", $layout_content;
  }
  say "Compile complete";
}

our sub serve() returns Proc::Async {
  my Proc::Async $p;
  my @args = ("--config={%config<path>}", "webserver");
  if path-exists("bin/uzu") {
    $p .= new: "perl6", "bin/uzu", @args;
  } else {
    $p .= new: "uzu", @args;
  }
  $p.stdout.tap: -> $v { $*OUT.print: $v };
  $p.stderr.tap: -> $v { $*ERR.print: $v };
  $p.start;
  return $p;
}

our sub web-server() {
  use Bailador;
  use Bailador::App;
  my Bailador::ContentTypes $content-types = Bailador::ContentTypes.new;
  my $build_dir = %config<build_dir>;
 
  get /(.+)/ => sub ($file) {
    # Trying to access files outside of build path
    return "Invalid path" if $file.match('..');

    # Catch / => index.html
    my $path;
    if $file ~~ '/' {
      $path = IO::Path.new(file-with-extension("$build_dir/index"));
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
  baile(%config<defaults><port>||3000);
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

our sub watch() returns Tap {

  unless 'partials'.IO.e {
    note "No project files available";
    exit(1);
  }

  # Initialize build
  render();

  # Start server
  my $app = serve();
  
  # Track time delta between FileChange events. 
  # Some editors trigger more than one event per
  # edit. 
  my Instant $last;
  my @exts = |%config<template_extensions>;
  my @dirs = |%config<template_dirs>;
  react {
    whenever watch-dirs(@dirs.grep: *.IO.e) -> $e {
      if $e.path().grep: / '.' @exts $/ and (!$last.defined or now - $last > 8) {
        $last = now;
        say "Change detected [$e.path(), $e.event()].";
        render();
      }
    }
  }
}

# Config
sub parse-config(Str $config_file) returns Hash {
  if path-exists($config_file) {
    for $config_file.IO.lines -> $line {
      # Skip yaml header, comment, and blank lines
      next if $line ~~ '---'|''|/^\#.+$/;
      for load-yaml($line).kv -> $key, $val {
        # Define only set key/value pairs in %config
        %config<defaults>{$key} = $val if $key !~~ '';
      }
    }
    return %config;
  } else {
    return {error => "Config file [$config_file] not found. Please run uzu init to generate."};
  }
}

sub load-config(Str $config_file) returns Hash {

  # Parse yaml config
  my %config = parse-config($config_file);
  
  # Set configuration
  my $project_root                = %config<defaults><project_root>||$*CWD;
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
  %config<template_extensions>    = ['tt', 'ms', 'mustache', 'html', 'yml'];

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

our sub config(Str :$config_file) returns Hash {
  %config = load-config $config_file.subst('~', $*HOME);
}

our sub init( Str :$config_file  = "config.yml", 
              Str :$project_name = "New Uzu Project",
              Str :$url          = "http://example.com",
              Str :$language     = "en",
              Str :$theme        = "default") returns Bool {

  %config<name>     = $project_name;
  %config<url>      = $url;
  %config<language> = $language;
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

=head3 C<watch>

Render all template files to ./build. This is destructive and replaces
all content in ./build with the new rendered content. Then start
a new development web server and watch template files for modification.
On file modification, re-render template content to ./build for testing.

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
