Uzu (渦) [![build status](https://gitlab.com/samcns/uzu/badges/master/build.svg)](https://gitlab.com/samcns/uzu/commits/master)
===

Uzu is a static site generator with built-in web server, file modification watcher, i18n, themes, and multi-page support.

Features
========
* **Easy to use**: Based on existing static site generator conventions
* **Built-in development webserver**: Test your modifications (http://localhost:3000) as you work
* **Auto Re-render**: `uzu watch` monitors the `theme/[your-theme]/layout/`, `pages`, `partials/`, and `i18n/` folders for modifications and auto-renders to build
* **i18n support**: Use YAML to define each language in the `i18n/` folder (e.g. `i18n/en.yml`)
* **Page / layout support**: Generate individual pages wrapped in the same theme layout
* **Actively developed**: More features coming soon (e.g. more tests, AWS, Github Pages, SSH support...)

**Note**: Uzu is a work in progress. It is functional and does a bunch of cool stuff, but it isn't perfect. Please post any [issues](https://gitlab.com/samcns/uzu/issues) you find.

Usage
=====

```
Usage:
  uzu init       - Initialize new project
  uzu webserver  - Start local web server
  uzu build      - Render all templates to build
  uzu watch      - Start web server and re-render
                   build on template modification
  uzu version    - Print uzu version and exit

Optional arguments:
  
  --config=      - Specify a custom config file
                   Default: `config`

  e.g. uzu --config=path/to/config init
```

Config
======

Each project has its own `config.yml` which uses the following format:

```yaml
---
# Name of the project
name: uzu-starter

# Language to use, determines which
# i18n/*.yml file to use for string variables
language: en

# Themes are stored in themes/[theme-name]
theme: default

# Site URL
url: https://gitlab.com/samcns/uzu-starter

# Optional parameters (also, comments like this are ok)

# Use a custom dev server port, default is 3000
port: 4040

# Specify a custom project root path
# default is .
project_root: path/to/project/folder
```

Project folder structure
========================
```
├── config.yml
├── pages
│   ├── about.mustache
│   └── index.mustache
├── partials
│   ├── footer.mustache
│   ├── head.mustache
│   ├── home.mustache
│   ├── jumbotron.mustache
│   ├── navigation.mustache
│   └── profiles.mustache
├── i18n
│   ├── en.yml
│   ├── fr.yml
│   ├── ja.yml
└── themes
    └── default
        ├── assets
        │   ├── css
        │   ├── favicon.ico
        │   ├── fonts
        │   ├── img
        │   ├── js
        └── layout
            └── layout.mustache
```

See [uzu-starter](https://gitlab.com/samcns/uzu-starter) for a full example.

i18n YAML and Templating
=========

You can separate out the content text to YAML files located in a project-root folder called `i18n`. Simply create a separate file for each language, like this:

```
─ i18n
  ├── en.yml
  ├── fr.yml
  ├── ja.yml
  └── ja.yml
```

An example YAML file might look like this:
```yaml
---
site_name: The Uzu Project Site
url: https://gitlab.com/samcns/uzu-starter
founders:
  - name: Sam
    title: "Dish Washer"
  - name: Elly
    title: CEO
  - name: Tomo
    title: CFO
```

Template Features
=================

Uzu uses the [Template Toolkit](http://template-toolkit.org/) templating format for template files.

## Features include:

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

## Examples

### Single variable

```html
<a class="navbar-brand" href="/">[% site_name %]</a>
```

### For loop
```html
<h1>Company Founders</h1>
<ul>
[% for founder in founders %]
  <li>[% founder.name %], [% founder.title %]</a>
[% end %]
</ul>
```

### IF/ELSEIF/UNLESS
```html
[% if graphics %]
    <img src="[% images %]/logo.gif" align=right width=60 height=40>
[% end %]
```

### Including partials
```html
<!doctype html>
<html lang="[% language %]">
[% INCLUDE "head %]
    <body>
			[% INCLUDE "navigation %]
			[% content %]
			[% INCLUDE "footer %]
			</div>
    </body>
</html>
```

Installation
============

```
panda install Uzu
```

Todo
====

* Add tests
* Add build steps to build.pl6
* Uglify JS / CSS
* Build deploy process push to S3
* Features
  * Posts for blogs

Requirements
============

* [Perl 6](http://perl6.org/)

AUTHORS
=======

[Sam Morrison](@samcns)

SEE ALSO
========

* Templating engine used in `uzu`: [Template6](https://github.com/supernovus/template6)
