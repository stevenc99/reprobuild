#!/usr/bin/perl -w

use WWW::Mechanize;
use LWP::ConnCache;

my $mech = WWW::Mechanize->new();
$mech->conn_cache(LWP::ConnCache->new);
	
sub lookup_snapshot {
	my $pkg  = shift;
	my $vers = shift;
	my $arch = shift;

	my ($search_uri, $text_regex, $link);

	if ($arch eq "source") {
		$search_uri = "http://snapshot.debian.org/package/$pkg/";
	} else {
		$search_uri = "http://snapshot.debian.org/binary/$pkg/";
	}
	warn "* Querying $search_uri...\n";
	$mech->get( $search_uri );
	
	$text_regex = qr/^\Q$vers\E( |$)/;
	$link = $mech->find_link( text_regex => $text_regex );
	if (!defined $link) {
		warn "$text_regex not found on page!";
		return undef;
	}

	$search_uri = $link->url_abs();
	warn "* Querying $search_uri...\n";
	$search_uri =~ s/#.*$//;	# Disregard anchors in URI
	$mech->get( $search_uri );
	
	$vers =~ s/^[0-9]+://;		# Disregard version epoch
	if ($arch eq "source") {
		$text_regex = qr/^\Q$pkg\E\_\Q$vers\E\.dsc$/;
	} else {
		$text_regex = qr/^\Q$pkg\E\_\Q$vers\E\_(all|$arch)\.deb$/;
	}

	$link = $mech->find_link( text_regex => $text_regex );
	if (!defined $link) {
		warn "$text_regex not found on page!";
		return undef;
	}
	$repo_uri = $link->url_abs();
	$repo_uri =~ qr#^(https?://[^ ]+/)pool/.*$#;
	
	if ($arch eq "source") {
		return "deb-src $1 sid main";
	} else {
		return "deb $1 sid main";
	}
}

use Dpkg::Control::Info;
use Dpkg::Deps;

my $exit_status;

if (!defined $ARGV[0] or !stat $ARGV[0]) {
	warn "Usage: $0 <buildinfo>\n";
	exit 1;
}

my $buildinfo = Dpkg::Control::Info->new(
	filename => $ARGV[0]
);
my $fields = $buildinfo->get_source();
my $installed_build_depends = deps_parse(
	$fields->{'Installed-Build-Depends'},
	union => 1
);

my $build_user = 'sbuild';
my $build_path = $fields->{'Build-Path'};

my $pkg = $fields->{'Source'};
my $vers = $fields->{'Version'};

my $arch = `dpkg-architecture -qDEB_HOST_ARCH`;
chomp $arch;

my @cmd_update  = qw(apt-get update);
my @cmd_install = qw(apt-get -y install);

my $sources_list = "/etc/apt/sources.list.d/repro-build-env.list";
unlink $sources_list;

# Sanity check
warn "* Executing @cmd_update\n";
$exit_status = system(@cmd_update);
exit if ($exit_status != 0);

open (my $outfile, '>', $sources_list) or die $!;

# Find snapshot containing the source we want to build
my $apt_src_source = lookup_snapshot($pkg, $vers, 'source');
if (!defined $apt_src_source) {
	warn "Failed to find apt source for src:$pkg=$vers";
}
print $outfile "# Source of $pkg=$vers\n";
print $outfile "$apt_src_source\n" or die $!;

# Find snapshots containing build-dependencies
my @deps = $installed_build_depends->get_deps();
foreach (@deps) {
	my $pkg  = $_->{package};
	my $vers = $_->{version};

	my $apt_source = lookup_snapshot($pkg, $vers, $arch);
	if (defined $apt_source) {
		print $outfile "# Added for $pkg=$vers\n";
		print $outfile "$apt_source\n" or die $!;
	}

	push @cmd_install, "$pkg=$vers";
}

close $outfile or die $!;

# Update with new package lists
warn "* Executing @cmd_update\n";
$exit_status = system(@cmd_update);
exit if ($exit_status != 0);

# Install the build dependencies
warn "* Executing @cmd_install\n";
$exit_status = system(@cmd_install);
exit if ($exit_status != 0);

# Create the build user
system("adduser --disabled-password --gecos ',,,' $build_user");

# Create the build path
$build_path =~ m#^(.*/)([^/]+)$#;

my $buildinfo_filename = $pkg."_".$vers."_".$arch;

system("mkdir -p $1");
system("chown -R $build_user:$build_user $1");
system("cp $ARGV[0] $1/$buildinfo_filename.orig");
chdir($1);

# Fetch and unpack source
open ($outfile, '>', 'build.sh') or die $!;
print $outfile "#!/bin/sh -e\n" or die $!;
print $outfile "apt-get source $pkg=$vers\n" or die $!;
print $outfile "cd $2\n" or die $!;
print $outfile "export DEB_BUILD_OPTIONS='nocheck parallel=2'\n" or die $!;
print $outfile "dpkg-buildpackage -B 2>&1 | tee ../build.log\n" or die $!;
close $outfile or die $!;
system("chmod +x build.sh\n");
system("su $build_user -s /bin/sh -c ./build.sh");

# Process buildinfo
system("diff -Nru $buildinfo_filename.orig $buildinfo_filename");
