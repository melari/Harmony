#!/usr/bin/env ruby
require 'net/ftp'
require 'terrun'
require_relative 'directory_watcher.rb'

class Harmony < TerminalRunner
  name "Harmony"

  param "server", "The FTP server to connect to"
  param "user", "The FTP user to use."
  param "password", "Password for the given user."
  param "directory", "The directory to watch."

  option "--help", 0, "", "Show this help document."
  option "--remote", 1, "path", "Remote path to use."
  option "--robust", 0, "", "Show all file transfers."

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
    @robust = @@options.include? "--robust"

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
    self.close_connection
  end

  def self.get_command
    print "Harmony:: ".yellow
    command = gets.chomp
    return true if command == "stop"
    self.show_help if command == "help"
    self.send_to_remote if command == "send" || command == "s"
    self.clear if command == "clear"
    self.show_status if command == "status" || command == "st"
    false
  end

  def self.send_to_remote
    @watcher.scan_now
    return if @modified.empty?
    self.open_connection
    @modified.each do |file|
      rpath = self.remote_path_for(file)
      @ftp.chdir rpath
      puts " ## #{file} => #{rpath}".green if @robust
      @ftp.puttextfile(file)
    end

    self.clear
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
    puts " ## Files to be uploaded".red
    @modified.each do |file|
      puts "+   #{file}".pink
    end
  end

  def self.show_help
    puts " ## Harmony Help".red
    puts "help - Show this help file"
    puts "stop - Quit Harmony"
    puts "status (st) - Show a list of files that will be transfered"
    puts "clear - Mark all files as synced"
    puts "send (s) - Send all new and modified files to the remote server"
  end

  def self.open_connection
    @ftp.list if @ftp # Checks for server induced timeouts.
    if @ftp.nil? || @ftp.closed?
      puts " ## Connection opening".red
      @ftp = Net::FTP.new(@server)
      @ftp.login(@user, @password)
    end
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
