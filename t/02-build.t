use v6;
use lib 'lib';

use Test;
use Test::Output;
use Uzu::Config;
use Uzu::HTTP;
use Uzu::Render;
use Uzu::Utilities;
use File::Temp;

plan 3;

# Source project files
my $test_root   = $*CWD.IO.child('t');

subtest {
    plan 5;

    my $source_root = $test_root.IO.child('example_project_tt');

    # Setup tmp project root
    my $tmp_root    = tempdir;

    # Copy all example project files to tmp project root
    copy-dir $source_root, $tmp_root.IO;

    # Add tmp path to project config
    my $config_path = $tmp_root.IO.child('config.yml');
    my $config_file = slurp $config_path;
    spurt $config_path, $config_file ~ "project_root: $tmp_root\n";

    # Set config file path
    my $config = Uzu::Config::from-file config_file => $config_path, no_livereload => True;

    # Generate HTML from templates
    Uzu::Render::build $config;

    # Did we generate the build directory?
    my $tmp_build_path = $tmp_root.IO.child('build').path;
    is $tmp_build_path.IO.e, True, 'render 1/5: build directory created';

    # Did we copy the assets folder contents?
    is $tmp_build_path.IO.child('img').child('logo.png').IO.e, True, 'render 2/5: assets folder contents copied';

    # Did we copy the pulic folder contents?
    is $tmp_build_path.IO.child('robots.txt').IO.e, True, 'render 3/5: public folder contents copied';

    # Generated HTML looks good?
    my $t3_expected_html  = slurp $test_root.IO.child('expected_tt').child('index.html');
    my $t3_generated_html = slurp $tmp_build_path.IO.child('index.html');

    is $t3_generated_html, $t3_expected_html, 'render 4/5: [Template6] rendered HTML matches test';

    # Generated nested HTML looks good?
    my $t4_expected_html  = slurp $test_root.IO.child('expected_tt').child('blog').child('fiji.html');
    my $t4_generated_html = slurp $tmp_build_path.IO.child('blog').child('fiji.html');

    is $t4_generated_html, $t4_expected_html, 'render 5/5: [Template6] rendered nested HTML matches test';
}, 'Rendering [Defaults]';

subtest {
    plan 2;

    my $source_root = $test_root.IO.child('example_project_mustache');

    # Setup tmp project root
    my $tmp_root    = tempdir;

    # Copy all example project files to tmp project root
    copy-dir $source_root, $tmp_root.IO;

    # Add tmp path to project config
    my $config_path = $tmp_root.IO.child('config.yml');
    my $config_file = slurp $config_path;
    spurt $config_path, $config_file ~ "project_root: $tmp_root\n";

    # Set config file path
    my $config = Uzu::Config::from-file config_file => $config_path, no_livereload => True;

    # Generate HTML from templates
    Uzu::Render::build $config;
    my $tmp_build_path = $tmp_root.IO.child('build').path;

    # Generated HTML looks good?
    my $t3_expected_html  = slurp $test_root.IO.child('expected_mustache').child('index.html');
    my $t3_generated_html = slurp $tmp_build_path.IO.child('index.html');

    is $t3_generated_html, $t3_expected_html, 'render 1/2: [Mustache] rendered HTML matches test';

    # Generated nested HTML looks good?
    my $t4_expected_html  = slurp $test_root.IO.child('expected_mustache').child('blog').child('fiji.html');
    my $t4_generated_html = slurp $tmp_build_path.IO.child('blog').child('fiji.html');
    spurt "tester.html", $t4_generated_html;

    is $t4_generated_html, $t4_expected_html, 'render 2/2: [Mustache] rendered nested HTML matches test';
}, 'Rendering [Mustache]';

subtest {
    plan 1;

    my $source_root = $test_root.IO.child('example_project_mustache');

    # Setup tmp project root
    my $tmp_root    = tempdir;

    # Copy all example project files to tmp project root
    copy-dir $source_root, $tmp_root.IO;

    # Add tmp path to project config
    my $config_path = $tmp_root.IO.child('config.yml');
    my $config_file = slurp $config_path;
    spurt $config_path, $config_file ~ "project_root: $tmp_root\n";

    # Set config file path
    my $config = Uzu::Config::from-file config_file => $config_path, no_livereload => True;

    # Expect a warning when i18n yaml is invalid
    my $t5_yaml = q:to/END/;
    ---
    company: Sam Morrison
    site_name: Uzu Test Project
    # Need to quote strings that start with numbers
    copyright: 2016 Sam Morrison
    ...
    END

    # Save to tmp_build_path i18n yaml file
    spurt $tmp_root.IO.child('i18n').child('en.yml'), $t5_yaml;
    stderr-like { Uzu::Render::build $config }, / "Invalid i18n yaml file" /, 'render 1/1: invalid i18n yaml warning to stdout';
}, 'Warnings';

# vim: ft=perl6
