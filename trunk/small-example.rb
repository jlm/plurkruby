require 'rubygems'
require 'plurkruby'

# This is a minimal example of how to use Plurkruby. It retrieves a user's unread counts,
# makes a plurk and a plurk response.

plurk = PlurkApi.new("your-api-key")

loginname = "plurkusername"
password = "plurkpassword"

profile = plurk.login(loginname, password)
puts "#{loginname}'s karma: #{profile.user_info.karma.to_s}"
plurk.getUnreadCount
print "#{loginname}'s unread counts: "
print "All: " + plurk.unread_all.to_s
print " Mine: " + plurk.unread_my.to_s
print " Private: " + plurk.unread_private.to_s
print " Responded: " + plurk.unread_responded.to_s
puts

### Add a new plurk
newplk = plurk.plurkAdd("testing the plurkruby Plurk API", "is")
puts "Plurked with id: #{newplk.plurk_id}"

### Add a response to a specified plurk
response = plurk.responseAdd(newplk, "responding to that plurk!", "likes")
puts "Responded with id: #{response.resp_id.to_s}"
