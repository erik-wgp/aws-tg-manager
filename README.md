# aws-tg-manager
Ruby scripts and basic libraries to manage AWS target groups

This is very much beta code to manage membership of servers in AWS target groups.  It could be used to stop traffic to persistent instances for updates and reboots, to remove instances from the target group(s) before destroying, or to add new instances to target groups.

## Requirements

This was built on ruby 2.6.5 and some common gems; see Gemfile.

Currently uses normal AWS credentials in ~/.aws/, using for ENV vars $ELB_MANAGER_AWS_PROFILE, or $AWS_PROFILE, or just "default"

## Configuration

The scripts derive an intended state from AWS tags in the target groups and instances, using a concept of instance groups, which are arbitrary tag-defined organizational collections.  They will presumably follow redundancy lines, such as of availability zones.

Target groups have tags like:

    AutoTGPolicy              instance_min=5 instance_group_min=2
    AutoTGInstanceGroups      prod-e1c prod-e1d

This defines that the target group will take instance groups prod-e1c and prod-e1d.  It also defines a policy of that the target group would like at least 5 instances total, and each instance group should have at least 2 instances.  These can be set to zero, in which case anything will be valid (including a down target group)

And instances tags like:

    AutoTGInstanceGroups      prod-e1d otherapp-e1d

This says the instance is a member of prod-e1d and otherapp-e1d (ie the instance can be in multiple groups)

These scripts then scan instances and with the AutoTGInstanceGroups, and the defined instance groups.  They then scan the target groups and their configuration, and produce a configuration of instance groups in target groups.  This configuration may be valid or not, based on the defined AutoTGPolicy.  Instances can be added or removed, which might then be valid or not.

Because these scripts keep no other state of configuration, they have limited knowledge and merely look at what is there and evaluate, add and/or remove as ordered.  It might be up to some other software to create new instances or manage auto scaling.

### Notes

The Tag names can be customized to support/isolate pools of target groups; for instance, AutoTGPolicyCMS for CMS related target groups, AutoTGPolicyAdmin for admin functions, etc.  This way these script won't object to unrelated outages.

### Todo
- further testing in more complex environments
- review tests and handling invalid instance ids, etc
- check for instance state before adding
- create a script to completely restore any available instances to all TGs
- create a script/methods to wait for a valid configuration before continuing, up to some timeout.  This way some instances could be added, then it would wait for everything to come up properly before removing other instances
