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
	$mech->get( $search_uri );	# :XXX: try multiple times?
	
	$text_regex = qr/^\Q$vers\E( |$)/;
	$link = $mech->find_link( text_regex => $text_regex );
	if (!defined $link) {
		warn "$text_regex not found on page!";
		return undef;
	}

	$search_uri = $link->url_abs();
	warn "* Querying $search_uri...\n";
	$search_uri =~ s/#.*$//;	# Disregard anchors in URI
	$mech->get( $search_uri );	# :XXX: try multiple times?
	
	$vers =~ s/^[0-9]+://;		# Disregard version epoch
	if ($arch eq "source") {
		$text_regex = qr/^\Q$pkg\E\_\Q$vers\E\.dsc$/;
	} else {
		$text_regex = qr/^\Q$pkg\E\_\Q$vers\E\_(all|$arch)\.deb$/;
	}

	$link = $mech->find_link(
		text_regex => $text_regex,
		url_abs_regex => qr#/archive/debian/#
	);
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
	allow_pgp => 1, #:XXX: doesn't work yet
	filename => $ARGV[0]
);

my $fields = $buildinfo->get_source();
my $installed_build_depends = deps_parse(
	$fields->{'Installed-Build-Depends'},
	union => 1
);

my $build_user = 'sbuild';
my $build_path = $fields->{'Build-Path'};

my $pkg  = $fields->{'Source'};
my $vers = $fields->{'Version'};
my $arch = $fields->{'Architecture'};

$pkg  =~ s/ .*$//;		# Discard version numbers seen in buildinfo format 0.2
# :XXX: format 0.2 has incomplete Pre-Depends?

$vers =~ s/\+b[0-9]+$//;	# Disregard binNMU version # :XXX: still fails

$arch =~ s/^all //;	# :XXX: hackish workaround
$arch =~ s/ source$//;  # :XXX: fails badly with arch:all packages

my @cmd_update  = qw(apt-get update);
my @cmd_install = qw(apt-get -y --allow-downgrades install);

open (my $outfile, '>', 'repro-build-env.list') or die $!;

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
warn "Created repro-build-env.list\n";

# Create a pre-build script
open ($outfile, '>', 'script.sh') or die $!;

# Update with new package lists
print $outfile "@cmd_update\n" or die $!;

# Install the build dependencies
print $outfile "@cmd_install\n" or die $!;

close $outfile or die $!;
warn "Created script.sh\n";

# Discard the last component of the path
$build_path =~ m#^(.*)/([^/]+)$#;

warn "Starting sbuild...\n";
exec("./sbuild.sh --build-path \"$1\" \"".$pkg."_".$vers."\"");
# :XXX: build-path may be missing in build-info
# :XXX: this script and sbuild.sh must be in the home directory
