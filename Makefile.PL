#!/usr/bin/perl

use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
	NAME             => 'Bolo::HTTP::Listener',
	AUTHOR           => q{Dan Molik <dan@d3fy.net>},
	VERSION_FROM     => 'lib/Bolo/HTTP/Listener.pm',
	ABSTRACT_FROM    => 'lib/Bolo/HTTP/Listener.pm',
	LICENSE          => 'artistic_2',
	PL_FILES         => {},
	MIN_PERL_VERSION => 5.022,
	CONFIGURE_REQUIRES => {
		'ExtUtils::MakeMaker' => 0,
	},
	EXE_FILES => [
		"bin/bolo-lhttpd",
	],
	BUILD_REQUIRES => {
		'Test::More' => 0,
	},
	PREREQ_PM => {
		'Sys::Syslog'  => 0,
		'Dancer'       => 0,
		'Gazelle'      => 0,
		'Bolo::Socket' => 0,
		'YAML::XS'     => 0,
		'JSON::XS'     => 0,
		'Getopt::Long' => 0,
	},
	dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
	clean => { FILES => 'Bolo-HTTP-Listener-*' },
);
