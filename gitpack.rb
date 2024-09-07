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

PREFIX = '/usr/local'

class GitPackActionRemove
  def initialize()
  end

  def to_s
    'GitPackActionRemove'
  end

  def run(gitpack)
    gitpack.files.all? { |f| system("rm #{f}") }
  end
end

class GitPackActionScript
  def initialize(ary)
    @scripts = ary
  end

  def to_s
    "GitPackActionStript: { #{@scripts} }"
  end

  def run_command(script)
    sudo_user = ENV['SUDO_USER'] || ''
    script = script.gsub('{{prefix}}', PREFIX)
    script = script.gsub('{{sudo.user}}', sudo_user)

    return system(script)
  end

  def run(gitpack)
    @scripts.all? { |sh| run_command(sh) }
  end
end

class GitPackActions
  def initialize(ary)
    @actions = []
    ary.each do |action|
      action = parse_hash_action(action) if action.class == Hash
      action = parse_string_action(action) if action.class == String
      @actions << action
    end
    @actions << GitPackActionRemove.new if ary.empty?
  end

  def parse_hash_action(action)
    return GitPackActionScript.new(action['sh']) if action['sh']
  end

  def parse_string_action(action)
    return GitPackActionRemove.new if action == 'remove_files'
  end

  def to_s
    "GitPackActions: < #{@actions} >"
  end

  def run(gitpack)
    @actions.all? { |action| return false unless action.run(gitpack) }
  end
end

class GitPack
  attr_accessor :name, :category, :files, :add, :rm

  def initialize(hash)
    @name = hash['name'].to_s
    @category = hash['category'].to_s
    @files = hash['files'].to_a.map { |f| f.gsub('{{prefix}}', PREFIX) }
    @add = GitPackActions.new(hash['add'].to_a)
    @rm = GitPackActions.new(hash['rm'].to_a)
  end

  def to_s
    "GitPack: { name: #{@name}, category: #{@category}, files: #{@files}, add: #{@add}, rm: #{@rm} }"
  end
end

class Client
  class Tool
    attr_reader :name, :ok

    def self.create(opt, argv)
      name = argv.pop
      return AddTool.new(name, opt, argv) if name == 'add'
      return RmTool.new(name, opt, argv) if name == 'rm'
      nil
    end

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

    def run
      false
    end
  end

  class AddTool < Tool
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

    def load_fail?(pack)
      return false if pack

      puts ".gitpack.yaml not found or could not be loaded from #{repo_dir}"
      true
    end

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

    def run
      run_helper { |pack| pack.add.run(pack) }
    end
  end

  class RmTool < AddTool
    def initialize(name, opt, argv)
      super(name, opt, argv)
    end

    def run
      run_helper { |pack| pack.rm.run(pack) }
    end
  end

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

  def main(argv)
    parse_args(argv)

    unless @tool.ok
      puts 'Usage: gitpack [options] add|rm <user>/<repo>[@<branch>]'
      return
    end

    @tool.run
  end
end

client = Client.new
exit(1) unless client.main(ARGV)
exit(0)
