require 'redditkit'
require 'httparty'
require 'oj'
require 'nokogiri'
require 'redis'

###############
# => Methods! #
###############

def linkExtract(raw_reddit_html)
	raw_reddit_html = raw_reddit_html.to_s
	return [] if raw_reddit_html.length < 2
	html = Nokogiri::HTML.parse(CGI.unescapeHTML(raw_reddit_html))
	html.css('a').map { |link| link['href'] }
end

def ytLinkExtract(links)
	# Only return links which end in .gif and do not contain gfycat.com
	links.select {|link| link.downcase.include?('://youtu.be') or link.downcase.include?('://youtube.com') and link.downcase.include?('t=')}
end

def get_time(link, link_id)
	link = link.split("t=")[1]
	if link.include?('h') || link.include?('m')
		 post_comment(link.gsub('s', ' seconds').gsub('m', ' minutes ').gsub('h', ' hours '))
	else link.include?('s')
		if link.to_i > 30
			 post_comment(link.gsub('s', ' seconds'), link_id)
		end
	end
end

def valid_json?(json)
  begin
    Oj.load(json)
    return true
  rescue Exception => e
    return false
  end
end

def post_comment(time, link_id)
	comment = <<COMMENT
OP says you should skip to #{time}.

Why?
People with some mobile Web Browsers and some Reddit Apps can't skip to the time set in the url automatically.

Hence, they have to do it manually. This bot is there to help them :)

^Comment ^will ^be ^deleted ^on ^a ^comment ^score ^of ^-1 ^or ^less.
COMMENT
	puts comment
	@bot.commentlink_id, comment)
	$redis.set(link_id, "true")
end

def delete_comment
	comments = @bot.my_content

	comments.each do |comment|
		if comment.score < -1
			@bot.delete(comment)
			puts "Deleted a comment."
		end
	end
end
###############
# => Config!  #
###############

loop = 1 #Set to 1 to prevent exit
@limit = 1000 #Number of results to return from search
@links = [] #An Array to store found links in memory
subs_link = 'videos'
username = ENV["Reddit_Username"] #Reddit U-name
password = ENV["Reddit_Password"] #Reddit P-word
@bot = RedditKit::Client.new username, password
$redis = Redis.new()
counter = 0 #Count number of requests made to Reddit since run
found = 0 # Count number of links found since run

while loop == 1

		#Fetching Latest Comments
		comments = HTTParty.get("http://reddit.com/r/#{subs_link}/comments.json?limit=#{@limit}")
		#Making sure the it's the correct response
		if valid_json?(comments.body)
			comments = Oj.load(comments.body)['data']['children']
			comments.each do |comment|
				comment = comment['data']
				links = ytLinkExtract(linkExtract(comment['body_html']))
				@links << { :links => links, :id => comment['name'], :post_link_id => comment['link_id'] } unless links.empty?
			end
			counter = counter + 1
			puts "Finshied Searching: #{counter} requests"
			sleep(2)
		end


		#Fetches latest posts
		posts = HTTParty.get("http://reddit.com/r/#{subs_link}/new.json?limit=#{@limit}")
		#Checks the response
		if valid_json?(posts.body)
			posts = Oj.load(posts.body)['data']['children']
				posts.each do |post|
					post = post['data']
					links = []

					if post['is_self']
						links.concat(ytLinkExtract(linkExtract(post['selftext_html'])))
					else
						links.concat(ytLinkExtract([post['url']]))
					end

					@links << { :links => links, :id => post['name'] } unless links.empty?
				end
			counter = counter + 1
			puts "Finshied Searching: #{counter} requests"
			sleep(2)
		end

	found =  found + @links.size
	puts "I found: #{found} links"
	puts @links
	#Checks we have links
	if @links.size > 0
			@links.each do |link|
				#Checking if we have already replied to the link once
				if $redis.get(link[:id]) == nil
						get_time(link[:links][0], link[:id])
				end
			end
			delete_comment
		sleep(2)
	end
end