check_akcp_sensorprobe
======================

This plugin queries AKCP sensors using SNMP MIB file is not required, OIDs are hardcoded. This plugin is able to discover your AKCP device capabilities, connected sensors and configured thresholds.

## Required Perl Libraries

* Net::SNMP

### Options

    check_akcp_sensorprobe.pl [options] -H

    -H  Hostname
    -C  Community string (default is "public")
