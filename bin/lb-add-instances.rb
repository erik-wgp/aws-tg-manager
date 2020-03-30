#!/usr/bin/env ruby

require_relative '../lib/init.rb'

elb = ElbManager.new

cnt = 0

ARGV.each do |instance_str|
   tg_names = elb.stage_add_instance_to_state(instance_str)

   if ! tg_names.empty?
      puts "added #{instance_str} to #{tg_names.join(' ')}"
      cnt += tg_names.size
   end
end

# don't validate here when we are adding; additions will only improve the situation
puts "#{cnt} total instances to add"
elb.execute_adds
puts "Complete"
