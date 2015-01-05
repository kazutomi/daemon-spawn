require 'test_helper'
require "socket"
require 'fileutils'

class DaemonSpawnTest < Test::Unit::TestCase

  SERVERS = File.join(File.dirname(__FILE__), "servers")

  # Try to make sure no pidfile (or process) is left over from another test.
  def setup
    %w{ echo_server deaf_server stubborn_server simple_server }.each do |server|
      begin
        Process.kill 9, possible_pid(server)
      rescue Errno::ESRCH
        # good, no process to kill
      end
      begin
        File.unlink pid_file(server)
      rescue Errno::ENOENT
        # good, no pidfile to clear
      end
    end
  end

  def with_socket
    socket = TCPSocket.new('127.0.0.1', 5150)
    socket.setsockopt(Socket::SOL_SOCKET,
                      Socket::SO_RCVTIMEO,
                      [1, 0].pack("l_2"))

    begin
      yield(socket) if block_given?
    ensure
      socket.close
    end
  end

  def echo_server(*args)
    `./echo_server.rb #{args.join(' ')}`
  end

  def while_running(&block)
    Dir.chdir(SERVERS) do
      `./echo_server.rb stop`
      assert_match(/EchoServer started./, `./echo_server.rb start 5150`)
      sleep 1
      begin
        with_socket &block
      ensure
        assert_match(//, `./echo_server.rb stop`)
        sleep 0.1
        assert_raises(Errno::ECONNREFUSED) { TCPSocket.new('127.0.0.1', 5150) }
      end
    end
  end

  def after_daemon_dies_leaving_pid_file
    Dir.chdir(SERVERS) do
      `./echo_server.rb stop`
      sleep 1
      `./echo_server.rb start 5150`
      sleep 1
      leftover_pid = IO.read(pid_file('echo_server')).to_i
      Process.kill 9, leftover_pid
      sleep 1
      assert dead?(leftover_pid)
      assert File.exists?(pid_file('echo_server'))
      yield leftover_pid
    end
  end

  def test_daemon_running
    while_running do |socket|
      socket << "foobar\n"
      assert_equal "foobar\n", socket.readline
    end
  end

  def test_status_running
    while_running do |socket|
      assert_match(/EchoServer is running/, `./echo_server.rb status`)
    end
  end

  def test_status_not_running
    Dir.chdir(SERVERS) do
      assert_match(/No PIDs found/, `./echo_server.rb status`)
    end
  end

  def test_start_after_started
    while_running do
      pid = echo_server("status").match(/PID (\d+)/)[1]
      assert_match(/Daemons already started! PIDS: #{pid}/,
                   echo_server("start"))
    end
  end

  def test_stop_after_stopped
    Dir.chdir(SERVERS) do
      assert_match("No PID files found. Is the daemon started?",
                   `./echo_server.rb stop`)
    end
  end

  def test_restart_after_stopped
    Dir.chdir(SERVERS) do
      assert_match(/EchoServer started/, `./echo_server.rb restart 5150`)
      assert_equal(0, $?.exitstatus)
      sleep 1
      with_socket do |socket|
        socket << "foobar\n"
        assert_equal "foobar\n", socket.readline
      end
    end
  end

  def test_restart_after_started
    Dir.chdir(SERVERS) do
      assert_match(/EchoServer started/, `./echo_server.rb start 5150`)
      assert_equal(0, $?.exitstatus)
      sleep 1

      assert_match(/EchoServer started/, `./echo_server.rb restart 5150`)
      assert_equal(0, $?.exitstatus)
      sleep 1

      with_socket do |socket|
        socket << "foobar\n"
        assert_equal "foobar\n", socket.readline
      end
    end
  end

  def test_start_after_daemon_dies_leaving_pid_file
    after_daemon_dies_leaving_pid_file do |leftover_pid|
      assert_match /EchoServer started/, `./echo_server.rb start 5150`
      sleep 1
      new_pid = IO.read(pid_file('echo_server')).to_i
      assert new_pid != leftover_pid
      assert alive?(new_pid)
    end
  end

  def test_restart_after_daemon_dies_leaving_pid_file
    after_daemon_dies_leaving_pid_file do |leftover_pid|
      assert_match /EchoServer started/, `./echo_server.rb restart 5150`
      sleep 1
      new_pid = reported_pid 'echo_server'
      assert new_pid != leftover_pid
      assert alive?(new_pid)
    end
  end

  def test_stop_using_custom_signal
    Dir.chdir(SERVERS) do
      `./deaf_server.rb start`
      sleep 1
      pid = reported_pid 'deaf_server'
      assert alive?(pid)
      Process.kill 'TERM', pid
      sleep 1
      assert alive?(pid)
      Process.kill 'INT', pid
      sleep 1
      assert alive?(pid)
      `./deaf_server.rb stop`
      sleep 1
      assert dead?(pid)
    end
  end

  def test_custom_signal_invokes_stop_handler
    log_file = File.join(Dir.tmpdir, 'deaf_server.log')
    Dir.chdir(SERVERS) do
      FileUtils.rm_f log_file
      `./deaf_server.rb start`
      sleep 1
      `./deaf_server.rb stop`
      assert_match /DeafServer stopped/, IO.read(log_file)
    end
  end

  def test_kill_9_following_timeout
    Dir.chdir(SERVERS) do
      `./stubborn_server.rb start`
      sleep 1
      pid = reported_pid 'stubborn_server'
      assert alive?(pid)
      Process.kill 'TERM', pid
      sleep 1
      assert alive?(pid)
      `./stubborn_server.rb stop`
      assert dead?(pid)
    end
  end

  def test_umask_unchanged
    Dir.chdir(SERVERS) do
      old_umask = File.umask 0124
      log_file = File.join(Dir.tmpdir, 'should_not_be_world_writable')
      begin
        `./simple_server.rb stop`
        FileUtils.rm_f log_file
        `./simple_server.rb start #{log_file}`
        sleep 1
        assert_equal 0100642, File.stat(log_file).mode
      ensure
        `./simple_server.rb stop`
        FileUtils.rm_f log_file
        File.umask old_umask
      end
    end
  end

  def test_log_file_is_world_writable
    log_file = File.join(Dir.tmpdir, 'echo_server.log')
    FileUtils.rm_f log_file
    while_running do
      assert_equal 0100666, File.stat(log_file).mode
    end
  end

  def test_io_log_output
    log_file = File.join(Dir.tmpdir, 'test_io_log.log')
    Dir.chdir(SERVERS) do
      begin
        `./log_to_io_server.rb stop #{log_file}`
        FileUtils.rm_f log_file
        assert_match /LogToIOServer started/, `./log_to_io_server.rb start #{log_file}`
        assert_match /LogToIOServer.*started/, IO.read(log_file)
      ensure
        `./log_to_io_server.rb stop #{log_file}`
        FileUtils.rm_f log_file
      end
    end
  end

  def test_using_logger
    discarded_output = '/tmp/logger_server_dev_null.out'  # specify /dev/null to really discard
    logger_log = '/tmp/logger_server_logger.log'  # literally specified in logger_server.rb
    Dir.chdir(SERVERS) do
      begin
        `./logger_server.rb stop #{discarded_output}`  # will write something in log files
        FileUtils.rm_f discarded_output
        FileUtils.rm_f logger_log
        assert_equal '', `./logger_server.rb start #{discarded_output}`
        assert_equal 0, File.size(discarded_output)
        lines = IO.read(logger_log).lines
        assert_equal 1, lines.count { |l| /\A# Logfile created/ =~ l }
        assert_equal 1, lines.count { |l| /INFO.*LoggerServer started/ =~ l }
        assert_equal 1, lines.count { |l| /INFO.*LoggerServer \(\d+\) started/ =~ l }
        assert_equal 3, lines.count
        assert_equal '', `./logger_server.rb start #{discarded_output}`
        lines = IO.read(logger_log).lines
        assert_equal 1, lines.count { |l| /INFO.*Daemons already started/ =~ l }
        assert_equal 4, lines.count
        assert_equal '', `./logger_server.rb status #{discarded_output}`
        lines = IO.read(logger_log).lines
        assert_equal 1, lines.count { |l| /INFO.*LoggerServer is running/ =~ l }
        assert_equal 5, lines.count
        assert_equal '', `./logger_server.rb stop #{discarded_output}`
        lines = IO.read(logger_log).lines
        assert_equal 0, lines.count { |l| /INFO.*LoggerServer \(\d+\) stopped/ =~ l }  # logger cannot write
        lines = IO.read(logger_log).lines
        assert_equal 1, lines.count { |l| /log writing failed. can't be called from trap context/ =~ l }
        assert_equal 1, lines.count
        assert_equal '', `./logger_server.rb stop #{discarded_output}`
        lines = IO.read(logger_log).lines
        assert_equal 1, lines.count { |l| /INFO.*No PID files found/ =~ l }
        assert_equal 6, lines.count
      ensure
        `./logger_server.rb stop #{discarded_output}`
        FileUtils.rm_f discarded_output
        FileUtils.rm_f logger_log
      end
    end
  end
end
