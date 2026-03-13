# frozen_string_literal: true

require 'fileutils'

module Legion
  class Process
    def self.run!(options)
      Legion::Process.new(options).run!
    end

    attr_reader :options, :quit, :service

    def initialize(options)
      @options = options
      options[:logfile] = File.expand_path(logfile) if logfile?
      options[:pidfile] = File.expand_path(pidfile) if pidfile?
    end

    def daemonize?
      options[:daemonize]
    end

    def logfile
      options[:logfile]
    end

    def pidfile
      options[:pidfile]
    end

    def logfile?
      !logfile.nil?
    end

    def pidfile?
      !pidfile.nil?
    end

    def info(msg)
      puts "[#{::Process.pid}] [#{Time.now}] #{msg}"
    end

    def run!
      start_time = Time.now
      @options[:time_limit] = @options[:time_limit].to_i if @options.key? :time_limit
      @quit = false
      check_pid
      daemonize if daemonize?
      write_pid
      trap_signals

      until quit
        sleep(1)
        @quit = true if @options.key?(:time_limit) && Time.now - start_time > @options[:time_limit]
      end
      Legion::Logging.info('Legion is shutting down!')
      Legion.shutdown
      Legion::Logging.info('Legion has shutdown. Goodbye!')

      exit
    end

    #==========================================================================
    # DAEMONIZING, PID MANAGEMENT, and OUTPUT REDIRECTION
    #==========================================================================

    def daemonize
      exit if fork
      ::Process.setsid
      exit if fork
      Dir.chdir '/'
    end

    def write_pid
      if pidfile?
        begin
          File.open(pidfile, ::File::CREAT | ::File::EXCL | ::File::WRONLY) { |f| f.write(::Process.pid.to_s) }
          at_exit { FileUtils.rm_f(pidfile) }
        rescue Errno::EEXIST
          check_pid
          retry
        end
      end
      false
    end

    def check_pid
      if pidfile?
        case pid_status(pidfile)
        when :running, :not_owned
          exit(1)
        when :dead
          File.delete(pidfile)
        end
      end
      false
    end

    def pid_status(pidfile)
      return :exited unless File.exist?(pidfile)

      pid = ::File.read(pidfile).to_i
      return :dead if pid.zero?

      ::Process.kill(0, pid)
      :running
    rescue Errno::ESRCH
      :dead
    rescue Errno::EPERM
      :not_owned
    end

    def trap_signals
      trap('SIGTERM') do
        info 'sigterm'
      end

      trap('SIGHUP') do
        info 'sithup'
      end
      trap('SIGINT') do
        @quit = true
      end
    end
  end
end
