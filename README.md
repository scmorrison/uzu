Uzu (渦)
===

Simple static site generator with built-in web server and file-modification change detector.

Installation
============

Install `Perl 6` using the following process:

1. Install `rakudobrew`

    ```bash
    git clone https://github.com/tadzik/rakudobrew ~/.rakudobrew
    export PATH=~/.rakudobrew/bin:$PATH
    rakudobrew init # Instructions for permanent installation.
    ```

2. Run `rakudobrew init` and follow instructions / output

    It should be something similar to this, changing the username `sam` to your own username:

    ```bash
    echo 'eval "$(/home/sam/.rakudobrew/bin/rakudobrew init -)"' >> ~/.profile
    ```

3. Install latest `Perl 6` and `panda`. 

    Note: This will take about ~5-10 minutes to compile

    ```bash
    rakudobrew build moar 2016.06
    rakudobrew build panda
    ```

4. Install Bailador

    ```
    cd src/
    git clone https://github.com/ufobat/Bailador.git
    cd Bailador/
    panda --notests install .
    ```

6. Clone the repository locally 

    ```
    git clone https://gitlab.com/samcns/uzu.git
    ```

6. Install project requirements

    ```
    cd uzu/
    panda -force install .
    ```

Todo
====

* Add tests
* Add build steps to build.pl6
* Uglify JS / CSS
* Build deploy process push to S3

Requirements
============

* [Perl 6](http://perl6.org/)

AUTHORS
=======

* [Sam Morrison](@samcns)
