# Plurkruby is an implementation of the Plurk API (http://plurk.com/API) in Ruby.
# The Plurk API is accessed using HTTP and HTTPS GET requests and in one case a POST. Plurkruby uses the Net::HTTP
# library to interact with the server, allowing better error reporting than was available using OpenURI.
# Responses from Plurk are in the form of JSON messages and these are processed on receipt using the Ruby JSON library.
# One approach to implementing an API in Ruby would be to deal with the JSON values returned as JSON objects directly.
# This is not the approach taken in Plurkruby.  Instead, elements received from the server are translated into
# native Ruby objects, either in code in the API implementation or in Class initializer methods.
#
# Author::    John Messenger
# Copyright:: Copyright (c) 2010 John Messenger
# License::   New BSD License
#
require 'json'
require 'net/http'
require 'net/https'

class PlurkApi
   # true if the login method has been successfully called and its session cookie stored.
   attr_reader :logged_in
   # A File stream which if set is used to provide a trace of interactions with the Plurk server.
   attr_reader :logstream
   # Following a call to getUnreadCount, this is a hash of the unread counts for the currently logged in user.
   # Note that Plurk currently limits the unread counts to 200.
   attr_reader :unread_count
   # Following a call to getUnreadCount, this is the total number of unread Plurks for this user.
   attr_reader :unread_all
   # Following a call to getUnreadCount, this is the count of unread Plurks made by the logged in user.
   attr_reader :unread_my
   # Following a call to getUnreadCount, this is the count of the logged-in user's unread private Plurks
   attr_reader :unread_private
   # Following a call to getUnreadCount, this is the count of unread Plurks to which the logged-in user has
   # responded.
   attr_reader :unread_responded

   # These constants represent the +filter+ parameter values of the timelineGetPlurks method.
   TIMELINEGETPLURKS_ALL = nil
   TIMELINEGETPLURKS_MINE = 'only_user'
   TIMELINEGETPLURKS_PRIVATE = 'only_private'
   TIMELINEGETPLURKS_RESPONDED = 'only_responded'

   # +api_key+::    The API key obtained from http://plurk.com/API
   # +logstream+::  If a pre-opened stream is passed as a parameter, then requests and responses to the API
   #                are logged to that stream.
   # +certpath+::   If a directory name is given, then this will be supplied to Net::HTTP to verify SSL
   #                certificates.  Note that the behaviour is to ignore peer certification problems.
   #
   # Before using the API, a +PlurkApi+ object must be created.  It serves to store the state associated with
   # the session.  It is worth noting that following a call to +logout+, much of the state becomes invalid.
   # The methods for accessing the API are defined in this class.

   def initialize(api_key, logstream = nil, certpath = nil)
      $debug = 0 if not $debug
      @api_key = api_key
      @logstream = logstream
      @logged_in = nil
      @certpath = certpath
   end

   # If a successful call to +login+ has been made, this method will return +true+.
   def is_logged_in?
      @logged_in
   end

   # +apipath+::     the string from the API documentation which follows '/API'
   # +paramstr+::    if specified, a string of parameters each in the form '&param=value'
   # +use_https+::   if specified and true, then HTTPS and SSL are used for the API call.
   #
   # This internal method is used by all API accessing methods.  It builds a URI amd uses Net::HTTP to connect
   # to the 'www.plurk.com/API' service.  In order to support SSL certificate verification, if a certification
   # path is supplied, it is configured for use.  If a logging stream is active, the request is logged.
   # If the user has already logged in, the session cookie returned at that time is sent with the request.
   # The request is sent to the server and the response collected.  If the user is not logged in, any returned
   # cookie is stored for later use.  The response is logged if a logging stream is active.
   #
   # The returned value is parsed as a JSON object, both in the case of a good and bad response code from the
   # server.  If the server said "400 BAD REQUEST", then the error text is raised as a run-time error.
   # The parsed JSON object is returned for further processing.
   private :call_api
   def call_api(apipath, paramstr = '', use_https = false)
      uri = URI::HTTP.build({ :host => 'www.plurk.com', :path => '/API' + apipath,
            :query => 'api_key=' + @api_key + paramstr })
      if use_https
         uri.scheme = 'https'
         uri.port = 443
      end
      # We use this method as we want to send a cookie
      # Why does no documentation tell you you have to add the query yourself?
      httpobj = Net::HTTP.new(uri.host, uri.port)
      httpobj.use_ssl = true if use_https
      if @certpath and File.directory? @certpath
	 httpobj.ca_path = @certpath
	 httpobj.verify_mode = OpenSSL::SSL::VERIFY_PEER
	 httpobj.verify_depth = 5
      else
         httpobj.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      p uri if $printuri
      logstream.puts "Request: " + uri.to_s if logstream
      if $pretending
	 puts "Only pretending"
	 exit
      end
      req = Net::HTTP::Get.new(uri.path + '?' + uri.query)
      req.add_field('Cookie', @cookie) if @logged_in
      res = httpobj.request(req)
      # Login requests return a cookie that has to be sent with subsequent requests.  We save that cookie
      # if we are not logged in, which is how we decide if there will be one.
      @cookie = res['set-cookie'] if not @logged_in
      logstream.puts "Response: " + res.body if logstream
      obj = JSON.parse(res.body)
      
      raise obj['error_text'] if res.is_a? Net::HTTPBadRequest

      obj
   end

   # Plurk API call::	/API/Users/login
   # +username+::	existing Plurk username
   # +password+::	password for the specified user
   # +no_data+::	if specified and true, OwnProfile will not be returned
   #
   # Log in to Plurk.  Returns an OwnProfile object representing the newly logged-in user.
   # The session cookie returned is stored for automatic use in subsequent requests.
   def login(username, password, no_data = nil)
      paramstr = '&username=' + username + "&password=" + password 
      paramstr += '&no_data=1' if no_data
      obj = call_api('/Users/login', paramstr, :use_https => true)
      #obj = call_api('/Users/login', paramstr)
      @logged_in = true
      p @cookie if $debug > 2
      if no_data
         nil
      else
         OwnProfile.new(obj)
      end
   end

   # Plurk API call::	/API/Users/logout
   # Log out of Plurk
   def logout
      raise "not logged in" unless @logged_in
      call_api('/Users/logout')
      @logged_in = nil
   end

   # Plurk API call::	/API/Profile/getPublicProfile
   # +username+::       existing Plurk username
   #
   # Fetch the public profile of +username+.  Returns a PublicProfile object.
   def getPublicProfile(username)
      obj = call_api('/Profile/getPublicProfile', '&user_id=' + username)
      PublicProfile.new( obj )
   end

   # Plurk API call::	/API/Timeline/plurkAdd
   # +content+::	The text of the plurk which is to be created.
   # +qualifer+::	The "qualifier" of the plurk (e.g., 'says', must be in English)
   # +limited_to+::	If present, an array of user ids of people to whom this plurk is restricted.
   #			If set to '[ 0 ]', the plurk is limited to the plurker's friends.
   # +no_comments+::	If present, limits who can comment on this plurk.  See NOCOMMENTS_COMMENTS,
   #			NOCOMMENTS_DISABLED and NOCOMMENTS_FRIENDS.
   # +lang+::		If present, specify the language of this plurk.
   def plurkAdd(content, qualifier, limited_to=nil, no_comments=nil, lang=nil)
      raise "not logged in" unless @logged_in
      paramstr = '&content=' + URI::escape(content) + '&qualifier=' + URI::escape(qualifier)
      paramstr += '&limited_to=' + URI::escape(JSON.generate(limited_to)) if limited_to
      case no_comments
         when NOCOMMENTS_COMMENTS, NOCOMMENTS_DISABLED, NOCOMMENTS_FRIENDS
            paramstr += '&no_comments=' + no_comments.to_s
	 when nil	# nothing
	 else
	    raise "Illegal value " + no_comments.to_s + " for no_comments"
      end
      paramstr += '&lang=' + lang.to_s if lang
      Plurk.new(call_api('/Timeline/plurkAdd', paramstr))
   end

   # Plurk API call::	/API/Timeline/plurkAdd
   # +id+::		numerical id of the plurk to be deleted.
   # Delete the specified plurk.  Requires login.
   def plurkDelete(id)
      raise "not logged in" unless @logged_in
      call_api('/Timeline/plurkDelete', '&plurk_id=' + id.to_s)
   end

   # Plurk API call::	/API/Polling/getUnreadCount
   # Retrieves and stores the undread counts for the logged in user.  Returns a hash of the values, but these
   # are typically retrieved using the accessor methods +unread_all+, +unread_my+, +unread_private+
   # and +unread_responded+.  Requires login.
   def getUnreadCount
      raise "not logged in" unless @logged_in
      @unread_count = call_api('/Polling/getUnreadCount')
      @unread_all       = @unread_count['all']
      @unread_my        = @unread_count['my']
      @unread_private   = @unread_count['private']
      @unread_responded = @unread_count['responded']
   end

   # Plurk API call::	/API/Timeline/getPlurk
   # +pid+::		numeric id of the plurk to be retrieved.
   # Returns a pair of values.  First a Plurk object representing the plurk, and second a UserInfo
   # object representing the user who created it.
   def getPlurk(pid)
      raise "not logged in" unless @logged_in
      # This raises the issue of memory management.  If I create a new UserInfo and Plurk
      # object for each retrieved plurk, you might expect that to be a waste of memory.
      # However as long as I forget them again, they'll be GCed.  It is helpful that
      # the API returns info on the plurk's owner along with the plurk, so we don't
      # have to keep a user table.
      obj = call_api('/Timeline/getPlurk', '&plurk_id=' + pid.to_s)
      [ Plurk.new(obj["plurk"]), UserInfo.new(obj["user"]) ]
   end

   # Plurk API call::	/API/Polling/getPlurks
   # +newer_than+::	The offset in time determining which plurks will be returned.  Plurks more recent
   #                    than this time will be returned.  This parameter can be a Time object, or an integer
   #			(no. of seconds since epoch), or a string of format "2009-6-12T21:13:24".
   # +limit+::		If present, limits the number of plurks returned.  If not specified, the server's
   #			default of 50 plurks maximum will be returned.
   # This is the preferred interface for getting groups of plurks, as it is more efficient at the server.
   # It returns a pair of values.  First, an array of Plurk objects which appear to be in time order, and
   # second, a hash of user-id to UserInfo objects representing the owners of the Plurks.  This makes it
   # possible to render the Plurks without needing to retrieve additional information about their owners.
   def pollingGetPlurks(newer_than, limit = nil)
      raise "not logged in" unless @logged_in
      if newer_than.is_a? String
         timestr = newer_than
      else
	 timestr = Time.at(newer_than.to_i).getutc.strftime("%Y-%m-%dT%H:%M:%S")
      end
      paramstr = '&offset=' + timestr
      paramstr += '&limit=' + limit.to_s if limit
      json = call_api('/Polling/getPlurks', paramstr)
      plurk_users = Hash.new
      json["plurk_users"].each { |id,obj| plurk_users[id] = UserInfo.new(obj) }
      plurks = Array.new
      json["plurks"].each { |obj| plurks << Plurk.new(obj) }
      [ plurks, plurk_users ]
   end

   # Plurk API call::	/API/Timeline/getPlurks
   # +older_than+::	The offset in time determining which plurks will be returned.  Plurks older
   #                    than this will be returned.  This parameter can be a Time object, or an integer
   #			(no. of seconds since epoch), or a string of format "2009-6-12T21:13:24".
   # +limit+::		If present, limits the number of plurks returned.  If not specified, the server's
   #			default of 20 plurks maximum will be returned.
   # +filter+::		If present, limits the plurks returned to only private plurks, responded plurks or
   #                    the user's own plurks (which currently does not work).  See TIMELINEGETPLURKS_PRIVATE,
   #			TIMELINEGETPLURKS_RESPONDED and TIMELINEGETPLURKS_MINE.
   # This alternate interface for getting groups of plurks is discouraged as it is less efficient at the server.
   # It returns a pair of values.  First, an array of Plurk objects which appear to be in time order, and
   # second, a hash of user-id to UserInfo objects representing the owners of the Plurks.  This makes it
   # possible to render the Plurks without needing to retrieve additional information about their owners.
   # This interface includes filtering but is less efficient than the "polling" interface above.
   def timelineGetPlurks(older_than, limit = nil, filter = nil)
      # older_than can be a Time object, or an integer (no. of seconds since epoch), or a
      # string of format "2009-6-12T21:13:24".
      raise "not logged in" unless @logged_in
      if older_than.is_a? String
         timestr = older_than
      else
	 timestr = Time.at(older_than.to_i).getutc.strftime("%Y-%m-%dT%H:%M:%S")
      end
      paramstr = '&offset=' + timestr
      paramstr += '&limit=' + limit.to_s if limit
      paramstr += '&filter=' + filter.to_s if filter
      json = call_api('/Timeline/getPlurks', paramstr)
      plurk_users = Hash.new
      json["plurk_users"].each { |id,obj| plurk_users[id] = UserInfo.new(obj) }
      plurks = Array.new
      json["plurks"].each { |obj| plurks << Plurk.new(obj) }
      [ plurks, plurk_users ]
   end

   # Plurk API call::	/API/Responses/get
   # +plk+::		A Plurk object which is modified by adding the responses, respondeers and counts.
   # +offset+::		If present, the number of responses to skip before starting to return responses.
   # This method takes an existing Plurk object and adds to it an array of Response objects (+plk.responses+)
   # and a hash of UserInfo objects indexed by user-id of the owners of those responses (+plk.friends+).
   # The modified Plurk is returned.
   def getResponses(plk, offset = 0)
     raise "not logged in" unless @logged_in
     obj = call_api('/Responses/get', '&plurk_id=' + plk.plurk_id.to_s + '&from_response=' + offset.to_s)
     obj['responses'].each { |response| plk.responses << Response.new(response) }
     obj['friends'].each { |uid, frd| plk.friends[uid] = UserInfo.new(frd) }
     plk.response_count = obj['response_count'].to_s; # update the response count in the plurk
     plk
   end

   def responseAdd(plk, content, qualifier)
     raise "not logged in" unless @logged_in
     pid = plk.respond_to?('plurk_id') ? plk.plurk_id : plk.to_i
     paramstr = '&plurk_id=' + pid.to_s
     paramstr += '&content=' + URI::escape(content) + '&qualifier=' + URI::escape(qualifier)
     Response.new(call_api('/Responses/responseAdd', paramstr))
   end

   def responseDelete(rsp, plk)
     raise "not logged in" unless @logged_in
     rid = rsp.respond_to?('resp_id') ? rsp.resp_id : rsp.to_i
     pid = plk.respond_to?('plurk_id') ? plk.plurk_id : plk.to_i
     paramstr = '&response_id=' + rid.to_s + '&plurk_id=' + pid.to_s
     call_api('/Responses/responseDelete', paramstr)
   end

   def alertsGetActive
     raise "not logged in" unless @logged_in
     alerts = []
     call_api('/Alerts/getActive').each { |obj|
        alerts << Alert.new(obj)
     }
     alerts
   end

   def alertsGetHistory
     raise "not logged in" unless @logged_in
     alerts = []
     call_api('/Alerts/getHistory').each { |obj|
        alerts << Alert.new(obj)
     }
     alerts
   end

   def getBlocks(offset = nil)
     raise "not logged in" unless @logged_in
     paramstr = offset ? '&offset=' + offset.to_s : ""
     blockobj = call_api('/Blocks/get', paramstr)
     nblocks = blockobj['total']
     blocks = []
     blockobj['users'].each { |obj|
        blocks << UserInfo.new(obj)
     }
     [ nblocks, blocks ]
   end
end

class UserInfo
   attr_reader :timezone, :karma, :id, :gender, :uid, :relationship, :recruited, :avatar, :nick_name, :date_of_birth, :full_name, :location

   def initialize(json)
      @has_profile_image        = json["has_profile_image"]
      @timezone                 = json["timezone"]
      @karma                    = json["karma"]
      @id                       = json["id"]
      @gender                   = json["gender"]
      @uid                      = json["uid"]
      @relationship             = json["relationship"]
      @recruited                = json["recruited"]
      @avatar                   = json["avatar"]
      @nick_name                = json["nick_name"]
      @date_of_birth            = json["date_of_birth"]
      @display_name             = json["display_name"]
      @full_name                = json["full_name"]
      @location                 = json["location"]
      if ($debug > 1)
        print "UserInfo.new says: I made this! ";
	p self
     end

     def display_name           # Return either the Display name, if set, or else the nickname
        @display_name ? @display_name : @nick_name
     end

     def to_s
       self.display_name
     end
   end

   # values for @gender:
   GENDER_FEMALE = 0
   GENDER_MALE = 1

   # values for @has_profile_image:
   HASPROFILEIMAGE_NO = 0
   HASPROFILEIMAGE_YES = 1

   def has_profile_image?
     @has_profile_image == HASPROFILEIMAGE_YES
   end
end

class OwnProfile
   attr_reader :unread_count, :plurks_users, :plurks, :user_info, :alerts_count, :privacy, :friends_count, :fans_count

   def initialize(json)
      @unread_count             = json["unread_count"]
      # plurks_users is only present in the getOwnProfile information
      if json["plurks_users"]
        @plurks_users             = Hash.new
        json["plurks_users"].each { |id,obj| @plurks_users[id] = UserInfo.new(obj) }
      else
        @plurks_users = nil
      end
      @plurks                   = Array.new
      json["plurks"].each { |obj| @plurks << Plurk.new(obj) }
      @user_info                = UserInfo.new(json["user_info"])
      @alerts_count             = json["alerts_count"]
      # has_read_permission is not always present in a user_info, but it's true/false
      @has_read_permission      = json["has_read_permission"]
      @privacy                  = json["privacy"]
      @friends_count            = json["friends_count"]
      @fans_count               = json["fans_count"]
      if ($debug > 2)
        print "OwnProfile.new says: I made this! ";
	p self
     end
   end

   def has_read_permission?
     @has_read_permission
   end
end

class PublicProfile < OwnProfile

  def initialize(json)
    super                       # invoke the superclass method of the name name with the
                                # same parameters

    @are_friends                = json["are_friends"]
    @is_fan                     = json["is_fan"]
    @is_following               = json["is_following"]
    if ($debug > 2)
      print "PublicProfile.new says: I made this! ";
      p self
    end
  end

  def are_friends?
    @are_friends
  end

  def is_following?
    @is_following
  end

  def is_fan?
    @is_fan
  end
end

class PlurkBase
   attr_reader :plurk_id, :content_raw, :qualifier, :content, :lang, :user_id, :posted

   def initialize(json)
      @plurk_id                 = json["plurk_id"]
      @content_raw              = json["content_raw"]
      @qualifier                = json["qualifier"]
      @lang                     = json["lang"]
      # Can't work out if responses_seen is ever non-zero
      @responses_seen           = json["responses_seen"]
      @is_unread                = json["is_unread"]
      @user_id                  = json["user_id"]
      @posted                   = json["posted"]
      if ($debug > 2)
        print "PlurkBase.new says: I made this! ";
	p self
     end
   end

   # values for @no_comments:
   NOCOMMENTS_COMMENTS = 0
   NOCOMMENTS_DISABLED = 1
   NOCOMMENTS_FRIENDS = 2

   # values for @plurk_type:
   PLURKTYPE_PUBLIC = 0
   PLURKTYPE_PRIVATE = 1
   PLURKTYPE_PUBLIC_RESPONDED = 2
   PLURKTYPE_PRIVATE_RESPONDED = 3

   # values for @is_unread
   ISUNREAD_READ = 0
   ISUNREAD_UNREAD = 1
   ISUNREAD_MUTED = 2

   def is_unread?
      @is_unread == ISUNREAD_UNREAD
   end

   def is_muted?
      @is_unread == ISUNREAD_MUTED
   end

   def is_private?
      @limited_to
   end

   def is_favorite?
      @favorite                 # Plurk returns this as true or false, and it seems to work
   end

   def to_s
      str = self.qualifier.to_s + " " + self.content_raw
      str
   end
end

class Plurk < PlurkBase
   attr_reader :limited_to, :no_comments, :plurk_type, :owner_id, :responses_seen, :favorite
   attr_accessor :responses, :response_count, :friends # these are filled in by getResponses

   def initialize(json)
      super

      @limited_to               = json["limited_to"]
      @owner_id                 = json["owner_id"]
      @no_comments              = json["no_comments"]
      @content                  = json["content"]
      @plurk_type               = json["plurk_type"]
      @favorite                 = json["favorite"]
      @response_count           = json["response_count"]
      @friends                  = {}                        # expected to be filled in by getResponses
      @responses                = []                        # expected to be filled in by getResponses
      if ($debug > 2)
        print "Plurk.new says: I made this! ";
	p self
     end
   end

   # The to_s method augments the base class' method by invoking it with super.
   def to_s
      str = super

      str += " [#{self.responses_seen}/#{self.response_count}]" if self.responses_seen
      str += " [unread]" if self.is_unread?
      str += " [PP]" if self.is_private?
      str
   end
end

class Response < PlurkBase
   attr_reader :resp_id

   def initialize(json)
      super

      @resp_id                  = json["id"]
      if ($debug > 2)
        print "Response.new says: I made this! ";
	p self
     end
   end
end

###
### Alerts
###

class Alert
   attr_reader :type, :user, :posted
   def initialize(json)
      @type                     = json["type"]
      @posted                   = json["posted"]
      @user = UserInfo.new(case @type
	   when "friendship_request"
	      json["from_user"]
	   when "friendship_pending"
	      json["to_user"]
	   when "new_fan"
	      json["new_fan"]
	   when "friendship_accepted"
	      json["friend_info"]
	   when "new_friend"
	      json["new_friend"]
	 end
      )
   end

   def to_s
      self.user.to_s + ": " + self.type + " at " + self.posted
   end
end
