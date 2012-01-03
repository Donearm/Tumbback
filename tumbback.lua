#!/usr/bin/env lua

--- Copyright 2011-2012, Gianluca Fiore © <forod.g@gmail.com>
-- @author Gianluca Fiore
--
-- You may redistribute this software and/or modify it under either
-- the terms of the GNU Lesser General Public License version 3
-- (http://www.gnu.org/licenses/lgpl.txt), or (at your option) any later 
-- version.
-- Redistribution and use in source and binary forms, with or without 
-- modification, are permitted provided that the following conditions 
-- are met:
-- 1. Redistributions of source code must retain the above copyright
-- notice, this list of conditions and the following disclaimer.
-- 2. Redistributions in binary form must reproduce the above
-- copyright notice, this list of conditions and the following
-- disclaimer in the documentation and/or other materials provided
-- with the distribution.
-- 3. The name of the author may not be used to endorse or promote
-- products derived from this software without specific prior
-- written permission.
--
-- THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS
-- OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
-- WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
-- ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
-- DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
-- DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
-- GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
-- INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
-- WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
-- NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
-- SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--

-- roughly based on http://codequaff.us/post/38721200/spumblr-lua

http = require("socket.http")
lfs = require("lfs")

--- Write data to a file.
-- @param f The filename.
-- @param c The data.
function put(f, c)
	if c ~= nil then
		-- write only if we have something to
		local fw = io.open(f, "w+")
		fw:write(c)
		fw:close()
	end
end

--- Check if a directory exits and if it doesn't, create it.
-- @param d The directory to be created.
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

--- Check that we got the correct command line argument.
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


--- Download a video among the supported hostings.
-- @param arg A table with 2 strings, "host" and "string".
function download_video(arg)
	-- both arg.host and arg.string must be strings
	if type(arg.host) ~= "string" or type(arg.string) ~= "string" then
		error("either host or url string are missing")
	else
		if arg.host == 'vimeo' then
			local data = http.request(arg.string)
			for m in data:gmatch('"video":{"id":([0-9]+)') do
				-- download the xml of the urls' video
				local xml_vimeo = http.request(VIMEOBASEURL .. 'load/clip:' .. m)
				-- extract signature and its expiry number
				local signature = string.match(xml_vimeo, '<request_signature>(.-)</request_signature>')
				local expires = string.match(xml_vimeo, '<request_signature_expires>(.-)</request_signature_expires>')

				-- make up the video url and download it locally
				local video = http.request(VIMEOBASEURL .. 'play/clip:' .. m .. '/' .. signature .. '/' .. expires .. '/?q=HD')
				put(VIDOUTDIR .. m .. '.mp4', video)
			end
		elseif arg.host == 'youtube' then
			-- check whether is an embedded video or not
			-- Extract video id
			if arg.embed then
				id = string.match(arg.string, '.*/(.-)$')
			else
				id = string.match(arg.string, '.*/(.-)[?&]')
			end
			-- ask for info to get the token and title
			local info_content = http.request('http://www.youtube.com/get_video_info?video_id=' .. id)
--			local token = string.match(info_content, 'token=(.-)&')
			local title = string.match(info_content, 'title=(.-)&')
			-- request the video itself
			-- get the html page of the video to extract the url and its 
			-- parameters from youtube's cache
			local html_page = http.request('http://www.youtube.com/watch?v=' .. id)
			-- multiple substitution to make the url valid for a http 
			-- request. This is ugly, I know.
			local params = string.match(html_page, 'img%.src%s=%s"(.-)";')
			local params = string.gsub(params, '\\u0026', '&')
			local params = string.gsub(params, '\\', '')
			local params = string.gsub(params, 'generate_[0-9]+', 'videoplayback')

			-- add mp4 to filename and download the video
			local outfile = VIDOUTDIR .. title .. '.mp4'
			local video_content = http.request(params)
			put(outfile, video_content)
		elseif arg.host == 'tumblr' then
			local n = string.gsub(arg.string, '.*/', '')
			local outfile = VIDOUTDIR .. n .. '.mp4'
			
			local content = http.request(arg.string)
			put(outfile, content)
		end
	end
end

--- Download an image from Tumblr.
-- @param arg A string containing the uri of the image.
function download_image(arg)
	if type(arg.string) ~= "string" then
		error("no string given")
	else
 		local content = http.request(arg.string)
		-- extract filename
		local n = string.gsub(arg.string, '.*/', '')
		-- check for filenames with an extension, otherwise add it
		local ext = string.match(n, '.*([.].+)$')
		if not ext then
			outfile = IMGOUTDIR .. n .. '.jpg'
		else
			outfile = IMGOUTDIR .. n
		end
		-- catch 500/400px images (named tumblr_.*o1_[45]00)
		local filename, px500 = string.match(outfile, 'images/(.*)(o1_r?1?_?[45]00)[.]')
		if px500 then
			-- if it's a 500/400px image generate the filename of the, 
			-- hypothetical full sized image and check if it is already 
			-- been downloaded. Download the current image only if there 
			-- isn't one with the same filename but without the 
			-- o1_[45]00 part
			local full_file = IMGOUTDIR .. filename .. ext
			local file_exists = io.open(full_file)
			if file_exists then
				io.close(file_exists)
				return
			else
				put(outfile, content)
			end
		end
 		put(outfile, content)
	end
end

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

-- if supplying a '-p' argument as the third, then only download the 
-- posts and not any media.
if arg[3] == '-p' then
	os.exit()
end

--- Xml parsing of the Tumblr page.
for files in lfs.dir(XMLOUTDIR) do
	if files ~= "." and file ~= ".." then
		local f = XMLOUTDIR .. '/' .. files
		attr = lfs.attributes(f)
		if attr.mode ~= "directory" then
			for line in io.lines(f) do
				for m in line:gmatch('<photo[-]url%smax[-]width="1?[25][80]0">(.-)</photo[-]url>') do
					local d = download_image{ string=m }
				end
				for v in line:gmatch('<video[-]source.*src="(.-)".-</video[-]source>') do
					if v:match('youtube%.com/v/') then
						local d = download_video{ host='youtube', string=v }
					elseif v:match('youtube%.com/embed/') then
						local d = download_video{ host='youtube', string=v, embed = true }
					else
						local d = download_video{ host='vimeo', string=v }
					end
				end
				for s in line:gmatch('<video[-]player.*src="(.-)".-</video[-]player>') do
					if s:match('youtube%.com/v/') then
						local d = download_video{ host='youtube', string=s }
					elseif s:match('youtube%.com/embed/') then
						local d = download_video{ host='youtube', string=s }
					else
						local d = download_video{ host='vimeo', string=s }
					end
				end
				for t in line:gmatch("'(.-/video_file/[0-9]+/tumblr_.-)'") do
					local d = download_video{ host='tumblr', string=t }
				end
				for a in line:gmatch('<audio[-]player>.-src="(.-)"') do
					local audio_url = string.match(a, '.*audio_file=(.-)&amp;')
					local plead = '?plead=please-dont-download-this-or-our-lawyers-wont-let-us-host-audio'
					local content = http.request(audio_url .. plead)
					-- extract and unique string as filename
					local n = string.gsub(a, '.*audio_file/([0-9]+)/.*', "%1")
					outfile = AUDOUTDIR .. n .. '.mp3'
					put(outfile, content)
				end
			end
		end
	end
end
