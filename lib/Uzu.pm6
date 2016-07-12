use v6;

unit module Uzu;

use IO::Notification::Recursive;
use Template::Mustache;
use File::Find;

# Globals
my $layout_template;
my @template_extensions = 'ms', 'mustache', 'html';
my $build_dir = IO::Path.new("$*CWD/build");
my @template_dirs = ['layouts/', 'partials/'];
my $assets_src_dir = IO::Path.new("$*CWD/assets");
my $partials_src_dir = IO::Path.new("$*CWD/partials");

sub path_exists(Str $path, Str $type) {
  if $type ~~ 'f' { return $path.IO ~~ :f }
  if $type ~~ 'd' { return $path.IO ~~ :d }
}

sub watch-it($p) {
    say "Starting watch on `$p`";
    whenever IO::Notification.watch-path($p) -> $e {
        if $e.event ~~ FileRenamed && $e.path.IO ~~ :d {
            watch-it($_) for find-dirs($e.path);
        }
        emit($e);
    }
}

our sub watch-dirs(@dirs) {
  supply {
      watch-it(~$_) for |@dirs.map: { find-dirs($_) };
  }
}

sub find-dirs (Str:D $p) {
  state $seen = {};
  return slip ($p.IO, slip find :dir($p), :type<dir>).grep: { !$seen{$_}++ };
}

sub watch-dir($dir) {
  my $supplier = Supplier.new;
  my $log = $supplier.Supply;
  my $last;
  IO::Notification.watch-path($dir)\
		.unique(:as(*.path), :expires(1))\
		.map(*.path)\
		.grep(/@template_extensions$/)\
		.act(-> $modified {
			# Prevent events from emmitting more than once
			# in a few seconds
			if (!$last.defined or now - $last > 6) {
				$last = now;
				$supplier.emit($modified);
			}

			CATCH {
					default {
							$supplier.emit("ERROR: incorrect file format: $_");
					}
			}
		});
}

sub partials() {
   return "partials/".IO.dir(:test(/:i '.' @template_extensions $/));
}

sub file-with-extension(Str $path) {
  my @files;
  for @template_extensions -> $ext { @files.push: "$path.$ext" }
  return @files.first: *.IO.e;
}

our sub render() {

  my $stache = Template::Mustache.new: :from<./partials>;
  my $layout_template_dir = 'layouts';
  my $template = slurp file-with-extension("$layout_template_dir/$layout_template");
  my @partial_templates = partials();
  my %context;
  my %partials;

  for @partial_templates -> $partial { 
    my $partial_name = IO::Path.new($partial).basename.Str.split('.')[0]; 
    %partials{$partial_name} = slurp($partial, :r);
  }

  # Create build dir if missing
  if !path_exists($build_dir.Str, 'd') { say "Creating build directory"; mkdir $build_dir }

  # Clear out build
  say "Clear old files";
  shell("rm -rf $build_dir/*");

  # Copy assets
  say "Copying asset files";
  shell("cp -rf $assets_src_dir/* $build_dir/");

  # Write to build
  say "Compiling template to HTML";
  spurt "$build_dir/index.html", $stache.render($template, %context, :from([%partials]));
  say "Compile complete";
}

our sub serve(Str :$build_dir) {
  my Proc::Async $p .= new: "uzu", "webserver", "$build_dir";
  $p.stdout.tap: -> $v { $*OUT.print: $v };
  $p.stderr.tap: -> $v { $*ERR.print: $v };
  $p.start;
  return $p;
}

our sub web-server(Str :$src_dir) {

  use Bailador;
  use Bailador::App;

  my Bailador::ContentTypes $content-types = Bailador::ContentTypes.new;
  my $root_dir = $*CWD;
  my $build_dir = "$root_dir/$src_dir";
 
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

  baile;
}

our sub watch() {

  # Initialize build
  render();

  # Start server
  my $app = serve(build_dir => 'build');
  
  # Track time delta between FileChange events. 
  # Some editors trigger more than one event per
  # edit. 
  my Instant $last;
  react {
    whenever watch-dirs(@template_dirs.grep: *.IO.e) -> $e {
      if $e.path().grep: / '.' @template_extensions $/ and (!$last.defined or now - $last > 8) {
        $last = now;
        say $last.WHAT;
        say "Change detected [$e.path(), $e.event()].";
        render();
      }
    }
  }
}

our sub config(:$base, :$layout) {
  watch-dir($base);
  $layout_template = $layout;
}
