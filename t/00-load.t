#!perl -T
use 5.006;
use strict;
use warnings;
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'Bolo::HTTP::Listener' ) || print "Bail out!\n";
}

diag( "Testing Bolo::HTTP::Listener $Bolo::HTTP::Listener::VERSION, Perl $], $^X" );
