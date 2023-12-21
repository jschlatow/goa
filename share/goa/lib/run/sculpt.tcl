proc run_genode { } {
	global run_dir tool_dir var_dir target target_opt

	if {![info exists target_opt($target-server)]} {
		exit_with_error "missing target option '$target-server'\n" \
		                "\n define 'set target_opt($target-server) <url>' in your" \
		                "\n goarc file, or specify '--target-opt-$target-server <url>'" \
		                "\n as command-line argument\n"
	}

	if {![info exists target_opt($target-port-http)]} {
		set target_opt($target-port-http) 80 }

	if {![info exists target_opt($target-port-telnet)]} {
		set target_opt($target-port-telnet) 23 }

	set host        $target_opt($target-server)
	set port_http   $target_opt($target-port-http)
	set port_telnet $target_opt($target-port-telnet)

	# create lambda to make config-deletion command re-usable
	set clear_config {{cmd} {
		diag "deleting config from server via: $cmd config DELETE=1"
		if {[catch { exec {*}$cmd config DELETE=1 >@stdout} msg]} {
			exit_with_error $msg }
	}}

	set     cmd "make"
	lappend cmd "-f" [file join $tool_dir lib sync_http.mk]
	lappend cmd "TMP_DIR=[file join $var_dir targets $target]"
	lappend cmd "SRC_DIR=$run_dir"
	lappend cmd "SERVER=http://$host:$port_http"

	# make sure the remote config is empty
	apply $clear_config $cmd

	# sync all files expect config
	set modules [glob -type f -directory $run_dir -tails *]
	set modules [lsearch -inline -all -not -exact $modules config]
	diag "uploading modules to server via: $cmd $modules"
	if {[catch { exec {*}$cmd {*}$modules >@ stdout} msg]} {
		exit_with_error $msg }
	
	# sync config and thereby start the scenario
	diag "uploading config to server via: $cmd config"
	if {[catch { exec {*}$cmd config >@stdout} msg]} {
		exit_with_error $msg }

	eval spawn -noecho telnet $host $port_telnet
#
	set timeout -1
	interact {
		\003 {
			send_user "Expect: 'interact' received 'strg+c' and was cancelled\n";
			# delete config on remote target
			apply $clear_config $cmd
			exit
		}
		-i $spawn_id
	}
}


proc parent_services { } {
	return [list TRACE RM VM Timer Rtc Gui Nic Event Capture \
	             Audio_out Audio_in Usb Gpu Report File_system] }


proc base_archives { } { return {} }


proc bind_provided_services { &services } {
	# use upvar to access array
	upvar 1 ${&services} services

	# instantiate NIC driver in uplink mode if required by runtime
	foreach name [array names services] {
		log "Ignoring provided <$name/> service." }

	return [list { } { } { } { }]
}


proc bind_required_services { &services } {
	# use upvar to access array
	upvar 1 ${&services} services

	# make sure to declare variables locally
	variable start_nodes routes archives modules

	set routes { }
	set start_nodes { }
	set archives { }
	set modules { }

	##
	# instantiate fonts_fs
	if {[info exists services(file_system)]} {
		set unknown_fs_label 0
		foreach fs_node $services(file_system) {
			variable label
			set label [query_from_string string(*/@label) $fs_node  ""]

			if {$label == "fonts"} {
				append routes "\n\t\t\t\t\t" \
					"<service name=\"File_system\" label=\"fonts\"> " \
					"<child name=\"fonts_fs\"/> " \
					"</service>"

				_instantiate_fonts_fs start_nodes archives modules
			} else {
				set unknown_fs_label 1
			}
		}

		# unsetting prevents that a generic parent route is added below
		if {!$unknown_fs_label} {
			unset services(file_system)
		}
	}

	##
	# route known ROMs by label
	if {[info exists services(rom)]} {
		set unknown_rom_label 0
		set known_roms [list clipboard platform_info capslock]
		foreach rom_node $services(rom) {
			variable label
			set label [query_from_string string(*/@label) $rom_node ""]

			if {[lsearch -exact $known_roms $label] > -1} {
				append routes "\n\t\t\t\t\t" \
					"<service name=\"ROM\" label=\"$label\"> " \
					"<parent label=\"$label\"/> " \
					"</service>"
			} else {
				set unknown_rom_label 1
			}
		}

		if {$unknown_rom_label} {
			append routes "\n\t\t\t\t\t" \
				"<service name=\"ROM\"> " \
				"<parent/> " \
				"</service>"
		}

		unset services(rom)
	}


	##
	# route known Reports by label
	if {[info exists services(report)]} {
		set unknown_report_label 0
		set known_reports [list clipboard shape]
		foreach report_node $services(report) {
			variable label
			set label [query_from_string string(*/@label) $report_node ""]

			if {[lsearch -exact $known_reports $label] > -1} {
				append routes "\n\t\t\t\t\t" \
					"<service name=\"Report\" label=\"$label\"> " \
					"<parent label=\"$label\"/> " \
					"</service>"
			} else {
				set unknown_report_label 1
			}
		}

		# unsetting prevents that a generic parent route is added below
		if {!$unknown_report_label} {
			unset services(report)
		}
	}


	# route remaining parent services if required by runtime
	foreach name [parent_services] {
		set name_lc [string tolower $name]
		if {[info exists services($name_lc)]} {
			append routes "\n\t\t\t\t\t" \
			              "<service name=\"$name\"> " \
			              "<parent/> " \
			              "</service>"
			unset services($name_lc)
		}
	}

	return [list $start_nodes $routes $archives $modules ]
}


proc _instantiate_fonts_fs { &start_nodes &archives &modules } {
	upvar 1 ${&start_nodes} start_nodes
	upvar 1 ${&archives} archives
	upvar 1 ${&modules} modules

	global run_as

	append start_nodes {
		<start name="fonts_fs" caps="100">
			<binary name="vfs"/>
			<resource name="RAM" quantum="2M"/>
			<provides> <service name="File_system"/> </provides>
			<route>
				<service name="ROM" label="config"> <parent label="fonts_fs.config"/> </service>
				<service name="PD">  <parent/> </service>
				<service name="CPU"> <parent/> </service>
				<service name="LOG"> <parent/> </service>
				<service name="ROM"> <parent/> </service>
			</route>
		</start>
	}

	lappend modules vfs fonts_fs.config

	lappend archives $run_as/pkg/fonts_fs
}
