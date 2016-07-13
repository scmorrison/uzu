use v6;

unit module Uzu:ver<0.0.2>:auth<gitlab:samcns>;

use IO::Notification::Recursive;
use File::Find;
use Config::INI;
use Config::INI::Writer;

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
    return "$path.$ext" if "$path.$ext".IO ~~ :e;
  }
}

sub included-partials(Str :$content) {
	my %partials;
	my @include_partials = $content.match: / '{{> ' (\w+) ' }}'/, :g;
	for @include_partials -> $partial {
		my $partial_name = $partial[0].Str;
		my $partial_path = file-with-extension("{%config<partials_dir>}/{$partial_name}");
		my $partial_content = slurp($partial_path, :r);
		%partials{$partial_name} = $partial_content;
	}
	return %partials;
}

our sub render() {
  use Template::Mustache;

  my $themes_dir = %config<themes_dir>;
  my $layout_dir = %config<layout_dir>;
  my $layout = slurp file-with-extension("$layout_dir/layout");
  my $assets_dir = %config<assets_dir>;
  my $build_dir = %config<build_dir>;

  # All available pages
  my %pages;
  my @page_templates = templates(dir => %config<pages_dir>);
  for @page_templates -> $page { 
    my $page_name = IO::Path.new($page).basename.Str.split('.')[0]; 
    %pages{$page_name} = slurp($page, :r);
  }

  # Create build dir if missing
  if !path-exists($build_dir) { say "Creating build directory"; mkdir $build_dir }

  # Clear out build
  say "Clear old files";
  shell("rm -rf $build_dir/*");

  # Copy assets
  say "Copying asset files";
  shell("cp -rf $assets_dir/* $build_dir/");

  # Mustache template engine
  my $stache = Template::Mustache.new;
  my %context;

  # Write to build
  say "Compiling template to HTML";
  for %pages.kv -> $page_name, $content {

    # Render the page content
    my %page_partials = included-partials(content => $content);
    my $page_content = $stache.render($content, %context, :from([%page_partials]));

    # Embed the page content into the layout
    my %layout_partials = included-partials(content => $layout);

    # This is a mess, find a better way to quickly decode HTML entities
    # The second $stache.render returns the %context<content> as encoded HTML
    # decoding it with HTML::Entity is too slow
    %context<content> = '{{ content }}';
    my $layout_content = $stache.render($layout, %context, :from([%layout_partials]));
    spurt "$build_dir/$page_name.html",
          $layout_content.subst('{{ content }}', $page_content);
  }
  say "Compile complete";
}

our sub serve(Str :$config_file = 'config') returns Proc::Async {
  my Proc::Async $p .= new: "uzu", "--config=$config_file", "webserver";
  $p.stdout.tap: -> $v { $*OUT.print: $v };
  $p.stderr.tap: -> $v { $*ERR.print: $v };
  $p.start;
  return $p;
}

our sub web-server(Str :$config_file = 'config') {
  use Bailador;
  use Bailador::App;

  %config = load-config($config_file);
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
    say "$type: $path";
    return $path.slurp if !$type.grep: / image|ttf|woff /;
    return $path.slurp(:bin);
  }    

  # Start bailador
  baile;
}

# Watchers
sub watch-it($p) returns Tap {
    say "Starting watch on $p";
    whenever IO::Notification.watch-path($p) -> $e {
        if $e.event ~~ FileRenamed && $e.path.IO ~~ :d {
            watch-it($_) for find-dirs($e.path);
        }
        emit($e);
    }
}

our sub watch-dirs(@dirs) returns Supply {
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
  my $app = serve(config_file => %config<path>);
  
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
sub load-config(Str $config_file) returns Hash {
  if !path-exists($config_file) { return say "$config_file not found. See uzu init." }
  my %config = Config::INI::parse_file($config_file);
  # Additional config for private use
  %config<path>                   = $config_file;
  %config<build_dir>              = 'build';
  %config<themes_dir>             = 'themes';
  %config<assets_dir>             = "themes/{%config<defaults><theme>}/assets";
  %config<layout_dir>             = "themes/{%config<defaults><theme>}/layout";
  %config<pages_dir>              = 'pages';
  %config<partials_dir>           = 'partials';
  %config<template_dirs>          = [%config<layout_dir>, %config<partials_dir>, %config<pages_dir>];
  %config<template_extensions>    = ['ms', 'mustache', 'html'];
  return %config;
}

our sub config(Str :$config_file) returns Hash {
  %config = load-config $config_file.subst('~', $*HOME);
}

our sub init( Str :$config_file  = "config", 
              Str :$project_name = "New Uzu Project",
              Str :$url          = "http://example.com",
              Str :$language     = "en-US",
              Str :$theme        = "default") returns Bool {

  %config<defaults><name>         = $project_name;
  %config<defaults><url>          = $url;
  %config<defaults><language>     = $language;
  %config<defaults><theme>        = $theme;

  # Write config file
  return Config::INI::Writer::dumpfile(%config, $config_file.subst('~', $*HOME));
}

# vim: ft=perl6
