--- The HTTP API allows interfacing with websites and downloading from them.
--- [http.request](http://www.computercraft.info/wiki/Http.request "Http.request") is used to send a HTTP request that completes asynchronously and generates an event (one of [http_success](http://www.computercraft.info/wiki/Http_success_(event) "Http success (event)") or [http_failure](http://www.computercraft.info/wiki/Http_failure_(event) "Http failure (event)")). [http.get](http://www.computercraft.info/wiki/Http.get "Http.get") and [http.post](http://www.computercraft.info/wiki/Http.post "Http.post") execute [http.request](http://www.computercraft.info/wiki/Http.request "Http.request") and block until the operation completes.
http = {}

--- [■](http://www.computercraft.info/wiki/Http.request)
--- Sends a HTTP request to a website, asynchronously.
---@return nil
---@param url string
---@param postData string
---@param headers table
---@overload fun(url: string, postData: string, headers: table): nil
function http.request(url, postData, headers) end

--- [■](http://www.computercraft.info/wiki/Http.get)
--- Sends a HTTP GET request to a website, synchronously.
---@return table handle
---@param url string
---@param headers table
function http.get(url, headers) end

--- [■](http://www.computercraft.info/wiki/Http.post)
--- Sends a HTTP POST request to a website, synchronously.
---@return table handle
---@param url string
---@param postData string
---@param headers table
function http.post(url, postData, headers) end

--- [■](http://www.computercraft.info/wiki/Http.checkURL)
--- Checks if a URL is valid and is included in the HTTP whitelist.
---@return boolean success [
---@return string error]
---@param url string
function http.checkURL(url) end
