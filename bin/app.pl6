#!/usr/bin/env perl6

use v6;

use Bailador;
use Bailador::App;
use Bailador::Route::StaticFile;


multi MAIN('serve', Str $src_dir) {

	my Bailador::ContentTypes $content-types = Bailador::ContentTypes.new;
	my $root_dir = $*CWD;
	my $build_dir = "$root_dir/$src_dir";
  
  get '/' => {
		my $path = IO::Path.new("$build_dir/index.html");
  }

	get /(.+)/ => sub ($file) {
    return "Invalid path" if $file.match('..');
		my $path = IO::Path.new($build_dir ~ $file.split('?')[0]);
		my $type = $content-types.detect-type($path);
		header("Content-Type", $type);
		say "$type: $path";
		return $path.slurp if !$type.grep: / image|ttf|woff /;
		return $path.slurp(:bin);
	}

  baile;

}

