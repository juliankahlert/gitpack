#!/usr/bin/env ruby
#
# MIT License
#
# Copyright (c) 2024 Julian Kahlert
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require 'fileutils'
require 'optparse'
require 'net/http'
require 'yaml'
require 'zip'

# GitPack module.
module GitPack
  # Default installation prefix.
  PREFIX = '/usr/local'

  # Class for handling the removal of GitPack files.
  class GitPackActionRemove
    # Initializes a new GitPackActionRemove instance.
    def initialize()
    end

    # String representation of the remove action
    #
    # @return [String] the name of the action.
    def to_s
      'GitPackActionRemove'
    end

    # Runs the removal action.
    #
    # @param gitpack [GitPack] The GitPack instance.
    # @return [Boolean] true if all files are removed, false otherwise.
    def run(gitpack)
      gitpack.files.all? { |f| system("rm #{f}") }
    end
  end

  # Class for handling script execution as part of GitPack actions.
  class GitPackActionScript
    # Initializes the script action with an array of script commands.
    #
    # @param ary [Array<String>] An array of shell script commands.
    def initialize(ary)
      @scripts = ary
    end

    # String representation of the script action.
    #
    # @return [String] The action description.
    def to_s
      "GitPackActionStript: { #{@scripts} }"
    end

    # Runs a script command, replacing placeholders.
    #
    # @param script [String] The shell script to run.
    # @return [Boolean] true if the script runs successfully, false otherwise.
    def run_command(script)
      sudo_user = ENV['SUDO_USER'] || ''
      script = script.gsub('{{prefix}}', PREFIX)
      script = script.gsub('{{sudo.user}}', sudo_user)

      return system(script)
    end

    # Executes all script actions.
    #
    # @param _gitpack [GitPack] The GitPack instance.
    # @return [Boolean] true if all scripts run successfully, false otherwise.
    def run(_gitpack)
      @scripts.all? { |sh| run_command(sh) }
    end
  end

  # Class that encapsulates a list of GitPack actions.
  class GitPackActions
    # Initializes GitPackActions with a list of actions.
    #
    # @param ary [Array<Hash, String>] An array of actions, either as Hashes or Strings.
    def initialize(ary)
      @actions = []
      ary.each do |action|
        action = parse_hash_action(action) if action.class == Hash
        action = parse_string_action(action) if action.class == String
        @actions << action
      end
      @actions << GitPackActionRemove.new if ary.empty?
    end

    # Parses a hash action.
    #
    # @param action [Hash] The hash action.
    # @return [GitPackActionScript] The parsed script action.
    def parse_hash_action(action)
      return GitPackActionScript.new(action['sh']) if action['sh']
    end

    # Parses a string action.
    #
    # @param action [String] The string action.
    # @return [GitPackActionRemove] The remove action.
    def parse_string_action(action)
      return GitPackActionRemove.new if action == 'remove_files'
    end

    # String representation of GitPack actions.
    #
    # @return [String] The action list as a string.
    def to_s
      "GitPackActions: < #{@actions} >"
    end

    # Runs all actions for the GitPack.
    #
    # @param gitpack [GitPack] The GitPack instance.
    # @return [Boolean] true if all actions run successfully, false otherwise.
    def run(gitpack)
      @actions.all? { |action| return false unless action.run(gitpack) }
    end
  end

  # Main class representing a GitPack.
  class GitPack
    attr_accessor :name, :category, :files, :add, :rm

    # Initializes a GitPack from a YAML hash.
    #
    # @param hash [Hash] The parsed YAML configuration.
    def initialize(hash)
      @name = hash['name'].to_s
      @category = hash['category'].to_s
      @files = parse_files(hash['files'])
      @add = GitPackActions.new(hash['add'].to_a)
      @rm = GitPackActions.new(hash['rm'].to_a)
    end

    # String representation of the GitPack.
    #
    # @return [String] The GitPack description.
    def to_s
      "GitPack: { name: #{@name}, category: #{@category}, files: #{@files}, add: #{@add}, rm: #{@rm} }"
    end

    private

    # Replaces placeholders in strings with actual values.
    #
    # @param str [String] The string to process.
    # @return [String] The processed string.
    def handle_variables(str)
      case str
      when '{{prefix}}'
        str.gsub('{{prefix}}', PREFIX)
      when '{{gem-contents}}'
        `gem contents #{@name}`
      end
    end

    # Parses the files list.
    #
    # @param files [Array<String>, String] The files specified in the GitPack.
    # @return [Array<String>] The list of files after processing.
    def parse_files(files)
      case files
      when Array
        files.to_a.map { |f| handle_variables(f) }
      when String
        [handle_variables(files)]
      end
    end
  end

  # The GitPack client for managing installation and removal of GitPacks.
  class Client
    # Base class for GitPack tools (AddTool, RmTool).
    class Tool
      attr_reader :name, :ok

      # Factory method to create an appropriate tool (AddTool, RmTool).
      #
      # @param opt [Hash] Command line options.
      # @param argv [Array<String>] Command line arguments.
      # @return [Tool, nil] The tool instance or nil if none match.
      def self.create(opt, argv)
        name = argv.pop
        return AddTool.new(name, opt, argv) if name == 'add'
        return RmTool.new(name, opt, argv) if name == 'rm'
        nil
      end

      # Attempts to load a YAML manifest file from a specified path.
      #
      # @param yaml_path [String] The file path to the YAML manifest.
      # @return [Hash, nil] The parsed YAML data if successful, or nil if the file doesn't exist or an error occurs.
      def try_load_manifest_yaml(yaml_path)
        return nil unless File.exist?(yaml_path)

        begin
          yaml_data = YAML.load_file(yaml_path)
          yaml_data['gitpack']
        rescue StandardError => e
          puts e
          nil
        end
      end

      # Loads the GitPack manifest YAML file.
      #
      # @param repo_dir [String] The repository directory.
      # @return [GitPack, nil] The loaded GitPack or nil if not found.
      def get_manifest_yaml(repo_dir)
        yaml_path = File.join(repo_dir, '.gitpack.yaml')
        yaml_data = try_load_manifest_yaml(yaml_path)
        return yaml_data if yaml_data

        yaml_path = File.join(repo_dir, '.manifest.yaml')
        yaml_data = try_load_manifest_yaml(yaml_path)
        return yaml_data if yaml_data

        yaml_path = File.join(repo_dir, '.dep.yaml')
        yaml_data = try_load_manifest_yaml(yaml_path)
        return yaml_data if yaml_data

        nil
      end

      # Checks for the existence of GitPack YAML files in various directories.
      #
      # @return [GitPack, nil] The loaded GitPack or nil if not found.
      def check_gitpack_yaml
        yaml_data = get_manifest_yaml('./')
        return GitPack.new(yaml_data) if yaml_data

        yaml_data = get_manifest_yaml('./.gitpack/')
        return GitPack.new(yaml_data) if yaml_data

        yaml_data = get_manifest_yaml('./.github/')
        return GitPack.new(yaml_data) if yaml_data

        yaml_data = get_manifest_yaml('./.gitlab/')
        return GitPack.new(yaml_data) if yaml_data

        yaml_data = get_manifest_yaml('./.meta/')
        return GitPack.new(yaml_data) if yaml_data

        puts 'Error loading gitpack'
        nil
      end

      # Downloads a file from a URL.
      #
      # @param url [String] The file URL.
      # @param destination [String] The destination path.
      # @param ssl [Boolean] Whether to use SSL.
      # @return [Boolean] true if the download succeeds, false otherwise.
      def download_file(url, destination, ssl = false)
        uri = URI.parse(url)

        token = @options['token']
        request = Net::HTTP::Get.new(uri)
        request['Authorization'] = "token #{token}" if token

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = ssl

        http.request(request) do |response|
          if response.code == '302'
            new_location = response['location']
            return download_file(new_location, destination, ssl)
          elsif response.code != '200'
            puts "Error: Download of #{url} failed: #{response}"
            return false
          end

          File.open(destination, 'wb') do |file|
            response.read_body do |chunk|
              file.write(chunk)
            end
          end
        end

        true
      end

      # Runs the tool's logic.
      #
      # @return [Boolean] true if the tool succeeds, false otherwise.
      def run
        false
      end
    end

    # Tool for adding a GitPack.
    class AddTool < Tool
      # Initializes an AddTool instance.
      #
      # @param name [String] The tool name.
      # @param opt [Hash] Command line options.
      # @param argv [Array<String>] Command line arguments.
      def initialize(name, opt, argv)
        @name = name
        @options = opt.to_h
        @refspec = argv.pop
        match = @refspec.match(/^([^\/]+\/[^@]+)@(.+)$/)
        match = @refspec.match(/^([^\/]+\/[^@]+)$/) unless match

        if match.nil?
          puts 'Invalid format for <GH_REPO>@<branch>'
          @ok = false
          return
        end

        @repo = match[1]
        @branch = match[2]
        @branch ||= 'main'
        @ok = true
      end

      # Downloads and unpacks a GitHub repository.
      #
      # @param tmp_dir [String] The temporary directory for downloading.
      # @return [String, nil] The unpacked repository directory, or nil if failed.
      def download_and_unpack_repo(tmp_dir)
        repo_owner, repo_name = @repo.split('/')
        zip_url = "https://codeload.github.com/#{repo_owner}/#{repo_name}/zip/#{@branch}"

        tmp_zip_file = File.join(tmp_dir, "#{repo_name}-#{@branch.gsub('/', '-')}.zip")

        return nil unless download_file(zip_url, tmp_zip_file, true)

        Zip::File.open(tmp_zip_file) do |zip_file|
          zip_file.each do |f|
            f_path = File.join(tmp_dir, f.name)
            FileUtils.mkdir_p(File.dirname(f_path))
            zip_file.extract(f, f_path) unless File.exist?(f_path)
          end
        end

        File.join(tmp_dir, "#{repo_name}-#{@branch.gsub('/', '-')}")
      end

      # Checks if loading the GitPack failed and prints an error message.
      #
      # @param pack [GitPack, nil] The loaded GitPack instance or nil if loading failed.
      # @return [Boolean] true if loading failed (i.e., pack is nil), false otherwise.
      def load_fail?(pack)
        return false if pack

        puts ".gitpack.yaml not found or could not be loaded from #{repo_dir}"
        true
      end

      # Helper for the run method.
      #
      # @yield [block] The block to execute.
      # @return [Boolean] true if success, false otherwise.
      def run_helper(&block)
        Dir.mktmpdir('gitpack') do |tmp_dir|
          repo_dir = download_and_unpack_repo(tmp_dir)
          return false unless repo_dir

          Dir.chdir(repo_dir) do
            pack = check_gitpack_yaml
            return false if load_fail?(pack)

            block.call(pack)
          end
        end

        true
      end

      # Runs the add action for a GitPack.
      #
      # @return [Boolean] true if the add action succeeds, false otherwise.
      def run
        run_helper { |pack| pack.add.run(pack) }
      end
    end

    # Tool for removing a GitPack.
    #
    class RmTool < AddTool
      # Runs the remove action for a GitPack.
      # @return [Boolean] true if the remove action succeeds, false otherwise.
      def run
        run_helper { |pack| pack.rm.run(pack) }
      end
    end

    # Parses command line arguments.
    #
    # @param argv [Array<String>] Command line arguments.
    def parse_args(argv)
      @options = {}
      opt_parser = OptionParser.new do |opts|
        opts.banner = 'Usage: gitpack [options] add|rm <user>/<repo>[@<branch>]'

        opts.on('--token TOKEN', 'GitHub Personal Access Token') do |val|
          @options['token'] = val
        end

        opts.on('-h', '--help', 'Prints this help') do
          puts opts
          exit(0)
        end
      end

      opt_parser.parse!(argv)
      argv = argv.reverse
      @tool = Tool.create(@options, argv)
    end

    # Main entry point for the GitPack client.
    #
    # @param argv [Array<String>] Command line arguments.
    # @return [void]
    def main(argv)
      parse_args(argv)

      unless @tool.ok
        puts 'Usage: gitpack [options] add|rm <user>/<repo>[@<branch>]'
        return
      end

      @tool.run
    end
  end

  # Command-line interface for GitPack.
  #
  # @param argv [Array<String>] Command line arguments.
  def cli(argv)
    client = Client.new
    exit(1) unless client.main(argv)
    exit(0)
  end
end
