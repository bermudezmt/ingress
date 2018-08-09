local configuration = require("configuration")
local unmocked_ngx = _G.ngx

function get_mocked_ngx_env()
    local _ngx = {
        status = 100,
        print = function(msg) return msg end,
        var = {},
        req = {
            read_body = function() end,
            get_body_data = function() end,
            get_body_file = function() end,
        }
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
        it("should log 'Only POST and GET requests are allowed!'", function()
            ngx.var.request_method = "PUT"
            local s = spy.on(ngx, "print")
            assert.has_no.errors(configuration.call)
            assert.spy(s).was_called_with("Only POST and GET requests are allowed!")
        end)

        it("should return a status code of 400'", function()
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

        it("should call get_backends_data()", function()
            local s = spy.on(configuration, "get_backends_data")
            assert.has_no.errors(configuration.call)
            assert.spy(s).was_called()
        end)

        it("should call configuration_data:get('backends')", function()
            ngx.shared.configuration_data.get = function(self, rsc) return {backend = true} end
            local s = spy.on(ngx.shared.configuration_data, "get")
            assert.has_no.errors(configuration.call)
            assert.spy(s).was_called_with(ngx.shared.configuration_data, "backends")
            assert.spy(s).returned_with({backend = true})
        end)

        it("should return a status of 200", function()
            assert.has_no.errors(configuration.call)
            assert.equal(ngx.status, ngx.HTTP_OK)
        end)
    end)

    context("POST request to /configuration/backends", function()
        before_each(function()
            ngx.var.request_method = "POST"
            ngx.var.request_uri = "/configuration/backends"
        end)
        
        it("should call configuration_data:set('backends')", function()
            ngx.req.get_body_data = function() return {body_data = true} end
            local s = spy.on(ngx.shared.configuration_data, "set")
            assert.has_no.errors(configuration.call)
            assert.spy(s).was_called_with(ngx.shared.configuration_data, "backends", {body_data = true})
        end)

        context("Failed to read request body", function()
            before_each(function()
                ngx.req.get_body_data = function() return false end
            end)

            it("should return a status of 400", function()
                ngx.req.get_body_file = function() return false end
                _G.io.open = function(filename, extension) return false end
                assert.has_no.errors(configuration.call)
                assert.equal(ngx.status, ngx.HTTP_BAD_REQUEST)
            end)
            
            it("should log 'dynamic-configuration: unable to read valid request body'", function()                
                local s = spy.on(ngx, "log")
                assert.has_no.errors(configuration.call)
                assert.spy(s).was_called_with(ngx.ERR, "dynamic-configuration: unable to read valid request body")
            end)
        end)

        context("Failed to set the new backends to the configuration dictionary", function()
            before_each(function()
                ngx.req.get_body_data = function() return true end
                ngx.shared.configuration_data.set = function(key, value) return false, "" end
            end)

            it("should return a status of 400", function()
                assert.has_no.errors(configuration.call)
                assert.equal(ngx.status, ngx.HTTP_BAD_REQUEST)
            end)

            it("should log 'dynamic-configuration: error updating configuration:'", function()
                local s = spy.on(ngx, "log")
                assert.has_no.errors(configuration.call)
                assert.spy(s).was_called_with(ngx.ERR, "dynamic-configuration: error updating configuration: ")
            end)
        end)

        context("Succeeded to update backends configuration", function()
            it("should return a status of 201", function()
                ngx.req.get_body_data = function() return true end
                ngx.shared.configuration_data.set = function(key, value) return true, "" end
                assert.has_no.errors(configuration.call)
                assert.equal(ngx.status, ngx.HTTP_CREATED)
            end)
        end)
    end)
end)

