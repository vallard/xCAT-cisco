#!/usr/bin/env perl
# vallard@benincosa.com
# vallard@cisco.com
# © 2011 Cisco Systems, Inc. All rights reserved.

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
use XML::LibXML;
$XML::Simple::PREFERRED_PARSER='XML::Parser';
use Data::Dumper;
use POSIX "WNOHANG";
use xCAT::DBobjUtils;
use Getopt::Long;
use xCAT::SvrUtils;

=head1 NAME 

xCAT_plugin::ucs - A UCS plugin for xCAT

=cut


=head1 SYNOPSYS

xCAT_plugin::ucs really only works with xCAT.
put it in the /opt/xcat/lib/perl/xCAT_plugin directory

=cut


=head1 AUTHOR

Vallard Benincosa - L<http://benincosa.com>

=head1 FUNCTIONS

=cut


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


=item process_request 

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


=item logon

Establish a session with UCSM and return the logon cookie.
This info was gotten from:
http://developer.cisco.com/web/unifiedcomputing/forums/-/message_boards/view_message/2357013

also:

http://developer.cisco.com/web/unifiedcomputing/resources?p_p_id=20&p_p_lifecycle=0&p_p_state=maximized&p_p_mode=view&_20_struts_action=%2Fdocument_library%2Fview&_20_folderId=2144116

=cut


sub logon {
	my $ucsm = shift;
	my $username = shift;
	my $password = shift;
	my $callback = shift;

	my $browser = LWP::UserAgent->new();

	my $xmlcmd ="<aaaLogin inName='".$username."' inPassword='".$password."'></aaaLogin>";
	my $url = 'http://'.$ucsm.'/nuova';
	my $xml_header = "<?xml version='1.0'?>";
	my $request = HTTP::Request->new(POST => $url);
	$request->content_type("application/x-www-form-urlencoded");
	$request->content($xmlcmd);

	my $response = $browser->request($request);
	# check to see that we could connecte
	unless($response->is_success){
		$callback->({error =>["$ucsm: " . $response->status_line],errorcode=>1});
		return 0;
	}
	# check to see if there was an error logging in:
	if($request->content =~ m/errorDescr/){
		$request->content =~ m/errorDescr=\"([a-zA-Z0-9_\-\.]+)\".*/;
		$callback->({error=>["Login failure: $1"],errorcode=>1});
	}
	#print Dumper($response);
	my $lCookie;
	# attempt to grab the outCookie from the login
	eval {
		my $lParser = XML::Simple->new();
		my $lConfig = $lParser->XMLin($response->content);
		print Dumper($lConfig);
		$lCookie = $lConfig->{'outCookie'};
		
		$lCookie = undef if ($lCookie && $lCookie eq "");
		print Dumper($lCookie);
	};
	if($@){
		$callback->({error=>["Login failure trying to evaluate cookie"],errorcode=>1});
		#print Dumper($@);
	}
	return $lCookie
}

=item doPostXML

Run the XML command through UCS and return the output.
this was taken and modified from the Cisco provided sample files here:

http://developer.cisco.com/web/unifiedcomputing/resources?p_p_id=20&p_p_lifecycle=0&p_p_state=maximized&p_p_mode=view&_20_struts_action=%2Fdocument_library%2Fview&_20_folderId=2144116

=cut

sub doPostXML {
    my ($aInUri, $aInPostData) = @_;

    my $browser = LWP::UserAgent->new();
    my $request = HTTP::Request->new(POST => $aInUri);
    $request->content_type("application/x-www-form-urlencoded");
    $request->content($aInPostData);

    # Print out the request and response
    #if ($lDebug==1)
    #{
    #    print ("\nRequest\n");
    #    print ("-------\n");
    #    print ($request->as_string() . "\n");
    #}
    my $resp = $browser->request($request);    #HTTP::Response object

    #if ($lDebug==1)
    #{
    #    print ("\nHeaders\n");
    #    print ("\nResponse\n");
    #    print ("-------\n");
    #    print ($resp->content() . "\n");
    #}

    return ($resp->content, $resp->status_line, $resp->is_success, $resp) if wantarray;
    return unless $resp->is_success;
    return $resp->content;
}





=item logout

function to logout from the current session.  Need to make sure you do this or too many sessions get tied up!
this was taken and modified from the Cisco provided sample files here:

http://developer.cisco.com/web/unifiedcomputing/resources?p_p_id=20&p_p_lifecycle=0&p_p_state=maximized&p_p_mode=view&_20_struts_action=%2Fdocument_library%2Fview&_20_folderId=2144116

=cut

sub logout
{
    my ($aInUri, $aInCookie) = @_;
    my $lXmlRequest = "<aaaLogout inCookie=\"REPLACE_COOKIE\" />";
    $lXmlRequest =~ s/REPLACE_COOKIE/$aInCookie/;

    my $lCookie = undef;
    my ($lContent, $lMessage, $lSuccess) = doPostXML($aInUri, $lXmlRequest,1);

    if ($lSuccess)
    {
        eval {
            my $lParser = XML::Simple->new();
            my $lConfig = $lParser->XMLin($lContent);
            $lCookie = $lConfig->{'outCookie'};
            $lCookie = undef if ($lCookie && $lCookie eq "");
        };
    }
    return $lCookie;
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
	foreach my $ucsm (keys %$nh){
		my $cookie = logon($ucsm, $nh->{$ucsm}->{username}, $nh->{$ucsm}->{password},$callback);
		#print Dumper($cookie);
		
		unless($cookie){
			next;
		}
		logout($ucsm,$cookie);
	}
}
   
=item buildNodeHash

buildNodeHash takes the noderange and builds a hash
that looks like this:

ucsm =>{

	username

	password

	node

		nodename

			chassis => 

			slot => 

		nodename

			chassis => 

			slot => 

}

IP address (or hostname) should be reachable
username and password should be specified in the mpa or passwd table
node chassis and slot information are defined in the mp table.
	
=cut

sub buildNodeHash {
	my $request = shift;
	my $callback = shift;
	my $errors = 0;
	# build the right stuff here!
	my $nh; # the node hash
	my $nodes = $request->{node};
	#print Dumper($nodes);
	

	my @tabs = qw(mp mpa passwd);
	my %db = ();
	# open all the tables.
	foreach(@tabs){
		$db{$_} = xCAT::Table->new($_);
		if(!$db{$_}){
			$callback->({error=>"Error opening $_ table",errorcode=>1});
			return 0;
		}
	}	
	
	# first get the mpas.
	my $mph = $db{'mp'}->getNodesAttribs($nodes, [qw(mpa id)]);
	#print Dumper($mph);
	foreach my $node (@$nodes){
		unless($mph->{$node}->[0] && $mph->{$node}->[0]->{mpa}){
			$errors++;
			$callback->({error=>["$node: Please specify the UCS Manager in mp.mpa"],errorcode=>1});
			next;
		}

		unless($mph->{$node}->[0]->{id}){
			$callback->({error=>["$node: No management id specified.  Please change mp.id to be chassis/slot, eg: 1/1"],errorcode=>1});
			next;	
		}

		my $id = $mph->{$node}->[0]->{id};
		unless($id =~ /\//){
			$callback->({error=>["$node: Invalid ID.  Please change mp.id to be chassis/slot, eg: 1/1"],errorcode=>1});
			next;
		}
		# id should be chassis/slot
		my ($chassis,$slot) = split('/', $id);
		#should make sure this is numeric
		
		my $currUCSM = $mph->{$node}->[0]->{mpa};
		unless($nh->{$currUCSM}){
			$nh->{$currUCSM}->{nodes} = ();
		}
		push @{$nh->{$currUCSM}->{nodes}},{$node=>{chassis => $chassis,slot => $slot}}
	}

	# first get the default user/password 
	my $passh = $db{'passwd'}->getAttribs({key=>'ucs'},'username','password');
	my $defaultUser = "";
	my $defaultPasswd = "";
	if($passh){
		#print Dumper($passh);
		$defaultUser = $passh->{username};	
		$defaultPasswd = $passh->{password};	
	}
	#my $mpah = $db{'mpa'}->getNodeAttribs(qw(mpa, username, password))
	
	# now get the user and password for the mpas
	foreach my $ucsm (keys %$nh){
		my $ent = $db{'mpa'}->getAttribs({mpa=>$ucsm},'username','password');		
		unless($ent){
		# if nothing specified in mpa table then add default
			if($defaultUser && $defaultPasswd){
				$nh->{$ucsm}->{username} = $defaultUser;
				$nh->{$ucsm}->{password} = $defaultPasswd;
			}else{
				$callback->({error=>["No username or password specified in mpa.{username,password} nor passwd.{username,password} table.  Please specify a username and password"],errorcode=>1});
				$errors++;
				next;
			}
		}else{
			# set the password
			#print Dumper($ent);
			if($ent->{password}){
					$nh->{$ucsm}->{password} = $ent->{password};
			}else{
				if($defaultPasswd){
					$nh->{$ucsm}->{password} = $defaultPasswd;
				}else{
					$callback->({error=>["No password specified in mpa.password nor passwd.password table.  Please specify a username and password"],errorcode=>1});
					$errors++;
					next;		
				}
			}

			if($ent->{username}){
					$nh->{$ucsm}->{username} = $ent->{username};
			}else{
				if($defaultUser){
					$nh->{$ucsm}->{username} = $defaultUser;
				}else{
					$callback->({error=>["No username specified in mpa.username nor passwd.username table.  Please specify a username and password"],errorcode=>1});
					$errors++;
					next;		
				}
			}
		}
	}
	
	if($errors){
		return 0;
	}
	#print Dumper($nh);
	return $nh;
} 

