#!/usr/bin/env ruby

$:.unshift(File.join(File.dirname(__FILE__), "..", "..", "lib"))

require "logger"
require "daemon_spawn"

class LogToIOServer < DaemonSpawn::Base

  def start(args)
    puts "#{self.class.name} (#{self.index}) started"
    while true  # keep running
      sleep 5
    end
  end

  def stop
    puts "#{self.class.name} (#{self.index}) stopped"  # goes to console
  end

end

params = {
  :working_dir => File.join(File.dirname(__FILE__), '..', '..'),
  :pid_file => '/tmp/log_to_io_server.pid',
  :sync_log => true,
}

if %w(start stop status restart).include?(ARGV[0]) and ARGV.count >= 2
  log_file = ARGV[1]
  params[:processes] = (ARGV[2] || '1').to_i
else
  abort "USAGE: #{File.basename(__FILE__)} <command> <log file> [<#processes>]"
end

ARGV[0..-1] = ARGV[0]

File.open(log_file, 'a') do |f|
  params[:log_file] = f
  LogToIOServer.spawn!(params)
end
