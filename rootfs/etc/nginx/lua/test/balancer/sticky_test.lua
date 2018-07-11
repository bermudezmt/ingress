package.path = "./rootfs/etc/nginx/lua/?.lua;./rootfs/etc/nginx/lua/test/mocks/?.lua;" .. package.path

local resty_chash = require("resty.chash")
local sticky = require("balancer.sticky")
local util = require("util")

local _ngx = {
    log = function(stream, msg) end,
    var = {},
}

_G.ngx = _ngx

local function get_test_backend()
    return {
        name = "access-router-production-web-80",
        endpoints = {
        { address = "10.184.7.40", port = "8080", maxFails = 0, failTimeout = 0 },
        },
        sessionAffinityConfig = { name = "cookie", cookieSessionAffinity = { name = "test_name", hash = "sha1" } },
    }
end

describe("Sticky", function()
    local test_backend = get_test_backend()
    local test_backend_endpoint= test_backend.endpoints[1].address .. ":" .. test_backend.endpoints[1].port

    describe("new(backend)", function()
        context("when backend specifies cookie name", function()
            it("should return an instance containing the corresponding cookie name", function()
                local sticky_balancer_instance = sticky:new(test_backend)
                local test_backend_cookie_name = test_backend.sessionAffinityConfig.cookieSessionAffinity.name
                assert.equal(sticky_balancer_instance.cookie_name, test_backend_cookie_name)
            end)
        end)

        context("when backend does not specify cookie name", function()
            it("should return an instance with 'route' as cookie name", function()
                local temp_backend = util.deepcopy(test_backend)
                temp_backend.sessionAffinityConfig.cookieSessionAffinity.name = nil
                local sticky_balancer_instance = sticky:new(temp_backend)
                local default_cookie_name = "route"
                assert.equal(sticky_balancer_instance.cookie_name, default_cookie_name)
            end)
        end)
        
        context("when backend specifies hash function", function()
            it("should return an instance with the corresponding hash implementation", function()
                local sticky_balancer_instance = sticky:new(test_backend)
                local test_backend_hash_fn = test_backend.sessionAffinityConfig.cookieSessionAffinity.hash
                local test_backend_hash_implementation = util[test_backend_hash_fn .. "_digest"]
                assert.equal(sticky_balancer_instance.digest_func, test_backend_hash_implementation)
            end)
        end)

        context("when backend does not specify hash function", function()
            it("should return an instance with the default implementation (md5)", function()
                local temp_backend = util.deepcopy(test_backend)
                temp_backend.sessionAffinityConfig.cookieSessionAffinity.hash = nil
                local sticky_balancer_instance = sticky:new(temp_backend)
                local default_hash_fn = "md5"
                local default_hash_implementation = util[default_hash_fn .. "_digest"]
                assert.equal(sticky_balancer_instance.digest_func, default_hash_implementation)
            end)
        end)
    end)

    describe("balance()", function()
        setup(function()
            util.sha1_digest = function(msg) return msg, false end
        end)

        teardown(function()
            package.loaded["util"] = nil
            util = require("util")
        end)
        
        before_each(function()
            package.loaded["resty.chash"] = nil
            resty_chash = require("resty.chash")

            package.loaded["balancer.sticky"] = nil
            sticky = require("balancer.sticky")

            resty_chash.new = function(self, nodes)
                return {
                    find = function(self, key)
                        -- cookie's value is the unhashed endpoint since we stubbed the hash function
                        return key
                    end,
                    next = function(self, index)
                        return test_backend_endpoint
                    end,
                    npoints = 1
                }
            end
        end)

        context("when client doesn't have a cookie set", function()
            it("should pick an endpoint for the client", function()
                local cookie = require("resty.cookie")
                cookie.new = function(self) 
                    return { 
                        get = function(self, n) return false end,
                        set = function(self, n) return true end
                    }
                end
                local sticky_balancer_instance = sticky:new(test_backend)
                local ip, port = sticky_balancer_instance:balance()
                assert.equal(ip .. ":" .. port, test_backend_endpoint)
            end)

            it("should set a cookie on the client", function() 
                local cookie = require("resty.cookie")
                local s = {}
                cookie.new = function(self) 
                    local cookie_instance = {
                        set = function(self, payload)
                            assert.equal(payload.key, test_backend.sessionAffinityConfig.cookieSessionAffinity.name)
                            assert.equal(payload.value, test_backend_endpoint)
                            assert.equal(payload.path, "/")
                            assert.equal(payload.domain, nil)
                            assert.equal(payload.httponly, true)
                            return true, nil 
                        end,
                        get = function(k) end,
                    }
                    s = spy.on(cookie_instance, "set")
                    return cookie_instance, false
                end
                local sticky_balancer_instance = sticky:new(get_test_backend())
                assert.has_no.errors(function() sticky_balancer_instance:balance() end)
                local cookie_set_payload = {
                    key = test_backend.sessionAffinityConfig.cookieSessionAffinity.name,
                    value = test_backend_endpoint,
                    path = "/",
                    domain = nil,
                    httponly = true,
                }
                assert.spy(s).was_called()
            end)
        end)

        context("when client has a cookie set", function()
            it("should not set a cookie", function()
                local cookie = require("resty.cookie")
                local s = {}
                cookie.new = function(self) 
                    local return_obj = {
                        set = function(v) return false, nil end,
                        get = function(k) return test_backend_endpoint end,
                    }
                    s = spy.on(return_obj, "set")
                    return return_obj, false
                end
                local sticky_balancer_instance = sticky:new(test_backend)
                assert.has_no.errors(function() sticky_balancer_instance:balance() end)
                assert.spy(s).was_not_called()
            end)

            it("should return the correct endpoint for the client", function()
                local cookie = require("resty.cookie")
                local s = {}
                cookie.new = function(self) 
                    local return_obj = {
                        get = function(k) return test_backend_endpoint end,
                    }
                    return return_obj, false
                end
                local sticky_balancer_instance = sticky:new(test_backend)
                local ip, port = sticky_balancer_instance:balance()
                assert.equal(ip .. ":" .. port, test_backend_endpoint)
            end)
        end)
    end)
end)

