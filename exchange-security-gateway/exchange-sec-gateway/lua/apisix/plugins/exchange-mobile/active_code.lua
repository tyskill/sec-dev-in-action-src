---
--- Generated by EmmyLua(https://github.com/EmmyLua)
--- Created by hartnett.
--- DateTime: 2019/11/8 15:15
---


local ngx = require("ngx")
local string = require("string")
local math = require("math")
local uuid = require('resty.jit-uuid')

local redis = require("apisix.core.redis")
local core = require("apisix.core")

local fetch_local_conf = require("apisix.core.config_local").local_conf
local config = fetch_local_conf()

-- 生成激活码
local function generate_active_code(username, device_id)
    uuid.seed()
    math.randomseed(tostring(ngx.now()):reverse():sub(1, 7))
    local t = math.random()
    local code = ngx.md5(t .. uuid() .. username .. device_id .. ngx.now())
    local active_code = string.sub(code, 10, 18)
    return active_code
end

-- 判断某设备id的激活码是否生成过
local function exist_active_code_flag(username, device_id)
    local key = string.format("%s%s_%s", config["prefix"]["code_prefix"], username, device_id)
    local has = false
    local redis_cli = redis.new()
    local res = redis_cli:get(key)
    local code = ""
    if res ~= nil and res ~= "" and type(res) == "string" then
        code = res
    end

    if code ~= nil and code ~= "" then
        has = true
    end

    core.log.warn(string.format("key: %s, has: %s, code: %s, res: %s", key, has, code, res))

    return has, code
end

-- 删除激活码的标志
local function del_active_code_flag(username, device_id)
    local key = string.format("%s%s_%s", config["prefix"]["code_prefix"], username, device_id)
    local redis_cli = redis.new()
    redis_cli:del(key)
end

-- 获取激活码的内容
local function get_value_by_code(code)
    local key = string.format("%s%s", config["prefix"]["code_prefix"], code)
    local redis_cli = redis.new()

    local value = ""
    local res = redis_cli:get(key)
    if res ~= nil and type(res) == "string" then
        value = res
    end

    return value
end

-- 通过激活码，返回用户名与设备ID信息
local function get_code_value(code)
    local value = get_value_by_code(code)
    local username = ""
    local device_info = {}

    if value ~= nil and value ~= "" then
        local tmp = stringy.split(value, "_-_")

        if next(tmp) then
            username = tmp[1]
            local device_str = tmp[3]
            -- ngx.log(ngx.DEBUG, string.format("value: %s, username: %s, device_str: %s", value, username, device_str))
            device_info = core.json.decode(device_str)
        end
    end

    return username, device_info
end

-- 设置验证码的标识，判断是否生成过验证码，10小时后失效
local function set_active_code_flag(username, device_id, code)
    local key = string.format("%s%s_%s", config["prefix"]["code_prefix"], username, device_id)
    local redis_cli = redis.new()
    local err, res = redis_cli:set(key, code)
    core.log.warn(string.format("set_active_code_flag, key: %s, code:%s, err: %s, res: %s", key, code, err, res))
    redis_cli:expire(key, 60 * 60 * 10)
end


-- 设置验证码的值及超时时间
local function _set_active_code(code, username, device_str)
    local key = string.format("%s%s", config["prefix"]["code_prefix"], code)
    local value = string.format("%s-_-%s", username, device_str)
    local redis_cli = redis.new()
    local err, res = redis_cli:set(key, value)
    core.log.warn(string.format("key: %s, err: %s, res: %s, value: %s", key, err, res, value))
    redis_cli:expire(key, 3600 * 12)
end

-- 获取设备信息json中的device_id
local function get_deviceid_by_devicestr(device_str)
    local device_info = core.json.decode(device_str)
    local deviceid = device_info["deviceid"] or ""
    deviceid = string.lower(deviceid)
    return deviceid
end

-- 激活码使用后的有效期为30分钟
local function set_active_code_state(code, username, device_str)
    local key = string.format("%s%s", config["prefix"]["code_prefix"], code)
    local value = string.format("%s_-_%s", username, device_str)
    local redis_cli = redis.new()
    redis_cli:set(key, value)
    redis_cli:expire(key, 60 * 30)

    local deviceid = get_deviceid_by_devicestr(device_str)
    deviceid = string.lower(deviceid)
    sms.reset_sms_status(username, deviceid, phone)
end


-- 删除验证码
local function remove_code(code)
    local key = string.format("%s%s", config["prefix"]["code_prefix"], code)
    local redis_cli = redis.new()
    redis_cli:del(key)
end

-- 激活码保存到redis中，有效期为8小时，多次生成的话，只有最后一次的有效
local function set_active_code(username, device_id, device_str)
    local code = generate_active_code(username, device_id)
    -- 判断某设备id的激活码是否生成过
    local has, code1 = exist_active_code_flag(username, device_id)
    core.log.warn(string.format("has: %s, code: %s", has, code1))
    if not has then
        set_active_code_flag(username, device_id, code)
        _set_active_code(code, username, device_str)
    else
        -- 如果已生成过激活码，就用老激活码
        code = code1
        _set_active_code(code, username, device_str)
    end

    return code
end

-- 保存设备来源IP
local function set_device_srcip(deviceid, srcip)
    local key = config["prefix"]["device_name"]
    local redis_cli = redis.new()
    redis_cli:hmset(key, deviceid, srcip)
end

-- 返回某个设备ID的来源IP
local function get_device_srcip(deviceid)
    local srcip = ""
    local key = config["prefix"]["device_name"]
    local redis_cli = redis.new()
    local res = redis_cli:hmget(key, deviceid)
    if res ~= nil then
        if type(res[1]) == "string" then
            srcip = res[1]
        end
    end

    return srcip
end

local _M = {
    generate_active_code = generate_active_code,
    set_active_code = set_active_code,
    del_active_code_flag = del_active_code_flag,
    _set_active_code = _set_active_code,
    set_active_code_state = set_active_code_state,
    remove_code = remove_code,
    set_device_srcip = set_device_srcip,
    get_device_srcip = get_device_srcip,
}

return _M