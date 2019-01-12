use v6;

use Test;
use Test::Output;
use Uzu::Config;
use Uzu::Render;
use Uzu::Utilities;
use File::Temp;

# Source project files
my $test_root = $*CWD.IO.child('t');

subtest {
    my $source_root = $test_root.IO.child('example_project_tt');

    # Setup tmp project root
    my $tmp_root    = tempdir;

    # Copy all example project files to tmp project root
    copy-dir $source_root, $tmp_root.IO;

    # Add tmp path to project config
    my $config_path = $tmp_root.IO.child('config.yml');
    my $config_file = slurp $config_path;
    spurt $config_path, $config_file ~ "project_root: $tmp_root\n";

    # Expect a warning when i18n yaml is invalid
    my $yaml = q:to/END/;
    ---
    company: Sam Morrison
    site_name: Uzu Test Project
    # Need to quote strings that start with numbers
    copyright: 2016 Sam Morrison
    @can't start a key with @
    END

    # Save to tmp_build_path i18n yaml file
    spurt $tmp_root.IO.child('i18n').child('en.yml'), $yaml;

    # Do not die when theme layout template is missing
    unlink $tmp_root.IO.child('themes').child('default').child('layout.tt');

    my $build_out = output-from {
        try {
            Uzu::Render::build
                Uzu::Config::from-file( config_file => $config_path, :no_livereload );
        }
    }
    say $build_out if %*ENV<UZUSTDOUT>;

    # Test warnings
    like $build_out, / 'No content found for page' /, 'empty page template warning to stdout';
    like $build_out, / 'Invalid i18n yaml file' /, 'invalid i18n yaml warning to stdout';
    like $build_out, / 'Theme [default] does not contain a layout template' /, 'theme layout template is missing warning to stdout';
    like $build_out, / 'Unable to load Local' /, 'extended library is missing subroutine context()';

}, 'Warnings';

done-testing;

# vim: ft=perl6
