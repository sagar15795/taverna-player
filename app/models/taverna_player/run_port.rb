module TavernaPlayer
  class RunPort < ActiveRecord::Base
    self.inheritance_column = "port_type"

    belongs_to :run, :class_name => "TavernaPlayer::Run"

    validates_presence_of :name
    validates_uniqueness_of :name, :scope => [:run_id, :port_type]

    attr_accessible :depth, :name, :value

    default_scope order("lower(name) ASC")
  end

  class RunPort::Input < RunPort
    attr_accessible :file

    has_attached_file :file,
      :path => ":rails_root/public/system/:class/:attachment/:id/:filename",
      :url => :file_url_via_run,
      :default_url => ""

    def value
      v = self[:value]
      if !v.blank? && !file.path.blank?
        File.read(file.path)
      else
        v
      end
    end

    def value=(v)
      if !v.blank? && v.size > 255
        self[:value] = v[0...255]
        save_value_to_file(v)
      else
        self.file = nil unless file.path.blank?
        self[:value] = v
      end
    end

    private

    def file_url_via_run
      "/runs/#{run_id}/input/#{name}"
    end

    def save_value_to_file(v)
      Dir.mktmpdir("#{id}", Rails.root.join("tmp")) do |tmp_dir|
        tmp_file_name = File.join(tmp_dir, "value.txt")

        File.open(tmp_file_name, "w") do |f|
          f.write(v)
        end

        self.file = File.new(tmp_file_name)
      end
    end

  end

  class RunPort::Output < RunPort
    attr_accessible :metadata

    serialize :metadata
  end
end
