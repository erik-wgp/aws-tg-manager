
class Instance
  attr_accessor :raw, :id, :instance_groups, :az, :tags

  @@ID_TO_NAME = {}
  @@NAME_TO_ID = {}

  def initialize(args)

    @raw = args[:raw_data]
    @id = args[:id]
    @tags = args[:tags]

    instance_groups_string = @tags[$tag_names["INSTANCE_GROUPS_TAG"]]

    @instance_groups = []
    if instance_groups_string
      @instance_groups = instance_groups_string.split(/[\s,]+/)
    end

    @@ID_TO_NAME[@id] = @tags["Name"]
    @@NAME_TO_ID[@tags["Name"]] = @id
  end

  def tag(key)
    @tags[key]
  end

  def name
    @tags["Name"]
  end

  def print
    printf("INST %-15s %-15s %-60s\n", name, @id, @instance_groups.join(' '))
  end

  def self.name_id(str)
    id = id_from_string(str)
    id ? "#{id_to_name(id)}[#{id}]" : "#{str}[unknown]"
  end

  def self.id_from_string(str)
    if @@NAME_TO_ID[str]
      return @@NAME_TO_ID[str]
    elsif @@ID_TO_NAME[str]
      return str
    else
      return nil
    end
  end

  def self.id_to_name(str)
    @@ID_TO_NAME[str]
  end

  def self.name_to_id(str)
    @@NAME_TO_ID[str]
  end

end
