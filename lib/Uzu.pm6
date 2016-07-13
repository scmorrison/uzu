use v6;

unit module Uzu;

use IO::Notification::Recursive;
use File::Find;
use Config::INI;
use Config::INI::Writer;

# Globals
my %config;

# Utils
sub path-exists(Str $path, Str $type) returns Bool {
  if $type ~~ 'f' { return $path.IO ~~ :f }
  if $type ~~ 'd' { return $path.IO ~~ :d }
}

sub find-dirs (Str:D $p) returns Slip {
  state $seen = {};
  return slip ($p.IO, slip find :dir($p), :type<dir>).grep: { !$seen{$_}++ };
}

sub partials() returns Seq {
   my @exts = |%config<template_extensions>;
   return "%config<defaults><partials_dir>".IO.dir(:test(/:i '.' @exts $/));
}

sub file-with-extension(Str $path) returns Str {
  my @files;
  my @exts = |%config<template_extensions>;
  for @exts -> $ext { @files.push: "$path.$ext" }
  return @files.first: *.IO.e;
}

our sub render() {
  use Template::Mustache;

  my $stache = Template::Mustache.new: :from<./partials>;
  my $themes_dir = %config<defaults><themes_dir>;
  my $theme = slurp file-with-extension("$themes_dir/%config<defaults><theme>");
  my $assets_dir = %config<defaults><assets_dir>;
  my $build_dir = %config<defaults><build_dir>;
  my @partial_templates = partials();
  my %context;
  my %partials;

  for @partial_templates -> $partial { 
    my $partial_name = IO::Path.new($partial).basename.Str.split('.')[0]; 
    %partials{$partial_name} = slurp($partial, :r);
  }

  # Create build dir if missing
  if !path-exists($build_dir, 'd') { say "Creating build directory"; mkdir $build_dir }

  # Clear out build
  say "Clear old files";
  shell("rm -rf $build_dir/*");

  # Copy assets
  say "Copying asset files";
  shell("cp -rf $assets_dir/* $build_dir/");

  # Write to build
  say "Compiling template to HTML";
  spurt "$build_dir/index.html", $stache.render($theme, %context, :from([%partials]));
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
  my $build_dir = %config<defaults><build_dir>;
 
  get /(.+)/ => sub ($file) {
    return "Invalid path" if $file.match('..');
    my $path;
    # Catch / => index.html
    if $file ~~ '/' {
      $path = IO::Path.new(file-with-extension("$build_dir/index"));
    } else {
      $path = IO::Path.new($build_dir ~ $file.split('?')[0]);
    }
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
    note "No partials files available";
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
  if !path-exists($config_file, 'f') { return say "$config_file not found. See uzu init." }
  my %config = Config::INI::parse_file($config_file);
  # Additional config for private use
  %config<path>                   = $config_file;
  %config<template_dirs>          = [%config<defaults><themes_dir>, %config<defaults><partials_dir>];
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
  %config<defaults><build_dir>    = 'build';
  %config<defaults><assets_dir>   = 'assets';
  %config<defaults><themes_dir>   = 'themes';
  %config<defaults><partials_dir> = 'partials';

  # Write config file
  return Config::INI::Writer::dumpfile(%config, $config_file.subst('~', $*HOME));
}

