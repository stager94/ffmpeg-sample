require 'fileutils'
require 'open3'
require 'json'

module FFMPEGHelper

  def self.which(cmd)
    exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
    ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
      exts.each { |ext|
        exe = File.join(path, "#{cmd}#{ext}")
        return exe if File.executable? exe
      }
    end
    raise Errno::ENOENT, "the #{cmd} binary could not be found in #{ENV['PATH']}"
  end

  def self.ffmpeg_binary
    which('ffmpeg')
  end

  def self.ffprobe_binary
    which('ffprobe')
  end

end

class Decoder

  attr_reader :video, :needed_format, :options
  attr_accessor :destination

  def initialize(video, needed_format, destination_dir, options = [])
    @video         = video
    @needed_format = needed_format
    @destination   = [destination_dir, "/", video.basename, "." ,needed_format].join ""
    @options       = options
  end

  def run!
    command = [FFMPEGHelper.ffmpeg_binary, '-y', '-i', video.path, *options, destination]
    decode command
  end

  private

  def decode(command)
    p "Start encoding to #{needed_format}"
    p command.join " "
    Open3.popen3(*command) do |_stdin, _stdout, stderr, wait_thr|
      next_line = Proc.new do |line|
        if line.include?("time=")
          if line =~ /time=(\d+):(\d+):(\d+.\d+)/
            time = ($1.to_i * 3600) + ($2.to_i * 60) + $3.to_f
          else
            time = 0.0
          end

          progress = (time / video.metadata['format']['duration'].to_f) * 100
          progress = progress.round 4

          print progress.to_s + "% completed \r"
          $stdout.flush
        end
      end

      stderr.each('size=', &next_line)
    end
  end

end


class Video

  attr_reader :path
  attr_accessor :extension, :basename, :metadata

  DESTINATION_DIR = "./destination"

  def initialize(path)
    @path        = path
    @extension   = File.extname(path)
    @basename    = File.basename(path, extension)
    get_information!
  end

  def process_file
    if need_decoding?
      decode! "mp4", DESTINATION_DIR
      decode! "webm", DESTINATION_DIR
    end
    move_original_file_to_destination_dir
  end

  def decode!(needed_format, destination_dir, options = [])
    Decoder.new(self, needed_format, destination_dir, options).run!
  end

  def need_decoding?
    ![".mp4", ".webm"].include? extension
  end

  private

  def move_original_file_to_destination_dir
    FileUtils.mv path, DESTINATION_DIR
  end

  def get_information!
    command = [FFMPEGHelper.ffprobe_binary, '-i', path, *%w(-print_format json -show_format -show_streams -show_error)]
    output = ''
    error  = ''

    Open3.popen3(*command) do |stdin, stdout, stderr|
      output = stdout.read unless stdout.nil?
      error =  stderr.read unless stderr.nil?
    end

    @metadata = JSON.parse output
  end
end


path = ARGV[0]
video = Video.new path
video.process_file
