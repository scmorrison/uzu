use Test;
use Uzu;
use File::Temp;

plan 3;

# Source project files
my $source_project_root = "t/example_project";

# Setup tmp project root
my $tmp_root = tempdir;

# Copy all example project files to tmp project root
shell("cp -rf $source_project_root/* $tmp_root/");

# Add tmp path to project config
my $config_file_path = "{$tmp_root.IO.path}/config.yml";
my $config_file = slurp $config_file_path;
spurt $config_file_path, $config_file ~ "project_root: $tmp_root";

# Set config file path
Uzu::config(config_file => $config_file_path);

# Generate HTML from templates
Uzu::render();

# Did we generate the build directory?
my $tmp_build_path = "{$tmp_root.IO.path}/build";
is $tmp_build_path.IO.e, True, 'render 1/3: build directory created';

# Did we copy the assets folder contents?
is "$tmp_build_path/img/logo.png".IO.e, True, 'render 2/3: assets folder contents copied';

# Generated HTML looks good?
my $generated_html = slurp "$tmp_build_path/index.html";
my $pregenerated_html = slurp "t/generated/index.html";
is $generated_html ~~ $pregenerated_html, True, 'render 3/3: rendered HTML matches test';

# vim: ft=perl6
