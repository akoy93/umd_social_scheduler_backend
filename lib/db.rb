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

  has n, :students, through: Resource

  # returns array of hashes with name, fbid, section
  def self.roster(term_code, course_code, section)
    term_code = term_code.to_s.upcase
    course_code = course_code.to_s.upcase
    section = section.to_s.upcase
    roster = []
    if section.nil? or section.empty? # get all sections
      Courses.all({term_code: term_code, course_code: course_code}).each do |course|
        roster += course.students.map { |s| {name: s.name, fbid: s.fbid, section: course.section} }
      end
    else
      roster = Course.get(term_code, course_code, section).students.map do |s|
        {name: s.name, fbid: s.fbid, section: section}
      end
    end
    roster
  end
end

class Student
  include DataMapper::Resource

  property :fbid, String, key: true
  property :name, String

  validates_length_of :fbid, minimum: 3, maximum: 25
  validates_length_of :name, minimum: 1, maximum: 100

  has n, :courses, through: Resource

  def self.create(fbid, name)
    student = Student.first_or_new({fbid: fbid, name: name})
    student.save ? student : nil
  end

  def delete_schedule(term_code)
    term_code = term_code.to_s.upcase
    status = true;
    self.courses.all({term_code: term_code.to_s.upcase}).each do |link|
      status &&= link.destroy!
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

DataMapper.finalize.auto_upgrade!
