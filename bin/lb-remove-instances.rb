#!/usr/bin/env ruby

require_relative '../lib/init.rb'

elb = ElbManager.new

errors = elb.validate

if ! errors.empty?
   elb.elb_validate_and_print
   puts "Not executing: pre-validation failed"
end

cnt = 0

ARGV.each do |instance_str|
   tg_names = elb.stage_remove_instance_from_state(instance_str)

   if ! tg_names.empty?
      puts "removed #{instance_str} to #{tg_names.join(' ')}"
      cnt += tg_names.size
   end
end

puts "#{cnt} total instance removed"

errors = elb.validate

if errors.empty?
   elb.execute_removes
else
   elb.validate_and_print
   puts "Not executing due to errors"
end

