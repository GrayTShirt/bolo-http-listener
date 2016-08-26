package Bolo::HTTP::Listener;

use strict;
use warnings;

use Dancer qw/:script/;
use JSON::XS qw/decode_json/;
use Plack::Handler::Gazelle;

use POSIX qw/setuid setgid/;
use Time::HiRes qw/usleep/;
use Bolo::Socket;
use Cwd;
use Fcntl qw/LOCK_EX LOCK_NB/;
use Sys::Syslog;

use YAML::XS qw/LoadFile/;
use Getopt::Long;
Getopt::Long::Configure "bundling";

our $VERSION = '1.0.3';

my %CONFIG = (
	 config   => '/etc/bolo/lhttpd.yml',
	 port     =>  4401,
	 workers  =>  5,
	 address  => '0.0.0.0',
	 endpoint => 'tcp://bolo:2999',

	'home.dir'     => '/var/lib/bolo/lhttpd',
	'db'           => '/data.db',

	'log.facility' => 'daemon',
	'log.level'    => 'info',
	'log.type'     => 'syslog',
	'pid'          => '/var/run/bolo/lhttpd.pid',

	 user  => 'bolo',
	 group => 'bolo',

	 debug      => 0,
	 foreground => 0,
	 keepalive  => 1,
);

my %OPTIONS = ();
# LOGGING {{{
my %log_lvl = (
	debug  => 4,
	info   => 3,
	notice => 2,
	warn   => 1,
	err    => 0,
	fatal  => 0 - 1,
);
sub LOG
{
	my ($level, $fmt, @args) = @_;
	return unless $CONFIG{'log.level'} >= $log_lvl{$level};
	if ($CONFIG{foreground} || $CONFIG{'log.type'} !~ m/syslog/i) {
		printf(STDERR "[%s] $fmt\n", uc $level, @args);
	} else {
		syslog $level, sprintf($fmt, @args);
	}
	die if $level eq 'fatal';
}
# }}}

# bolo socket {{{
my $SOCK;
sub SOCK
{
	return $SOCK if $SOCK;
	$SOCK = Bolo::Socket->new->pusher;
	LOG notice => 'initializing connection to endpoint, %s', $CONFIG{endpoint};
	$SOCK->connect($CONFIG{endpoint}) or LOG err => "failed to connecto to endpoint %s", $CONFIG{endpoint};
	return $SOCK;
}
# preprime SOCK
# SOCK;
sub submit
{
	my ($pdu) = @_;
	SOCK->send($pdu) or LOG err => "failed to send PDU";
}
# }}}

# sub parse_submit {{{
my $ST = {
	OK => 0,
	ok => 0,
	0  => 0,
	warn => 1,
	WARN => 1,
	WARNING => 1,
	warning => 1,
	1 => 1,
	crit => 2,
	CRIT => 2,
	CRITICAL => 2,
	critical => 2,
	2 => 2,
	unknown => 3,
	UNKNOWN => 3,
	3 => 3,
};
my $type_qr = qr{^(STATE|EVENT|RATE|SAMPLE|COUNTER|KEY)$};
my $metric_qr = qr{^(RATE|SAMPLE|COUNTER)$};
sub parse_submit
{
	my ($type, $submit) =  @_;
	$type = uc $type;
	if ($type !~ $type_qr) {
		LOG err => "invalid type submittal %s", $type;
		return (400, 'invalid submit post, type not supported');
	}
	if (!$submit->{name}) {
		LOG err => "%s submittal missing name", $type;
		return (400, "invalid submit post, namespace required");
	}
	if ($type =~ $metric_qr) {
		unless (defined $submit->{value}) {
			LOG err => '%s|%s missing value', $type, $submit->{name};
			return (400, 'all metrics require a value');
		}
		LOG info => 'submitted %s to endpoint, %s, %s|%s|%s', $type, $CONFIG{endpoint}, $submit->{name}, $submit->{time} || time, $submit->{value};
		submit([uc $type, $submit->{time} || time, $submit->{name}, $submit->{value} || $submit->{increment}]);
	} elsif ($type eq 'STATE' or $type eq 'state') {
		unless (defined $submit->{code}) {
			LOG err => "%s|%s requires a code", $type, $submit->{name};
			return (400, "states require a code");
		}
		unless (defined $ST->{$submit->{code}}) {
			LOG err => "%s|%s invalid code %s", $type, $submit->{name}, $submit->{code};
			return (400, "invalid submit code $submit->{code}");
		}
		$submit->{code} = $ST->{$submit->{code}};
		unless ($submit->{message} || $submit->{msg}) {
			LOG err => "%s|%s requires a message", $type, $submit->{name};
			return (400, "states require a msg/message");
		}
		LOG info => 'submitted STATE to endpoint, %s, %s|%s|%s|%s', $CONFIG{endpoint}, $submit->{name}, $submit->{time} || time, $submit->{code}, $submit->{message} || $submit->{msg};
		submit(['STATE', $submit->{time} || time, $submit->{name}, $submit->{code}, $submit->{message} || $submit->{msg}]);
	} elsif ($type eq 'EVENT' or $type eq 'event') {
		unless ($submit->{msg} || $submit->{message}) {
			LOG err => "%s|%s requires a message", $type, $submit->{name};
			return (400, "events require a msg or message field");
		}
		LOG info => 'submitted EVENT to endpoint, %s, %s|%s|%s', $CONFIG{endpoint}, $submit->{name}, $submit->{time} || time, $submit->{message} || $submit->{msg};
		submit(['EVENT', $submit->{time} || time, $submit->{name}, $submit->{message} || $submit->{msg}]);
	} else {
		LOG info => 'submitted KEY to endpoint, %s, %s|%s|%s', $CONFIG{endpoint}, $submit->{name}, $submit->{value} || 1;
		submit(['KEY', $submit->{name}, $submit->{value} || 1]);
	}
	return (200, 'OK');
}
# }}}

# post /submit batch submittal {{{
post '/submit' => sub {
	LOG debug => "incomming batch submittal %s", request->body;
	my $batch = {} ; eval { $batch = decode_json (request->body); 1; } or
		do {
			status 500;
			LOG err => "invalid json submittal %s", $@;
			return "invalid json submitted $@";
		};
	unless (ref $batch eq 'ARRAY') {
		status 400;
		LOG err => 'batch not an array';
		return "batch not an array";
	}
	my ($code, $message);
	for (@$batch) {
		unless (ref eq 'HASH') {
			status 400;
			LOG err => 'invalid batch element, not a hash';
			return "batch element not a hash";
		}
		unless ($_->{type}) {
			status 400;
			LOG err => 'batch elements require a type key';
			return 'batch elements require a type key';
		}
		unless ($_->{data}) {
			status 400;
			LOG err => 'batch elements require a data key';
			return 'batch elements require a data key';
		}
		($code, $message) = parse_submit $_->{type}, $_->{data};
		status $code;
		return $message unless $code == 200;
	}
	return $message;
};
# }}}
# post /submit/:type serial submittal {{{
post '/submit/:type' => sub {
	LOG debug => "incomming submittal %s", request->body;
	my $submit = {} ; eval { $submit = decode_json (request->body); 1; } or
		do {
			status 500;
			LOG err => "invalid json submittal %s", $@;
			return "invalid json submitted $@";
		};
	my ($code, $message) = parse_submit param('type'), $submit;
	status $code;
	return $message;
};
# }}}

sub run
{
	GetOptions(\%OPTIONS, qw/
		help|h|?
		config|c=s
		foreground|F
		endpoint|e=s
		address|a=s
		port|p=i
		debug|D+
	/) or die "failed to get cli options: $!";
	for (keys %OPTIONS) {
		$CONFIG{$_} = $OPTIONS{$_}
	}
	if (-f $CONFIG{config}) {
		%OPTIONS = %{LoadFile $CONFIG{config}} or print STDERR "failed to open config $CONFIG{config}: $!";
		for (keys %OPTIONS) {
			$CONFIG{$_} = $OPTIONS{$_}
		}
	}
	$CONFIG{'log.level'} =  $log_lvl{$CONFIG{'log.level'}};
	openlog __PACKAGE__, "ndelay,pid", $CONFIG{'log.facility'} or print STDERR "unable to open syslog connection: $!";
	LOG notice => "starting server on $CONFIG{port}";
	my $server = Plack::Handler::Gazelle->new(
		port              => $CONFIG{port},
		host              => $CONFIG{address},
		workers           => $CONFIG{workers},
		argv              => [__PACKAGE__,],
		keepalive_timeout => $CONFIG{keepalive},
	);
	if (!$CONFIG{foreground}) {
		LOG info => "forking to background";
		# set public       => $CONFIG{'home.dir'}.$CONFIG{static};
		set content_type => 'application/json';
		#open(SELFLOCK, "<$0") or LOG err => "Couldn't find $0: $!\n";
		#flock(SELFLOCK, LOCK_EX | LOCK_NB) or LOG err => "Lock failed; is another nlma daemon running?\nShawn, are you sure you didn't mean to add the '-t' flag?\n";

		open(PIDFILE, ">", $CONFIG{pid}) or LOG err => "Couldn't open $CONFIG{pid}: $!\n";
		LOG info => "opened pidfile";
		my $uid = getpwnam($CONFIG{user})  or LOG err => "User $CONFIG{user} does not exist\n";
		my $gid = getgrnam($CONFIG{group}) or LOG err => "Group $CONFIG{group} does not exist\n";

		LOG info => "dropping privs";
		if ($) != $gid) {
			setgid($gid) || LOG err => "Could not setgid to $CONFIG{group} group\n";
		}
		if ($> != $uid) {
			setuid($uid) || LOG err => "Could not setuid to $CONFIG{user} user\n";
		}
		LOG info => "privs set";
		open STDIN,  "</dev/null" or LOG err => "daemonize: failed to reopen STDIN\n";
		open STDOUT, ">/dev/null" or LOG err => "daemonize: failed to reopen STDOUT\n";
		open STDERR, ">/dev/null" or LOG err =>  "daemonize: failed to reopen STDERR\n";

		LOG info => "changing dir";
		chdir('/');

		LOG info => "forking";
		exit if fork;
		exit if fork;
		LOG info => "now in background";

		usleep(1000) until getppid == 1;

		LOG info => "writing to pidfile";
		print PIDFILE "$$\n";
		close PIDFILE;
		LOG info => "finished setting daemon";
	} else {
		LOG info => 'setting homedir';
		$CONFIG{'log.level'} = $CONFIG{debug} + $CONFIG{'log.level'};
		$CONFIG{'home.dir'} = getcwd;
	}
	$server->run(sub {Bolo::HTTP::Listener->dance(Dancer::Request->new(env => shift))});
}
