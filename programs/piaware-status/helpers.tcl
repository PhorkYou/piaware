#
# flightaware helper routines for piaware-status program
#
#

set ::nRunning 0

#
# report_status - report on what's running, inspect network connections and
#  report (if allowed), and then connect to ports and listen for data for
#  a while
#
proc report_status {} {
	set ::config [::fa_piaware_config::new_combined_config #auto]
	$::config read_config

	report_on_whats_running
	puts ""

	netstat_report
	puts ""

	check_ports_for_data
}

#
# subst_is_or_is_not - substitute "is" or "is not" into a %s in string
#  based on if value is true or false
#
proc subst_is_or_is_not {string value} {
    if {$value} {
		set value "is"
    } else {
		set value "is NOT"
    }

    return [format $string $value]
}

#
# netstat_report - parse netstat output and report
#
proc netstat_report {} {
    inspect_sockets_with_netstat

	set localPort [receiver_local_port $::config]
	if {$localPort eq 0} {
		puts "the ADS-B listener is on another host, I can't check on its status."
	} else {
		if {![info exists ::netstatus($localPort)]} {
			puts "no program appears to be listening for connections on port $localPort."
		} else {
			lassign $::netstatus($localPort) prog pid
			puts "$prog (pid $pid) is listening for connections on port $localPort."
		}
	}

	if {$::netstatus_reliable} {
		puts [subst_is_or_is_not "faup1090 %s connected to the ADS-B receiver." $::netstatus_faup1090]
		puts [subst_is_or_is_not "piaware %s connected to FlightAware." $::netstatus_piaware]
	}
}



#
# find_processes - return a list of pids running with a command of exactly "name"
#
proc find_processes {name} {
	set pidlist {}
	set fp [open "|pgrep $name"]
	while {[gets $fp line] >= 0} {
		set pid [string trim $line]
		lappend pidlist $pid
	}
	catch {close $fp}
	return $pidlist
}

#
# process_running_report - report on processes matching a regular expression
#
proc process_running_report {description expected pattern} {
	set found 0
	set fp [open "|pgrep -l $pattern"]
	while {[gets $fp line] >= 0} {
		lassign [split [string trim $line] " "] pid name
		puts "$description ($name) is running with pid $pid."
		incr found
	}
	catch {close $fp}
	if {!$found} {
		puts "$description ($expected) is not running."
	}
}

#
# report_on_whats_running - look at some programs that are interesting to
#  know about
#
proc report_on_whats_running {} {
	process_running_report "PiAware master process" piaware {^piaware$}
	process_running_report "PiAware ADS-B client" faup1090 {^faup1090$}
	process_running_report "PiAware mlat client" fa-mlat-client {^fa-mlat-client$}

	set service [receiver_local_service $::config]
	if {$service ne ""} {
		process_running_report "Local ADS-B receiver" $service "^$service"
	}
}

#
# check_ports_for_data - check for data on beast and flightaware-style ports
#
proc check_ports_for_data {} {
	set ::nRunning 0

	lassign [receiver_underlying_host_and_port $::config] rhost rport
	if {$rhost ne ""} {
		incr ::nRunning
		test_port_for_traffic $rhost $rport [list adsb_data_callback [receiver_description $::config] $rhost $rport]
	}

	lassign [receiver_host_and_port $::config] lhost lport
	if {$lhost ne "" && ($rhost ne $lhost || $rport ne $lport)} {
		incr ::nRunning
		test_port_for_traffic $lhost $lport [list adsb_data_callback "Local ADS-B relay" $lhost $lport]
	}

	while {$::nRunning > 0} {
		vwait ::nRunning
	}
}


#
# adsb_data_callback - callback when data is received on the data port
#
proc adsb_data_callback {what host port state} {
	puts [subst_is_or_is_not "$what %s producing data on $host:$port." $state]
	incr ::nRunning -1
}
