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

## Roadmap

Use fewer snapshots:  adding 100+ APT sources is way too slow for
serious use.  Sometimes only one or two snapshots are needed to satisfy
the entire set of Installed-Build-Depends.


Paul Gevers pointed out to me that package downgrades are not a
supported feature;  it may not produce the same environment as if a
fresh chroot was debootstrapped.

So to rebuild old packages, it may be better to debootstrap a fresh
chroot, based on a snapshot of sid from the time of the source package
upload (SOURCE\_DATE\_EPOCH);  and then only update some packages, as
needed.

For newly-uploaded packages, a (cached) debootstrap of sid should
already be sufficient however.


Another idea is to fetch the required .deb files to a local repository,
individually.  The resulting repository would be smaller and much faster
to index;  but we'd need some other way to verify integrity of the
.deb files.


Hector Oron suggested merging my sbuild hooks into sbuild itself so that
my external tool is simpler or even no longer necessary.  Or:  look into
Open Build Service to find across-platform solution.
