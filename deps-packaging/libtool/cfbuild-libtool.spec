Summary: CFEngine Build Automation -- libtool
Name: cfbuild-libtool
Version: 1.5.24
Release: 1
Source0: libtool-1.5.24.tar.gz
License: MIT
Group: Other
Url: http://example.com/
BuildRoot: %{_topdir}/BUILD/%{name}-1.5.24-buildroot

AutoReqProv: no

%prep
mkdir -p %{_builddir}
%setup -q -n libtool-1.5.24

./configure --prefix=/usr

%build

make

%install
rm -rf ${RPM_BUILD_ROOT}

make install DESTDIR=${RPM_BUILD_ROOT}

rm -rf ${RPM_BUILD_ROOT}/usr/lib/*.a
rm -rf ${RPM_BUILD_ROOT}/usr/lib/*.la
rm -rf ${RPM_BUILD_ROOT}/usr/share/info
rm -rf ${RPM_BUILD_ROOT}/usr/include

%clean
rm -rf $RPM_BUILD_ROOT

%description
CFEngine Build Automation -- libtool

%files
%defattr(-,root,root)

%dir /usr/bin
/usr/bin/libtool
/usr/bin/libtoolize

%dir /usr/lib
/usr/lib/libltdl.so
/usr/lib/libltdl.so.3
/usr/lib/libltdl.so.3.1.5

%dir /usr/share
/usr/share/aclocal
/usr/share/libtool

%changelog
