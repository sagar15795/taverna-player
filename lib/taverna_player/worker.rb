module TavernaPlayer
  class Worker
    include TavernaPlayer::Engine.routes.url_helpers

    def initialize(run)
      @run = run
      @workflow = TavernaPlayer.workflow_proxy.class_name.find(@run.workflow_id)
    end

    def perform
      unless TavernaPlayer.pre_run_callback.nil?
        status_message "Running pre-run tasks"
        run_callback(TavernaPlayer.pre_run_callback, @run)
      end

      status_message "Connecting to Taverna Server"

      server_uri = URI.parse(TavernaPlayer.server_address)
      credentials = T2Server::HttpBasic.new(TavernaPlayer.server_username,
        TavernaPlayer.server_password)
      conn_params = TavernaPlayer.server_connection

      begin
        server = T2Server::Server.new(server_uri, conn_params)
        wkf = File.read(TavernaPlayer.workflow_proxy.file(@workflow))

        # Try and create the run bearing in mind that the server might be at
        # the limit of runs that it can hold at once.
        begin
          run = server.create_run(wkf, credentials)
        rescue T2Server::ServerAtCapacityError
          status_message "Server full - please wait; run will start soon"

          if cancelled?
            cancel
            return
          end

          sleep(TavernaPlayer.server_retry_interval)
          retry
        end

        status_message "Initializing new workflow run"

        @run.run_id = run.id
        @run.state = run.status
        @run.create_time = run.create_time
        @run.proxy_notifications = run.notifications_uri.to_s
        @run.proxy_interactions = run.interactions_uri.to_s
        @run.save

        unless @run.inputs.size == 0
          status_message "Uploading run inputs"
          @run.inputs.each do |input|
            if input.value.blank? && !input.file.blank?
              run.input_port(input.name).file = input.file.path
            else
              run.input_port(input.name).value = input.value
            end
          end
        end

        # Just add in all service credentials right now
        TavernaPlayer::ServiceCredential.all.each do |cred|
          run.add_password_credential(cred.uri, cred.login, cred.password)
        end

        status_message "Starting run"
        run.name = @run.name

        # Try and start the run bearing in mind that the server might be at
        # the limit of runs that it can run at once.
        while !run.start
          status_message "Server busy - please wait; run will start soon"

          if cancelled?
            cancel(run)
            return
          end

          sleep(TavernaPlayer.server_retry_interval)
        end

        @run.state = run.status
        @run.start_time = run.start_time
        @run.save

        status_message "Running"
        until run.finished?
          sleep(TavernaPlayer.server_poll_interval)
          waiting = false

          if cancelled?
            cancel(run)
            return
          end

          run.notifications(:requests).each do |note|
            waiting = true unless note.has_reply?
            int = Interaction.find_or_create_by_run_id_and_unique_id(@run.id, note.id)

            # Need to catch this here in case some other process has replied.
            if note.has_reply? && !int.replied?
              int.replied = true
              int.save
            end

            unless int.replied?
              if int.page.blank?
                page = server.read(note.uri, "text/html", credentials)
                page.gsub!(@run.proxy_interactions,
                  run_url(@run, :protocol => TavernaPlayer.hostname[:scheme],
                    :host => TavernaPlayer.hostname[:host]) +
                  "/proxy/#{int.unique_id}")
                page.gsub!(@run.proxy_notifications,
                  run_url(@run, :protocol => TavernaPlayer.hostname[:scheme],
                    :host => TavernaPlayer.hostname[:host]) +
                  "/proxy/#{int.unique_id}")
                int.page = page
              end

              if !int.feed_reply.blank? && !int.output_value.blank?
                note.reply(int.feed_reply, int.output_value)

                int.replied = true
              end

              int.save
            end

          end

          status_message(waiting ? "Waiting for user input" : "Running")
        end

        status_message "Gathering run outputs and log"
        download_outputs(run)
        download_log(run)

        @run.outputs = process_outputs(run)
        @run.finish_time = run.finish_time
        @run.save

        run.delete
      rescue Exception => exception
        begin
          unless run.nil?
            download_log(run)
            run.delete
          end
        rescue
          # Try and grab the log then delete the run from Taverna Server here,
          # but at this point we don't care if we fail...
        end

        backtrace = exception.backtrace.join("\n")
        @run.failure_message = "#{exception.message}\n#{backtrace}"

        @run.state = :failed
        status_message "Failed"
        return
      end

      unless TavernaPlayer.post_run_callback.nil?
        status_message "Running post-run tasks"
        run_callback(TavernaPlayer.post_run_callback, @run)
      end

      @run.state = :finished
      status_message "Finished"
    end

    private

    def run_callback(callback, *params)
      if callback.is_a? Proc
        callback.call(*params)
      else
        method(callback).call(*params)
      end
    end

    def download_log(run)
      Dir.mktmpdir(run.id, Rails.root.join("tmp")) do |tmp_dir|
        tmp_file_name = File.join(tmp_dir, "log.txt")
        begin
          run.log(tmp_file_name)
          @run.log = File.new(tmp_file_name)
          @run.save
        rescue T2Server::AttributeNotFoundError
          # We don't care if there's no log but we do want to catch the error!
        end
      end
    end

    def download_outputs(run)
      Dir.mktmpdir(run.id, Rails.root.join("tmp")) do |tmp_dir|
        tmp_file_name = File.join(tmp_dir, "all.zip")
        run.zip_output(tmp_file_name)
        @run.results = File.new(tmp_file_name)
        @run.save
      end
    end

    def process_outputs(run)
      outputs = []

      run.output_ports.each_value do |port|
        output = TavernaPlayer::RunPort::Output.new(:name => port.name,
          :depth => port.depth)

        if port.depth == 0 && port.type =~ /text/
          if port.size < 255
            output.value = port.value
          else
            output.value = port.value(0..255)
          end
        end

        output.metadata = {
          :size => port.size,
          :type => port.type
        }

        outputs << output
      end

      outputs
    end

    def status_message(message)
      @run.status_message = message
      @run.save!
    end

    def cancelled?
      # Need to poll for updates as the run instance may have been
      # changed in the Rails app.
      @run.reload
      @run.cancelled?
    end

    def cancel(run = nil)
      status_message "Cancelling"

      unless run.nil?
        download_log(run)
        run.delete
      end

      unless TavernaPlayer.run_cancelled_callback.nil?
        status_message "Running post-cancel tasks"
        run_callback(TavernaPlayer.run_cancelled_callback, @run)
      end

      status_message "Cancelled"
    end

  end
end
