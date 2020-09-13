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
    my $source_root = $test_root.IO.child('example_project_mustache');
    # Setup tmp project root
    my $tmp_root    = tempdir;

    # Copy all example project files to tmp project root
    copy-dir $source_root, $tmp_root.IO;
    rm-dir $tmp_root.IO.child('build');

    # Add tmp path to project config
    my $config_path = $tmp_root.IO.child('config.yml');
    my $config_file = slurp $config_path;
    spurt $config_path, $config_file ~ "\nproject_root: $tmp_root\n";

    # Set config file path
    my $config = Uzu::Config::from-file config_file => $config_path, :no_livereload;

    # Generate HTML from templates
    my $stdout = output-from {
        try {
           Uzu::Render::build $config;
        }
    }
    say $stdout if %*ENV<UZUSTDOUT>;

    my $tmp_build_path = $tmp_root.IO.child('build').child('default').path;

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
    is trim($t4_generated_html), trim($t4_expected_html), '[Mustache] i18n language in uri for non-default languages';

    # Use theme partial
    my $t5_expected_html  = slurp $test_root.IO.child('expected_mustache').child('themepartial.html');
    my $t5_generated_html = slurp $tmp_build_path.IO.child('themepartial.html');
    is $t5_generated_html, $t5_expected_html, '[Mustache] use theme partial';

    # Rebuild page when related page modified
    my $t6_generated_pre_modified  = $tmp_build_path.IO.child('related.html').modified;
    my $t6_related_page            = $tmp_root.IO.child('pages').child('about.mustache');
    spurt $t6_related_page, slurp($t6_related_page);
    my $stdout6 = stdout-from {
        try {
            Uzu::Render::build $config;
        }
    }
    say $stdout6 if %*ENV<UZUSTDOUT>;
    my $t6_generated_post_modified = $tmp_build_path.IO.child('related.html').modified;
    ok $t6_generated_post_modified > $t6_generated_pre_modified, '[Mustache] modifying a related page triggers page rebuild';

    # Modifying an unrelated partial does not trigger page rebuild
    my $t7_generated_pre_modified  = $tmp_build_path.IO.child('related.html').modified;
    my $t7_unrelated_partial       = $tmp_root.IO.child('partials').child('usetheme.mustache');
    spurt $t7_unrelated_partial, slurp($t7_unrelated_partial);
    my $stdout7 = stdout-from {
        try {
            Uzu::Render::build $config;
        }
    }
    say $stdout7 if %*ENV<UZUSTDOUT>;
    my $t7_generated_post_modified = $tmp_build_path.IO.child('related.html').modified;
    ok $t7_generated_post_modified == $t7_generated_pre_modified, '[Mustache] modifying an unrelated partial does not trigger page rebuild';

    # Disable theme layout from page yaml
    my $t8_expected_html  = slurp $test_root.IO.child('expected_mustache').child('nolayout.html');
    my $t8_generated_html = slurp $tmp_build_path.IO.child('nolayout.html');
    is $t8_generated_html, $t8_expected_html, '[Mustache] disable theme layout from page yaml';

    # Embedded partials can access page vars
    my $t9_expected_html  = slurp $test_root.IO.child('expected_mustache').child('embedded.html');
    my $t9_generated_html = slurp $tmp_build_path.IO.child('embedded.html');
    is $t9_generated_html, $t9_expected_html, '[Mustache] embedded partials can access page vars';

    # Deeply embedded partials can access page vars
    my $t10_expected_html  = slurp $test_root.IO.child('expected_mustache').child('deepembed.html');
    my $t10_generated_html = slurp $tmp_build_path.IO.child('deepembed.html');
    is $t10_generated_html, $t10_expected_html, '[Mustache] deeply embedded partials can access page vars';

    my $t11_expected_html  = slurp $test_root.IO.child('expected_mustache').child('summer2017').child('layout.html');
    my $t11_generated_html = slurp $tmp_root.IO.child('build').child('summer2017').child('layout.html');
    is $t11_generated_html, $t11_expected_html, '[Mustache] multi-theme build with layout specific varibles';

    my $t12_excluded_page = $tmp_root.IO.child('build').child('summer2017').child('excludeme.html').IO.e;
    nok $t12_excluded_page, '[Mustache] multi-theme exclude page for theme via config';

    my $t13_excluded_dir = so $tmp_root.IO.child('build').child('bad_folder').IO.e;
    nok $t13_excluded_dir, '[Mustache] exclude directory from build via config';

    my $t14_excluded_file = so $tmp_root.IO.child('build').child('bad_file.txt').IO.e;
    nok $t14_excluded_file, '[Mustache] exclude file from build via config';

    my $t15_pre_command = so $stdout7.contains('pre-command test');
    ok $t15_pre_command, '[Mustache] pre_command via config';

    my $t16_post_command = so $stdout7.contains('post-command test');
    ok $t16_post_command, '[Mustache] post_command via config';
 
}, 'Rendering [Mustache]';

subtest {
    
    my $source_root = $test_root.IO.child('example_project_mustache');
    # Setup tmp project root
    my $tmp_root    = tempdir;

    # Copy all example project files to tmp project root
    copy-dir $source_root, $tmp_root.IO;
    rm-dir $tmp_root.IO.child('build');

    # Add tmp path to project config
    my $config_path = $tmp_root.IO.child('config.yml');
    my $config_file = slurp $config_path;
    spurt $config_path, $config_file ~ "project_root: $tmp_root\ni18n_scheme: 'directory'\n";

    # Set config file path
    my $config = Uzu::Config::from-file config_file => $config_path, :no_livereload;

    # Generate HTML from templates
    my $stdout = stdout-from {
        try {
	        Uzu::Render::build $config;
        }
    }
    say $stdout if %*ENV<UZUSTDOUT>;

    my $tmp_build_path = $tmp_root.IO.child('build').child('default').path;
    ok $tmp_build_path.IO.child('ja').child('related.html').e, '[Mustache] i18n language for non-default languages (scheme: directory)';

}, 'Rendering i18n scheme directory [Mustache]';
done-testing;

# vim: ft=perl6
