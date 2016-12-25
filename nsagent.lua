#!/usr/bin/env lua

-- flock -xn /tmp/ns-agent.lock -c "/usr/bin/lua <agent_path>"

local cjson = require "cjson"
local md5 = require "md5"
local http = require "socket.http"
local inspect = require "inspect"

local API_VERSION = "1.0"
local API_PACKAGE_CONFIG = 'http://localhost:8888/api/v1/package-config.json'
local LOCK_FILE = '/tmp/ns-agent.lock'
local SD_CARD_DIR = '/tmp'
local PKG_CACHE_DIR = SD_CARD_DIR .. '/ipa_cache'
local PKG_META_DIR = SD_CARD_DIR .. '/ipa_meta'
local TPM_PKG_DIR = SD_CARD_DIR .. '/tpm_ipa'
local TPM_PKG_NAME = "tpm.ipa"
local DELIMITER = "/"

local function catch(what)
	return what[1]
end

local function try(what)
	status, result = pcall(what[1])
	if not status then
		what[2](result)
	end
	return result
end

local function calc_md5sum(filename)
	local file, err = io.open(filename, "rb")
	if err then
		error("Can't open file: " .. filename .. " Reason: " .. err)
	end

	local content = file:read("*a")
	file:close()

	return md5.sumhexa(content)
end


function is_file_exists(name)
	local f = io.open(name, "r")
	if f ~= nil then
	    io.close(f)
	    return true
    else
        return false
	end
end


local function startswith(str, substr)  
	if str == nil or substr == nil then  
		return nil, "the string or the sub-stirng parameter is nil"  
	end  
	if string.find(str, substr) ~= 1 then  
		return false  
	else  
		return true  
	end  
end


local function try_lock_file()
    -- 使用flock
    return true
end


local function unlock_file()
	-- 使用flock
end


local function get_package_config()
    local response, status_code = http.request(API_PACKAGE_CONFIG)

    if status_code ~= 200 then
        error("Get package config failed.")
    end

    return cjson.decode(response)
end


-- 包都匹配返回true, 否则返回false
local function check_all_pkg(packages)
    -- NOTE: 因为是move过去的, 所以认为一定成功, 不再校验md5
    local all_exist = true
    for i=1, #packages do
        local delimiter = ''
		local path = packages[i]["path"]
        if not startswith(path, "/") then
			delimiter = DELIMITER
		end
        path = PKG_CACHE_DIR .. delimiter .. path
     	-- print(path)
		if not is_file_exists(path) then
			all_exist = false
		end
    end
	return all_exist
end


local function get_tpm_pkg_name()
	return TPM_PKG_DIR .. DELIMITER .. TPM_PKG_NAME
end


local function download_pkg(package)
	local tmp_pkg_name = get_tpm_pkg_name()

	local cmd = "rm -f " .. tmp_pkg_name
	os.execute(cmd)

	cmd = string.format("wget '%s' -O %s", package["url"], tmp_pkg_name)
	os.execute(cmd)

	local file_md5 = calc_md5sum(tmp_pkg_name)
	if file_md5 ~= package["md5sum"] then
		error(string.format("Invalid MD5: %s md5sum: %s", package["url"], file_md5))
	end
end


local function move_pkg_to_cache_dir(package)
	local path = PKG_CACHE_DIR .. string.match(package["path"], "(.+)/[^/]*%.%w+$")
	local cmd = "mkdir -p " .. path
	os.execute(cmd)
	cmd = string.format("mv -f %s %s%s", get_tpm_pkg_name(), PKG_CACHE_DIR, package["path"])
	print(cmd)
	os.execute(cmd)
end


local function remove_pkg_cache_dir()
	local cmd = "rm -rf " .. PKG_CACHE_DIR .. "/*"
	print(cmd)
	os.execute(cmd)
end


local function make_all_dir()
	local cmd = "mkdir -p " .. PKG_CACHE_DIR
	os.execute(cmd)
	cmd = "mkdir -p " .. TPM_PKG_DIR
	os.execute(cmd)
end

-----------------------------------

if not try_lock_file() then
    os.exit()
end

try {
	function()
		make_all_dir()

		local config = get_package_config()

		if config["version"] ~= API_VERSION then
	    	error("API version does't match")
		end

		-- TODO: check schema
		if not check_all_pkg(config["packages"]) then
			remove_pkg_cache_dir()
			make_all_dir()

			for i=1, #config["packages"] do
	    		local pkg = config["packages"][i]
				download_pkg(pkg)
				move_pkg_to_cache_dir(pkg)
			end
		end

		print("status: " .. tostring(check_all_pkg(config["packages"])))

		unlock_file()
	end,
	catch {
		function(err)
			print('caught error: ' .. err)
			unlock_file()
		end
	}
}
