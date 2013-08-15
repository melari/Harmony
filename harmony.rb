#!/usr/bin/env ruby
require 'net/ftp'
require 'terrun'
require 'timeout'
require_relative 'directory_watcher.rb'

class Harmony < TerminalRunner
  name "Harmony"

  param "server", "The FTP server to connect to"
  param "user", "The FTP user to use."
  param "password", "Password for the given user."
  param "directory", "The directory to watch."

  option "--help", 0, "", "Show this help document."
  option "--remote", 1, "path", "Remote path to use."
  option "--timeout", 1, "seconds", "Length of time to allow files to transfer. (default 2)"

  help ""

  def self.run
    if @@options.include? "--help"
      show_usage
      exit
    end

    @modified = []

    @server = @@params["server"]
    @user = @@params["user"]
    @password = @@params["password"]
    @directory = Dir.new(@@params["directory"])
    @remote_path = @@options.include?("--remote") ? @@options["--remote"][0] : ""
    @timeout = @@options.include?("--timeout") ? @@options["--timeout"][0].to_i : 2

    @watcher = Dir::DirectoryWatcher.new(@directory)

    @modified_proc = Proc.new do |file, info|
      @modified << file.path
    end

    @watcher.on_add = @modified_proc
    @watcher.on_modify = @modified_proc
    #@watcher.on_remove = @modified_proc

    @watcher.scan_now
    self.clear

    puts " ## Harmony is now running".red
    while true
      break if self.get_command
    end
    @thread.kill if @thread
    self.close_connection
  end

  def self.get_command
    print "Harmony:: ".yellow
    command = gets.chomp
    return true if command == "exit" || command == "quit"
    self.show_help if command == "help"
    self.send_to_remote if command == "send" || command == "s"
    self.clear if command == "clear"
    self.show_status if command == "status" || command == "st"
    self.deploy if command == "deploy"
    self.start_auto if command == "auto"
    self.stop_auto if command == "stop"
    false
  end

  def self.start_auto
    puts " ## Auto upload has been started. Type 'stop' to kill the thread.".red
    @thread = Thread.new do
      while true
        self.send_to_remote
        sleep 2
      end
    end
  end

  def self.stop_auto
    return unless @thread
    @thread.kill
    puts " ## Auto upload thread has been killed.".red
  end

  def self.deploy
    @watcher.add_all
    self.send_to_remote
  end

  def self.send_to_remote
    @watcher.scan_now
    return if @modified.empty?
    failed = !self.open_connection
    unless failed
      @modified.each do |file|
        next if file.end_with? "~"
        begin
          Timeout::timeout(@timeout) do
            rpath = self.remote_path_for(file)
            @ftp.chdir rpath
            if file.end_with? ".png", ".gif", ".jpg", ".bmp", ".svg", ".tiff", ".raw"
              @ftp.putbinaryfile(file)
            else
              @ftp.puttextfile(file)
            end
            puts " ## [SUCCESS] #{file} => #{rpath}".green
          end
        rescue Timeout::Error
          failed = true
          puts " ## [ FAIL  ] #{file} timed out while syncing".red
        rescue Net::FTPError
          failed = true
          puts " ## [ FAIL  ] #{file} failed to sync".red
        end
      end
    end

    if failed
      puts " ## Some files failed to transfer. The dirty list has not been cleared.".pink
    else
      self.clear
    end
  end

  def self.remote_path_for(file)
    extra_path = file.sub(@directory.path, "")
    @remote_path + extra_path[0, extra_path.rindex("/")]
  end

  def self.clear
    @modified = []
  end

  def self.show_status
    @watcher.scan_now

    return puts " ## Directory is in sync".green if @modified.count == 0

    puts " ## Files to be uploaded".red
    @modified.each do |file|
      puts "+   #{file}".pink
    end
  end

  def self.show_help
    puts " ## Harmony Help".red
    puts "help - Show this help file"
    puts "exit (quit) - Quit Harmony"
    puts "status (st) - Show a list of files that will be transfered"
    puts "clear - Mark all files as synced"
    puts "send (s) - Send all new and modified files to the remote server"
    puts "deploy - Send all files, regardless of their state"
    puts "auto - Automatically run 'send' every 2 seconds"
    puts "stop - reverses the 'auto' command"
  end

  def self.open_connection
    Timeout.timeout(@timeout) do
      if @ftp
        begin
          @ftp.list
        rescue Net::FTPError
          puts " ## Connection was closed by server".pink
          @ftp.close
        end
      end

      if @ftp.nil? || @ftp.closed?
        puts " ## Connection opening".red
        @ftp = Net::FTP.new(@server)
        @ftp.login(@user, @password)
      end
    end
    true
  rescue SocketError
    puts " ## [FAIL] Unable to open connection to server.".red
    false
  rescue Timeout::Error
    puts " ## [TIMEOUT] Failed to connect to server.".red
    @ftp.close
    @ftp = nil
    false
  end

  def self.close_connection
    if @ftp
      puts " ## Connection closing".red
      @ftp.close
    end
  end

end


# Monkey patching the string class for easy colors (you mad?)
class String
  def colorize(color_code)
    "\e[#{color_code}m#{self}\e[0m"
  end

  def red
    colorize(31)
  end

  def green
    colorize(32)
  end

  def yellow
    colorize(33)
  end

  def pink
    colorize(35)
  end
end



if __FILE__ == $0
  x = Harmony.start(ARGV)
end
