//simplified MC that is designed to fail when procs 'break'. When it fails it's just replaced with a new one.
//It ensures master_controller.process() is never doubled up by killing the MC (hence terminating any of its sleeping procs)
//WIP, needs lots of work still

var/global/datum/controller/game_controller/master_controller //Set in world.New()

var/global/controller_iteration = 0
var/global/last_tick_duration = 0

var/global/air_processing_killed = 0
var/global/pipe_processing_killed = 0

var/global/initialization_stage = 0

datum/controller/game_controller
	var/list/shuttle_list	                    // For debugging and VV
	var/init_immediately = FALSE

datum/controller/game_controller/New()
	//There can be only one master_controller. Out with the old and in with the new.
	if(master_controller != src)
		log_debug("Rebuilding Master Controller")
		if(istype(master_controller))
			qdel(master_controller)
		master_controller = src

	if(!job_master)
		job_master = new /datum/controller/occupations()
		job_master.SetupOccupations(setup_titles=1)
		job_master.LoadJobs("config/jobs.txt")
		admin_notice("<span class='danger'>Job setup complete</span>", R_DEBUG)

	if(!syndicate_code_phrase)		syndicate_code_phrase	= generate_code_phrase()
	if(!syndicate_code_response)	syndicate_code_response	= generate_code_phrase()

datum/controller/game_controller/proc/setup()
	world.tick_lag = config.Ticklag

	spawn(20)
		createRandomZlevel()


	preloadTemplates()

	setup_objects()
	setupgenetics()
	SetupXenoarch()

	transfer_controller = new

	report_progress("Initializations complete")
	initialization_stage |= INITIALIZATION_COMPLETE

#ifdef UNIT_TEST
#define CHECK_SLEEP_MASTER // For unit tests we don't care about a smooth lobby screen experience. We care about speed.
#else
#define CHECK_SLEEP_MASTER if(!(initialization_stage & INITIALIZATION_NOW) && ++initialized_objects > 500) { initialized_objects=0;sleep(world.tick_lag); }
#endif

datum/controller/game_controller/proc/setup_objects()
#ifndef UNIT_TEST
	var/initialized_objects = 0
#endif

	// Do these first since character setup will rely on them

	// Set up antagonists.
	populate_antag_type_list()

	//Set up spawn points.
	populate_spawn_points()

	initialization_stage |= INITIALIZATION_HAS_BEGUN

	report_progress("Initializing turbolifts")
	for(var/thing in turbolifts)
		if(!deleted(thing))
			var/obj/turbolift_map_holder/lift = thing
			lift.initialize()
			CHECK_SLEEP_MASTER

	report_progress("Initializing objects")
	for(var/atom/movable/object)
		if(!deleted(object))
			object.initialize()
			CHECK_SLEEP_MASTER

	report_progress("Initializing areas")
	for(var/area/area)
		area.initialize()
		CHECK_SLEEP_MASTER

	report_progress("Initializing pipe networks")
	for(var/obj/machinery/atmospherics/machine in machines)
		machine.build_network()
		CHECK_SLEEP_MASTER

	report_progress("Initializing atmos machinery")
	for(var/obj/machinery/atmospherics/unary/U in machines)
		if(istype(U, /obj/machinery/atmospherics/unary/vent_pump))
			var/obj/machinery/atmospherics/unary/vent_pump/T = U
			T.broadcast_status()
		else if(istype(U, /obj/machinery/atmospherics/unary/vent_scrubber))
			var/obj/machinery/atmospherics/unary/vent_scrubber/T = U
			T.broadcast_status()
		CHECK_SLEEP_MASTER

#undef CHECK_SLEEP_MASTER

datum/controller/game_controller/proc/report_progress(var/progress_message)
	admin_notice("<span class='danger'>[progress_message]</span>", R_DEBUG)
#ifdef UNIT_TEST
	to_world_log("\[[time2text(world.realtime, "hh:mm:ss")]\] [progress_message]")
#endif
