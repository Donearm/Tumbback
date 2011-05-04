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
	io.write(string.format("Usage: %s tumblr_url\n", arg[0]))
	io.write("\nWhere tumblr_url is like http://myname.tumblr.com\n\n")
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


local start = 0
local num = 50 -- tumblr api limit
TUMBLRAPIURL = TUMBLRURL .. "/api/read"

local xmlout = http.request(TUMBLRAPIURL)
local totalposts = string.match(xmlout, "<posts start=\".-\" total=\"(.-)\">")

while start < tonumber(totalposts) do
	TUMBLRAPIURL = TUMBLRURL .. string.format("/api/read/?start=%s&num=%s", start, num)
	local xmlout = http.request(TUMBLRAPIURL)
	local startpost, endpost = posts_filename(start, num)
	local outfile = XMLOUTDIR .. "/posts_" .. startpost .. "_" .. endpost
	put(outfile, xmlout)
	start = start + num
end

-- xml parsing
for files in lfs.dir(XMLOUTDIR) do
	if files ~= "." and file ~= ".." then
		local f = XMLOUTDIR .. '/' .. files
		attr = lfs.attributes(f)
		if attr.mode ~= "directory" then
			for line in io.lines(f) do
				for m in line:gmatch('<photo[-]url%smax[-]width="1?[25][80]0">(.-)</photo[-]url>') do
					local content = http.request(m)
					-- extract filename
					local n = string.gsub(m, '.*/', '')
					-- check for filenames with an extension; if not, add it
					local ext = string.match(n, '.*([.].+)$')
					if not ext then
						outfile = IMGOUTDIR .. n .. '.jpg'
					else
						outfile = IMGOUTDIR .. n
					end
					put(outfile, content)
				end
				-- currently audio and video backup is basically worthless, 
				-- still have to find a way to extract and download the real 
				-- content
				for v in line:gmatch('<video[-]source.*src="(.-)".-</video[-]source>') do
					local content = http.request(v)
					-- extract filename
					local n = string.gsub(v, '.*/', '')
					outfile = VIDOUTDIR .. n
					put(outfile, content)
				end
				for s in line:gmatch('<video[-]player.*src="(.-)".-</video[-]player>') do
					local content = http.request(s)
					-- extract filename
					local n = string.gsub(s, '.*/', '')
					outfile = VIDOUTDIR .. n
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

