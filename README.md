UMD Social Scheduler
====================

UMD Social Scheduler is a browser extension for Google Chrome that displays social information on top of the University of Maryland scheduling website at http://www.sis.umd.edu. 

API (backend)
-------------
Refer to backend/lib/app.rb. UMD Social Scheduler's backend is written in Ruby using the Sinatra gem.

####Facebook Login
  Submit a GET request to /login. This will use Facebook's server side login process. Once logged in, a session will be created. Note: the API calls below require that a Facebook user is logged in.
  
####Facebook Logout
  Submit a GET request to /logout. This will clear the session.
  
####Render Schedule JPEG
  Submit a POST request to /render_schedule containing "term" and "html" parameters. The "term" parameter corresponds to the six digit term code that the University of Maryland uses to denote semesters, and the "html" parameter should contain the html of the schedule to be rendered. Once the request is received and validated, the html will be rendered into a jpeg image.
  
####Post Schedule to Facebook
  Submit a GET request to /post_schedule. An image will be uploaded to the current user's Facebook account only if it was rendred during the current session.

####Add Schedule Data
  Submit a POST request to /add_schedule containing "term" and "schedule" paremeters. The "schedule" parameter contains the user's class schedule in the form of "course,section|course,section|course,section" i.e. "CMSC433,0101|CMSC451,0101|MATH410,0201". The user's schedule information will then be updated with the information in the POST request.
  
####Get Friends in a Class
  Submit a GET request to /friends/"term"/"course"/"section" i.e. /friends/201401/CMSC412/0101. This call will return a JSON of Facebook ID's of students who are friends with the current user and enrolled in "course", section "section" for the specified "term". The "section" parameter is optional and, if left out, the call will consider all sections of the course.
  
####Get Friends of Friends in a Class
  Similar to getting friends in a class, submit a GET request to /friendsoffriends/"term"/"course"/"section". The returned JSON will exclude friends of the current user.
  
####Get a Friend's Schedule Image
  Submit a GET request to /schedule/"term"/"facebook id" i.e. /schedule/201401/2359273392. This call will return a jpeg image of the user corresponding to the specified Facebook ID only if that user is friends with the current user.
  
Contact
-------
If you have any ideas for new features, if you would like to use my code, or if you would like to collaborate, contact me at albertkoy(at)gmail(dot)com.
