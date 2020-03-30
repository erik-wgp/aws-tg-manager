#!/usr/bin/env ruby

require_relative '../lib/init.rb'

elb = ElbManager.new

cnt = 0

ARGV.each do |group_str|
   tg_names = elb.stage_add_group_to_state(group_str)

   if ! tg_names.empty?
      puts "added instances in #{group_str} from #{tg_names.join(' ')}"
      cnt += tg_names.size
   end
end

# don't validate here when we are adding; additions will only improve the situation

puts "#{cnt} total instances to be added"
elb.execute_adds
puts "Complete"
