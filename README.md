Uzu (渦) [![build status](https://travis-ci.org/scmorrison/uzu.svg?branch=master)](https://travis-ci.org/scmorrison/uzu)
===

Uzu is a static site generator with built-in web server, file modification watcher, live reload, i18n, themes, multi-page support, inject external data via local Raku module, and external pre/post command execution.

**Note:** Uzu 0.3.6 and higher requires at least raku 2020.06.

- [Features](#features)
- [Getting started](#getting-started)
  * [Uzu Demo Site](#uzu-demo-site)
- [Usage](#usage)
- [Config](#config)
  * [Config variables](#config-variables)
- [Project folder structure (Template6)](#project-folder-structure-template6)
- [Project folder structure (Mustache)](#project-folder-structure-mustache)
- [Public and Assets directories](#public-and-assets-directories)
- [i18n YAML and Templating](#i18n-yaml-and-templating)
  * [Nested i18n variable files](#nested-i18n-variable-files)
  * [i18n output paths](#i18n-output-paths)
- [Template Features](#template-features)
  * [Template6](#template6)
    + [Examples](#examples-template6)
  * [Mustache](#mustache)
    + [Examples](#examples-mustache)
  * [Theme layouts](#theme-layouts)
  * [Partials](#partials)
  * [Global variables](#global-variables)
  * [Extended variables](#extended-variables)
  * [Template variables](#template-variables)
  * [Layout variables](#layout-variables)
  * [Related / linked pages](#related--linked-pages)
- [Page render conditions](#page-render-conditions)
- [Installation](#installation)
- [Todo](#todo)
- [Requirements](#requirements)
- [Troubleshooting](#troubleshooting)
- [Authors](#authors)
- [Contributors](#contributors)
- [License](#license)
- [See also](#see-also)

Features
========
* **Easy to use**: Based on existing static site generator conventions
* **Built-in development webserver**: Test your modifications (http://localhost:3000) as you work
* **Auto Re-render**: `uzu watch` monitors the `theme/[your-theme]/`, `pages/`, `partials/`, and `i18n/` folders for modifications and auto-renders to build
* **Live reload**: `uzu watch` automatically reloads the browser when a re-render occurs
* **Templating**: Supports [Template6](#template6) and [Mustache](#mustache) template engines.
* **i18n support**: Use YAML to define each language in the `i18n/` folder (e.g. `i18n/en.yml`)
* **Page / layout support**: Generate individual pages wrapped in the same theme layout
* **Extended variables**: Inject dynamically generated data into project via external `Raku` module.
* **Pre/Post commands**: Trigger external commands to execute before or after build. 
* **YAML variables**: Create page-specific and partial-specific variables as a [YAML block](#page-variables) at the top of any page or partial template.
* **Trigger rebuild manually**: Press `r enter` to initiate a full rebuild. This is useful for when you add new files or modify files that are not actively monitored by `uzu`, e.g. images, css, fonts, or any non `.tt`, `.mustache`, or `.yml` files
* **Actively developed**: More features coming soon (e.g. more tests, AWS, Github Pages, SSH support...)

**Note**: Uzu is a work in progress. It is functional and does a bunch of cool stuff, but it isn't perfect. Please post any [issues](https://github.com/scmorrison/uzu/issues) you find.

Getting started
===============

After [installing](#installation) uzu, run the following command from an empty directory:

```
uzu init
```

Enter your site name, default language, and template engine when prompted.

## Uzu Demo Site

@uzluisf has created an excellent [Uzu Demo Site](https://github.com/uzluisf/uzu-demo-site) that shows how a fully working Uzu project is organized / functions.

Usage
=====

```
Usage:
  uzu init          - Initialize new project
  uzu webserver     - Start local web server
  uzu build         - Render all templates to build
  uzu clear         - Delete build directory and all of its contents
  uzu watch         - Start web server and re-render
                      build on template modification
  uzu version       - Print uzu version and exit

Optional arguments:
  
  --config=         - Specify a custom config file
                      Default is `config`

  e.g. uzu --config=path/to/config.yml init 

  --no-livereload   - Disable livereload when
                      running uzu watch.

  --clear           - Delete build directory before 
                      render when running with build.

  --page-filter     - Restrict build to pages starting
                      from this directory

  --theme           - Limit build / watch to single theme

  e.g. uzu --theme=default build 
```

Config
======

Each project has its own `config.yml` which uses the following format:

```yaml
---
# 
# Core variables
#

# Name of the project
name: uzu-starter

# Languages to use, determines which
# i18n/*.yml file to use for string variables
#
# The first language in the list is considered
# the default language. The defualt language
# will render to non-suffixed files (e.g index.html).
# All other languages will render with the
# language as a file suffix (e.g index-fr.html,
# index-ja.html). This will be overridable in
# future releases.

language:
  - en
  - ja
  - fr

# i18n scheme (default: suffix)
i18n_scheme: 'directory' # Render non-default languages to /[lang]/[page name].[extension]

# Template engine
# - Template6: tt
# - Mustache: mustache
template_engine: mustache

# Stored theme directories under themes/[theme-name]
#
# Themes can be specified with either the single theme
# variable:
theme: default

# .. or multiple themes:
themes:
  - default              # Specify a theme directory using the default options
  - summer2017:          
      build_dir: web2017 # Override build director
      port: 4333         # Port to start watch on for this theme.
      exclude_pages:     # List of page template names to ignore for this theme
        - index

# Optional parameters (also, comments like this are ok)

# Use a custom dev server port, default is 3000
port: 4040

# Specify a custom project root path
# default is .
project_root: path/to/project/folder

# List of page template names to ignore for all themes
exclude_pages:
  - about
  - blog/fiji-scratch

# List of directories and files to exclude from build/
exclude:
  - node_modules
  - packages.json
  - yarn.lock

# Pre / post build commands
pre_command: "webpack"
post_command: "echo 'post-build command'"

# Omit .html extension from generated HTML files
omit_html_ext: true
```

### Config variables

Config variables are defined in `config.yml`:

* `name`: Project name
* `language`: List of languages to render for site. First item is default language. When rendering, the `language` variable is set to the current rendering language and can be referenced in templates. For example, if `uzu` is rendering an `en` version of a page, then the `language` variable will be set to `en`.

* `i18n_scheme`: By default `uzu` will generate files with the language suffix appended for non-default language output. (e.g. `fr`: `index-fr`). This behaviour can be set to 'directory' witch will render non-default languages to `/[lang]/[page name].[extension]` (e.g. `fr`: `/fr/index.html`).
* `theme`: The theme to apply to the layout (themes/themename). `default` refers to the folder named `default` in the themes folder.
* `themes`: Alternatively, using the `themes` yaml hash supports multiple themes. Themes will be rendered at the same time into their target build directories. By default the theme build directory is `build/[theme-name]`. This can be overridden with the `build_dir` variable. Relative and absolute paths are supported:
  * `build_dir`: 
     ```yaml
     themes:
       - summer2017:
           build_dir: web2017
     ```
  * `port`: A dev web server will spawn for rach theme specified in the `themes` yaml dict. The default port for the first theme is `3000`, this port number is incremented by one for every subsequent theme listed in the `themes` dict. This variable will override that behavior.
     ```yaml
     themes:
       - summer2017:
           port: 4444
     ```
  * `exclude_pages`: List page templates that should not be rendered for the associated theme. 
     ```yaml
     themes:
       - summer2017:
           exclude_pages:
             - about
             - blog/fiji
             - sitemap.xml
     ```
* `exclude`: List of directories and files to exclude from `build/`
   ```yaml
   exclude:
     - node_modules
     - packages.json
     - yarn.lock
   ```
* `pre_command`: Run command prior to build step
* `post_command`: Run command after to build step
* `host`: Host IP for the dev server. Defaults to `127.0.0.1`.
* `port`: Host TCP port for dev server. Defaults to `3000`.
* `project_root`: Project root folder. Defaults to `.`.
* `omit_html_ext`: Omit `.html` from generated HTML files.

### Accessing config variables in templates

Config variables can be accessed from inside templates directly (e.g. `port`, `theme`, etc.)

### Accessing non-core variables in templates

Non-core variables are any additional variables found in config.yml and can be accessed in templates using `site.variablename` (e.g. `site.url`, `site.author`).

Project folder structure (Template6)
========================
```
├── config.yml                    # Uzu config file
├── pages                         # Each page becomes a .html file
│   ├── about.tt
│   ├── index.tt
│   └── blog                      # Pages can be nested in sub-folders. Their URI
│       └── vacation.tt           # will follow the same path (e.g. /blog/vacation.html)
│
├── partials                      # Partials can be included in pages
│   ├── footer.tt                 # and theme layouts
│   ├── head.tt
│   ├── home.tt
│   ├── jumbotron.tt
│   ├── navigation.tt
│   └── profiles.tt
├── public                        # Static files / assets independant of theme (copied to /)
├── i18n                          # Language translation files
│   └── blog
│       └── vacation              # i18n variables can be defined for specific pages
│           └── en.yml
│   ├── en.yml
│   ├── fr.yml
│   ├── ja.yml
└── themes                        # Project themes
    └── default
        ├── assets                # Theme specific static files / assets (copied to /)
        │   ├── css
        │   ├── favicon.ico
        │   ├── fonts
        │   ├── img
        │   ├── js
        ├── partials              # Theme specific partials. These will override any top-level
        │   ├── footer.tt         # partials with the same file name.
        └── layout.tt             # Theme layout file
```

Project folder structure (Mustache)
========================
```
├── config.yml                    # Uzu config file
├── pages                         # Each page becomes a .html file
│   ├── about.mustache
│   ├── index.mustache
│   └── blog                      # Pages can be nested in sub-folders. Their URI
│       └── vacation.mustache     # will follow the same path (e.g. /blog/vacation.html)
│
├── partials                      # Partials can be included in pages
│   ├── footer.mustache           # and theme layouts
│   ├── head.mustache
│   ├── home.mustache
│   ├── jumbotron.mustache
│   ├── navigation.mustache
│   └── profiles.mustache
├── public                        # Static files / assets independant of theme (copied to /)
├── i18n                          # Language translation files
│   └── blog
│       └── vacation              # i18n variables can be defined for specific pages
│           └── en.yml
│   ├── en.yml
│   ├── fr.yml
│   ├── ja.yml
└── themes                        # Project themes
    └── default
        ├── assets                # Theme specific static files / assets (copied to /)
        │   ├── css
        │   ├── favicon.ico
        │   ├── fonts
        │   ├── img
        │   ├── js
        ├── partials              # Theme specific partials. These will override any top-level
        │   ├── footer.tt         # partials with the same file name.
        └── layout.mustache       # Theme layout file
```
See [uzu-starter](https://github.com/scmorrison/uzu-starter) for a full example.

# Public and Assets directories

* `public/` - The root public directory is where project-wide static assets are stored.
* `themes/**/assets/` - The theme's assets directory is where theme-specific static assets are stored.

Files found in either of these directories are copied wholesale to the root of the `build/` directory on successful build. For example:

* `public/js/site.js` will be copied to `build/js/site.js`
* `themes/default/assets/img/logo.png` will be copied to `build/img/logo.png`

**Note:** Any tmp / swp files created by editors will also be copied into `build/`. Most editors provide options to configure this behavior. For example, you can have all `vim` `.swp` files saved into a central directory by adding something like this to `~/.vimrc`:

```
set backupdir=~/.vim/backup//
set directory=~/.vim/swp//
```

# i18n YAML and Templating

You can separate out the content text to YAML files located in a project-root folder called `i18n`. Simply create a separate file for each language, like this:

```
─ i18n
  ├── blog
  │   └── vacation     # Page specific i18n variables
  │       ├── en.yml   # en i18n variables for page pages/blog/vacation.tt
  │       └── ja.yml   # ja i18n variables for page pages/blog/vacation.tt
  ├── en.yml           # Main en i18n variables
  ├── fr.yml           # Main fr i18n variables
  └── ja.yml           # Main ja i18n variables
```

An example i18n YAML file might look like this:
```yaml
---
# Template access i18n.site_name
site_name: The Uzu Project Site

# Template access i18n.url
url: https://github.com/scmorrison/uzu-starter

# Template access i18n.founders
founders:
  - name: Sam
    title: "Dish Washer"
  - name: Elly
    title: CEO
  - name: Tomo
    title: CFO

# Comments start with a #

# Do not use blank values
this_will_break_things:
do_this_instead: ""
```

### Accessing i18n variables in templates

Variables defined in i18n files can be accessed in templates using the `i18n.variablename` format (e.g. `i18n.site_name`, `i18n.founders`). 

```html
<h1>[% i18n.site_name %]</h1>
```

#### Nested i18n variable files

Any variables defined in page specific i18n files, e.g. `i18n/blog/vacation/en.yml`, will override any top-level language i18n file (e.g `i18n/en.yml`) defined variables that share the same name. For example:

```
# i18n/en.yml
site_name: Uzu Starter Project
```

...will be overridden by:

```
# i18n/blog/vacation/en.yml
site_name: "Our Vacation 2017"
```

## i18n output paths

By default `uzu` generates language specific files with the following pattern:

`[page name]-[language code].html`

For example, if the default language is `en` and secondary language is `ja`, the `index` page template would be rendered to the following files:

* Default language: `build/index.html`
* Subsequent languages: `build/index-ja.html`

This output behavior can be changed to `directory` in `config.yml` with the `i18n_scheme` variable:

```yaml
i18n_scheme: 'directory'
```

With this option set, the output will be rendered to the following files:

* Default language: `build/index.html`
* Subsequent languages: `build/ja/index.html`

Template Features
=================

## Template6

Uzu supports the [Template Toolkit](http://template-toolkit.org/) templating format for template files. This is the default template engine.

### Features include:

* GET and SET statements, including implicit versions

     * [% get varname %]
     * [% varname %]
     * [% set varname = value %]
     * [% varname = value %]

* FOR statement

     * [% for names as name %]
     * [% for names -> name %]
     * [% for name in names %]
     * [% for name = names %]

     If used with Hashes, you'll need to query the .key or .value accessors.

* IF/ELSIF/ELSE/UNLESS statements.

     * [% if display_links %]
         -- do this ---
       [% else %]

         -- do that --

       [% end %]

     * [% unless graphics %]

         -- some html ---

       [% end %]

* Querying nested data structures using a simple dot operator syntax.
* CALL and DEFAULT statements.
* INSERT, INCLUDE and PROCESS statements.

### Examples (Template6)

### Single i18n variable

```html
<a class="navbar-brand" href="/">[% i18n.site_name %]</a>
```

### For loop from yaml dict (non-core variable) defined in config.yml
```html
<h1>Company Founders</h1>
<ul>
[% for founder in site.founders %]
  <li>[% founder.name %], [% founder.title %]</a>
[% end %]
</ul>
```

### IF/ELSEIF/UNLESS
```html
[% if site.graphics %]
    <img src="[% images %]/logo.gif" align=right width=60 height=40>
[% end %]
```

## Mustache

Uzu also supports the [Mustache](http://mustache.github.io/) templating format for template files. 

Enable mustache support by adding the following line to your `config.yml`:

`template_engine: mustache`

For example:

```yaml
---
name: mysite
language:
  - en
theme: default
template_engine: mustache
```

### Examples (Mustache)

### Single i18n variable

```html
<a class="navbar-brand" href="/">{{ i18n.site_name }}</a>
```

### For loop from yaml dict (non-core variable) defined in config.yml
```html
<h1>Company Founders</h1>
<ul>
{{#founders}}
  <li>{{ name }}, {{ title }}</a>
{{/founders}}
</ul>
```

### If conditionals

Mustache is a 'logic-less' templating system, but you can test for the existence of a variable, and if it exists then anything inside the test block with be processed. Otherwise it is ignored.

```html
{{#site.graphics}}
    <img src="{{ images }}/logo.gif" align=right width=60 height=40>
{{/site.graphics}}
```

## Theme layouts

Theme layout templates are located at the `themes/THEME_NAME/layout.tt` or `themes/THEME_NAME/layout.mustache`. Use the `content` partial to include rendered page content in a layout.

For `Template6`:

```html
<!doctype html>
<html lang="[% language %]">
[% INCLUDE "head" %]
    <body>
      [% INCLUDE "navigation" %]
      <!-- Rendered page content -->
      [% INCLUDE "content" %]
      [% INCLUDE "footer" %]
    </body>
</html>
```

For `Mustache`:

```html
<!doctype html>
<html lang="{{ language }}">
{{> head }}
    <body>
      {{> navigation }}
      <!-- Rendered page content -->
      {{> content }}
      {{> footer }}
    </body>
</html>
```

## Partials 

Partials are stored in the `partials` and `themes/THEME_NAME/partials` directories. Any theme partial will override any partial found in the top-level `partials` directory with the same file name. Partials can be include in layouts, pages, and other partials.

For `Template6`:

```html
[% INCLUDE "navigation" %]
<div>
    [% INCLUDE "login_form" %]
</div>
```

For `Mustache`:

```html
{{> navigation }}
<div>
    {{> login_form }}
</div>
```

## Global variables

Some variables are generated dynamically and exposed to templates for use:

* **language**: The current language as a string (e.g. `en`, `ja`, etc.)
* **lang_**: The `lang_CURRENT_LANG` variable provides the current rendering language. This is useful if you want to display certain content depending on the i18n language.
    
    For `Template6`:

    ```html
    [% if lang_en %]
    <a href='/index-ja.html'>日本語</a>
    [% end %]
    [% if lang_ja %]
    <a href='/'>English</a>
    [% end %]

    ```

    For `Mustache`:

    ```html
    {{#lang_en}}
    <a href='/index-ja.html'>日本語</a>
    {{/lang_en}}
    {{#lang_ja}}
    <a href='/'>English</a>
    {{/lang_ja}}
    ```


* **theme_**: The current theme is exposed to the templates as `theme_NAME_OF_THEM`. For example, the variable `theme_default` will be available if the `default` theme is being used:

    For `Template6`:

    ```html
    [% if theme_default %]
    [% INCLUDE "default_header" %]
    [% end %]

    [% if theme_enoshima %]
    [% INCLUDE "enoshima_header" %]
    [% end %]
    ```

    For `Mustache`:

    ```html
    {{#theme_default}}
    {{> default_header }}
    {{/theme_default}}

    {{#theme_enoshima}}
    {{> enoshima_header }}
    {{/theme_enoshima}}
    ```


* **randnum**: A dynamically generated 16 digit integer. This value is generated any time a page is generated / regenerated.
    ```html
    <link rel="stylesheet" type="text/css" href="/css/site.css?v=[% randnum %]">
    ```
* **dt**: A date hash that includes common date values. This is a dynamic variable that contains `datetime` data for current build.
    ```html
    <span>&copy;[% dt.year %] Uzu, Inc.</span>

    ```
    Available `dt` values:

    * dt.hour
    * dt.minute
    * dt.second
    * dt.day
    * dt.month
    * dt.year
    * dt.hh-mm-ss
    * dt.utc
    * dt.day-of-month
    * dt.day-of-week
    * dt.weekday-of-month
    * dt.is-leap-year
    * dt.day-of-year
    * dt.week-year
    * dt.daycount
    * dt.week-number
    * dt.days-in-month
    * dt.week
    * dt.yyyy-mm-dd
    * dt.timezone

### Extended variables

Uzu can be extended with external / dynamically generated data provided via a local `Raku` module.

In order to inject external data into your project you must use the `PERL6LIB` environment variable when running `uzu`:

```
PERL6LIB=lib uzu watch
```

Create your module, for example `MyApp`, in your `uzu` project directory under `lib` (e.g. `lib/MyApp.pm6`). The app must export a subroutine named `context()`. This is `uzu`'s entry point:

```raku
# lib/MyApp.pm6

unit module MyApp;

our sub context(--> Hash) {
    return %{
        number_of_products => get-remote-product-count(),
        favorite_food      => 'Bean Burrito',
    }
}
```

Add the name of your `Raku` module to your config as `extended` (do not add the module file extension):

```yaml
extended: 'MyApp'
```

When `uzu` starts it will attempt to load the local module and inject the `Hash` returned by `context()` into the global render context Hash. The keys defined in the injected Hash will be available from within templates.

```html
<span>Total Products: [% number_of_products %]</span>
```

If `&MyApp::context()` is unavailable, `uzu` will print a message indicating that `MyApp` or `&MyApp::context()` could not be loaded.

The external module will be executed on every build by default. To disable this behavior while using the local dev server (`uzu watch`) set the config variable `refresh_extended` to `false` in your config.yml:

```yaml
refresh_extended: false
```

### Template variables

You can define variables using a yaml block at the top of any page or partial (`pages/`, `partials/`):

`pages/index.tt`

```html
---
title: 'Welcome to Uzu'
subtitle:  'The best'
---
```

To access these variables inside of a template you do not need to use the `i18n.` scope prefix.

For `Template6`:

`partials/head.tt`

```html
<head>
    <meta charset="utf-8">
    <title>[% title %] - [% subtitle %]</title>
</head>
```

...and for `Mustache`:

`partials/head.mustache`

```html
<head>
    <meta charset="utf-8">
    <title>{{ title }} - {{ subtitle }}</title>
</head>
```

### Layout variables

You can define variables in the layout template and access them using the `layout.` prefix in templates;

For example:

Define yaml definitions in `themes/**/layout.tt` or `themes/**/layout.mustache`:

```
---
root_url: https://www.raku.org
name: Dark Theme
---
<!doctype html>
<html>
...
```

Will be accessible in templates like this:

For `Template6`:

```
<a href="[% layout.root_url %]/about-this-theme.html">[% layout.name %]</a>
```

...and for `Mustache`:

```
<a href="{{ layout.root_url }}/about-this-theme.html">{{ layout.name }}</a>
```

### Related / linked pages

Uzu will append any yaml dict ending with `_pages` with additional page-related variables if the variables are defined in the associated page template.

For `Template6`:

```html
---
related_pages:
    - page: about
    - page: blog/fiji
    - page: https://www.raku.org
      title: The Raku Programming Language
      author: Raku
---
<ul>
[% for rp in related_pages %]
    <li>
        <a href="[% rp.url %]">[% rp.title %]</a> [[% rp.author %]]
    </li>
[% end %]
</ul>
```

...and for `Mustache`:

```html
<ul>
{{#related_pages}}
    <li>
        <a href="{{ url }}">{{ title }}</a> [{{ author }}]
    </li>
{{/related_pages}}
</ul>
```

The above produces the following HTML. Note that the `author` and `title` values are pulled from the related page's template yaml variables: 

```html
<ul>
    <li>
        <a href="/about.html">About Us</a> [Camelia]
    </li>
    <li>
        <a href="/blog/fiji.html">Fiji Vacation</a> [Camelia]
    </li>
    <li>
        <a href="https://www.raku.org">The Raku Programming Language</a> [Raku]
    </li>
</ul>
```

### Disable layout rendering for page template

To disable layout rendering for specific pages add the `nolayout` variable to the page's yaml variables:

```yaml
---
nolayout: true
---
```

# Page render conditions

In order to reduce build times Uzu will try to avoid rerendering a page if it hasn't been modified.

Pages will only be rendered under the following conditions:

* Rendered page does not exist in `build` directory
* The page template has been modified
* A partial file included in the layout, page, or any partial included in the page has been modified
* The page includes a related / linked pages `_pages` yaml dict and one of the linked pages templates has been modified
* Running `uzu --clear build` will rebuild all pages
* Pressing `c enter` while running `uzu watch` will rebuild all pages

Installation
============

```
zef install Uzu
```
Installation issue? See [Troubleshooting](#troubleshooting).

Todo
====

* More tests
* Uglify JS / CSS
* Build deploy process push to remote services
* Features
  * Additional templating support (markdown)
  * Dynamic variables (categories, tags, pagination) 

Requirements
============

* [Raku](http://raku.org/)

Troubleshooting
===============

* **Errors installing from previous version:**
  
  Remove the zef tmp / store uzu.git directories:

  ```
  # Delete these folders from your zef install 
  # directory.
  rm -rf ~/.zef/store/uzu.git ~/.zef/tmp/uzu.git 
  ```

  In some instances it might help to delete your local `~/.raku/precomp` directory. 

* **Tests failing during install**

Sometimes tests might fail during install. Try re-installing all of the dependencies via `zef`:

```
zef install --force-install --/test \
    File::Directory::Tree \
    File::Find File::Temp \
    Terminal::ANSIColor \
    Template6 \
    Template::Mustache \
    Test::Output \
    HTTP::Parser \
    HTTP::Server::Tiny \
    YAMLish;
```

In some instances it might help to delete your local `~/.raku/precomp` directory. 

If installing from source, remove the `lib/.precomp` folder inside the `uzu` root folder and attempt the install again.

Authors
=======

* [Sam Morrison](@samcns)

Contributors
============

* [ab5tract ](@ab5tract)


License
=======

Uzu is free software; you can redistribute it and/or modify it under the terms of the Artistic License 2.0. (Note that, unlike the Artistic License 1.0, version 2.0 is GPL compatible by itself, hence there is no benefit to having an Artistic 2.0 / GPL disjunction.) See the file LICENSE for details.

See also
========

* [Template6](https://github.com/supernovus/template6)
* [Mustache](https://github.com/softmoth/p6-Template-Mustache/)
