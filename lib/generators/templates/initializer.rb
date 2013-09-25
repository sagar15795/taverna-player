# Taverna Player configuration

TavernaPlayer.setup do |config|
  # This should be set to the name of the workflow model class in the main
  # application and the listed methods should also be mapped if necessary.
  config.workflow_model_proxy("Workflow")
  #config.workflow_model_proxy("Workflow") do |proxy|
    # This is the method that returns the name of the workflow file. Your
    # model MUST provide this otherwise a workflow cannot be run.
    #proxy.file_method_name = :file

    # This is the method that returns the title of the workflow. This can be
    # set to nil if your model does not have this field.
    #proxy.title_method_name = :title
  #end

  # Taverna Server configuration information. The poll interval is in seconds.
  config.server_address = "http://localhost:8080/taverna"
  config.server_username = "taverna"
  config.server_password = "taverna"
  config.server_poll_interval = 5

  # Callbacks to be run at various points during a workflow run. These can be
  # defined as Proc objects or as methods and referenced by name.
  #
  # Be careful! If a callback fails then the worker running the job will fail!
  #
  # Add callbacks in this initializer or define them elsewhere and require the
  # file as usual (if they are not pulled in by some other code). You can
  # create example stub callbacks using:
  #   "rails generate taverna_player:callbacks"
  # which will put them in "lib/taverna_player_callbacks.rb".
  #require "taverna_player_callbacks"

  # The pre-run callback is called before the run has started (before Taverna
  # Server is contacted, in fact).
  # It takes the run model object as its parameter.
  #config.pre_run_callback = Proc.new { |run| puts "Starting: #{run.name}" }
  #config.pre_run_callback = "player_pre_run_callback"
  #config.pre_run_callback = :player_pre_run_callback

  # The post-run callback is called after the run has completed normally.
  # It takes the run model object as its parameter.
  #config.post_run_callback = Proc.new { |run| puts "Finished: #{run.name}" }
  #config.post_run_callback = "player_post_run_callback"
  #config.post_run_callback = :player_post_run_callback

  # The run-cancelled callback is called if the run is cancelled by the user.
  # It takes the run model object as its parameter.
  #config.run_cancelled_callback = Proc.new { |run| puts "Cancelled: #{run.name}" }
  #config.run_cancelled_callback = "player_run_cancelled_callback"
  #config.run_cancelled_callback = :player_run_cancelled_callback
end

# Example callbacks defined in the initializer.

#def player_pre_run_callback(run)
#  puts "Starting: #{run.name}"
#end

#def player_post_run_callback(run)
#  puts "Finished: #{run.name}"
#end

#def player_run_cancelled_callback(run)
#  puts "Cancelled: #{run.name}"
#end