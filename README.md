Uzu (渦) [![build status](https://travis-ci.org/scmorrison/uzu.svg?branch=master)](https://travis-ci.org/scmorrison/uzu)
===

Uzu is a static site generator with built-in web server, file modification watcher, live reload, i18n, themes, and multi-page support.

- [Features](#features)
- [Usage](#usage)
- [Config](#config)
- [Project folder structure (Template6)](#project-folder-structure-template6)
- [Project folder structure (Mustache)](#project-folder-structure-mustache)
- [i18n YAML and Templating](#i18n-yaml-and-templating)
  * [Nested i18n variable files](#nested-i18n-variable-files)
- [Template Features](#template-features)
  * [Template6](#template6)
    + [Examples](#examples-template6)
  * [Mustache](#mustache)
    + [Examples](#examples-mustache)
  * [Page variables](#page-variables)
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
* **Auto Re-render**: `uzu watch` monitors the `theme/[your-theme]/layout/`, `pages`, `partials/`, and `i18n/` folders for modifications and auto-renders to build
* **Live reload**: `uzu watch` automatically reloads the browser when a re-render occurs
* **Templating**: Supports [Template6](#template6) and [Mustache](#mustache) template engines.
* **i18n support**: Use YAML to define each language in the `i18n/` folder (e.g. `i18n/en.yml`)
* **Page / layout support**: Generate individual pages wrapped in the same theme layout
* **Trigger rebuild manually**: Press `r enter` to initiate a full rebuild. This is useful for when you add new files or modify files that are not actively monitored by `uzu`, e.g. images, css, fonts, or any non `.tt`, `.ms`, `.mustache`, or `.yml` files
* **Actively developed**: More features coming soon (e.g. more tests, AWS, Github Pages, SSH support...)

**Note**: Uzu is a work in progress. It is functional and does a bunch of cool stuff, but it isn't perfect. Please post any [issues](https://github.com/scmorrison/uzu/issues) you find.

Usage
=====

```
Usage:
  uzu init          - Initialize new project
  uzu webserver     - Start local web server
  uzu build         - Render all templates to build
  uzu watch         - Start web server and re-render
                      build on template modification
  uzu version       - Print uzu version and exit

Optional arguments:
  
  --config=         - Specify a custom config file
                      Default is `config`

  e.g. uzu --config=path/to/config.yml init 

  --no-livereload   - Disable livereload when
                      running uzu watch.
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

# Themes are stored in themes/[theme-name]
theme: default

# Optional parameters (also, comments like this are ok)

# Use a custom dev server port, default is 3000
port: 4040

# Specify a custom project root path
# default is .
project_root: path/to/project/folder

#
# Non-core variables
#

url: https://github.com/scmorrison/uzu-starter
author: Sam Morrison

```

### Core variables

Core variables are dynamically set by `uzu` or defined / overridden in `config.yml`:

* `name`: Project name
* `language`: List of languages to render for site. First item is default language. When rendering, the `language` variable is set to the current rendering language and can be referenced in templates. For example, if `uzu` is rendering an `en` version of a page, then the `language` variable will be set to `en`.
* `theme`: The theme to apply to the layout (themes/themename). `default` refers to the folder named `default` in the themes folder.
* `host`: Host IP for the dev server. Defaults to `127.0.0.1`.
* `port`: Host TCP port for dev server. Defaults to `3000`.
* `project_root`: Project root folder. Defaults to `.`.

### Accessing core variables in templates

Core variables can be accessed from inside templates directly (e.g. `port`, `theme`, etc.)

### Accessing non-core variables in templates

Non-core varibles are any additional variables found in config.yml and can be accessed in templates using `site.variablename` (e.g. `site.url`, `site.author`).

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
            └── en.yml
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
        └── layout                # Theme layout file
            └── layout.tt
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
            └── en.yml
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
        └── layout                # Theme layout file
            └── layout.mustache
```
See [uzu-starter](https://github.com/scmorrison/uzu-starter) for a full example.

i18n YAML and Templating
=========

You can separate out the content text to YAML files located in a project-root folder called `i18n`. Simply create a separate file for each language, like this:

```
─ i18n
  ├── blog
  │   └── vacation     # Page specific i18n variables
  │       ├── en.yml   # en i18n variables for page pages/blog/vacation.tt
          └── ja.yml   # ja i18n variables for page pages/blog/vacation.tt
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

### Including partials 

Partials are stored in the `partials` directory. You can include these in layouts and pages.

```html
<!doctype html>
<html lang="[% language %]">
[% INCLUDE "head" %]
    <body>
      [% INCLUDE "navigation" %]
      [% content %]
      [% INCLUDE "footer" %]
    </body>
</html>
```

## Mustache

Uzu also supports the [Mustache](http://mustache.github.io/) templating format for template files. 

Enable mustache support by adding the following line to your `config.yaml`:

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
{{ #founders }}
  <li>{{ name }}, {{ title }}</a>
{{ /founders }}
</ul>
```

### If conditionals

Mustache is a 'logic-less' templating system, but you can test for the existence of a variable, and if it exists then anything inside the test block with be processed. Otherwise it is ignored.

```html
{{ #site.graphics }}
    <img src="{{ images }}/logo.gif" align=right width=60 height=40>
{{ /site.graphics }}
```

### Including partials

Partials are stored in the `partials` directory. You can include these in layouts and pages.

```html
<!doctype html>
<html lang="{{ language }}">
{{> head }}
    <body>
      {{> navigation }}
      {{ content }}
      {{> footer }}
    </body>
</html>
```

### Page variables

You can define page-specific variables using a yaml block at the top of any page (`pages/`):

`pages/index.tt`

```html
---
title: 'Welcome to Uzu'
date:  '2017/07/16'
---
```

To access these variables inside of a template you do not need to use the `i18n.` scope prefix.

For `Template6`:

`partials/head.tt`

```html
<head>
    <meta charset="utf-8">
    <title>[% title %] - [% date %]</title>
</head>
```

...and for `Mustache`:

`partials/head.mustache`

```html
<head>
    <meta charset="utf-8">
    <title>{{ title }} - {{ date }}</title>
</head>
```

Installation
============

```
zef install Uzu
```
Installation issue? See [Troubleshooting](#troubleshooting).

Todo
====

* Add tests
* Add build steps to build.pl6
* Uglify JS / CSS
* Build deploy process push to S3
* Features
  * Posts for blogs
  * Additional templating support (mustache, markdown)
  * Nested directory support for pages / i18n variables
  * Dynamic variables (tags, pagination) 

Requirements
============

* [Perl 6](http://perl6.org/)

Troubleshooting
===============

* **Errors installing from previous version:**
  
  Remove the zef tmp / store uzu.git directories:

  ```
  # Delete these folders from your zef install 
  # directory.
  rm -rf ~/.zef/store/uzu.git ~/.zef/tmp/uzu.git 
  ```

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
