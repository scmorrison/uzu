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
    plan 10;

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
    stdout-from { Uzu::Render::build $config }

    # Did we generate the build directory?
    my $tmp_build_path = $tmp_root.IO.child('build').path;
    is $tmp_build_path.IO.e, True, 'build directory created';

    # Did we copy the assets folder contents?
    is $tmp_build_path.IO.child('img').child('logo.png').IO.e, True, 'assets folder contents copied';

    # Did we copy the pulic folder contents?
    is $tmp_build_path.IO.child('robots.txt').IO.e, True, 'public folder contents copied';

    # Generated HTML looks good?
    my $t4_expected_html  = slurp $test_root.IO.child('expected_tt').child('index.html');
    my $t4_generated_html = slurp $tmp_build_path.IO.child('index.html');
    is $t4_generated_html, $t4_expected_html, '[Template6] rendered HTML matches test';

    # Generated nested HTML looks good?
    my $t5_expected_html  = slurp $test_root.IO.child('expected_tt').child('blog').child('fiji.html');
    my $t5_generated_html = slurp $tmp_build_path.IO.child('blog').child('fiji.html');
    is $t5_generated_html, $t5_expected_html, '[Template6] rendered nested HTML matches test';

    # Generated *_pages links exposed
    my $t6_expected_html  = slurp $test_root.IO.child('expected_tt').child('related.html');
    my $t6_generated_html = slurp $tmp_build_path.IO.child('related.html');
    is $t6_generated_html, $t6_expected_html, '[Template6] expose and utilize *_pages dict variables';

    # Use i18n language in uri for non-default languages
    my $t7_expected_html  = slurp $test_root.IO.child('expected_tt').child('related-ja.html');
    my $t7_generated_html = slurp $tmp_build_path.IO.child('related-ja.html');
    is $t7_generated_html, $t7_expected_html, '[Template6] i18n language in uri for non-default languages';

    # Use theme partial
    my $t8_expected_html  = slurp $test_root.IO.child('expected_tt').child('themepartial.html');
    my $t8_generated_html = slurp $tmp_build_path.IO.child('themepartial.html');
    is $t8_generated_html, $t8_expected_html, '[Template6] use theme partial';

    # Rebuild page when related page modified
    my $t9_generated_pre_modified  = $tmp_build_path.IO.child('related.html').modified;
    my $t9_related_page            = $tmp_root.IO.child('pages').child('about.tt');
    spurt $t9_related_page, slurp($t9_related_page);
    stdout-from { Uzu::Render::build $config }
    my $t9_generated_post_modified = $tmp_build_path.IO.child('related.html').modified;
    ok $t9_generated_post_modified > $t9_generated_pre_modified, '[Template6] modifying a related page triggers page rebuild';

    # Modifying an unrelated partial does not trigger page rebuild
    my $t10_generated_pre_modified  = $tmp_build_path.IO.child('related.html').modified;
    my $t10_unrelated_partial       = $tmp_root.IO.child('partials').child('usetheme.tt');
    spurt $t10_unrelated_partial, slurp($t10_unrelated_partial);
    stdout-from { Uzu::Render::build $config }
    my $t10_generated_post_modified = $tmp_build_path.IO.child('related.html').modified;
    ok $t10_generated_post_modified == $t10_generated_pre_modified, '[Template6] modifying an unrelated partial does not trigger page rebuild';
}, 'Rendering [Defaults]';

subtest {
    plan 7;

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
    stdout-from { Uzu::Render::build $config }
    my $tmp_build_path = $tmp_root.IO.child('build').path;

    # Generated HTML looks good?
    my $t1_expected_html  = slurp $test_root.IO.child('expected_mustache').child('index.html');
    my $t1_generated_html = slurp $tmp_build_path.IO.child('index.html');
    is $t1_generated_html, $t1_expected_html, '[Mustache] rendered HTML matches test';

    # Generated nested HTML looks good?
    my $t2_expected_html  = slurp $test_root.IO.child('expected_mustache').child('blog').child('fiji.html');
    my $t2_generated_html = slurp $tmp_build_path.IO.child('blog').child('fiji.html');
    is $t2_generated_html, $t2_expected_html, '[Mustache] rendered nested HTML matches test';

    # Generated *_pages links exposed
    my $t3_expected_html  = slurp $test_root.IO.child('expected_mustache').child('related.html');
    my $t3_generated_html = slurp $tmp_build_path.IO.child('related.html');
    is $t3_generated_html, $t3_expected_html, '[Mustache] expose and utilize *_pages dict variables';

    # Use i18n language in uri for non-default languages
    my $t4_expected_html  = slurp $test_root.IO.child('expected_mustache').child('related-ja.html');
    my $t4_generated_html = slurp $tmp_build_path.IO.child('related-ja.html');
    is $t4_generated_html, $t4_expected_html, '[Mustache] i18n language in uri for non-default languages';

    # Use theme partial
    my $t5_expected_html  = slurp $test_root.IO.child('expected_mustache').child('themepartial.html');
    my $t5_generated_html = slurp $tmp_build_path.IO.child('themepartial.html');
    is $t5_generated_html, $t5_expected_html, '[Mustache] use theme partial';

    # Rebuild page when related page modified
    my $t6_generated_pre_modified  = $tmp_build_path.IO.child('related.html').modified;
    my $t6_related_page            = $tmp_root.IO.child('pages').child('about.mustache');
    spurt $t6_related_page, slurp($t6_related_page);
    stdout-from { Uzu::Render::build $config }
    my $t6_generated_post_modified = $tmp_build_path.IO.child('related.html').modified;
    ok $t6_generated_post_modified > $t6_generated_pre_modified, '[Mustache] modifying a related page triggers page rebuild';

    # Modifying an unrelated partial does not trigger page rebuild
    my $t10_generated_pre_modified  = $tmp_build_path.IO.child('related.html').modified;
    my $t10_unrelated_partial       = $tmp_root.IO.child('partials').child('usetheme.mustache');
    spurt $t10_unrelated_partial, slurp($t10_unrelated_partial);
    stdout-from { Uzu::Render::build $config }
    my $t10_generated_post_modified = $tmp_build_path.IO.child('related.html').modified;
    ok $t10_generated_post_modified == $t10_generated_pre_modified, '[Mustache] modifying an unrelated partial does not trigger page rebuild';
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
    stderr-like { Uzu::Render::build $config }, / "Invalid i18n yaml file" /, 'invalid i18n yaml warning to stdout';
}, 'Warnings';

# vim: ft=perl6
