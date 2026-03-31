# frozen_string_literal: true

require 'fileutils'
require 'concurrent/atomic/atomic_boolean'

module Legion
  class Process
    class << self
      attr_accessor :quit_flag
    end

    def self.run!(options)
      Legion::Process.new(options).run!
    end

    attr_reader :options, :service

    def initialize(options)
      @options = options
      options[:logfile] = File.expand_path(logfile) if logfile?
      options[:pidfile] = File.expand_path(pidfile) if pidfile?
    end

    def quit
      @quit.is_a?(Concurrent::AtomicBoolean) ? @quit.true? : @quit
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
      @quit = Concurrent::AtomicBoolean.new(false)
      self.class.quit_flag = @quit
      check_pid
      daemonize if daemonize?
      write_pid
      trap_signals
      retrap_after_puma

      until quit
        sleep(1)
        @quit.make_true if @options.key?(:time_limit) && Time.now - start_time > @options[:time_limit]
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
          Legion::Logging.info "[Process] PID #{::Process.pid} written to #{pidfile}" if defined?(Legion::Logging)
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
    rescue Errno::ESRCH => e
      Legion::Logging.debug "Process#pid_status: pid=#{pid} is dead: #{e.message}" if defined?(Legion::Logging)
      :dead
    rescue Errno::EPERM => e
      Legion::Logging.debug "Process#pid_status: pid=#{pid} not owned: #{e.message}" if defined?(Legion::Logging)
      :not_owned
    end

    def trap_signals
      trap('SIGTERM') do
        Legion::Logging.info '[Process] received SIGTERM, shutting down' if defined?(Legion::Logging)
        @quit.make_true
      end

      trap('SIGHUP') do
        Legion::Logging.info '[Process] received SIGHUP, triggering reload' if defined?(Legion::Logging)
        info 'sighup: triggering reload'
        Thread.new { Legion.reload }
      end

      trap('SIGINT') do
        Legion::Logging.info '[Process] received SIGINT, shutting down' if defined?(Legion::Logging)
        @quit.make_true
      end
    end

    def retrap_after_puma
      @retrap_thread = Thread.new do
        15.times do
          sleep 1
          trap('SIGINT') { @quit.make_true }
          trap('SIGTERM') { @quit.make_true }
        end
      end
    end
  end
end
