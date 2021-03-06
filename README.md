# xCAT-cisco 

A plugin to allow xCAT hardware management 
commands (like rpower, rinv, etc) to run on the Cisco UCS platform.  

[xCAT](http://xcat.org) (Extreme Cloud Administration Toolkit) is an open source 
hardware tool used to provision physical and virtual machines 
with proven scalability.  In addition to provisioning methods it provides
methods to manipulate and query hardware, including getting information from 
management interfaces (like IPMI, other vendor blades, etc).

Think of it this way:  Every hardware vendor sells/packages some sort of management 
solution to manage their hardware:  IBM - Director, HP - Insight, 
Dell - something else, ... etc.  xCAT is a way to manage all hardware.

For more information on xCAT see: http://xcat.sf.net

Installation instructions:

*AFTER* you have installed xCAT.  
Get the RPM here: http://benincosa.com/xCAT/

For information on how to install xCAT see: 
http://sumavi.com/sections/local-installation
- And -
The xCAT documentation wiki here:
http://sourceforge.net/apps/mediawiki/xcat/index.php?title=XCAT_on_Cisco_UCS_B-Series_Blades


Building Instructions

If you want to build this source you can use git commands to download this
tree and extract it on your home directory.

To build this and install it on your xCAT server you can simply follow
the links and copy opt/xcat/lib/perl/xCAT_plugin/ucs.pm to the xCAT
server in /opt/xcat/lib/perl/xCAT_plugin and then restart xCAT:
service xcatd restart

Or

You can download this git repository to a RedHat or CentOS Linux 
machine and do:

./build-xCAT-cisco-RPM
cd /usr/src/redhat/RPMS/noarch/
rpm -ivh xCAT-cisco*rpm

Configuration Instructions


* Add the UCSM to the nodelist
nodeadd <my ucsm virtual ip address> groups=ucs-domain
e.g: nodeaddd ucs001 groups=ucs-domain

* Add UCS to the mpa tab
tabedit mpa
Add the following line:
<UCS>,<userid>,<password>

In my case:
ucs001,admin,cisco.123

* Make sure that SSL is enabled on UCS Manager via the GUI
- This can be done in Admin -> Communication Management -> HTTPS
- This version of the plugin will not work with HTTP, only HTTPS

* Verify you can get service profiles from UCS Managers
lssp <ucs fabric interconnect>
e.g.:
	lssp ucs001
	lssp ucs001,ucs008,ucs0[11-12]

* Add blades
nodeadd  blade001-blade120 groups,=ucsnodes

* Set the nodes management interface
nodech ucsnodes nodehm.mgt=ucs

* Add an entry for each service profile to map it to the node in the mp table

tabedit mp

#node,mpa,id,nodetype,comments,disable
"blade001","ucs001","org-root/ls-ESXi-1000v-01",,,
"blade002","ucs001","org-root/ls-ESXi-1000v-02",,,
...

* run a command to make sure it works:
[root@xcat ~]# rinv blade001
blade001: memory available: 49152
blade001: memory speed: 1067
...

* Troubleshooting:

If you have questions please send them my way:
vallard@benincosa.com
-or-
xcat@cisco.com
