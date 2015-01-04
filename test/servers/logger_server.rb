#!/usr/bin/env ruby

$:.unshift(File.join(File.dirname(__FILE__), "..", "..", "lib"))

require "logger"
require "daemon_spawn"

module DaemonSpawn
  def self.info(s)
    LoggerServer.logger.info(s)
  end
  def self.warn(s)
    LoggerServer.logger.fatal(s)
  end
end

class LoggerServer < DaemonSpawn::Base

  @@logger = Logger.new('/tmp/logger_server_logger.log')

  def self.logger
    @@logger
  end

  def self.info(str)
    self.logger.info(str)
  end

  def self.warn(str)
    self.logger.fatal(str)
  end

  def puts(str)
    self.class.logger.info(str)
  end

  def start(args)
    abort "USAGE: #{File.basename(__FILE__)}" unless args.empty?
    puts "#{self.class.name} (#{self.index}) started"
    while true                  # keep running like a real daemon
      sleep 5
    end
  end

  def stop  # called from trap("TERM") { here }
    # Cannot log messages in trap context with Ruby stdlib's logger;
    # use other logging libraries like mono_logger
    puts "#{self.class.name} (#{self.index}) stopped"  # not output to log
  end

end

params = {
  :working_dir => File.join(File.dirname(__FILE__), '..', '..'),
  :pid_file => '/tmp/logger_server.pid',
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
  LoggerServer.spawn!(params)
end
