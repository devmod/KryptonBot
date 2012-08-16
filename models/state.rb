
class State 
  include DataMapper::Resource
  property :id, Serial
  property :last_processed_id, Integer
  property :date, DateTime
end