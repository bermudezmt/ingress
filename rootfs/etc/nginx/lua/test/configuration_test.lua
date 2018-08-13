local configuration = require("configuration")
local cjson = require("cjson")
local unmocked_ngx = _G.ngx

function get_backends() 
    return {
        {
            name = "my-dummy-backend-1", ["load-balance"] = "sticky",
            endpoints = { { address = "10.183.7.40", port = "8080", maxFails = 0, failTimeout = 0 } },
            sessionAffinityConfig = { name = "cookie", cookieSessionAffinity = { name = "route", hash = "sha1" } },
        },
        {
            name = "my-dummy-backend-2", ["load-balance"] = "ewma",
            endpoints = {
                { address = "10.184.7.40", port = "7070", maxFails = 3, failTimeout = 2 },
                { address = "10.184.7.41", port = "7070", maxFails = 2, failTimeout = 1 },
            }
        },
        {
            name = "my-dummy-backend-3", ["load-balance"] = "round_robin",
            endpoints = {
                { address = "10.185.7.40", port = "6060", maxFails = 0, failTimeout = 0 },
                { address = "10.185.7.41", port = "6060", maxFails = 2, failTimeout = 1 },
            }
        },
    }
end

function get_mocked_ngx_env()
    local _ngx = {
        status = ngx.HTTP_OK,
        var = {},
        req = {
            read_body = function() end,
            get_body_data = function() return cjson.encode(get_backends()) end,
            get_body_file = function() return false end,
        },
        log = function(msg) end
    }
    setmetatable(_ngx, {__index = _G.ngx})
    return _ngx
end

describe("Configuration", function()
    before_each(function()
        _G.ngx = get_mocked_ngx_env()
    end)

    after_each(function()
        _G.ngx = unmocked_ngx
        package.loaded["configuration"] = nil
        configuration = require("configuration")
    end)

    context("Request method is neither GET nor POST", function()
        it("sends 'Only POST and GET requests are allowed!' in the response body", function()
            ngx.var.request_method = "PUT"
            local s = spy.on(ngx, "print")
            assert.has_no.errors(configuration.call)
            assert.spy(s).was_called_with("Only POST and GET requests are allowed!")
        end)

        it("returns a status code of 400", function()
            ngx.var.request_method = "PUT"
            assert.has_no.errors(configuration.call)
            assert.equal(ngx.status, ngx.HTTP_BAD_REQUEST)
        end)
    end)

    context("GET request to /configuration/backends", function()
        before_each(function()
            ngx.var.request_method = "GET"
            ngx.var.request_uri = "/configuration/backends"
        end)

        it("returns the current configured backends on the response body", function()
            -- Encoding backends since comparing tables fail due to reference comparison
            local encoded_backends = cjson.encode(get_backends())
            ngx.shared.configuration_data:set("backends", encoded_backends)
            local s = spy.on(ngx, "print")
            assert.has_no.errors(configuration.call)
            assert.spy(s).was_called_with(encoded_backends)
        end)

        it("returns a status of 200", function()
            assert.has_no.errors(configuration.call)
            assert.equal(ngx.status, ngx.HTTP_OK)
        end)
    end)

    context("POST request to /configuration/backends", function()
        before_each(function()
            ngx.var.request_method = "POST"
            ngx.var.request_uri = "/configuration/backends"
        end)
        
        it("stores the posted backends on the shared dictionary", function()
            -- Encoding backends since comparing tables fail due to reference comparison
            assert.has_no.errors(configuration.call)
            assert.equal(ngx.shared.configuration_data:get("backends"), cjson.encode(get_backends()))
        end)

        context("Failed to read request body", function()
            local mocked_get_body_data = ngx.req.get_body_data
            before_each(function()
                ngx.req.get_body_data = function() return nil end
            end)

            teardown(function()
                ngx.req.get_body_data = mocked_get_body_data
            end)

            it("returns a status of 400", function()
                _G.io.open = function(filename, extension) return false end
                assert.has_no.errors(configuration.call)
                assert.equal(ngx.status, ngx.HTTP_BAD_REQUEST)
            end)
            
            it("logs 'dynamic-configuration: unable to read valid request body to stderr'", function()
                local s = spy.on(ngx, "log")
                assert.has_no.errors(configuration.call)
                assert.spy(s).was_called_with(ngx.ERR, "dynamic-configuration: unable to read valid request body")
            end)
        end)

        context("Failed to set the new backends to the configuration dictionary", function()
            before_each(function()
                ngx.shared.configuration_data.set = function(key, value) return false, "" end
            end)

            after_each(function()
                ngx.shared.configuration_data.set = function(key, value) return true, "" end
            end)

            it("returns a status of 400", function()
                assert.has_no.errors(configuration.call)
                assert.equal(ngx.status, ngx.HTTP_BAD_REQUEST)
            end)

            it("logs 'dynamic-configuration: error updating configuration:' to stderr", function()
                local s = spy.on(ngx, "log")
                assert.has_no.errors(configuration.call)
                assert.spy(s).was_called_with(ngx.ERR, "dynamic-configuration: error updating configuration: ")
            end)
        end)

        context("Succeeded to update backends configuration", function()
            it("returns a status of 201", function()
                assert.has_no.errors(configuration.call)
                assert.equal(ngx.status, ngx.HTTP_CREATED)
            end)
        end)
    end)
end)

