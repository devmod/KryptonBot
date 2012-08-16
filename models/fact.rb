class Fact
  include DataMapper::Resource
  
  property :id,           Serial
  property :keyword,      String
  property :author,       Text
  property :definition,   Text
  property :date_created,   DateTime
end
