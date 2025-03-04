# frozen_string_literal: true

require 'spec_helper'
require 'cucumber/glue/registry_and_more'
require 'support/fake_objects'

module Cucumber
  module Glue
    describe StepDefinition do
      let(:user_interface) { double('user interface') }
      let(:registry)       { support_code.registry }
      let(:support_code) do
        Cucumber::Runtime::SupportCode.new(user_interface)
      end
      let(:dsl) do
        registry
        Object.new.extend(Glue::Dsl)
      end

      # rubocop:disable Style/GlobalVars
      describe '#load_code_file' do
        before(:each) { $foo = nil }

        after(:each) do
          FileUtils.rm_rf('tmp.rb')
          FileUtils.rm_rf('docs.md')
        end

        def a_file_called(name)
          File.open(name, 'w') do |f|
            f.puts yield
          end
        end

        context 'by default' do
          after(:each) do
            FileUtils.rm_rf('tmp1.rb')
          end

          it 'does not re-load the file when called multiple times' do
            a_file_called('tmp1.rb') do
              '$foo = 1'
            end

            registry.load_code_file('tmp1.rb')
            expect($foo).to eq 1

            a_file_called('tmp1.rb') do
              '$foo = 2'
            end

            registry.load_code_file('tmp1.rb')
            expect($foo).to eq 1
          end

          it 'only loads ruby files' do
            a_file_called('docs.md') do
              '$foo = 1'
            end

            registry.load_code_file('docs.md')
            expect($foo).to be nil
          end
        end

        context 'With `use_legacy_autoloader` set to true' do
          before(:each) do
            allow(Cucumber).to receive(:use_legacy_autoloader).and_return(true)
          end

          after(:each) do
            FileUtils.rm_rf('tmp2.rb')
          end

          it 're-loads the file when called multiple times' do
            a_file_called('tmp2.rb') do
              '$foo = 1'
            end

            registry.load_code_file('tmp2.rb')
            expect($foo).to eq 1

            a_file_called('tmp2.rb') do
              '$foo = 2'
            end

            registry.load_code_file('tmp2.rb')
            expect($foo).to eq 2
          end

          it 'only loads ruby files' do
            a_file_called('docs.md') do
              '$foo = 1'
            end

            registry.load_code_file('docs.md')
            expect($foo).to be nil
          end
        end

        context 'With `use_legacy_autoloader` set to false' do
          before(:each) do
            allow(Cucumber).to receive(:use_legacy_autoloader).and_return(false)
          end

          after(:each) do
            FileUtils.rm_rf('tmp3.rb')
          end

          it 'does not re-load the file when called multiple times' do
            a_file_called('tmp3.rb') do
              '$foo = 1'
            end

            registry.load_code_file('tmp3.rb')
            expect($foo).to eq 1

            a_file_called('tmp3.rb') do
              '$foo = 2'
            end

            registry.load_code_file('tmp3.rb')
            expect($foo).to eq 1
          end

          it 'only loads ruby files' do
            a_file_called('docs.md') do
              '$foo = 1'
            end

            registry.load_code_file('docs.md')
            expect($foo).to be nil
          end
        end
        # rubocop:enable Style/GlobalVars
      end

      describe 'Handling the World' do
        it 'raises an error if the world is nil' do
          dsl.World {}

          begin
            registry.begin_scenario(nil)
            raise 'Should fail'
          rescue Glue::NilWorld => e
            expect(e.message).to eq 'World procs should never return nil'
            expect(e.backtrace.length).to eq 1
            expect(e.backtrace[0]).to match(/spec\/cucumber\/glue\/registry_and_more_spec\.rb:\d+:in `World'/)
          end
        end

        it 'implicitlys extend world with modules' do
          dsl.World(FakeObjects::ModuleOne, FakeObjects::ModuleTwo)
          registry.begin_scenario(double('scenario').as_null_object)
          class << registry.current_world
            extend RSpec::Matchers

            expect(included_modules.inspect).to match(/ModuleOne/) # Workaround for RSpec/Ruby 1.9 issue with namespaces
            expect(included_modules.inspect).to match(/ModuleTwo/)
          end
          expect(registry.current_world.class).to eq Object
        end

        it 'raises error when we try to register more than one World proc' do
          expected_error = %(You can only pass a proc to #World once, but it's happening
in 2 places:

spec/cucumber/glue/registry_and_more_spec.rb:\\d+:in `World'
spec/cucumber/glue/registry_and_more_spec.rb:\\d+:in `World'

Use Ruby modules instead to extend your worlds. See the Cucumber::Glue::Dsl#World RDoc
or http://wiki.github.com/cucumber/cucumber/a-whole-new-world.

)
          dsl.World { {} }

          expect { dsl.World { [] } }.to raise_error(Glue::MultipleWorld, /#{expected_error}/)
        end
      end

      describe 'Handling namespaced World' do
        it 'extends the world with namespaces' do
          dsl.World(FakeObjects::ModuleOne, module_two: FakeObjects::ModuleTwo, module_three: FakeObjects::ModuleThree)
          registry.begin_scenario(double('scenario').as_null_object)
          class << registry.current_world
            extend RSpec::Matchers
            expect(included_modules.inspect).to match(/ModuleOne/)
          end
          expect(registry.current_world.class).to eq Object
          expect(registry.current_world).to respond_to(:method_one)

          expect(registry.current_world.module_two.class).to eq Object
          expect(registry.current_world.module_two).to respond_to(:method_two)

          expect(registry.current_world.module_three.class).to eq Object
          expect(registry.current_world.module_three).to respond_to(:method_three)
        end

        it 'allows to inspect the included modules' do
          dsl.World(FakeObjects::ModuleOne, module_two: FakeObjects::ModuleTwo, module_three: FakeObjects::ModuleThree)
          registry.begin_scenario(double('scenario').as_null_object)
          class << registry.current_world
            extend RSpec::Matchers
          end
          expect(registry.current_world.inspect).to match(/ModuleOne/)
          expect(registry.current_world.inspect).to include('ModuleTwo (as module_two)')
          expect(registry.current_world.inspect).to include('ModuleThree (as module_three)')
        end

        it 'merges methods when assigning different modules to the same namespace' do
          dsl.World(namespace: FakeObjects::ModuleOne)
          dsl.World(namespace: FakeObjects::ModuleTwo)
          registry.begin_scenario(double('scenario').as_null_object)
          class << registry.current_world
            extend RSpec::Matchers
          end
          expect(registry.current_world.namespace).to respond_to(:method_one)
          expect(registry.current_world.namespace).to respond_to(:method_two)
        end

        it 'resolves conflicts when assigning different modules to the same namespace' do
          dsl.World(namespace: FakeObjects::ModuleOne)
          dsl.World(namespace: FakeObjects::ModuleMinusOne)
          registry.begin_scenario(double('scenario').as_null_object)
          class << registry.current_world
            extend RSpec::Matchers
          end
          expect(registry.current_world.namespace).to respond_to(:method_one)
          expect(registry.current_world.namespace.method_one).to eql(-1)
        end
      end

      describe 'hooks' do
        it 'finds before hooks' do
          fish = dsl.Before('@fish') {}
          meat = dsl.Before('@meat') {}

          scenario = double('Scenario')

          expect(scenario).to receive(:accept_hook?).with(fish) { true }
          expect(scenario).to receive(:accept_hook?).with(meat) { false }
          expect(registry.hooks_for(:before, scenario)).to eq [fish]
        end

        it 'finds around hooks' do
          a = dsl.Around do |scenario, block|
          end

          b = dsl.Around('@tag') do |scenario, block|
          end

          scenario = double('Scenario')

          expect(scenario).to receive(:accept_hook?).with(a) { true }
          expect(scenario).to receive(:accept_hook?).with(b) { false }
          expect(registry.hooks_for(:around, scenario)).to eq [a]
        end
      end
    end
  end
end
