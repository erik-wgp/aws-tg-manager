#!/usr/bin/env ruby

require_relative '../lib/init.rb'

elb = ElbManager.new
elb.validate_and_print
