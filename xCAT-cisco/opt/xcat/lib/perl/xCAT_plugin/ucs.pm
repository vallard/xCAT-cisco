#!/usr/bin/env perl
# vallard@benincosa.com
# vallardx@cisco.com
# © 2011-2012 Cisco Systems, Inc. All rights reserved.
# nsavin@griddynamics.com

package xCAT_plugin::ucs;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

#perl Libraries
use strict;
use LWP;
use XML::Simple;
use IO::Socket;
use Data::Dumper;
use Getopt::Long;
use Carp;
$XML::Simple::PREFERRED_PARSER='XML::Parser';

#xCAT libraries
use lib "$::XCATROOT/lib/perl";
use xCAT::Table;
use xCAT::Utils;
use xCAT::DBobjUtils;
use xCAT::SvrUtils;


my %powermap = (
    on      =>  'up',
    off     =>  'down',
    softoff => 'soft-shut-down',
    cycle   => 'cycle-immediate',
    'reset' => 'hard-reset-immediate',
    boot    => 'cycle-immediate',
);


=head1 NAME 

xCAT_plugin::ucs - A UCS plugin for xCAT

=cut


=head1 SYNOPSYS

xCAT_plugin::ucs really only works with xCAT.
put it in the /opt/xcat/lib/perl/xCAT_plugin directory

=cut


=head1 AUTHOR

Vallard Benincosa - L<http://benincosa.com>

Savin Nikita <nsavin@griddynamics.com>

=cut

=head1 FUNCTIONS

=cut


sub handled_commands {
  return {
    rpower => 'nodehm:power,mgt',
    getmacs => 'nodehm:getmac,mgt',
		lsflexnode => 'ucs',
		lssp => 'ucs',
		rinv => 'nodehm:mgt'
  };
}

=item preprocess_request

Used to handle service nodes.  We don't have support for this right now.
TODO: Test this with service nodes!

=cut

sub preprocess_request {
    	Getopt::Long::Configure("bundling");
    	Getopt::Long::Configure("no_pass_through");
	my $req = shift;
	# ignore this function for now and just return
	return [$req];
}


=item process_request 

This is the main entry point for the plugin.  The commands get handed
here and we process them based on what command was asked for.

=cut

sub process_request {
	# pass the getops to this function
    	Getopt::Long::Configure("bundling");
    	Getopt::Long::Configure("no_pass_through");
	my $request = shift;
	my $callback = shift;
	my $command = $request->{command}->[0];
    if ($request->{arg}) {
        @ARGV = @{$request->{arg}};
    } else {
        @ARGV = ();
    }
	

	if($command eq 'rpower'){
		power($request, $callback);
  }elsif ($command eq 'getmacs') {
  	getmacs($request, $callback);
	} elsif ($command  eq 'lssp' || $command eq 'lsflexnode'){
		lssp($request, $callback);
	} elsif ($command  eq 'rinv'){
		rinv($request, $callback);
	} else{
		$callback->({error=>["$command is not yet supported for UCS"],errorcode=>1});
	}
	return;
}



### Finished xCAT API
#
### Interal logic


sub getmacs { 
	my $request = shift;
	my $callback = shift;
    my $mactab = xCAT::Table->new('mac',-create=>1);
    my $nrtab = xCAT::Table->new('noderes');
    if (!$nrtab) { 
		$callback->({error => ["Can't open noderes table"],errorcode=>1});
        return;
    }
    my $ucsm = buildNodes($request->{node}, $callback);
    my @node2dn = _profile2dn($ucsm);
    for my $gn (@node2dn) { 
        my %nodes = %{$gn->{nodes}};
        my $ucsm = $gn->{ucsm};
        for my $node (keys %nodes) {
						
        	my $nent = $nrtab->getNodeAttribs($node,['primarynic','installnic']);
          my $mkey = $nent->{installnic} || $nent->{primarynic};
          if (!$mkey) { 
            $callback->({error=> ["please set noderes.installnic or noderes.primarynic for $node"], errorcode=>1});
            next;
          }
					# nic can be anything, doesn't have to be eth0, eth1, etc.  could be something else.
          #if ($mkey !~ /^eth\d+$/) { 
          #    $callback->({error=> ["please set noderes.installnic or noderes.primarynic for $node in form eth1"], errorcode=>1});
          #    next;
          #}

					my $s = $ucsm->get_scope($nodes{$node}{_profile}{dn}, 'vnicEther');
          my %mac;
					
          for my $ifdn (values %{$s->{outConfigs}}) {
						foreach my $if (keys %$ifdn){
							unless($if){
								$callback->({error =>["vNIC interface: $if does not have a name.  This may be a bug in the code"], errorcode =>1});
								next;
							}
							# skip dynamic vNICs as these will be used by VMs
							my $name = lc $ifdn->{$if}->{name};
							my $addr = uc $ifdn->{$if}->{addr};
							if($name =~/dynamic/){next};
								$mac{$name} = $addr;
								$callback->({node => [{name => [$node], data => [ {desc => [ $node . "-" . $name ],
														contents => [ $addr]}]}]});

							}
					}
            
					if (not exists $mac{$mkey}) { 
						$ucsm->err("%s: noderes.installnic or noderes.primarynic is set to be %s but there is no vNIC in the service profile with that name.\nPlease change noderes.installnic or noderes.primarynic to be one of the following: %s\n e.g: nodech %s noderes.primarynic=%s", $node, $mkey, join(",", keys %mac), $node, keys %mac);
						next;
					}
	        	#$callback->({node => [ {name => [$node], data => [{desc => [
            #    join ", ", values %mac], contents =>["blah"]}] } ]});
                #join ", ", values %mac], contents =>["used: ".$mac{$mkey}]}] } ]});
					my @macs;
					push @macs, $mac{$mkey} ."!".$node;
					foreach my $m (keys %mac){
						if($m eq $mkey){
							next
						}
						push @macs, $mac{$m} ."!".$node."-".$m;
					}
        	$mactab->setNodeAttribs($node,{mac=>join("|", @macs)});
        }
        $ucsm->logout();
    }
    $mactab->close();
    $nrtab->close(); 
}


sub rinv {
	my $request = shift;
	my $callback = shift;
	my $usage = sub {
		$callback->({data => [ "Usage: ", "   rinv " . $request->{noderange}->[0] . "all|bios" ]});
		return;
	};

	my $help = 0;
	GetOptions( 'h|?|help' => \$help, );
	if($help){$usage->($callback); return }
	my $subcmd = shift(@ARGV);
	my $ucsm = buildNodes($request->{node}, $callback);
	inv($ucsm, $callback);
}



sub power {
	my $request = shift;
	my $callback = shift;
	# get additional arguments
	my $usage = sub {
		$callback->({data => 
			[
			"Usage: ",
			"   rpower " . $request->{noderange}->[0] . " on|off|stat|reset|boot|softoff|cycle"
			]
		});
		return;
	};

    my $help = 0;
	GetOptions(
		'h|?|help' => \$help,
	);
	if($help){ $usage->($callback); return }

	my $subcmd = shift( @ARGV);
	unless($subcmd){
		$callback->({error => ["No power action specified"],errorcode=>1});
		$usage->();
		return;
	}

	unless($subcmd =~ /on|off|stat|reset|boot|cycle|softoff/){
		$callback->({error => ["Invalid power action: $subcmd"],errorcode=>1});
		$usage->();
		return;
	}

    my $ucsm = buildNodes($request->{node}, $callback);
	if($subcmd =~ /stat/){
		powerStat($ucsm, $callback);
	}
    else{
		powerOp($ucsm, $callback, $subcmd);
	}
}








sub powerOp {
	my $ucsm = shift;
	my $callback = shift;
	my $op = shift; 
	unless($ucsm){
		return;
	}
    my $error = 0;
	foreach my $gn (@$ucsm){
        if ($error) {
            $gn->{ucsm}->logout();
            next;
        }
		my $xml = "<configConfMo ^^cookie^^ dn='' inHierarchical='no'><inConfig>\n";
        $xml .= "<lsPower dn='$_' state='$powermap{$op}' status='modified'/>\n" 
            for values %{$gn->{nodes}};
		$xml .= "</inConfig></configConfMo>\n";
        my $resp = $gn->{ucsm}->_request($xml);
        $gn->{ucsm}->logout();
        if ($resp->{errorCode}) {
            #print Dumper $resp;
            $callback->({error => $resp->{errorDescr}});
            $error++;
        }
        else {
						my $desc = $_->{dn};
								$desc =~ s/sys\///g;
								$desc =~ s/-//g;
	        $callback->({node => [ {name => [$_], data => [{desc => [ $gn->{nodes}{$_}], 
                contents =>[$op]}] } ]}) for keys %{$gn->{nodes}};
        }
	}	
}


=item inv

Possible values:
         'adminPower' => 'policy',
          'model' => 'N20-B6620-1',
          'fsmStatus' => 'nop',
          'numOfCoresEnabled' => '8',
          'fltAggr' => '68719476736',
          'uuid' => '00000000-0000-0000-dead-beef00000007',
          'numOfEthHostIfs' => '6',
          'serverId' => '2/1',
          'chassisId' => '2',
          'fsmTry' => '0',
          'usrLbl' => '',
          'presence' => 'equipped',
          'serial' => 'QCI1412A116',
          'fsmRmtInvRslt' => '',
          'name' => '',
          'discovery' => 'complete',
          'connStatus' => 'A,B',
          'descr' => '',
          'fsmRmtInvErrCode' => 'none',
          'revision' => '0',
          'mfgTime' => '2010-03-25T01:00:00.000',
          'lcTs' => '1969-12-31T16:00:00.000',
          'checkPoint' => 'discovered',
          'operPower' => 'off',
          'intId' => '2715902',
          'availableMemory' => '49152',
          'managingInst' => 'B',
          'lowVoltageMemory' => 'regular-voltage',
          'fsmStamp' => '2012-04-12T20:54:25.868',
          'availability' => 'unavailable',
          'fsmProgr' => '100',
          'operState' => 'power-off',
          'numOfThreads' => '16',
          'fsmPrev' => 'SoftShutdownSuccess',
          'association' => 'associated',
          'fsmStageDescr' => '',
          'connPath' => 'A,B',
          'slotId' => '1',
          'fsmFlags' => '',
          'numOfAdaptors' => '1',
          'memorySpeed' => '1333',
          'fsmRmtInvErrDescr' => '',
          'operability' => 'operable',
          'totalMemory' => '49152',
          'assignedToDn' => 'org-root/org-vallard-test/ls-lucky02',
          'numOfCores' => '8',
          'lc' => 'discovered',
          'adminState' => 'in-service',
          'operQualifier' => '',
          'fsmDescr' => '',
          'dn' => 'sys/chassis-2/blade-1',
          'numOfCpus' => '2',
          'numOfFcHostIfs' => '2',
          'originalUuid' => 'dd8c55e1-3774-11df-bf46-18a905163202',
          'vendor' => 'Cisco Systems Inc'


=cut



sub inv {
	my $ucsm = shift;
	my $callback = shift;
	unless($ucsm){
		return;
	}
	# key is what user sees.  value is ucs key word.
	my %inv_hash = (
		'memory available' => 'availableMemory',
		'memory total' => 'totalMemory',
		'memory speed' => 'memorySpeed',
		'model' => 'model',
		'number of CPUs' => 'numOfCpus',
		'number of cores' => 'numOfCores',
		'number of cores enabled' => 'numOfCoresEnabled',
		'number of ethernet interfaces' => 'numOfEthHostIfs',
		'number of fc interfaces' => 'numOfFcHostIfs',
		'serial number' => 'serial',
		'server chassis' => 'chassisId',
		'server slot' => 'slotId',
		'uuid' => 'uuid', 
		'uuid original' => 'originalUuid',
		'vendor' => 'vendor',
	);



	my @res = _profile2dn($ucsm);
	foreach my $gn (@res){
		my %nodes = %{$gn->{nodes}};  # hash of nodename => service profile name
		my $blade = $gn->{ucsm}->get_dns(map {$_->{dn}} values %nodes);
		#print("rack mount: ", $blade->{outConfigs}->{rack_mount}, "\n");
		#print Dumper $blade;
		my $blade_out;
		if (exists $blade->{outConfigs}->{computeBlade}) {
		  $blade_out = $blade->{outConfigs}->{computeBlade};
                }elsif(exists $blade->{outConfigs}->{computeRackUnit}) {
		  $blade_out = $blade->{outConfigs}->{computeRackUnit};
		}
		# if less than one have to change the hash
		$blade_out = {$blade_out->{dn} => $blade_out} if $blade_out->{dn};
		$blade_out->{$_}{dn}=$_ for keys %$blade_out;
		my %cmap = map { $nodes{$_}{dn} => $_ } keys %nodes;
		for my $bo (values %$blade_out) {
			if (exists $cmap{$bo->{dn}}) {
				my $node = $cmap{$bo->{dn}};
				#print Dumper $bo;
				foreach my $key (sort keys %inv_hash){
					$callback->({node => [ {
						name => [$node], 
						data => [{desc => [$key], 
						contents =>[$bo->{$inv_hash{$key}}]}],
					}]});
				}
			}
		}	
	}
}


sub powerStat {
	my $nh = shift;
	my $callback = shift;
	unless($nh){
		return;
	}
	my @res = _profile2dn($nh); 
	foreach my $gn (@res){
        my %nodes = %{$gn->{nodes}};
        my $blade = $gn->{ucsm}->get_dns(map {$_->{dn}} values %nodes);
	my $blade_out;
	if (exists $blade->{outConfigs}->{computeBlade}) {
	  $blade_out = $blade->{outConfigs}->{computeBlade};
        }elsif(exists $blade->{outConfigs}->{computeRackUnit}) {
	  $blade_out = $blade->{outConfigs}->{computeRackUnit};
	}
        $blade_out = {$blade_out->{dn} => $blade_out} if $blade_out->{dn};
        $blade_out->{$_}{dn}=$_ for keys %$blade_out;
        my %cmap = map { $nodes{$_}{dn} => $_ } keys %nodes;
        for (values %$blade_out) {
            if (exists $cmap{$_->{dn}}) {
                my $node = $cmap{$_->{dn}};
								my $desc = $_->{dn};
								$desc =~ s/sys\///g;
								$desc =~ s/-//g;
            	$callback->({node => [ {
                    name => [$node], 
                    data => [{desc => [$desc], 
                    contents =>[$_->{operPower}]}],
                 }]});
            }
            else { 
			        $callback->({error=>"Unknown profile returned",errorcode=>1});
            }
        }
        $gn->{ucsm}->logout();
	}
}
  

sub _profile2dn { 
    my $nh = shift;
    my @res;
	foreach my $gn (@$nh){
        my %res;
        my %profile2n = map {$gn->{nodes}{$_} => $_ } keys %{$gn->{nodes}};
        my $profile = $gn->{ucsm}->get_dns(values %{$gn->{nodes}});
        my $profile_out = $profile->{outConfigs}->{lsServer};
        # if several records returned, it outputed as subhashes, if only
        # one - as flat hash
        $profile_out = {$profile_out->{dn} => $profile_out} if $profile_out->{dn};
        $profile_out->{$_}{dn}=$_ for keys %$profile_out;
        for (values %$profile_out) {
            if (exists $profile2n{$_->{dn}}) {
                my $node = $profile2n{$_->{dn}};
                my %n;
                $n{configState} = $_->{configState};
                $n{dn} = $_->{pnDn};
                $n{node} = $node;
                $n{_profile} = $_;
								# when firmware updates are pending, node goes into applying state pending reboot.  Want to accept applying
								# as well as applied.	
                if ($n{configState} =~ /applied|applying/) {
                    $res{$node} = \%n;
                }
                else {
                    $n{configState} ||= 'UnknownState';
			        $gn->{ucsm}->err("%s in %s state and not ready", 
                        $node, $n{configState});
                }
            }
            else { 
			        $gn->{ucsm}->err("Unknown profile returned: %s", $_->{dn});
            }
        }
        my $profile_unexist = $profile->{outUnresolved}{dn};
        if ($profile_unexist) { 
        for (ref $profile_unexist eq 'ARRAY' ? @{$profile_unexist} : $profile_unexist) {
			$gn->{ucsm}->err("%s: service profile %s does not exist", $profile2n{$_->{value}}, $_->{value});
        }
        }
        push @res, {ucsm=>$gn->{ucsm}, nodes=>\%res};
    }
    return @res;
}


=item lssp

print out the Service Profiles that are found on a UCS system:
# lssp ucs101
ucs101: esxi01
ucs101: esxi02
ucs101: esxi03
...

# lssp ucs101 esxi01

# lssp 

=cut


sub lssp {
	my $request = shift;
	my $callback = shift;
	my $help;
	my $lsspUsage = sub {
		my %rsp;
		push @{$rsp{data}}, "Usage: lssp <ucs manager>";
		push @{$rsp{data}}, "       Gets all the service profiles inside of UCS Manager.";
		push @{$rsp{data}}, "       Service profiles that are associated with nodes are displayed first.";
		push @{$rsp{data}}, "       UCS Manager information should be populated in the mpa table.";
		$callback->(\%rsp);
	};
	# get UCSM information
	if($request->{arg}){
		@ARGV = @{$request->{arg}};
		GetOptions(
			'h|?|help' => \$help
		);
		if($help){
			$lsspUsage->();	
			return;
		}
	}
	
  	my $ucsm = getUCSMInfo($request->{node}, $callback);
	unless($ucsm){ return 0 }
	my $xml = "<configResolveClass classId=\"lsServer\" inHierarchical=\"false\" ^^cookie^^ />";
	foreach my $ucs (keys %$ucsm){
  	my $resp = $ucsm->{$ucs}{ucsm}->_request($xml);
		printSPs($ucs, $resp, $callback);		
  	$ucsm->{$ucs}{ucsm}->logout();
	}
}

=item printSPs

Output is expected to be something like:
    'classId' => 'lsServer',
          'response' => 'yes',
          'outConfigs' => {
                          'lsServer' => {
                                        'org-root/org-vallard-test/ls-lucky06' => {
					'mgmtFwPolicyName' => '2.0-1t',
          'fsmStatus' => 'nop',
          'fltAggr' => '1',
          'operScrubPolicyName' => 'org-root/scrub-default',
          'uuid' => '00000000-0000-0000-cafe-00000000000f',
          'operVconProfileName' => '',
          'fsmTry' => '0',
          'usrLbl' => '',
          'solPolicyName' => '',
          'bootPolicyName' => 'ESX-PXEBoot',
          'statsPolicyName' => 'default',
          'vconProfileName' => '',
					'pnDn' => '',
          'fsmRmtInvRslt' => '',
          'name' => 'Server-Template-1',
          'hostFwPolicyName' => 'B200-M2-2.0',
          'srcTemplName' => '',
          'descr' => 'Test template',
          'fsmRmtInvErrCode' => 'none',
          'operSrcTemplName' => '',
          'type' => 'initial-template',
          'intId' => '3168361',
          'operStatsPolicyName' => 'org-root/org-tige-test/thr-policy-default',
          'operMgmtAccessPolicyName' => '',
          'configQualifier' => '',
          'operBiosProfileName' => '',
          'mgmtAccessPolicyName' => '',
          'biosProfileName' => 'vallard-test',
          'fsmStamp' => 'never',
          'powerPolicyName' => 'default',
          'operSolPolicyName' => '',
          'fsmProgr' => '100',
          'operHostFwPolicyName' => 'org-root/fw-host-pack-B200-M2-2.0',
          'operState' => 'unassociated',
          'operMaintPolicyName' => 'org-root/maint-user-ack',
          'fsmPrev' => 'nop',
          'uuidSuffix' => '0000-000000000000',
          'operBootPolicyName' => '',
          'configState' => 'not-applied',
          'fsmStageDescr' => '',
          'operLocalDiskPolicyName' => 'org-root/local-disk-config-RAID-1',
          'operPowerPolicyName' => 'org-root/org-tige-test/power-policy-default',
          'owner' => 'management',
          'operIdentPoolName' => 'org-root/uuid-pool-default',
          'operMgmtFwPolicyName' => 'org-root/fw-mgmt-pack-B200-M2-2.0',
          'identPoolName' => 'vallard-test',
          'agentPolicyName' => '',
          'scrubPolicyName' => '',
          'fsmFlags' => '',
          'localDiskPolicyName' => 'RAID-1',
          'operDynamicConPolicyName' => '',
          'fsmRmtInvErrDescr' => '',
          'assignState' => 'unassigned',
          'extIPState' => 'none',
          'assocState' => 'unassociated',
          'fsmDescr' => '',
          'maintPolicyName' => 'user-ack',
          'dynamicConPolicyName' => ''

=cut



sub printSPs {
	my $ucs = shift;
	my $resp = shift;
	my $callback = shift;
	unless($resp->{outConfigs}->{lsServer}) { 
		$callback->({error=>["XML response for printing service profiles is not formatted as we expect it."],errorcode=>1});
		return;
	}
	my @unassigned;
	#print Dumper($resp);	
	foreach my $sp (keys %{$resp->{outConfigs}->{lsServer}}){
		#print Dumper $resp->{outConfigs}->{lsServer}->{$sp};
    my $aB = $resp->{outConfigs}->{lsServer}->{$sp}->{pnDn};
		unless($aB){
			push @unassigned, $sp;
			next;
		}
	 	$callback->({node => 
									[ {name => [$ucs], 
										data => [{desc => [
               					#$resp->{outConfigs}->{lsServer}->{$sp}->{name}
												$sp
												], 
											contents => [ 
												$aB
											]
							}
							] } ]});
	}

	foreach (@unassigned){
	 	$callback->({node => 
									[ {name => [$ucs], 
										data => [{desc => [
												$_
												], 
											contents => [ 
												"unassigned"
											]
							}
							] } ]});
		
	}


}


sub getUCSMInfo {
	my $ucsH;
	my $nodes = shift;
	my $callback = shift;
	my $mpaTab = xCAT::Table->new('mpa');
	if(!$mpaTab){
		$callback->({error=>"Error opening mpa table",errorcode=>1});
		return 0;
	}

	# if user doesn't specify UCSM on the command line go and get all of them.
	if(! $nodes){
		$callback->({error => "No UCS Fabric Interconnects Specified", errorcode=> 1});
		return 0;

		#my @m = ("password", 'username');
		#my $n = $mpaTab->getAllEntries;
		#my $newNodes;
		##print Dumper($n);
		#if(@$n == 0 ){
		#	$callback->({error=>"There are no enabled entries in the mpa table",errorcode=>1});
		#	return 0;
		#}
		#foreach my $h (@$n){
		#	if($h->{mpa}){
		#		push @$newNodes, $h->{mpa};
		#	}
		#}
		#$nodes = $newNodes;
	}

	foreach my $ucs (@$nodes){
		my $errCount = 0;
		my $ent = $mpaTab->getAttribs({mpa=>$ucs},'username','password');		
		# check that there is an entry
		if (! $ent){
			$errCount++;
			$callback->({error=>["$ucs: No entry in mpa table."],errorcode=>1});
		}else {
				if ($ent->{password} eq ""){
					$errCount++;
					$callback->({error=>["$ucs: No password specified in mpa table."],errorcode=>1});
				}
			
				if ($ent->{username} eq ""){
					$errCount++;
					$callback->({error=>["$ucs: No user specified in mpa table."],errorcode=>1});
				}
		}

		if($errCount){
			next;
		}
		$ucsH->{$ucs}{ucsm} = xCAT_plugin::ucs->new($callback, $ucs, $ent->{username}, $ent->{password}, $callback);
		if(! $ucsH->{$ucs}{ucsm}){
			delete $ucsH->{$ucs}{ucsm};
		}	
	}
	return $ucsH;
}

sub buildNodes {
	my $nodes = shift;
	my $callback = shift;
	my $errors = 0;
	# build the right stuff here!
	my %nh; # the node hash
	

	my @tabs = qw(mp mpa);
	my %db = ();
	# open all the tables.
	for my $table (qw(mp mpa)) {
		$db{$table} = xCAT::Table->new($table);
		if(!$db{$table}){
			$callback->({error=>"Error opening $table table",errorcode=>1});
			return 0;
		}
	}	
	
	# first get the mpas.
	my $mph = $db{'mp'}->getNodesAttribs($nodes, [qw(mpa id)]);
	foreach my $node (@$nodes){
		unless($mph->{$node}->[0] && $mph->{$node}->[0]->{mpa}){
			$errors++;
			$callback->({error=>["$node: Please specify the UCS Manager in mp.mpa"],errorcode=>1});
			next;
		}

		unless($mph->{$node}->[0]->{id}){
			$callback->({error=>["$node: No management id specified.  Please change mp.id to be service profile"],errorcode=>1});
			next;	
		}

		my $id = $mph->{$node}->[0]->{id};
		
		my $ucsm_host = $mph->{$node}->[0]->{mpa};
        $nh{$ucsm_host} ||= { 
            ucsm => undef, 
            nodes =>{}, 
        }; 

		$nh{$ucsm_host}{nodes}{$node} = $id;
	}

	# now get the user and password for the mpas
	foreach my $ucsm (keys %nh){
		my $ent = $db{'mpa'}->getAttribs({mpa=>$ucsm},'username','password');		
		if (not $ent and $ent->{password} and $ent->{username}){
            $callback->({error=>["No username or password specified in mpa.{username,password} table.  Please specify a username and password"],errorcode=>1});
            $errors++;
            next;
		}else{
            $nh{$ucsm}{ucsm} = xCAT_plugin::ucs->new($callback, $ucsm, 
                $ent->{username}, $ent->{password}, $callback);
            if (!$nh{$ucsm}{ucsm}) {
                #login error
                delete $nh{$ucsm};
            }
		}
	}
	
	if($errors){
		return 0;
	}
	return [values %nh];
} 

### Working with UCSM
#

sub new { 
    my ($class, $callback, $host, $login, $password) = @_;
    my $self = { 
        host =>             $host,
        login =>            $login,
        password =>         $password,
        callback =>         $callback,
        _cookie =>          '',
    };

    bless $self, $class;
    $self->login();
    return $self;
}

sub login {
    my $self = shift;
    my $xmlcmd =sprintf "<aaaLogin inName='%s' inPassword='%s'></aaaLogin>", 
                $self->{login}, $self->{password};
    my $resp = $self->_request($xmlcmd);
    return $self->err("login failure: %s", $resp->{errorDescr}) if $resp->{errorDescr}; 
    $self->{_cookie} = $resp->{'outCookie'};
    return $self->{_cookie};
}

sub logout {
    my $self = shift;
    $self->_request(sprintf "<aaaLogout inCookie='%s' />", $self->{_cookie});
    return;
}

sub get_dns { 
    my $self = shift;
    my @dns = @_;
	my $xml = '<configResolveDns ^^cookie^^ inHierarchical="false">'."\n";
	$xml .= "<inDns>\n";
	$xml .= "<dn value=\"$_\"/>\n" for @dns; 
	$xml .= "</inDns>\n";
	$xml .= "</configResolveDns>\n";
    return $self->_request($xml);
}

sub get_scope { 
    my $self = shift;
    my ($dn, $class) = @_;
    my $xml = sprintf '<configScope ^^cookie^^ dn="%s" inClass="%s" inHierarchical="false"'.
        ' inRecursive="false"><inFilter></inFilter></configScope>', $dn, $class;
    return $self->_request($xml);
}

sub _request {
    my ($self, $cmd) = @_;
    $cmd =~ s/\^\^cookie\^\^/ cookie="$self->{_cookie}" /gs;
    print " --> $cmd\n" if $ENV{DEBUG};
    my $browser = LWP::UserAgent->new(
      ssl_opts => {
	    verify_hostname => 0,
	    SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE
      }
    );
    my $url = sprintf 'https://%s/nuova', $self->{host};
    my $xml_header = "<?xml version='1.0'?>";
    my $request = HTTP::Request->new(POST => $url);
    $request->content_type("application/x-www-form-urlencoded");
    $request->content($cmd);

    my $response = $browser->request($request);
    unless($response->is_success){
        my $err = sprintf "xml fetch error: %s", $response->status_line;
        $self->err($err);
        my %rc = ( "errorDescr" => $err);
	my $r_ref = \%rc;
	return $r_ref;
    }
    print " <-- ".$response->content."\n\n" if $ENV{DEBUG};
    my $parser = XML::Simple->new();
    my $xml = eval {$parser->XMLin($response->content, KeyAttr => 'dn')};
    return $self->err("parsing xml %s\n----\n%s\n----\n", $@, 
        $response->content) if $@;
    return $xml;
};

sub err { 
    my ($self, $msg) = (shift, shift);
    my @params = @_;
    my $msg = "%s/".$msg;
    $self->{callback}->({error=>[sprintf $msg, $self->{host}, @params], errorcode=>1});
    #TODO make error bubling
    return 0;  
}


1;
