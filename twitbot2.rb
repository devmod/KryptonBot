require "rubygems"
require "twitter"
require 'twitpic-full'
require 'RMagick'
require 'dm-sqlite-adapter'
require 'data_mapper'
require 'yaml'
require 'hashie'
require 'dm-migrations'

require './models/fact'
require './models/state'
include Magick

$CONFIG = Hashie::Mash.new(YAML.load_file("config/config.yml"))
#DataMapper::Logger.new($stdout, :debug)
DataMapper.setup(:default, "sqlite://#{File.absolute_path $CONFIG.my_db_name}")
DataMapper.finalize

MY_VERSION = "0.2.0"

MY_USERNAME = $CONFIG.my_username
MY_NAME = $CONFIG.my_name
ADMIN_USERNAME = $CONFIG.admin_username
ADMINS = $CONFIG.admins


Twitter.configure do |config|
  config.consumer_key = $CONFIG.consumer_key
  config.consumer_secret = $CONFIG.consumer_secret
  config.oauth_token = $CONFIG.token
  config.oauth_token_secret = $CONFIG.secret
end

$twitPic = TwitPic::Client.new
$twitPic.config.api_key = $CONFIG.twitpic_key
$twitPic.config.consumer_key = $CONFIG.twitpic_consumer_key
$twitPic.config.consumer_secret = $CONFIG.twitpic_consumer_secret
$twitPic.config.oauth_token = $CONFIG.twitpic_token
$twitPic.config.oauth_secret = $CONFIG.twitpic_secret

def create_and_upload_pic keyword, definition
  str = "caption:[#{Time.now.strftime("%H:%M:%S")}] <#{MY_NAME}> #{keyword} == #{definition}"
  img = Image.read(str) do
    self.background_color = "black"
    self.fill = "white"
    self.size = "600"
    self.pointsize = 20
    self.font = "Tahoma"
  end
  img[0].write("tmp.png")
  res = $twitPic.upload "./tmp.png", "[#{Time.now.strftime("%H:%M:%S")}] ?? keyword"
  if res
#   => {"id"=>"a8z3ag", "text"=>"test1", "url"=>"http://twitpic.com/a8z3ag", "width"=>1000, "height"=>115, "size"=>10122, "type"=>"png", "timestamp"=>"Wed, 18 Jul 2012 12:39:20 +0000", "user"=>{"id"=>243748835, "screen_name"=>"KryptonLC"}}
    return res["url"]
  else
    return nil
  end
end

#puts Twitter::Client::TimeLine.inspect
state = State.first
if state.nil?
  last_id = 30812698992189440 
  puts "No state found. Default last_id_processed: #{last_id}"
  state = State.new(:last_processed_id => last_id, :date => Time.now.strftime("%Y-%m-%d %H:%M:%S"))
  state.save
else
  last_id = state.last_processed_id
  puts "State found. last_id_processed: #{last_id}"
end

prev_last_id = last_id

callsLeft = Twitter.rate_limit_status
if callsLeft.remaining_hits < 10
  Twitter.update("Twitter.com is complaining that I tweet too much! Going to sleep for #{callsLeft.reset_time_in_seconds/60} minutes / cc @#{ADMIN_USERNAME}")
  puts "We hit the limit already! Going to sleep for #{callsLeft.reset_time_in_seconds/60} minutes."
  sleep callsLeft.reset_time_in_seconds
else
  puts "STARTING UP | HITS: #{callsLeft.remaining_hits}/#{callsLeft.hourly_limit} | Reset in #{callsLeft.reset_time_in_seconds} seconds | Reset @ #{callsLeft.reset_time}"
end

while(1)
  begin
    callsLeft = Twitter.rate_limit_status
  rescue Exception => e
    puts "Twitter is not available at the moment. Sleeping for 30 seconds"
    sleep 30
    next
  end
  if callsLeft.remaining_hits < 64
    puts "HITS: #{callsLeft.remaining_hits}/#{callsLeft.hourly_limit} | Reset in #{callsLeft.reset_time_in_seconds} seconds | Reset @ #{callsLeft.reset_time}"
  end
  if callsLeft.remaining_hits > 15
    options = { :since_id => last_id, :include_rts => 0, :include_entities => 0 }
    begin
      Twitter.mentions(options).reverse.each do |mention|
        if mention.user.screen_name.downcase != MY_USERNAME.downcase
          #Handle the mention and move onto the next one
          puts "DEBUG : " + mention.id.to_s + " : " + mention.text
          begin
            if mention.text.downcase.start_with? "@#{MY_USERNAME.downcase} ?? version"
              puts "Got a version request from @#{mention.user.screen_name}"
              Twitter.update("@#{mention.user.screen_name} Version #{MY_VERSION} | #{rand(89)+10}".slice(0..139), {:in_reply_to_status_id => mention.id})
            elsif mention.text.downcase.start_with? "@#{MY_USERNAME.downcase} ?? help"
              puts "Got a help request from @#{mention.user.screen_name}"
              Twitter.update("@#{mention.user.screen_name} ?? help | ?? version | ?? keyword | !randomkey bleh | !randomdef blah | !learn key def | !say @user meh | !who key | #{rand(89)+10}", {:in_reply_to_status_id => mention.id})
            elsif mention.text.downcase.start_with? "@#{MY_USERNAME.downcase} !learn "
              keyword = mention.text[/learn (\S+) (.+)/,1]
              definition = mention.text[/learn (\S+) (.+)/,2]
              if ADMINS.index(mention.user.screen_name).nil?
                puts "NOT Learning: #{keyword} => #{definition} | I don't know who #{mention.user.screen_name} is!"
                Twitter.update("@#{mention.user.screen_name} Sure... wait who are you again? | #{rand(89)+10}".slice(0..139), { :in_reply_to_status_id => mention.id })
              else  
                key = Fact.first(:keyword =>keyword)
                if key.nil? 
                  puts "Learning: #{keyword} => #{definition}"
                  w = Fact.new( :keyword => keyword, :definition => definition, :author => mention.user.screen_name, :date_created => Time.now.strftime("%Y-%m-%d %H:%M:%S"))
                  w.save
                  Twitter.update("@#{mention.user.screen_name} Got it! (#{keyword}: #{definition}) | #{rand(89)+10}".slice(0..139), { :in_reply_to_status_id => mention.id })
                else 
                  puts "Updating: #{keyword} => #{definition}"
                  key.update(:keyword => keyword, :definition => definition, :author => mention.user.screen_name, :date_created => Time.now.strftime("%Y-%m-%d %H:%M:%S"))
                  Twitter.update("@#{mention.user.screen_name} Updated! (#{keyword}: #{definition}) | #{rand(89)+10}".slice(0..139), { :in_reply_to_status_id => mention.id })
                end
              end
            elsif mention.text.downcase.start_with? "@#{MY_USERNAME.downcase} !say @"
              username = mention.text[/say @(\S+) (.+)/,1]
              message = mention.text[/say @(\S+) (.+)/,2]
              if ADMINS.index(mention.user.screen_name).nil?
                puts "NOT saying to @#{username} => #{message} | I don't know who #{mention.user.screen_name} is!"
                Twitter.update("@#{mention.user.screen_name} Sure... wait who are you again? | #{rand(89)+10}".slice(0..139), { :in_reply_to_status_id => mention.id })
              else  
                puts "Saying to @#{username} => #{message}"
                Twitter.update("@#{username} #{message} | #{rand(89)+10}".slice(0..139))
              end
            elsif mention.text.downcase.start_with? "@#{MY_USERNAME.downcase} !who "
              keyword = mention.text[/who (\S+)/,1]
              key = Fact.first(:keyword => keyword)
              if key.nil?
                Twitter.update("@#{mention.user.screen_name} Sorry, I don't know who defined #{keyword}. | #{rand(89)+10}".slice(0..139), {:in_reply_to_status_id => mention.id})
              else
                puts "Who @#{keyword} ? #{key.author}"
                Twitter.update("@#{mention.user.screen_name} #{keyword} defined by #{key.author} on #{key.date_created} | #{rand(89)+10}".slice(0..139), { :in_reply_to_status_id => mention.id })
              end
            elsif mention.text.downcase.start_with? "@#{MY_USERNAME.downcase} ?? "
              #?? keyword @includeme
              keyword = mention.text[/\?\? (\S+)/,1]
              puts "Searching for #{keyword} for @#{mention.user.screen_name}"
              w = Fact.first( :keyword => keyword )
              #TODO: save twitpic url in db to use it later instead of uploading a new pic everytime.
              if w.nil?
                Twitter.update("@#{mention.user.screen_name} Sorry, I don't know what #{keyword} means. | #{rand(89)+10}".slice(0..139), {:in_reply_to_status_id => mention.id})
              else
                url = nil
                begin
                  url = create_and_upload_pic w.keyword, w.definition
                rescue Exception => e
                  puts "Exception while uploading... #{e.inspect}"
                end
              
                if !url.nil?
                  Twitter.update("@#{mention.user.screen_name} #{keyword}: #{url}".slice(0..139), {:in_reply_to_status_id => mention.id})
                else
                  Twitter.update("@#{mention.user.screen_name} #{keyword}: Twitpic is not responding... Oopsie! | #{rand(89)+10}".slice(0..139), {:in_reply_to_status_id => mention.id})
                end
              end
            elsif mention.text.downcase.start_with? "@#{MY_USERNAME.downcase} !randomdef "
              str = mention.text[/\!randomdef (\S+)/,1]
              puts "Searching for #{str} for @#{mention.user.screen_name}"
              #w = Fact.all.sample
              w = Fact.all(:definition.like => "%#{str}%").sample
              #TODO: save twitpic url in db to use it later instead of uploading a new pic everytime.
              if w.nil?
                Twitter.update("@#{mention.user.screen_name} Nothing was found. | #{rand(89)+10}".slice(0..139), {:in_reply_to_status_id => mention.id})
              else
                url = nil
                begin
                  url = create_and_upload_pic w.keyword, w.definition
                rescue Exception => e
                  puts "Exception while uploading... #{e.inspect}"
                end
                if !url.nil?
                  Twitter.update("@#{mention.user.screen_name} #{w.keyword}: #{url}".slice(0..139), {:in_reply_to_status_id => mention.id})
                else
                  Twitter.update("@#{mention.user.screen_name} #{w.keyword}: Twitpic is not responding... Oopsie! | #{rand(89)+10}".slice(0..139), {:in_reply_to_status_id => mention.id})
                end
              end  
            elsif mention.text.downcase.start_with? "@#{MY_USERNAME.downcase} !randomkey "
              str = mention.text[/\!randomkey (\S+)/,1]
              puts "Searching for #{str} for @#{mention.user.screen_name}"
              #w = Fact.all.sample
              w = Fact.all(:keyword.like => "%#{str}%").sample
              #TODO: save twitpic url in db to use it later instead of uploading a new pic everytime.
              if w.nil?
                Twitter.update("@#{mention.user.screen_name} Nothing was found. | #{rand(89)+10}".slice(0..139), {:in_reply_to_status_id => mention.id})
              else
                url = nil
                begin
                  url = create_and_upload_pic w.keyword, w.definition
                rescue Exception => e
                  puts "Exception while uploading... #{e.inspect}"
                end
                if !url.nil?
                  Twitter.update("@#{mention.user.screen_name} #{w.keyword}: #{url}".slice(0..139), {:in_reply_to_status_id => mention.id})
                else
                  Twitter.update("@#{mention.user.screen_name} #{w.keyword}: Twitpic is not responding... Oopsie! | #{rand(89)+10}".slice(0..139), {:in_reply_to_status_id => mention.id})
                end
              end
            elsif (mention.text.downcase.start_with? "@#{MY_USERNAME.downcase} !") || (mention.text.downcase.start_with? "@#{MY_USERNAME.downcase} ?")
              puts "I don't know this command: #{mention.text}"
              Twitter.update("@#{mention.user.screen_name} Sorry, I have no idea what you are talking about! (try @#{MY_USERNAME} ?? help) | #{rand(89)+10}".slice(0..139), {:in_reply_to_status_id => mention.id})
            else
              puts "No idea what this is: #{mention.text}"
            end
          rescue Exception => e   
  #        rescue Twitter::BadRequest, Twitter::Unauthorized, Twitter::Forbidden, Twitter::NotFound, 
  #                  Twitter::NotAcceptable, Twitter::EnhanceYourCalm, Twitter::InternalServerError, 
  #                  Twitter::BadGateway, Twitter::ServiceUnavailable => e
            puts e.message
          end
        end
        last_id = mention.id
      end
    rescue Exception => e
      puts e.message
    end
    if prev_last_id != last_id
      prev_last_id = last_id
      puts "Last id processed: #{last_id}"
      state.update(:last_processed_id => last_id, :date => Time.now.strftime("%Y-%m-%d %H:%M:%S"))
    end
    sleep 15
  else
    begin
      Twitter.update("Twitter.com is complaining that I tweet too much! Going to sleep for #{callsLeft.reset_time_in_seconds/60} minutes / cc @#{ADMIN_USERNAME}")
      puts "We hit the limit already! Going to sleep for #{callsLeft.reset_time_in_seconds/60} minutes."
      sleep callsLeft.reset_time_in_seconds
    rescue Exception => e
      puts "Twitter is not available at the moment. Sleeping for 30 seconds"
      sleep 30
      next
    end    
  end
end
