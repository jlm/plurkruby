require 'rubygems'
require 'plurkruby'
require 'highline/import'

def get_password(prompt="Enter password: ")
   ask(prompt) {|q| q.echo = false}
end

###
### Main program
###

# apikey.rb contains a single line like $api_key = "your API key goes here"
load 'apikey.rb'

#
# Process command line options
#
require "getoptlong"
# require "rdoc/usage"
opts = GetoptLong.new(
  [ '--login',      '-l', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--username',   '-u', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--password',         GetoptLong::REQUIRED_ARGUMENT ],
  [ '--testuser',   '-t', GetoptLong::NO_ARGUMENT ],
  [ '--nodata',           GetoptLong::NO_ARGUMENT ],
  [ '--printplurks',      GetoptLong::NO_ARGUMENT ],
  [ '--outfile',    '-o', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--plurk_id',         GetoptLong::REQUIRED_ARGUMENT ],
  [ '--addplurk',   '-a', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--addresponse',      GetoptLong::REQUIRED_ARGUMENT ],
  [ '--qual',       '-q', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--delresponse',      GetoptLong::REQUIRED_ARGUMENT ],
  [ '--private',    '-p', GetoptLong::NO_ARGUMENT ],
  [ '--delete',     '-r', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--alerthistory',     GetoptLong::NO_ARGUMENT ],
  [ '--not',        '-n', GetoptLong::NO_ARGUMENT ],
  [ '--logout',           GetoptLong::NO_ARGUMENT ],
  [ '--printuri',   '-v', GetoptLong::NO_ARGUMENT ],
  [ '--debug',      '-d', GetoptLong::NO_ARGUMENT ]
)

do_login = nil
loginname = nil
username = nil
password = nil
infilename = nil
outfilename = nil
qualifier = nil
addplurk = nil
addresponse = nil
plurk_id = nil
delresponse = nil
private = nil
deleteplurk = nil
alerthistory = nil
nodata = nil
printplurks = nil
logout = nil
$bluffing = nil
$debug = 0
$printuri = nil
opts.each do |opt, arg|
  case opt
    when '--printuri'
      $printuri = true
    when '--debug'
      $debug = $debug + 1
    when '--not'
      $bluffing = true
    when '--login'
      loginname = arg.to_s
      do_login = true
    when '--password'
      password = arg.to_s
    when '--testuser'
      loginname = "testUserName"
      password = "testPassword"
    when '--nodata'
      nodata = true
    when '--printplurks'
      printplurks = true
    when '--username'
      username = arg.to_s
    when '--private'
      private = true
    when '--delete'
      deleteplurk = arg.to_s
    when '--alerthistory'
      alerthistory = true
    when '--addplurk'
      addplurk = arg.to_s
    when '--addresponse'
      addresponse = arg.to_s
    when '--plurk_id'
      plurk_id = arg.to_s
    when '--qual'
      qualifier = arg.to_s
    when '--delresponse'
      delresponse = arg.to_s
    when '--outfile'
      outfilename = arg.to_s
    when '--logout'
      logout = true
  end
end


if do_login and loginname and not password
  password = get_password("Enter password for #{loginname}: ")
end

puts "Debug level is " + $debug.to_s if $debug > 0

###
### Open a tracefile if required
###
logfile = outfilename ? File.new(outfilename, 'w') : nil

###
### Initialise the API
###
plurk = PlurkApi.new($api_key, logfile)           # logfile can be omitted if not required

###
### Login and retrieve some basic information
###
if do_login
  puts "Logging in as #{loginname}"
  profile = plurk.login(loginname, password, nodata)
  puts "#{loginname}'s karma: #{profile.user_info.karma.to_s}"
  plurk.getUnreadCount
  print "#{loginname}'s unread counts: "
  print "All: " + plurk.unread_all.to_s
  print " Mine: " + plurk.unread_my.to_s
  print " Private: " + plurk.unread_private.to_s
  print " Responded: " + plurk.unread_responded.to_s
  puts
  puts "Active alerts:"
  plurk.alertsGetActive.each { |alert|
    puts "  #{alert.user.to_s}: #{alert.type} at #{alert.posted}"
  if alerthistory
    puts "Alert history:"
    plurk.alertsGetHistory.each { |alert|
      puts "  " + alert.to_s
    }
  end
  }
  nblocks, blocks = plurk.getBlocks
  if nblocks.to_i > 0
    puts "Blocked users:"
    blocks.each { |user|
      puts "  #{user.to_s}"
    }
  end
end

if username
  puts "Retrieving public profile of #{username}"
  profile = plurk.getPublicProfile(username)
  print "User " + profile.user_info.nick_name + " has " + profile.friends_count.to_s + " friends.\n"
  if loginname
    puts "#{loginname} is " + (profile.are_friends? ? '' : 'not ') + "friends with #{username}"
    puts "#{loginname} is " + (profile.is_fan? ? '' : 'not ') + "a fan of #{username}"
    puts "#{loginname} is " + (profile.is_following? ? '' : 'not ') + "following #{username}"
  end
end

###
### Print a few plurks
###
pid = nil
if profile and printplurks
  profile.plurks.each { |plk|
    if profile.plurks_users
      user = profile.plurks_users[plk.owner_id.to_s].nick_name 
    else
      user = plk.owner_id.to_s
    end
    pid = plk.plurk_id
    print user + " " + plk.to_s
    print "\n"
  }
end

###
### Get info on a specific plurk
###
pid = plurk_id.to_s if plurk_id
if pid
   plk, user = plurk.getPlurk(pid)
   puts "#{user.nick_name} #{plk.to_s}"
   plurk.getResponses(plk).responses.each { |response| puts "    " + plk.friends[response.user_id.to_s].display_name + " " + response.to_s }
end

###
### Add a response to a specified plurk
###
if addresponse
   qualifier = ':' if ! qualifier
   puts "Response " + plurk.responseAdd(plk, addresponse, qualifier).resp_id.to_s + " added"
end

###
### Delete a response from a specified plurk
###
if delresponse
   plurk.responseDelete(delresponse, plk)
end

###
### Add a new plurk, optionally making it private.
###
if addplurk
   $pretending = true if $bluffing   # This is a mechanism to avoid actually submitting the plurk
   qualifier = ':' if ! qualifier
   if private
      # Limit this plurk to just my own user-id
      limit = [ profile.user_info.id ]
   else
      limit = nil
   end
   if true
      newplk = plurk.plurkAdd(addplurk, qualifier, limit)
      puts "Plurked with id: #{newplk.plurk_id}"
   end
end

###
### Delete a plurk by identifier
###
if deleteplurk
   plurk.plurkDelete(deleteplurk)
end

###
### Log out
###
if logout
   plurk.logout
end
