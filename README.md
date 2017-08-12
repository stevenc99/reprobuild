# repro-build.pl

## How to use

Install dependencies:  libdpkg-perl libwww-mechanize-perl sbuild

Create a non-privileged user in the sbuild group (e.g. "buildd")

Install repro-build.pl and sbuild.sh into that user's home directory
(e.g. "/home/buildd")

Usage:

    repro-build.pl <buildinfo>

## Known issues

  * cannot handle the .buildinfo of binNMUs

  * cannot handle signed .buildinfo files (allow\_pgp has no effect),
    so remove it first with:

        gpg -d -o outfile infile

  * lack of robustness to error conditions (e.g. network issues)
