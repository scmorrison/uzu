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
    rm-dir $tmp_root.IO.child('build');

    # Add tmp path to project config
    my $config_path = $tmp_root.IO.child('config.yml');
    my $config_file = slurp $config_path;
    spurt $config_path, $config_file ~ "project_root: $tmp_root\n";

    # Set config file path
    my $config = Uzu::Config::from-file config_file => $config_path, :no_livereload;

    # Generate HTML from templates
    my $stdout = stdout-from {
        try {
	        Uzu::Render::build $config;
        }
    }
    say $stdout if %*ENV<UZUSTDOUT>;

    # Did we generate the build directory?
    my $tmp_build_path = $tmp_root.IO.child('build').child('default').path;
    ok $tmp_build_path.IO.e, 'build directory created';

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
    my $stdout9 = stdout-from {
        try {
	      Uzu::Render::build $config;
        }
    }
    say $stdout9 if %*ENV<UZUSTDOUT>;

    my $t9_generated_post_modified = $tmp_build_path.IO.child('related.html').modified;
    ok $t9_generated_post_modified > $t9_generated_pre_modified, '[Template6] modifying a related page triggers page rebuild';

    # Modifying an unrelated partial does not trigger page rebuild
    my $t10_generated_pre_modified  = $tmp_build_path.IO.child('related.html').modified;
    my $t10_unrelated_partial       = $tmp_root.IO.child('partials').child('usetheme.tt');
    spurt $t10_unrelated_partial, slurp($t10_unrelated_partial);
    my $stdout10 = stdout-from { Uzu::Render::build $config };
    say $stdout10 if %*ENV<UZUSTDOUT>;
    my $t10_generated_post_modified = $tmp_build_path.IO.child('related.html').modified;
    ok $t10_generated_post_modified == $t10_generated_pre_modified, '[Template6] modifying an unrelated partial does not trigger page rebuild';

    # Disable theme layout from page yaml
    my $t11_expected_html  = slurp $test_root.IO.child('expected_tt').child('nolayout.html');
    my $t11_generated_html = slurp $tmp_build_path.IO.child('nolayout.html');
    is $t11_generated_html, $t11_expected_html, '[Template6] disable theme layout from page yaml';

    # Embedded partials can access page vars
    my $t12_expected_html  = slurp $test_root.IO.child('expected_tt').child('embedded.html');
    my $t12_generated_html = slurp $tmp_build_path.IO.child('embedded.html');
    is $t12_generated_html, $t12_expected_html, '[Template6] embedded partials can access page vars';

    # Deeply embedded partials can access page vars
    my $t13_expected_html  = slurp $test_root.IO.child('expected_tt').child('deepembed.html');
    my $t13_generated_html = slurp $tmp_build_path.IO.child('deepembed.html');
    is $t13_generated_html, $t13_expected_html, '[Template6] deeply embedded partials can access page vars';

    my $t14_expected_html  = slurp $test_root.IO.child('expected_tt').child('summer2017').child('layout.html');
    my $t14_generated_html = slurp $tmp_root.IO.child('build').child('summer2017').child('layout.html');
    is $t14_generated_html, $t14_expected_html, '[Template6] multi-theme build with layout specific varibles';

    my $t15_excluded_page = $tmp_root.IO.child('build').child('summer2017').child('excludeme.html').IO.e;
    nok $t15_excluded_page, '[Template6] multi-theme exclude page for theme via config';

    my $t16_excluded_dir = so $tmp_root.IO.child('build').child('bad_folder').IO.e;
    nok $t16_excluded_dir, '[Template6] exclude directory from build via config';

    my $t17_excluded_file = so $tmp_root.IO.child('build').child('bad_file.txt').IO.e;
    nok $t17_excluded_file, '[Template6] exclude file from build via config';

    if %*ENV<UZUSTDOUT> {
        my $t18_pre_command = 'pre-command test' (elem) $stdout;
        ok $t18_pre_command, '[Template6] pre_command via config';

        my $t19_post_command = 'post-command test' (elem) $stdout;
        ok $t19_post_command, '[Template6] post_command via config';
    }
}, 'Rendering [tt]';

subtest {
    
    my $source_root = $test_root.IO.child('example_project_tt');
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
    ok $tmp_build_path.IO.child('ja').child('related.html').e, '[Template6] i18n language for non-default languages (scheme: directory)';

}, 'Rendering i18n scheme directory [tt]';

done-testing;

# vim: ft=perl6
