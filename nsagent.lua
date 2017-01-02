#!/usr/bin/env lua

-- flock -xn /tmp/ns-agent.lock -c "/usr/bin/lua <agent_path>"

local cjson = require "cjson"
local md5 = require "md5"
local http = require "socket.http"
local inspect = require "inspect"

local API_VERSION = "1.0"
local API_PACKAGE_CONFIG = 'http://localhost:8888/api/v1/package-config.json'
local SD_CARD_DIR = '/tmp'
local APK_CACHE_DIR = SD_CARD_DIR .. '/apk_cache'
local IPA_CACHE_DIR = SD_CARD_DIR .. '/ipa_cache'
local TPM_IPA_DIR = SD_CARD_DIR .. '/tpm_ipa'
local TPM_APK_DIR = SD_CARD_DIR .. '/tpm_apk'
local TPM_IPA_NAME = "tpm.ipa"
local TPM_APK_NAME = "tpm.apk"
local DELIMITER = "/"
local PLATFORM_IOS = "ios"
local PLATFORM_ANDROID = "android"


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


local function get_package_config()
    local response, status_code = http.request(API_PACKAGE_CONFIG)

    if status_code ~= 200 then
        error("Get package config failed.")
    end

    return cjson.decode(response)
end


local function get_cache_dir(platform)
    if platform == PLATFORM_ANDROID then
        return APK_CACHE_DIR
    elseif platform == PLATFORM_IOS then
        return IPA_CACHE_DIR
    else
        error(string.format("Invalid platform: %s", platform))
    end
end


-- 包都匹配返回true, 否则返回false
local function check_all_pkg(packages, platform)
    -- NOTE: 因为是move过去的, 所以认为一定成功, 不再校验md5
    local all_exist = true
    for i=1, #packages do
        local delimiter = ''
        local path = packages[i]["path"]
        if not startswith(path, "/") then
            delimiter = DELIMITER
        end
        path = get_cache_dir(platform) .. delimiter .. path
         -- print(path)
        if not is_file_exists(path) then
            all_exist = false
        end
    end
    return all_exist
end


local function get_tmp_pkg_name(platform)
    if platform == PLATFORM_ANDROID then
        return TPM_APK_DIR .. DELIMITER .. TPM_APK_NAME
    elseif platform == PLATFORM_IOS then
        return TPM_IPA_DIR .. DELIMITER .. TPM_IPA_NAME
    else
        error(string.format("Invalid platform: %s", platform))
    end
end


local function download_pkg(package, platform)
    local tmp_pkg_name = get_tmp_pkg_name(platform)

    local cmd = "rm -f " .. tmp_pkg_name
    os.execute(cmd)

    cmd = string.format("wget '%s' -O %s", package["url"], tmp_pkg_name)
    os.execute(cmd)

    local file_md5 = calc_md5sum(tmp_pkg_name)
    if file_md5 ~= package["md5sum"] then
        error(string.format("Invalid MD5: %s md5sum: %s", package["url"], file_md5))
    end
end


local function move_pkg_to_cache_dir(package, platform)
    local delimiter = ''
    local path = package["path"]
    if not startswith(path, "/") then
        delimiter = DELIMITER
    end
    path = get_cache_dir(platform) .. delimiter .. path

    local cmd = "mkdir -p " .. path
    os.execute(cmd)
    cmd = string.format("mv -f %s %s%s", get_tmp_pkg_name(platform), get_cache_dir(platform), package["path"])
    -- print(cmd)
    os.execute(cmd)
end


local function remove_cache_dir(platform)
    local cmd = string.format("rm -rf %s/*", get_cache_dir(platform))
    os.execute(cmd)
end

local function make_all_dir()
    local cmd = "mkdir -p " .. IPA_CACHE_DIR
    os.execute(cmd)
    cmd = "mkdir -p " .. TPM_IPA_DIR
    os.execute(cmd)
    cmd = "mkdir -p " .. APK_CACHE_DIR
    os.execute(cmd)
    cmd = "mkdir -p " .. TPM_APK_DIR
    os.execute(cmd)
end


local function update_pkg(package, platform)
    if not check_all_pkg(package, platform) then
        remove_cache_dir(platform)
        make_all_dir()

        for i=1, #package do
            local pkg = package[i]
            download_pkg(pkg, platform)
            move_pkg_to_cache_dir(pkg, platform)
        end
    end

    print(string.format("%s status: %s", platform, tostring(check_all_pkg(package, platform))))
end

local function run()
    make_all_dir()

    local config = get_package_config()

    if config["version"] ~= API_VERSION then
        error("API version does't match")
    end

    -- TODO: check schema

    update_pkg(config["iosPackages"], PLATFORM_IOS)
    update_pkg(config["androidPackages"], PLATFORM_ANDROID)
end


-----------------------------------

run()
