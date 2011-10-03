Summary:  Cisco UCS plugins for xCAT 
Name: xCAT-cisco
Version: %(cat Version)
Release: snap%(date +"%Y%m%d%H%M")
Epoch: 4
Group: Applications/System
Source: xCAT-cisco-%(cat Version).tar.gz
Packager: Cisco Systems Inc.
Vendor: Cisco Systems Inc.
Prefix: /opt/xcat
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root
License: Cisco Systems Inc.
BuildArch: noarch
Requires: xCAT-server >= 2.6
Requires: xCAT-client >= 2.6
Provides: xCAT-cisco = %{epoch}:%{version}

%description
xCAT-cisco contains UCS plugins for managing Cisco UCS servers.  The code
speaks directly to the UCSM using the native API.

%prep
%setup -q -n xCAT-cisco
%build
%install
rm -rf $RPM_BUILD_ROOT
mkdir -p ${RPM_BUILD_ROOT}%{prefix}/lib/perl/xCAT_plugin
set +x

cp opt/xcat/lib/perl/xCAT_plugin/* $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin

chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/*

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)
%{prefix}

%changelog
* Mon Jun 06 2011 - Vallard Benincosa <vallard@benincosa.com>
- initial SPEC file

%post
if [ -f "/proc/cmdline" ]
then
	echo "Restarting xCAT for plugins to take effect..."
	/etc/init.d/xcatd reload
fi
