use v6;

unit module UZU;

use IO::Notification::Recursive;
use Template::Mustache;
use File::Find;

our $supplier;
our $log;
our $layout;

our sub config(:$base, :$layout) {
  $supplier = Supplier.new;
  $log = $supplier.Supply;
  watch_dir($base);
  $layout = $layout;
}

sub partials() {
   return "partials/".IO.dir(:test(/ .* ".mustache" $/));
}

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

our sub watch-recursive(@dirs) {
  supply {
      watch-it(~$_) for |@dirs.map: { find-dirs($_) };
  }
}

sub find-dirs (Str:D $p) {
  state $seen = {};
  return slip ($p.IO, slip find :dir($p), :type<dir>).grep: { !$seen{$_}++ };
}

sub watch_dir($dir) {
    my $last;
    IO::Notification.watch-path($dir)\
        .unique(:as(*.path), :expires(1))\
        .map(*.path)\
        .grep(/.mustache$/)\
        .act(-> $modified {
          # Prevent events from emmitting more than once
          # in a few seconds
          if (!$last.defined or now - $last > 6) {
            $last = now;
            $!supplier.emit($modified);
          }

          CATCH {
              default {
                  $!supplier.emit("ERROR: incorrect file format: $_");
              }
          }
        });
}

our sub serve(Str :$build_dir) {
  #my $app = StaticSite.new(src_dir => $build_dir);
  #app $app;
  my Proc::Async $p .= new: $?FILE, "webserver", "$build_dir";
  #my Proc::Async $p .= new: "bin/sitegen", "webserver", "$build_dir";
  $p.stdout.tap: -> $v { $*OUT.print: $v };
  $p.stderr.tap: -> $v { $*ERR.print: $v };
  $p.start;
  return $p;
}

our sub render() {

    my $build_dir = IO::Path.new("$*CWD/build");
    my $build_assets_dir = IO::Path.new("$build_dir/assets");
    my $assets_src_dir = IO::Path.new("$*CWD/assets");
    my $partials_src_dir = IO::Path.new("$*CWD/partials");
    #my $tmp_dir = IO::Path.new("$*CWD/tmp");
    #my $partials_tmp_dir = IO::Path.new("$tmp_dir/partials");

    my $stache = Template::Mustache.new: :from<./partials>;
    my $layout_dir = 'layouts';
    my $template = slurp "$layout_dir/$!layout.mustache";
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
    #for dir $build_dir { .unlink }
    say "Clear old files";
    shell("rm -rf $build_dir/*");

    # Copy assets
    #for dir $assets_dir -> $file { copy $file, $build_dir }
    say "Copying asset files";
    shell("cp -rf $assets_src_dir/* $build_dir/");

    # Write to build
    say "Compiling template to HTML";
    #$stache.render($template, %context, :from([%partials]));
    spurt "build/index.html", $stache.render($template, %context, :from([%partials]));
    say "Compile complete";
}
