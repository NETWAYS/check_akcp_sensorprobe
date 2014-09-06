#!/usr/bin/perl -w
# $Id: a0ce22f1761eee78dbe31f438a70a9fa27e81c9a $

=pod

=head1 COPYRIGHT

 
This software is Copyright (c) 2010 NETWAYS GmbH, Thomas Gelf
                               <support@netways.de>

(Except where explicitly superseded by other copyright notices)

=head1 LICENSE

This work is made available to you under the terms of Version 2 of
the GNU General Public License. A copy of that license should have
been provided with this software, but in any event can be snarfed
from http://www.fsf.org.

This work is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
02110-1301 or visit their web page on the internet at
http://www.fsf.org.


CONTRIBUTION SUBMISSION POLICY:

(The following paragraph is not intended to limit the rights granted
to you to modify and distribute this software under the terms of
the GNU General Public License and is only of importance to you if
you choose to contribute your changes and enhancements to the
community by submitting them to NETWAYS GmbH.)

By intentionally submitting any modifications, corrections or
derivatives to this work, or any other work intended for use with
this Software, to NETWAYS GmbH, you confirm that
you are the copyright holder for those contributions and you grant
NETWAYS GmbH a nonexclusive, worldwide, irrevocable,
royalty-free, perpetual, license to use, copy, create derivative
works based on those contributions, and sublicense and distribute
those contributions and any derivatives thereof.

Nagios and the Nagios logo are registered trademarks of Ethan Galstad.

=head1 NAME

check_akcp

=head1 SYNOPSIS

This plugin queries AKCP sensors using SNMP

=head1 OPTIONS

check_akcp_sensorprobe.pl [options] -H <hostname> <SNMP community>

=over

=item   B<-H>

Hostname

=item   B<-C>

Community string (default is "public")

=back

=head1 DESCRIPTION

This plugin queries AKCP sensors using SNMP

MIB file is not required, OIDs are hardcoded. This plugin is able to
discover your AKCP device capabilities, connected sensors and configured
thresholds.

=cut

use Getopt::Long;
use Pod::Usage;
use File::Basename;
use Net::SNMP;
use Data::Dumper;

# predeclared subs
use subs qw/help fail fetchOids checkAkcp/;

# predeclared vars
use vars qw (
  $PROGNAME
  $VERSION

  %states
  %state_names
  %performance

  @info
  @perflist

  $opt_host
  $opt_help
  $opt_man
  $opt_verbose
  $opt_version
);

# Main values
$PROGNAME = basename($0);
$VERSION  = '1.2';

# Nagios exit states
%states = (
	'OK'       => 0,
	'WARNING'  => 1,
	'CRITICAL' => 2,
	'UNKNOWN'  => 3
);

# Nagios state names
%state_names = (
	0 => 'OK',
	1 => 'WARNING',
	2 => 'CRITICAL',
	3 => 'UNKNOWN'
);

# SNMP
my $opt_community = 'public';
#my $snmp_version  = "2c";
my $snmp_version  = '1';
my $global_state = 'OK';

# Retrieve commandline options
Getopt::Long::Configure('bundling');
GetOptions(
	'h|help'    => \$opt_help,
	'man'       => \$opt_man,
	'H=s'       => \$opt_host,
	'C=s',      => \$opt_community,
	'v|verbose' => \$opt_verbose,
	'V'		    => \$opt_version
) || help( 1, 'Please check your options!' );

# Any help needed?
help( 1) if $opt_help;
help(99) if $opt_man;
help(-1) if $opt_version;
help(1, 'Not enough options specified!') unless ($opt_host);

### OID definitions ###
my $vendor = '.1.3.6.1.4.1.3854';   # Enterprise OID for AKCP (KPC Inc.)
my $baseOid = $vendor . '.1.2.2.1'; # sensorProbe(1).spSensor(2).sensorProbeDetail(2).sensorProbeEntry(1)
my $baseOidTemp = $baseOid . '.16'; # Temperature sensors
my $baseOidHumi = $baseOid . '.17'; # Humidity sensors
my $baseOidSwit = $baseOid . '.18'; # Switch sensors
my $overall_status_oid = $vendor . '.1.1.2.0'; # sensorProbe(1).spSummary(1).spStatus(2).0
my $product_name_oid   = $vendor . '.1.1.8.0'; # sensorProbe(1).spSummary(1).productName(8).0

# Prepare SNMP Session
my ($session, $error) = Net::SNMP->session(
	-hostname  => $opt_host,
	-community => $opt_community,
	-port      => 161,
	-version   => $snmp_version,
);
fail('UNKNOWN', $error) unless defined($session);

# Mapping global sensor status values to Nagios/Icinga status codes
my %global_status_map = (
	1 => 'UNKNOWN', # noStatus
	2 => 'OK',       # normal
	3 => 'WARNING',  # warning
	4 => 'CRITICAL', # critical
	5 => 'CRITICAL'  # sensorError
);

# Mapping per-sensor status values to Nagios/Icinga status codes
my %status_map = (
    0 => 'OK',       # OFF
	1 => 'CRITICAL', # noStatus
	2 => 'OK',       # normal
	3 => 'WARNING',  # highWarning
	4 => 'CRITICAL', # highCritical
	5 => 'WARNING',  # lowWarning
	6 => 'CRITICAL', # lowCritical
	7 => 'CRITICAL', # sensorError / anyError
	8 => 'OK',       # relayOn (really OK??)
	9 => 'CRICITAL'  # relayOff (CRITICAL??)
);

# Mapping AKCP degree type to textual representation
my %degree_map = (
	0 => 'F',
	1 => 'C'
);

checkAkcp();

foreach (keys %performance) {
	push @perflist, $_ . '=' . $performance{$_};
}
my $info_delim = ', ';
$info_delim = "\n";
printf('%s %s|%s', $global_state, join($info_delim, @info), join(' ', sort @perflist));
exit $states{$global_state};

sub checkAkcp()
{
    my %global = fetchOids({
        $overall_status_oid => 'status',
        $product_name_oid   => 'product',
    });
    $global_state = $global_status_map{$global{'status'}};
    my %global_info = (
        'OK'       => 'Sensor reports that everything is fine',
        'WARNING'  => 'Sensor reports one or more non-critical problems',
        'CRITICAL' => 'Sensor reports one or more critical issues',
        'UNKNOWN'  => 'Sensor state is currently unknown',
    );
    push @info, sprintf('%s: %s', $global{'product'}, $global_info{$global_status_map{$global{'status'}}});

    my @ts = getEnabledSensors($baseOidTemp . '.1.5');
    my @hs = getEnabledSensors($baseOidHumi . '.1.5');
    my @ss = getEnabledSensors($baseOidSwit . '.1.4');

    foreach my $s (@ts) {
        checkTempSensor($s);
    }
    foreach my $s (@hs) {
        checkHumiSensor($s);
    }
    foreach my $s (@ss) {
        checkSwitchSensor($s);
    }
}

sub checkTempSensor {
    my $id = shift;
    my $oid = $baseOidTemp;

    my %result = fetchOids({
	    $oid . '.1.1.'  . $id  => 'description',  # Sensor name / description
	    $oid . '.1.14.' . $id  => 'degree',	      # Currently measured degree
	    $oid . '.1.4.'  . $id  => 'status',	      # Sensor status, see %status_map
	    $oid . '.1.7.'  . $id  => 'highWarning',  # Configured upper warning threshold
	    $oid . '.1.8.'  . $id  => 'highCritical', # Configured upper critical threshold
	    $oid . '.1.9.'  . $id  => 'lowWarning',   # Configured lower warning threshold
	    $oid . '.1.10.' . $id  => 'lowCritical',  # Configured lower critical threshold
	    $oid . '.1.12.' . $id  => 'degreeType',   # fahr(0), celcius(1)
    });
    $performance{sanitize($result{'description'})} = sprintf(
	    "%.2f;%.1f:%.1f;%.1f:%.1f",
        $result{'degree'} / 10,
        $result{'lowWarning'},
        $result{'highWarning'},
        $result{'lowCritical'},
        $result{'highCritical'}
    );
    push @info, sprintf(
	    '%s Temperature sensor "%s": %.2f%s (%.1f:%.1f/%.1f:%.1f)',
        $status_map{$result{'status'}},
        $result{'description'},
        $result{'degree'} / 10,
        $degree_map{$result{'degreeType'}},
        $result{'lowWarning'},
        $result{'highWarning'},
        $result{'lowCritical'},
        $result{'highCritical'}
    );
}

sub sanitize {
    my $name = shift;
    $name =~ s/[^a-zA-Z0-9_-]/_/g;
    return $name;
}

sub checkHumiSensor {
    my $id = shift;
    my $oid = $baseOidHumi;

    my %result = fetchOids({
	    $oid . '.1.1.' . $id   => 'description',  # Sensor name / description
	    $oid . '.1.3.' . $id   => 'percent',	  # Currently measured percentage
	    $oid . '.1.4.' . $id   => 'status',	      # Sensor status, see %status_map
	    $oid . '.1.7.' . $id   => 'highWarning',  # Configured upper warning threshold
	    $oid . '.1.8.' . $id   => 'highCritical', # Configured upper critical threshold
	    $oid . '.1.9.' . $id   => 'lowWarning',   # Configured lower warning threshold
	    $oid . '.1.10.' . $id  => 'lowCritical',  # Configured lower critical threshold
    });
    $performance{sanitize($result{'description'})} = sprintf(
	    "%.2f%%;%.1f:%.1f;%.1f:%.1f",
        $result{'percent'},
        $result{'lowWarning'},
        $result{'highWarning'},
        $result{'lowCritical'},
        $result{'highCritical'}
    );
    push @info, sprintf(
	    '%s Humidity sensor "%s": %.2f%% (%.1f:%.1f/%.1f:%.1f)',
        $status_map{$result{'status'}},
        $result{'description'},
        $result{'percent'},
        $result{'lowWarning'},
        $result{'highWarning'},
        $result{'lowCritical'},
        $result{'highCritical'}
    );
}

sub checkSwitchSensor {
    my $id = shift;
    my $oid = $baseOidSwit;

    my %result = fetchOids({
	    $oid . '.1.1.' . $id   => 'description',  # Sensor name / description
	    $oid . '.1.3.' . $id   => 'status',	      # Sensor status, see %status_map
	    $oid . '.1.7.' . $id   => 'normalState',  # closed(0), open(1)
        # Removed, as not available on all sensors:
	    # $oid . '.1.9.' . $id   => 'sensorType',   # Sensor type: temperature(1),
                               # fourTo20mA(2), humidity(3), water(4), atod(5),
                               # security(6), airflow(8), siren(9), dryContact(10),
                               # voltage(12), relay(13), motion(14)
    });

    my %stat = (
        0 => 'closed',
        1 => 'open'
    );
    my $status = $status_map{$result{'status'}};

    push @info, sprintf(
	    '%s Switch sensor "%s" is normally %s',
        $status,
        $result{'description'},
        $stat{$result{'normalState'}},
    );
}

###
# Returns an array with all enabled sensors for a given sensor family base OID
#
# Example fetching all temperature sensors (.16):
# @array = getEnabledSensors(".1.3.6.1.4.1.3854.1.2.2.1.16");
###
sub getEnabledSensors {
	my $oid = $_[0];
	my $result = $session->get_table(
		# Whether this sensor is administratively up
		# (switched on or off): 1 -> online, 2 -> offline
		-baseoid => $oid
	);
	my @enabled;

	foreach my $oid (keys %$result) {
		if ($result->{$oid} == 1) {
			push @enabled, $1 if $oid =~ /\.(\d+)$/;
		}
	}
	return @enabled;
}

###
# Counts available sensors for a given sensor family base OID
#
# Example returning the number of enabled humidity sensors (.17):
# $count = countSensors(".1.3.6.1.4.1.3854.1.2.2.1.17");
###
sub countSensors {
	my $baseOid = $_[0];
	my $result = $session->get_table(
		-baseoid => $baseOid . ".1.5"
	);
	return scalar keys %$result;
}

# Fetch given OIDs, return a hash
sub fetchOids {
	my %result;
	my %oids = %{$_[0]};
	my ($r, $error) = $session->get_request(keys %oids);
	if (!defined($r)) {
		fail('CRITICAL', sprintf(
            'Failed to query device %s: %s',
            $opt_host,
            $session-> error()
        ));
	};
    foreach (keys %{$r}) {
       $result{$oids{$_}} = $r->{$_};
    }
	return %result;
}

# Raise global state if given one is higher than the current state
sub raiseGlobalState {
	my @states = @_;
	foreach my $state (@states) {
		# Pay attention: UNKNOWN > CRITICAL
		if ($states{$state} > $states{$global_state}) {
			$global_state = $state;
		}
	}
}

# Print error message and terminate program with given status code
sub fail {
	my ($state, $msg) = @_;
	print $state_names{ $states{$state} } . ": $msg";
	exit $states{$state};
}

# help($level, $msg);
# prints some message and the POD DOC
sub help {
	my ($level, $msg) = @_;
	$level = 0 unless ($level);
	if ($level == -1) {
		print "$PROGNAME - Version: $VERSION\n";
		exit $states{UNKNOWN};
	}
	pod2usage({
		-message => $msg,
		-verbose => $level
	});
	exit $states{'UNKNOWN'};
}

1;
