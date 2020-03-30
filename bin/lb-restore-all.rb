#!/usr/bin/env ruby

require_relative '../lib/init.rb'

Aws.config[:credentials] = Aws::SharedCredentials.new(profile_name: "default")

elb = ElbManager.new

code, info = elb.validate_current
error = false

code, current_error = elb.restore_all

if ! code
  STDERR.print "Failed to add instance #{instance_str}: #{current_error}"
end

if error
   STDERR.print "Aborting add due to errors"
   exit
end

#elb.execute_adds
