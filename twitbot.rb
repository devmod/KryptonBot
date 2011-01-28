require "rubygems"
require "twitter"
require 'sqlite3'
require 'active_record'
require 'config.rb'
MY_VERSION = "0.0.3"

ActiveRecord::Base.establish_connection(:adapter => 'sqlite3', :database => MY_DB_NAME)
class Fact < ActiveRecord::Base
  if !Fact.table_exists?
    ActiveRecord::Base.connection.create_table(:facts) do |t|
      t.column :keyword, :string
      t.column :definition, :string
      t.column :author, :string
      t.column :date_created, :datetime
    end
  end
end
#How to store a single key?
class State < ActiveRecord::Base
  if !State.table_exists?
    ActiveRecord::Base.connection.create_table(:states) do |t|
      t.column :last_processed_id, :int
      t.column :date, :datetime
    end
  end
end

Twitter.configure do |config|
  config.consumer_key = @consumer_key
  config.consumer_secret = @consumer_secret
  config.oauth_token = @token
  config.oauth_token_secret = @secret
end

#puts Twitter::Client::TimeLine.inspect
state = State.find(:first)
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
  rescue Twitter::ServiceUnavailable, Twitter::BadGateway 
    puts "Twitter is not available at the moment. Sleeping for 30 seconds"
    sleep 30
    continue
  end
  if callsLeft.remaining_hits < 64
    puts "HITS: #{callsLeft.remaining_hits}/#{callsLeft.hourly_limit} | Reset in #{callsLeft.reset_time_in_seconds} seconds | Reset @ #{callsLeft.reset_time}"
  end
  if callsLeft.remaining_hits > 15
    options = { :since_id => last_id, :include_rts => 0, :include_entities => 0 }
    #Check for new mentions.
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
            Twitter.update("@#{mention.user.screen_name} ?? help | ?? version | ?? keyword | !learn keyword definition | !say @user blah | !who keyword | #{rand(89)+10}", {:in_reply_to_status_id => mention.id})
          elsif mention.text.downcase.start_with? "@#{MY_USERNAME.downcase} !learn "
            keyword = mention.text[/learn (\S+) (.+)/,1]
            definition = mention.text[/learn (\S+) (.+)/,2]
            if ADMINS.index(mention.user.screen_name).nil?
              puts "NOT Learning: #{keyword} => #{definition} | I don't know who #{mention.user.screen_name} is!"
              Twitter.update("@#{mention.user.screen_name} Sure... wait who are you again? | #{rand(89)+10}".slice(0..139), { :in_reply_to_status_id => mention.id })
            else  
              key = Fact.find_by_keyword(keyword)
              if key.nil? 
                puts "Learning: #{keyword} => #{definition}"
                w = Fact.new( :keyword => keyword, :definition => definition, :author => mention.user.screen_name, :date_created => Time.now.strftime("%Y-%m-%d %H:%M:%S"))
                w.save
                Twitter.update("@#{mention.user.screen_name} Got it! (#{keyword}: #{definition}) | #{rand(89)+10}".slice(0..139), { :in_reply_to_status_id => mention.id })
              else 
                puts "Updating: #{keyword} => #{definition}"
                Fact.update(key.id, :keyword => keyword, :definition => definition, :author => mention.user.screen_name, :date_created => Time.now.strftime("%Y-%m-%d %H:%M:%S"))
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
            key = Fact.find_by_keyword(keyword)
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
            w = Fact.find_by_keyword( keyword, :first )
            if w.nil?
              Twitter.update("@#{mention.user.screen_name} Sorry, I don't know what #{keyword} means. | #{rand(89)+10}".slice(0..139), {:in_reply_to_status_id => mention.id})
            else
              Twitter.update("@#{mention.user.screen_name} #{keyword}: #{w.definition} | #{rand(89)+10}".slice(0..139), {:in_reply_to_status_id => mention.id})
            end
          elsif mention.text.downcase.start_with? "@#{MY_USERNAME.downcase}"
            puts "I don't know this command: #{mention.text}"
            Twitter.update("@#{mention.user.screen_name} Sorry, I have no idea what you are talking about! (try @#{MY_USERNAME} ?? help) | #{rand(89)+10}".slice(0..139), {:in_reply_to_status_id => mention.id})
          else
            puts "No idea what this is: #{mention.text}"
          end
        rescue Twitter::BadRequest, Twitter::Unauthorized, Twitter::Forbidden, Twitter::NotFound, 
                  Twitter::NotAcceptable, Twitter::EnhanceYourCalm, Twitter::InternalServerError, 
                  Twitter::BadGateway, Twitter::ServiceUnavailable => e
          puts e.message
        end
      end
      last_id = mention.id
    end
    if prev_last_id != last_id
      prev_last_id = last_id
      puts "Last id processed: #{last_id}"
      State.update(state.id, :last_processed_id => last_id, :date => Time.now.strftime("%Y-%m-%d %H:%M:%S"))
    end
    sleep 15
  else
    begin
      Twitter.update("Twitter.com is complaining that I tweet too much! Going to sleep for #{callsLeft.reset_time_in_seconds/60} minutes / cc @#{ADMIN_USERNAME}")
      puts "We hit the limit already! Going to sleep for #{callsLeft.reset_time_in_seconds/60} minutes."
      sleep callsLeft.reset_time_in_seconds
    rescue Twitter::ServiceUnavailable, Twitter::BadGateway 
      puts "Twitter is not available at the moment. Sleeping for 30 seconds"
      sleep 30
      continue
    end    
  end
end

