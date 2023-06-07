##
##
# Acquire config XML
#
proc _acquire_config { runtime_file } {
	set config ""
	set routes ""

	catch {
		set config [query_from_file /runtime/config $runtime_file]
		set config [desanitize_xml_characters $config]
	}

	catch {
		set rom_name [query_attr_from_file /runtime config $runtime_file]
		append routes "\n\t\t\t\t\t" \
		              "<service name=\"ROM\" label=\"config\"> " \
		              "<parent label=\"$rom_name\"/> " \
		              "</service>"

		if {$config != ""} {
			exit_with_error "runtime config is ambiguous,"
			                "specified as 'config' attribute as well as '<config>' node" }

		# check existence of $rom_name in raw/
		set config_file [file join raw $rom_name]
		if {![file exists $config_file]} {
			exit_with_error "runtime declares 'config=\"$rom_name\"' but the file raw/$rom_name is missing" }

		# load content into config variable
		set config [query_from_file /* $config_file]
		set config [desanitize_xml_characters $config]
	}

	if {$config == ""} {
		exit_with_error "runtime lacks a configuration\n" \
		                "\n You may declare a 'config' attribute in the <runtime> node, or" \
		                "\n define a <config> node inside the <runtime> node.\n"
	}
	return [list $config $routes]
}


##
##
# Check consistency between config of init component and required/provided
# runtime services
#
proc _validate_init_config { config &required_services &provided_services } {
	upvar 1 ${&required_services} required_services
	upvar 1 ${&provided_services} provided_services

	# get services from <parent-provides>
	set parent_provides [query_attrs_from_string "/config/parent-provides/service" name $config]
	set parent_provides [string tolower $parent_provides]

	# check that all required services are mentioned as <parent-provides>
	foreach service_name [array names required_services] {
		if {[lsearch -exact $parent_provides $service_name] == -1} {
			exit_with_error "runtime requires <$service_name/>, which is not mentioned in <parent-provides>" }
	}

	# check that all parent_provides services are base services or required services
	foreach parent_service $parent_provides {
		if {[lsearch -exact [list rom pd cpu log] $parent_service] > -1} { continue }

		if {[lsearch -nocase [array names required_services] $parent_service] == -1} {
			log "config mentions $parent_service service as parent provided" \
			    "but runtime lacks corresponding requirement"
		}
}

	# get services from config
	set services_from_config { }
	catch {
		set services_from_config [query_attrs_from_string /config/service name $config]
		set services_from_config [lsort -unique [string tolower $services_from_config]]
	}

	# check that provided service is mentioned in config
	set checked_provided_services { }
	foreach service_name [array names provided_services] {
		if {[lsearch -exact $services_from_config $service_name] == -1} {
			exit_with_error "runtime provides <$service_name/> but the corresponding" \
			                "service routing is missing in config"
		} else {
			lappend checked_provided_services $service_name
		}
	}

	# check that services mentioned/routed in config are provided
	foreach service $services_from_config {
		if {[lsearch -exact $checked_provided_services $service] == -1} {
			exit_with_error "runtime does not provide <$service/> as specified by config" }
	}
}


##
##
# Acquire list of required and provided services (as XML nodes)
# This procedure also conducts a couple of sanity checks on the way.
#
proc _acquire_services { known_services runtime_file config } {
	# get required services from runtime file
	array set required_services { }
	catch {
		set service_nodes [query_from_file "/runtime/requires/*" $runtime_file]
		set service_nodes [split $service_nodes \n]

		foreach service_node $service_nodes {
			set service_name [query_from_string "name(/*)" $service_node ""]

			if {![info exists required_services($service_name)]} {
				set required_services($service_name) { } }

			lappend required_services($service_name) $service_node
		}
	}

	# check that all required services are known
	foreach service_name [array names required_services] {
		if {[lsearch -exact $known_services $service_name] == -1} {
			exit_with_error "runtime requires unknown <$service_name/>" }
	}

	# get provided services from runtime file
	array set provided_services { }
	catch {
		set service_nodes [query_from_file "/runtime/provides/*" $runtime_file]
		set service_nodes [split $service_nodes \n]

		foreach service_node $service_nodes {
			set service_name [query_from_string "name(/*)" $service_node ""]

			if {![info exists provided_services($service_name)]} {
				set provided_services($service_name) { } }

			lappend provided_services($service_name) $service_node
		}
	}

	# check that all provided services are known
	foreach service_name [array names provided_services] {
		if {[lsearch -exact $known_services $service_name] == -1} {
			exit_with_error "runtime provides unknown <$service_name/>" }
	}

	catch {
		# if <parent-provides> is present in config, do more consistency checks
		set dummy [query_from_string "/config/parent-provides" $config ""]
		_validate_init_config $config required_services provided_services
	}

	return [list [array get required_services] [array get provided_services]]
}


##
##
# Generate and install runtime config.
# The procedure may extend the lists of 'runtime_archives' and 'rom_modules'.
#
proc generate_runtime_config { runtime_file &runtime_archives &rom_modules } {
	upvar 1 ${&runtime_archives} runtime_archives
	upvar 1 ${&rom_modules} rom_modules

	global project_name run_dir var_dir run_as

	set ram    [try_query_attr_from_file $runtime_file ram]
	set caps   [try_query_attr_from_file $runtime_file caps]
	set binary [try_query_attr_from_file $runtime_file binary]

	# get config XML from runtime file
	lassign [_acquire_config $runtime_file] config routes

	# list of services that are do not need to mentioned as requirement
	set base_services   [list CPU PD LOG]

	# remaining services
	set other_services [list Audio_in Audio_out Uplink Nic Capture Event Gui TRACE \
	                         Block Platform IO_MEM IO_PORT IRQ File_system Timer RM \
	                         Rtc Gpu Report ROM Usb Terminal VM Pin_ctrl Pin_state]

	# all known services
	set known_services [concat $base_services $other_services]]

	# services supported by black_hole component
	set blackhole_supported_services [list report audio_io audio_out]

	# check and acquire required/provided services from runtime file
	lassign [_acquire_services [string tolower $known_services] \
	                           $runtime_file $config] required provided

	array set required_services $required
	array set provided_services $provided

	# warn if base services are mentioned as requirements
	foreach service_name [array names required_services] {
		if {[lsearch -exact -nocase $base_services $service_name] > -1} {
			log "runtime explicitly requires <$service_name/>, which is always routed" }
	}

	set rom_modules [query_attrs_from_file "/runtime/content/rom" label $runtime_file]
	lappend rom_modules core ld.lib.so init

	set start_nodes ""
	set provides ""

	# add provided services to <provides>
	foreach service_name [array names provided_services] {
		set cased_name [lindex $known_services [lsearch -exact -nocase $known_services $service_name]]
		append provides "\n\t\t\t\t\t" \
			{<service name="} $cased_name {"/>}
	}

	# bind provided services
	set _res [bind_provided_services provided_services]
	append  start_nodes         [lindex $_res 0]
	append  routes              [lindex $_res 1]
	lappend runtime_archives {*}[lindex $_res 2]
	lappend rom_modules      {*}[lindex $_res 3]

	foreach service [array names provided_services] {
		log "runtime-declared provided <$service/> will be ignored" }

	# bind services by target-specific implementation
	set _res [bind_required_services required_services]
	append  start_nodes         [lindex $_res 0]
	append  routes              [lindex $_res 1]
	lappend runtime_archives {*}[lindex $_res 2]
	lappend rom_modules      {*}[lindex $_res 3]


	# route remaining services to blackhole component
	set blackhole_config ""
	set blackhole_provides ""

	foreach service [array names required_services] {
		if {[llength $required_services($service)] == 0} { continue }

		if {[lsearch -exact $blackhole_supported_services $service] > -1} {
			set cased_name [lindex $known_services [lsearch -exact -nocase $known_services $service]]

			append blackhole_config {
					<} $service {/>}
			append blackhole_provides {
					<service name="} $cased_name {"/>}

			foreach service_node $required_services($service) {
				set label [query_from_string string(*/@label) $service_node ""]

				if {$label == ""} {
					append routes "\n\t\t\t\t\t" \
						{<service name="} $cased_name {"> <child name="black_hole"/> </service>}

					log "routing <$service/> requirement to black-hole component"
				} else {
					append routes "\n\t\t\t\t\t" \
						{<service name="} $cased_name {" label_last="} $label {">}\
						{ <child name="black_hole"/> </service>}

					log "routing <$service label=\"$label\"/> requirement to black-hole component"
				}
			}


		} else {
			log "runtime-declared <$service/> requirement is not supported" }
	}

	if {$blackhole_config != ""} {
		append start_nodes {
			<start name="black_hole" caps="100">
				<resource name="RAM" quantum="2M"/>
				<provides> } $blackhole_provides {
				</provides>
				<config> } $blackhole_config {
				</config>
				<route>
					<service name="PD">  <parent/> </service>
					<service name="CPU"> <parent/> </service>
					<service name="LOG"> <parent/> </service>
					<service name="ROM"> <parent/> </service>
				</route>
			</start>
		}

		lappend rom_modules black_hole

		lappend runtime_archives "$run_as/src/black_hole"
	}

	install_config {
		<config>
			<parent-provides>
				<service name="ROM"/>
				<service name="PD"/>
				<service name="RM"/>
				<service name="CPU"/>
				<service name="LOG"/>
				<service name="TRACE"/>
			</parent-provides>

			} $start_nodes {

			<start name="} $project_name {" caps="} $caps {">
				<resource name="RAM" quantum="} $ram {"/>
				<binary name="} $binary {"/>
				<provides>} $provides {</provides>
				<route>} $routes {
					<service name="ROM">   <parent/> </service>
					<service name="PD">    <parent/> </service>
					<service name="RM">    <parent/> </service>
					<service name="CPU">   <parent/> </service>
					<service name="LOG">   <parent/> </service>
				</route>
				} $config {
			</start>
		</config>
	}

	lappend runtime_archives "$run_as/src/init"
	lappend runtime_archives {*}[base_archives]

	set rom_modules      [lsort -unique $rom_modules]
	set runtime_archives [lsort -unique $runtime_archives]
}
