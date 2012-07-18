require 'rubygems'
require 'dm-sqlite-adapter'
require 'data_mapper'
require 'yaml'
require 'hashie'
require 'dm-migrations'

$CONFIG = Hashie::Mash.new(YAML.load_file("config/config.yml"))
#DataMapper::Logger.new($stdout, :debug)
DataMapper.setup(:default, "sqlite://#{File.absolute_path $CONFIG.db_name}")
class Fact
  include DataMapper::Resource

  property :id,           Serial
  property :keyword,      String
  property :author,       Text
  property :definition,   Text
  property :date_created,   DateTime
end

DataMapper.finalize
#To create db
DataMapper.auto_migrate!

if !File.exist? $CONFIG.zlearn_file
  puts "Cannot find zlearn file"
end

lines = File.readlines $CONFIG.zlearn_file 
i = 0
inserted = 0
while i < (lines.count) do
  if lines[i].start_with?("k") && lines[i+1].start_with?("c") && 
      lines[i+2].start_with?("a") && lines[i+3].start_with?("f") &&
      lines[i+4].start_with?("d")
    begin
      #puts "Got a valid entry: [#{lines[i].strip.reverse.chop.reverse}, #{lines[i+4].strip.reverse.chop.reverse}, #{lines[i+2].strip.reverse.chop.reverse}]"
      fact = Fact.new(
        :keyword      => lines[i].strip.reverse.chop.reverse,
        :author       => lines[i+2].strip.reverse.chop.reverse,
        :definition   => lines[i+4].strip.reverse.chop.reverse,
        :date_created   => Time.now
      )
      if fact.save == true
        #puts "Inserted into db!"
        inserted += 1
      else
        puts "Error: #{fact.errors.inspect}"
      end
    rescue Exception => e
      puts "#### Exception #{e.inspect}"
    end
  else
    #puts "This line does not start with k(ey), skipping... #{lines[i]}"
  end
  i += 1
end

puts "Inserted #{inserted} facts into the db"