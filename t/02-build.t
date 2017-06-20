use v6;
use lib 'lib';

use Test;
use Test::Output;
use Uzu;
use File::Temp;

plan 4;

# Source project files
my $test_root   = $*CWD.IO.child('t');
my $source_root = $test_root.IO.child('example_project');

# Setup tmp project root
my $tmp_root    = tempdir;

# Copy all example project files to tmp project root
Uzu::copy-dir $source_root, $tmp_root.IO;

# Add tmp path to project config
my $config_path = $tmp_root.IO.child('config.yml').path;
my $config_file = slurp $config_path;
spurt $config_path, $config_file ~ "project_root: $tmp_root";

# Set config file path
my $config = uzu-config config_file => $config_path;

# Generate HTML from templates
Uzu::build $config;

# Did we generate the build directory?
my $tmp_build_path = $tmp_root.IO.child('build').path;
is $tmp_build_path.IO.e, True, 'render 1/3: build directory created';

# Did we copy the assets folder contents?
is $tmp_build_path.IO.child('img').child('logo.png').IO.e, True, 'render 2/3: assets folder contents copied';

# Generated HTML looks good?
my $sample_html    = slurp $test_root.IO.child('generated').child('index.html');
my $generated_html = slurp $tmp_build_path.IO.child('index.html');
is $generated_html ~~ $sample_html, True, 'render 3/4: rendered HTML matches test';

# Expect a warning when i18n yaml is invalid
my $test4 = q:to/END/;
---
company: Sam Morrison
site_name: Uzu Test Project
copyright: 2016 Sam Morrison
...
END

# Save to tmp_build_path i18n yaml file
spurt $tmp_root.IO.child('i18n').child('en.yml'), $test4;
output-like { Uzu::build $config }, / "Invalid i18n yaml file" /, 'render 4/4: invalid i18n yaml warning to stdout';

# vim: ft=perl6
