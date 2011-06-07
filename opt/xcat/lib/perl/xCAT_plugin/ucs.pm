#!/usr/bin/env perl
# vallard@benincosa.com
# (C) Cisco Systems, Inc

package xCAT_plugin::ucs;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use xCAT::Table;
use xCAT::Utils;
use IO::Socket;
use xCAT_monitoring::monitorctrl;
use strict;
use LWP;
use XML::Simple;
$XML::Simple::PREFERRED_PARSER='XML::Parser';
use Data::Dumper;
use POSIX "WNOHANG";
use xCAT::DBobjUtils;
use Getopt::Long;
use xCAT::SvrUtils;

sub handled_commands {
  return {
    rpower => 'nodehm:power,mgt',
  };
}

=item preprocess_request

Used to handle service nodes.  We don't have support for this right now.
TODO: Test this with service nodes!

=cut

sub preprocess_request {
	my $req = shift;
	# ignore this function for now and just return
	return [$req];
}


=item process_request {

This is the main entry point for the plugin.  The commands get handed
here and we process them based on what command was asked for.

=cut

sub process_request {
	my $request = shift;
	my $callback = shift;
	my $command = $request->{command}->[0];
	if($command eq 'rpower'){
		power($request, $callback);
	}else{
		$callback->({error=>["$command is not yet supported for UCS"],errorcode=>1});
	}
	return;
}


=item power 

This function is responsible for sending power on/off/stat/boot/reset
commands to the UCSM.

=cut


sub power {
	my $request = shift;
	my $callback = shift;
	my $nh = buildNodeHash($request, $callback);
	unless($nh){
		return;
	}
}
   
=item buildNodeHash

buildNodeHash takes in a request and forms it like this:

ucsm
	ip address
	username
	password
	node
		nodename
			chassis => 
			slot => 
	node
		nodename
			chassis => 
			slot => 

	IP address (or hostname) should be reachable
	username and password should be specified in the mpa or passwd table
	
=cut

sub buildNodeHash {
	my $request = shift;
	my $callback = shift;
	# build the right stuff here!
	my $nh; # the node hash
	my $nodes = $request->{node};
	print Dumper($nodes);

} 
