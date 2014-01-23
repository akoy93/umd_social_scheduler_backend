configure :development do
  DataMapper.setup(:default, ENV['DATABASE_URL'] || "sqlite3://#{Dir.pwd}/dev.db")
end

configure :production do
  DB_USER, DB_PASS = File.readlines("#{settings.root}/db_data.txt").map(&:chomp)

  DataMapper.setup(:default,
    adapter: 'mysql',
    user: DB_USER,
    password: DB_PASS,
    host: 'localhost',
    database: 'umd_social_scheduler_backend')
end

class Course
  include DataMapper::Resource

  property :term_code, String, key: true
  property :course_code, String, key: true
  property :section, String, key: true

  validates_length_of :term_code, is: 6
  validates_length_of :course_code, minimum: 7, maximum: 8
  validates_length_of :section, is: 4

  has n, :students, through: Resource, constraint: :destroy

  # returns array of hashes with name, fbid, section
  def self.roster(term_code, course_code, section)
    term_code = term_code.to_s.upcase
    course_code = course_code.to_s.upcase
    section = section.to_s.upcase
    roster = []
    if section.nil? or section.empty? # get all sections
      Course.all({term_code: term_code, course_code: course_code}).each do |course|
        roster += course.students.map { |s| {name: s.name, fbid: s.fbid, 
          section: course.section, share: s.share} }
      end
    else
      course = Course.get(term_code, course_code, section)
      return [] if course.nil?
      roster = Course.get(term_code, course_code, section).students.map do |s|
        {name: s.name, fbid: s.fbid, section: section, share: s.share}
      end
    end
    roster
  end
end

class Student
  include DataMapper::Resource

  property :fbid, String, key: true
  property :name, String
  property :share, Boolean

  validates_presence_of :share
  validates_length_of :fbid, minimum: 3, maximum: 25
  validates_length_of :name, minimum: 1, maximum: 100

  has n, :courses, through: Resource, constraint: :destroy

  def self.new_student(fbid, name, share = true)
    student = Student.get(fbid)
    return student unless student.nil?
    student = Student.new({fbid: fbid, name: name, share: share})
    student.save! ? student : nil
  end

  def enable_sharing
    return true if share
    old_fbid = fbid
    old_name = name
    destroy!
    return !Student.new_student(old_fbid, old_name).nil?
  end

  def disable_sharing
    return true unless share
    old_fbid = fbid
    old_name = name
    destroy!
    return !Student.new_student(old_fbid, old_name, false).nil?
  end

  def delete_schedule(term_code)
    term_code = term_code.to_s.upcase
    status = true;
    course_students.all({course_term_code: term_code.to_s.upcase}).each do |l|
      status &&= l.destroy!
    end
    status
  end

  def get_schedule(term_code)
    term_code = term_code.to_s.upcase
    self.courses.all({term_code: term_code}).map do |c|
      {term_code: c.term_code, course_code: c.course_code, section: c.section}
    end
  end

  def add_course(term_code, course_code, section)
    term_code = term_code.to_s.upcase
    course_code = course_code.to_s.upcase
    section = section.to_s.upcase
    course = Course.first_or_new({ term_code: term_code, 
      course_code: course_code, section: section })
    course.students << self
    course.save
  end
end

# ISBN to ASIN mapping
class ISBN
  include DataMapper::Resource

  property :isbn, String, key: true
  property :asin, String

  validates_length_of :isbn, is: 13
  validates_length_of :asin, is: 10
end

DataMapper.finalize.auto_upgrade!
