local HttpService = game:GetService("HttpService")

local WEBHOOK_URL = "https://discord.com/api/webhooks/1453406641767579699/Pa0gVrr_8psmx3B62U0uass2WD6Mny4Khpr1_j6bMkpCeKfS0ko3EPxpUe_qwcuXH6A7"

local function getExecutorUserAgent()
    local ua = "Unknown"

    local ok, result = pcall(function()
        if request then
            local response = request({
                Url = "https://httpbin.org/user-agent",
                Method = "GET",
            })

            if type(response) == "table" and response.StatusCode == 200 and response.Body then
                local data = HttpService:JSONDecode(response.Body)
                if type(data) == "table" and type(data["user-agent"]) == "string" then
                    return data["user-agent"]
                end
            end
        end
    end)

    if ok and type(result) == "string" then
        ua = result
    end

    return ua
end

local function sendToWebhook(message)
    if not request then return end

    local body = HttpService:JSONEncode({
        content = message
    })

    request({
        Url = WEBHOOK_URL,
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json"
        },
        Body = body
    })
end

local userAgent = getExecutorUserAgent()

print("Executor User-Agent:", userAgent)

sendToWebhook("Executor User-Agent: **" .. userAgent .. "**")
