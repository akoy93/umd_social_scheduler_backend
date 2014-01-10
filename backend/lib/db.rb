DataMapper.setup(:default, ENV['DATABASE_URL]'] || "sqlite3://#{Dir.pwd}/dev.db")

class Course
  include DataMapper::Resource

  property :id, Serial
  property :fbid, Integer
  property :course, String
  property :section, String

  validates_presence_of :fbid
  validates_presence_of :course
  validates_presence_of :section
  validates_length_of :course, :minimum => 7, :maximum => 8
  validates_length_of :section, :is => 4
end

DataMapper.finalize.auto_upgrade!
