DataMapper.setup(:default, ENV['DATABASE_URL'] || "sqlite3://#{Dir.pwd}/dev.db")

class Term
  include DataMapper::Resource

  property :term_code, String, key: true

  validates_length_of :term_code, is: 6

  has n, :courseEntries

  # create new term unless it already exists
  def self.new_term(term_code)
    term_code.to_s.upcase!
    if Term.get(term_code).nil?
      Term.new({term_code: term_code}).save
      return true
    end
    false
  end

  # delete all entires for a user in a particular term
  def self.delete_user(term_code, fbid)
    status = true
    Term.get(term_code.to_s.upcase).courseEntries.all(fbid: fbid.to_s).each do |c|
      status &&= c.destroy!
    end
    status
  end

  # add a new course entry to a particular term
  def self.add(term_code, course_entry)
    term = Term.get(term_code.to_s.upcase)
    term.courseEntries << course_entry
    term.save
  end

  # get the class roster for a class and section in a particular term
  def self.classmates(term_code, course, section)
    term = Term.get(term_code.to_s.upcase)

    classmates = term.courseEntries.all(course: course.to_s.upcase)
    classmates = courses.all(section: section.to_s.upcase) unless section.nil? or section.empty?
    classmates
  end
end

class CourseEntry
  include DataMapper::Resource

  property :fbid, String, key: true
  property :course, String, key: true
  property :section, String

  validates_length_of :fbid, minimum: 3, maximum: 25
  validates_length_of :course, minimum: 7, maximum: 8
  validates_length_of :section, is: 4

  belongs_to :term

  # create a new course entry
  def self.create_entry(fbid, course, section)
    CourseEntry.new({fbid: fbid.to_s.upcase, course: course.to_s.upcase, 
      section: section.to_s.upcase})
  end
end

DataMapper.finalize.auto_upgrade!
