#!/usr/bin/env lua

-- roughly based on http://codequaff.us/post/38721200/spumblr-lua

http = require("socket.http")
lfs = require("lfs")

function put(f, c)
	if c ~= nil then
		-- write only if we have something to
		local fw = io.open(f, "w+")
		fw:write(c)
		fw:close()
	end
end

function chkmk_dir(d)
	local p = io.open(d)
	if not p then
		lfs.mkdir(d)
	else
		p:close()
	end
end

function posts_filename(s, e)
	-- return starting and ending number of posts to read with enough 
	-- prefixing zeros to nicely offset. Limit is 1Mil posts
	if s < 10 then
		startpost = "00000" .. (s + 1)
		endpost = "0000" .. (s + e)
	elseif s >= 10 and s < 100 then
		startpost = "0000" .. (s + 1)
		endpost = "000" .. (s + e)
	elseif s >= 100 and s < 1000 then
		startpost = "000" .. (s + 1)
		endpost = "000" .. (s + e)
	elseif s >= 1000 and s < 10000 then
		startpost = "00" .. (s + 1)
		endpost = "00" .. (s + e)
	elseif s >= 10000 and s < 100000 then
		startpost = "0" .. (s + 1)
		endpost = "0" .. (s + e)
	else
		startpost = (s + 1)
		endpost = (s + e)
	end
	return startpost, endpost
end


TUMBLRURL = arg[1] or nil
if not TUMBLRURL or not string.match(arg[1], "^http://") then
	io.write(string.format("Usage: %s tumblr_url [path]\n", arg[0]))
	io.write("\nWhere tumblr_url is like http://myname.tumblr.com\n")
	io.write("and path is where to save the backup\n")
	os.exit()
end

SITETITLE = string.gsub(TUMBLRURL, "^http://", '')
BASEDIR = arg[2] or '/mnt/documents/stuff/blogs/backup/'
XMLOUTDIR = BASEDIR .. SITETITLE
IMGOUTDIR = XMLOUTDIR .. '/images/'
AUDOUTDIR = XMLOUTDIR .. '/audio/'
VIDOUTDIR = XMLOUTDIR .. '/videos/'

-- make base and media directories. Fucking ugly, I know
chkmk_dir(XMLOUTDIR)
chkmk_dir(IMGOUTDIR)
chkmk_dir(AUDOUTDIR)
chkmk_dir(VIDOUTDIR)

-- Video hosting base urls
VIMEOBASEURL = 'http://vimeo.com/moogaloop/'


function download_video(h, f)
	if h == 'vimeo' then
			for m in f:gmatch('"video":{"id":([0-9]+)') do
				-- download the xml of the urls' video
				local xml_vimeo = http.request(VIMEOBASEURL .. 'load/clip:' .. m)
				-- extract signature and its expiry number
				local signature = string.match(xml_vimeo, '<request_signature>(.-)</request_signature>')
				local expires = string.match(xml_vimeo, '<request_signature_expires>(.-)</request_signature_expires>')

				-- make up the video url and download it locally
				local video = http.request(VIMEOBASEURL .. 'play/clip:' .. m .. '/' .. signature .. '/' .. expires .. '/?q=HD')
				put(VIDOUTDIR .. m .. '.mp4', video)
			end
	end
end

local start = 0
local num = 50 -- tumblr api limit
TUMBLRAPIURL = TUMBLRURL .. "/api/read"

local xmlout = http.request(TUMBLRAPIURL)
local totalposts = string.match(xmlout, "<posts start=\".-\" total=\"(.-)\">")

--while start < tonumber(totalposts) do
--	TUMBLRAPIURL = TUMBLRURL .. string.format("/api/read/?start=%s&num=%s", start, num)
--	local xmlout = http.request(TUMBLRAPIURL)
--	local startpost, endpost = posts_filename(start, num)
--	local outfile = XMLOUTDIR .. "/posts_" .. startpost .. "_" .. endpost
--	put(outfile, xmlout)
--	start = start + num
--end

-- xml parsing
for files in lfs.dir(XMLOUTDIR) do
	if files ~= "." and file ~= ".." then
		local f = XMLOUTDIR .. '/' .. files
		attr = lfs.attributes(f)
		if attr.mode ~= "directory" then
			for line in io.lines(f) do
--				for m in line:gmatch('<photo[-]url%smax[-]width="1?[25][80]0">(.-)</photo[-]url>') do
--					local content = http.request(m)
--					-- extract filename
--					local n = string.gsub(m, '.*/', '')
--					-- check for filenames with an extension; if not, add it
--					local ext = string.match(n, '.*([.].+)$')
--					if not ext then
--						outfile = IMGOUTDIR .. n .. '.jpg'
--					else
--						outfile = IMGOUTDIR .. n
--					end
--					put(outfile, content)
--				end
				-- currently audio and video backup is limited to vimeo and tumblr videos
				for v in line:gmatch('<video[-]source.*src="(.-)".-</video[-]source>') do
					if v:match('youtube%.com/v/') then
						-- extract id of video
						local id = string.match(v, '.*/(.-)[?&]')
						-- ask for info to get the token
						local info_content = http.request('http://www.youtube.com/get_video_info?video_id=' .. id)
						local token = string.match(info_content, 'token=(.-)&')
						local title = string.match(info_content, 'title=(.-)&')
--						-- request the video itself
						local video_content = http.request('http://www.youtube.com/get_video?video_id=' .. id .. '&t=' .. token .. '&asv=2')
						put(VIDOUTDIR .. title, video_content)
					elseif v:match('youtube%.com/embed/') then
						local id = string.match(v, '.*/(.-)$')
						-- ask for info to get the token
						local info_content = http.request('http://www.youtube.com/get_video_info?video_id=' .. id)
						local token = string.match(info_content, 'token=(.-)&')
						local title = string.match(info_content, 'title=(.-)&')
--						-- request the video itself
						local video_content = http.request('http://www.youtube.com/get_video?video_id=' .. id .. '&t=' .. token .. '&asv=2')
						put(VIDOUTDIR .. title, video_content)
					else
--						print("vimeo video")
						local content = http.request(v)
						download_video('vimeo', content)
					end
				end
				for s in line:gmatch('<video[-]player.*src="(.-)".-</video[-]player>') do
					if s:match('youtube%.com/v/') then
						-- extract id of video
						local id = string.match(s, '.*/(.-)[?&]')
						-- ask for info to get the token
						local info_content = http.request('http://www.youtube.com/get_video_info?video_id=' .. id)
						local token = string.match(info_content, 'token=(.-)&')
						local title = string.match(info_content, 'title=(.-)&')
--						-- request the video itself
						local video_content = http.request('http://www.youtube.com/get_video?video_id=' .. id .. '&t=' .. token .. '&asv=2')
						put(VIDOUTDIR .. title, video_content)
					elseif s:match('youtube%.com/embed/') then
						local id = string.match(s, '.*/(.-)$')
						-- ask for info to get the token
						local info_content = http.request('http://www.youtube.com/get_video_info?video_id=' .. id)
						local token = string.match(info_content, 'token=(.-)&')
						local title = string.match(info_content, 'title=(.-)&')
--						-- request the video itself
						local video_content = http.request('http://www.youtube.com/get_video?video_id=' .. id .. '&t=' .. token .. '&asv=2')
						put(VIDOUTDIR .. title, video_content)
					else
--						print("vimeo video")
						local content = http.request(s)
						download_video('vimeo', content)
					end
				end
				for t in line:gmatch("'(.-/video_file/[0-9]+/tumblr_.-)'") do
					-- tumblr hosted videos don't need to be sent to 
					-- download_video
					--
					-- extract filename
					local n = string.gsub(t, '.*/', '')
					local outfile = VIDOUTDIR .. n .. '.mp4'
					
					local content = http.request(t)
					put(outfile, content)
				end
				for a in line:gmatch('<audio[-]player>.-src="(.-)"') do
					local content = http.request(a)
					-- extract and unique string as filename
					local n = string.gsub(a, '.*audio_file/([0-9]+)/.*', "%1")
					outfile = AUDOUTDIR .. n .. '.swf'
					put(outfile, content)
				end
			end
		end
	end
end

