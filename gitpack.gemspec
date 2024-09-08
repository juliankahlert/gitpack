# revtree.gemspec
Gem::Specification.new do |spec|
  spec.name = 'gitpack'
  spec.version = '0.1.0'
  spec.authors = ['Julian Kahlert']
  spec.email = ['90937526+juliankahlert@users.noreply.github.com']

  spec.summary       = 'A GitHub repository-based package manager.'
  spec.description   = 'GitPack allows users to install and uninstall software from GitHub repositories using a manifest file (.gitpack.yaml). It automates installation and removal processes for packages hosted on public and private repositories, streamlining package management.'
  spec.homepage = 'https://github.com/juliankahlert/gitpack'
  spec.license = 'MIT'

  spec.metadata['homepage_uri'] = 'https://juliankahlert.github.io/gitpack'
  spec.metadata['documentation_uri'] = 'https://www.rubydoc.info/gems/gitpack/0.1.0'
  spec.metadata['source_code_uri'] = 'https://github.com/juliankahlert/gitpack'

  spec.files = Dir['{bin,lib}/**/*', 'LICENSE', 'README.md']
  spec.test_files = Dir['spec/**/*']
  spec.require_paths = ['lib']
  spec.executables << 'gitpack'

  spec.add_development_dependency 'simplecov-cobertura', '~> 2', '>= 2.1'
  spec.add_development_dependency 'simplecov-console', '~> 0.9', '>= 0.9.1'
  spec.add_development_dependency 'simplecov', '~> 0.22', '>= 0.22.0'
  spec.add_development_dependency 'yard', '~> 0.9', '>= 0.9.37'
  spec.add_development_dependency 'rspec', '~> 3', '>= 3.4'

  spec.add_dependency 'rubyzip', '~> 2.3', '>= 2.3.2'

  spec.required_ruby_version = '>= 3.0.0'
end
