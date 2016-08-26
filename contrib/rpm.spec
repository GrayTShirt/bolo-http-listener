Name:           bolo-lhttpd
Version:        1.0.0
Release:        1%{?dist}

Summary:        A bolo rest endpoint to submit PDUs to a Bolo aggregator
URL:            https://github.com/graytshirt/bolo-lhttpd
License:        GPLv2
Group:          System Environment/Daemons

BuildRoot:      %{_tmppath}/%{name}-root
BuildArch:      noarch
Source:         Bolo-HTTP-Listener-%{version}.tar.gz

BuildRequires:  perl(Test::More)

Requires:       perl(YAML)
Requires:       perl(YAML::XS)
Requires:       perl(Dancer)
Requires:       perl(Sys::Syslog)
Requires:       perl(JSON::XS)
Requires:       perl(Gazelle)
Requires:       perl(Bolo::Socket);

%description
A Bolo HTTP Rest endpoint

Submit you metrics
nom nom nom

###############################################
%prep
%setup -q -n Bolo-HTTP-Listener-%{version}


%define __new_perl_provides %{_builddir}/bolo-perl-provides
cat > %{__new_perl_provides} <<END_PROVIDES
#!/bin/sh
# drop bad 'Provides' symbols
%{__perl_provides} $* |\
  sed -e 's/\s+$//' |\
  sed -e '/^perl(Parse::/d' |\
  cat
END_PROVIDES
chmod +x %{__new_perl_provides}
%define __perl_provides %{__new_perl_provides}
%define __find_provides %{__new_perl_provides}

%define __new_perl_requires %{_builddir}/bolo-perl-requires
cat > %{__new_perl_requires} <<END_REQUIRES
#!/bin/sh
# drop bad 'Requires' symbols
%{__perl_requires} $* |\
  sed -e 's/\s+$//' |\
  cat
END_REQUIRES
chmod +x %{__new_perl_requires}
%define __perl_requires %{__new_perl_requires}
%define __find_requires %{__new_perl_requires}


##########################################################
%build

CFLAGS="$RPM_OPT_FLAGS" \
PERL_AUTOINSTALL='--skipdeps' \
  perl Makefile.PL INSTALLDIRS=vendor
make


##########################################################
# %check
# make test # disable for now


##########################################################
%clean
rm -rf $RPM_BUILD_ROOT


##########################################################
%install
rm -rf $RPM_BUILD_ROOT
export PERL5LIB=$(perl -e "print join(':', map { '$RPM_BUILD_ROOT'.\$_ } @INC);")
make install DESTDIR=$RPM_BUILD_ROOT

[ -x /usr/lib/rpm/brp-compress ] && /usr/lib/rpm/brp-compress

# move some of the bins into sbin
(cd $RPM_BUILD_ROOT
 mkdir -p usr/sbin
 mv usr/bin/bolo-lhttpd  usr/sbin)

# copy in in the init.d files
mkdir -p $RPM_BUILD_ROOT%{_initrddir}
install -m 0755 contrib/init.d/bolo-lhttpd  $RPM_BUILD_ROOT%{_initrddir}

# copy the static assets and views
mkdir -p $RPM_BUILD_ROOT%{_datarootdir}/%{name}
cp -a public $RPM_BUILD_ROOT%{_datarootdir}/%{name}
cp -a views  $RPM_BUILD_ROOT%{_datarootdir}/%{name}
cp -a schema $RPM_BUILD_ROOT%{_datarootdir}/%{name}
# ... but ignore the public/t/ directory
rm -rf $RPM_BUILD_ROOT%{_datarootdir}/%{name}/public/t

# remove some stuff we don't want
find $RPM_BUILD_ROOT \( -name perllocal.pod -o -name .packlist \) -exec rm -v {} \;

# generate the file list for the main package
find $RPM_BUILD_ROOT/usr -type f -print | \
  grep -v '/bin/ack' | grep -v '/bin/downtime' |\
  sed "s@^$RPM_BUILD_ROOT@@g" > %{__bolo_filelist}

if test ! -s %{__bolo_filelist}; then
  echo "Error: No files found to package!!"
  exit 1
fi


%post
# register services
chkconfig --add bolo-lhttpd
%define user    bolo
%define group %{user}
%define homedir /var/lib/bolo/lhttpd
getent group %{group} >/dev/null || groupadd -r %{group}
getent passwd %{user} >/dev/null || \
	useradd -r -g %{group} -d %{homedir} -s /sbin/nologin \
			-c "bolo httpd listener" %{user}
%preun
if [[ $1 != 0 ]]; then # upgrade!
	service bolo-lhttpd  condrestart

else # erase!
	service bolo-lhttpd stop
	chkconfig --del bolo-lhttpd
fi

%files -f %{__bolo_filelist}
%defattr(-,root,root)
%{_initrddir}/bolo-lhttpd


%changelog
* Fri Aug 26 2016 Dan Molik <dan@d3fy.net> 1.0.0-1
- Initial package
