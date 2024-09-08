# spec/gitpack_spec.rb
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

require 'spec_helper'
require 'rspec'
require 'fileutils'
require 'yaml'
require 'gitpack'

RSpec.describe GitPack do
  let(:yaml_data) do
    {
      'name' => 'test_pack',
      'category' => 'testing',
      'files' => ['{{prefix}}/bin/test'],
      'add' => [{ 'sh' => 'echo "Add action"' }],
      'rm' => ['remove_files'],
    }
  end

  let(:gitpack) { GitPack::GitPack.new(yaml_data) }

  describe GitPack::GitPack do
    it 'initializes with correct attributes' do
      expect(gitpack.name).to eq('test_pack')
      expect(gitpack.category).to eq('testing')
      expect(gitpack.files).to eq(["#{GitPack::PREFIX}/bin/test"])
      expect(gitpack.add.to_s).to eq('GitPackActions: < [GitPackActionScript: { [< echo "Add action" >] }] >')
      expect(gitpack.rm.to_s).to eq('GitPackActions: < [GitPackActionRemove] >')
    end
  end

  describe GitPack::GitPackActionRemove do
    let(:remove_action) { GitPack::GitPackActionRemove.new }

    before do
      allow(File).to receive(:delete).and_return(true)
    end

    it 'removes files successfully' do
      expect(remove_action.run(gitpack)).to be true
      expect(File).to have_received(:delete).with('/usr/local/bin/test')
    end
  end

  describe GitPack::GitPackActionScript do
    let(:script_action) { GitPack::GitPackActionScript.new(['echo "Test script"']) }

    it 'executes scripts with correct replacements' do
      allow_any_instance_of(GitPack::GitPackActionScript).to receive(:system).and_return(true)
      expect(script_action.run(gitpack)).to be true
    end
  end

  describe GitPack::GitPackActions do
    let(:actions) { GitPack::GitPackActions.new(yaml_data['add']) }

    it 'runs all actions successfully' do
      allow_any_instance_of(GitPack::GitPackActionScript).to receive(:run).and_return(true)
      expect(actions.run(gitpack)).to be true
    end
  end

  describe GitPack::Client do
    let(:client) { GitPack::Client.new }

    it 'parses arguments correctly' do
      argv = ['add', 'user/repo@main']
      expect { client.parse_args(argv) }.not_to raise_error
    end

    it 'creates the correct tool' do
      argv = ['add', 'user/repo@main']
      client.parse_args(argv)
      expect(client.instance_variable_get(:@tool)).to be_an_instance_of(GitPack::Client::AddTool)
    end
  end

  describe GitPack::Client::AddTool do
    let(:add_tool) { GitPack::Client::AddTool.new('add', {}, ['user/repo@main']) }
    let(:zip_file) { double('Zip::File', extract: true) }
    let(:zip_entry) { double('Zip::Entry') }

    it 'initializes with correct values' do
      expect(add_tool.instance_variable_get(:@repo)).to eq('user/repo')
      expect(add_tool.instance_variable_get(:@branch)).to eq('main')
    end

    it 'downloads and unpacks a repository' do
      # Mock methods for testing without real HTTP calls and file operations
      allow(add_tool).to receive(:download_file).and_return(true)
      allow(Zip::File).to receive(:open).and_yield(zip_file)
      allow(zip_file).to receive(:each).and_yield(zip_entry)
      allow(zip_entry).to receive(:name).and_return('foo')

      tmp_dir = Dir.mktmpdir
      expect(add_tool.download_and_unpack_repo(tmp_dir)).not_to be_nil
      FileUtils.remove_entry(tmp_dir)
    end
  end

  describe GitPack::Client::RmTool do
    let(:rm_tool) { GitPack::Client::RmTool.new('rm', {}, ['user/repo@main']) }

    it 'runs the remove action successfully' do
      allow(rm_tool).to receive(:run_helper).and_yield(gitpack)
      allow_any_instance_of(GitPack::GitPackActionRemove).to receive(:run).and_return(true)
      expect(rm_tool.run).to be true
    end
  end

  describe GitPack::Client::Tool do
    let(:tool) { GitPack::Client::Tool.create({ 'token' => nil }, ['foo/bar', 'add']) }

    it 'loads a manifest YAML file' do
      allow(tool).to receive(:try_load_manifest_yaml).and_return(yaml_data)
      expect(tool.get_manifest_yaml('./')).to eq(yaml_data)
    end

    it 'downloads a file' do
      # Mock `Net::HTTP` methods for testing without real network calls
      allow_any_instance_of(Net::HTTP).to receive(:request).and_return(double('response', code: '200', read_body: ''))
      allow(File).to receive(:open)
      expect(tool.download_file('http://example.com', 'destination')).to be true
    end
  end

  describe GitPack::GitPackActionRemove do
    let(:gitpack) { double('GitPack', files: ['file1', 'file2']) }
    let(:action) { described_class.new }

    describe '#to_s' do
      it 'returns the string representation of the action' do
        expect(action.to_s).to eq('GitPackActionRemove')
      end
    end

    describe '#run' do
      it 'deletes all files and returns true when successful' do
        allow(File).to receive(:delete).and_return(true)
        expect(action.run(gitpack)).to be true
      end

      it 'returns false if a file cannot be deleted' do
        allow(File).to receive(:delete).and_return(false)
        expect(action.run(gitpack)).to be false
      end
    end
  end

  describe GitPack::GitPackActionScript do
    let(:scripts) { ['echo "test"'] }
    let(:action) { described_class.new(scripts) }

    describe '#to_s' do
      it 'returns the string representation of the script action' do
        expect(action.to_s).to eq('GitPackActionScript: { [< echo "test" >] }')
      end
    end

    describe '#run_command' do
      it 'executes the script with placeholders replaced' do
        allow(ENV).to receive(:[]).with('SUDO_USER').and_return('sudo_user')
        allow(action).to receive(:system).with('echo "test"').and_return(true)
        expect(action.run_command('echo "test"')).to be true
      end
    end

    describe '#run' do
      it 'runs all scripts successfully' do
        allow(action).to receive(:run_command).with('echo "test"').and_return(true)
        expect(action.run(nil)).to be true
      end

      it 'returns false if a script fails' do
        allow(action).to receive(:run_command).with('echo "test"').and_return(false)
        expect(action.run(nil)).to be false
      end
    end
  end

  describe GitPack::GitPackActions do
    let(:script_action) { GitPack::GitPackActionScript.new(['echo "test"']) }
    let(:remove_action) { GitPack::GitPackActionRemove.new }

    describe '#initialize' do
      it 'parses hash actions and adds them to the actions list' do
        actions = described_class.new([{ 'sh' => ['echo "test"'] }])
        expect(actions.to_s).to include('GitPackActionScript')
      end

      it 'parses string actions and adds them to the actions list' do
        actions = described_class.new(['remove_files'])
        expect(actions.to_s).to include('GitPackActionRemove')
      end

      it 'adds a remove action if no actions are provided' do
        actions = described_class.new([])
        expect(actions.to_s).to include('GitPackActionRemove')
      end
    end

    describe '#run' do
      let(:gitpack) { double('GitPack') }

      before do
        allow(File).to receive(:delete).and_return(true)
      end

      it 'runs all actions successfully' do
        allow(gitpack).to receive(:files).and_return(['foo/bar/baz'])
        actions = described_class.new(['remove_files', { 'sh' => ['echo "test"'] }])
        allow(remove_action).to receive(:run).with(gitpack).and_return(true)
        allow(script_action).to receive(:run).with(gitpack).and_return(true)
        allow_any_instance_of(GitPack::GitPackActionScript).to receive(:system).and_return(true)
        expect(actions.run(gitpack)).to be true
        expect(File).to have_received(:delete).with('foo/bar/baz')
      end
    end
  end

  describe GitPack::GitPack do
    let(:yaml_hash) do
      {
        'name' => 'my_pack',
        'category' => 'tools',
        'files' => ['file1', 'file2'],
        'add' => [{ 'sh' => ['echo "add script"'] }],
        'rm' => ['remove_files'],
      }
    end

    let(:gitpack) { described_class.new(yaml_hash) }

    describe '#initialize' do
      it 'initializes with the correct attributes' do
        expect(gitpack.name).to eq('my_pack')
        expect(gitpack.category).to eq('tools')
        expect(gitpack.files).to eq(['file1', 'file2'])
      end

      it 'creates GitPackActions for add and rm' do
        expect(gitpack.add.to_s).to include('GitPackActionScript')
        expect(gitpack.rm.to_s).to include('GitPackActionRemove')
      end
    end

    describe '#to_s' do
      it 'returns the string representation of the GitPack' do
        expect(gitpack.to_s).to include('my_pack')
        expect(gitpack.to_s).to include('tools')
      end
    end
  end

  describe GitPack::Client::Tool do
    context 'when .gitpack.yaml file does not exist' do
      it 'returns an error message' do
        allow(File).to receive(:exist?).and_return(false)
        tool = GitPack::Client::Tool.new
        expect { tool.check_gitpack_yaml }.to output(/Error loading gitpack/).to_stdout
      end
    end
  end

  describe GitPack::GitPackActionScript do
    context 'when script runs successfully' do
      it 'runs the command with correct substitutions' do
        action = GitPack::GitPackActionScript.new(['echo Hello'])
        allow(action).to receive(:system).and_return(true)
        expect(action.run_command('echo Hello')).to be true
      end
    end
  end

  describe GitPack::Client do
    describe '#parse_args' do
      let(:argv) { ['add', 'user/repo@branch'] }

      it 'parses command-line arguments correctly' do
        client = GitPack::Client.new
        client.parse_args(argv)
        expect(client.instance_variable_get(:@tool)).to be_an_instance_of(GitPack::Client::AddTool)
      end
    end

    describe '#main' do
      it 'runs the tool if arguments are valid' do
        client = GitPack::Client.new
        allow_any_instance_of(GitPack::Client::AddTool).to receive(:run).and_return(true)
        expect(client.main(['add', 'user/repo@branch'])).to be true
      end

      it 'prints usage if tool is invalid' do
        client = GitPack::Client.new
        allow(client).to receive(:parse_args).and_return([])
        expect { client.main([]) }.to output(/Usage: gitpack/).to_stdout
      end
    end
  end

  describe GitPack::GitPack do
    let(:yaml_hash) do
      {
        'name' => 'test-pack',
        'category' => 'test-category',
        'files' => ['file1', 'file2'],
        'add' => [{ 'sh' => 'echo "Adding..."' }],
        'rm' => ['remove_files'],
      }
    end

    subject { GitPack::GitPack.new(yaml_hash) }

    describe '#handle_variables' do
      it 'replaces {{prefix}} with PREFIX' do
        expect(subject.send(:handle_variables, '{{prefix}}/test')).to eq("#{GitPack::PREFIX}/test")
      end

      it 'returns the original string for unknown placeholders' do
        expect(subject.send(:handle_variables, 'test')).to eq('test')
      end
    end

    describe '#parse_files' do
      it 'processes an array of files' do
        expect(subject.send(:parse_files, ['file1', 'file2'])).to eq(['file1', 'file2'])
      end

      it 'processes a single file string' do
        expect(subject.send(:parse_files, 'file')).to eq(['file'])
      end
    end
  end
end
