#
# Author:: Adam Jacob (<adam@opscode.com>)
# Copyright:: Copyright (c) 2008 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'tempfile'
require 'chef/provider/execute'
require 'chef/win32/security'
require 'forwardable'

class Chef
  class Provider
    class Script < Chef::Provider::Execute
      extend Forwardable

      provides :bash
      provides :csh
      provides :perl
      provides :python
      provides :ruby
      provides :script

      def_delegators :@new_resource, :interpreter, :flags

      attr_accessor :code

      def initialize(new_resource, run_context)
        super
        self.code = new_resource.code
      end

      def command
        "\"#{interpreter}\" #{flags} \"#{script_file.path}\""
      end

      def load_current_resource
        super
        # @todo Chef-13: change this to an exception
        if code.nil?
          Chef::Log.warn "#{@new_resource}: No code attribute was given, resource does nothing, this behavior is deprecated and will be removed in Chef-13"
        end
      end

      def action_run
        script_file.puts(code)
        script_file.close

        set_owner_and_group

        super

        unlink_script_file
      end

      def set_owner_and_group
        # FileUtils itself implements a no-op if +user+ or +group+ are nil
        # You can prove this by running FileUtils.chown(nil,nil,'/tmp/file')
        # as an unprivileged user.
        if ! Chef::Platform.windows?
          FileUtils.chown(new_resource.user, new_resource.group, script_file.path)
        else
          grant_alternate_user_read_access
        end
      end

      def grant_alternate_user_read_access
        securable_object = Chef::ReservedNames::Win32::Security::SecurableObject.new(script_file.path)
        aces = securable_object.security_descriptor.dacl.reduce([]) { | result, current | result.push(current) }
#        aces = securable_object.security_descriptor.dacl.flatten
        user_sid = Chef::ReservedNames::Win32::Security::SID.from_account(new_resource.user)
        read_ace = Chef::ReservedNames::Win32::Security::ACE.access_allowed(user_sid, Chef::ReservedNames::Win32::API::Security::GENERIC_READ | Chef::ReservedNames::Win32::API::Security::GENERIC_EXECUTE, 0)
        aces.push(read_ace)
        acl = Chef::ReservedNames::Win32::Security::ACL.create(aces)
        securable_object.dacl = acl
      end


      def script_file
        @script_file ||= Tempfile.open("chef-script")
      end

      def unlink_script_file
        script_file && script_file.close!
      end

    end
  end
end
