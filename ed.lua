-- Get file to edit
local tArgs = { ... }
if #tArgs == 0 then
    local programName = arg[0] or fs.getName(shell.getRunningProgram())
    print("Usage: " .. programName .. " <path>")
    return
end

-- Error checking
local sPath = shell.resolve(tArgs[1])
local bReadOnly = fs.isReadOnly(sPath)
if fs.exists(sPath) and fs.isDir(sPath) then
    print("Cannot edit a directory.")
    return
end

-- Create .lua files by default
if not fs.exists(sPath) and not string.find(sPath, "%.") then
    local sExtension = settings.get("edit.default_extension")
    if sExtension ~= "" and type(sExtension) == "string" then
        sPath = sPath .. "." .. sExtension
    end
end

-- Colours
local highlightColour, keywordColour, commentColour, textColour, bgColour, stringColour
if term.isColour() then
    bgColour = colours.black
    textColour = colours.white
    highlightColour = colours.yellow
    keywordColour = colours.yellow
    commentColour = colours.green
    stringColour = colours.red
else
    bgColour = colours.black
    textColour = colours.white
    highlightColour = colours.white
    keywordColour = colours.white
    commentColour = colours.white
    stringColour = colours.white
end

local function load(_sPath)
    tLines = {}
    if fs.exists(_sPath) then
        local file = io.open(_sPath, "r")
        local sLine = file:read()
        while sLine do
            table.insert(tLines, sLine)
            sLine = file:read()
        end
        file:close()
    end

    if #tLines == 0 then
        table.insert(tLines, "")
    end
	print(tLines)
end

local function save(_sPath)
    -- Create intervening folder
    local sDir = _sPath:sub(1, _sPath:len() - fs.getName(_sPath):len())
    if not fs.exists(sDir) then
        fs.makeDir(sDir)
    end

    -- Save
    local file, fileerr
    local function innerSave()
        file, fileerr = fs.open(_sPath, "w")
        if file then
            for _, sLine in ipairs(tLines) do
                file.write(sLine .. "\n")
            end
        else
            error("Failed to open " .. _sPath)
        end
    end

    local ok, err = pcall(innerSave)
    if file then
        file.close()
    end
    return ok, err, fileerr
end

local tKeywords = {
    ["and"] = true,
    ["break"] = true,
    ["do"] = true,
    ["else"] = true,
    ["elseif"] = true,
    ["end"] = true,
    ["false"] = true,
    ["for"] = true,
    ["function"] = true,
    ["if"] = true,
    ["in"] = true,
    ["local"] = true,
    ["nil"] = true,
    ["not"] = true,
    ["or"] = true,
    ["repeat"] = true,
    ["return"] = true,
    ["then"] = true,
    ["true"] = true,
    ["until"] = true,
    ["while"] = true,
}

local function tryWrite(sLine, regex, colour)
    local match = string.match(sLine, regex)
    if match then
        if type(colour) == "number" then
            term.setTextColour(colour)
        else
            term.setTextColour(colour(match))
        end
        term.write(match)
        term.setTextColour(textColour)
        return string.sub(sLine, #match + 1)
    end
    return nil
end

local function writeHighlighted(sLine)
    while #sLine > 0 do
        sLine =
            tryWrite(sLine, "^%-%-%[%[.-%]%]", commentColour) or
            tryWrite(sLine, "^%-%-.*", commentColour) or
            tryWrite(sLine, "^\"\"", stringColour) or
            tryWrite(sLine, "^\".-[^\\]\"", stringColour) or
            tryWrite(sLine, "^\'\'", stringColour) or
            tryWrite(sLine, "^\'.-[^\\]\'", stringColour) or
            tryWrite(sLine, "^%[%[.-%]%]", stringColour) or
            tryWrite(sLine, "^[%w_]+", function(match)
                if tKeywords[match] then
                    return keywordColour
                end
                return textColour
            end) or
            tryWrite(sLine, "^[^%w_]", textColour)
    end
end

local tCompletions
local nCompletion

local tCompleteEnv = _ENV
local function complete(sLine)
    if settings.get("edit.autocomplete") then
        local nStartPos = string.find(sLine, "[a-zA-Z0-9_%.:]+$")
        if nStartPos then
            sLine = string.sub(sLine, nStartPos)
        end
        if #sLine > 0 then
            return textutils.complete(sLine, tCompleteEnv)
        end
    end
    return nil
end

local function recomplete()
    local sLine = tLines[y]
    if sStatus == "Insert" and not bReadOnly and x == #sLine + 1 then
        tCompletions = complete(sLine)
        if tCompletions and #tCompletions > 0 then
            nCompletion = 1
        else
            nCompletion = nil
        end
    else
        tCompletions = nil
        nCompletion = nil
    end
end

local function writeCompletion(sLine)
    if nCompletion then
        local sCompletion = tCompletions[nCompletion]
        term.setTextColor(colours.white)
        term.setBackgroundColor(colours.grey)
        term.write(sCompletion)
        term.setTextColor(textColour)
        term.setBackgroundColor(bgColour)
    end
end

local function acceptCompletion()
    if nCompletion then
        -- Append the completion
        local sCompletion = tCompletions[nCompletion]
        tLines[y] = tLines[y] .. sCompletion
        setCursor(x + #sCompletion , y)
    end
end

--Main program
local y = 1
local x = 1
local bRunning = true
local normal_mode = true
local write_line = nil
local unsaved = false

load(sPath)
term.setBackgroundColour(bgColour)
term.clear()
term.setCursorPos(x, y)
term.setCursorBlink(true)

local function parseAddr( input )
	local addressBuff = {}
	-- Replace all fullstops with current address
		input = input:gsub("%.", y)
	-- Replace all dollars with the end of the buffer
		input = input:gsub("%$", #tLines)
	-- Replace all "+%D" with "+1"
		while input:match("[%+%-]%D") do
			-- Insert space between "+" and "%D"
			local i,j = input:find("[%+%-][%a%p]")
			input = input:sub(1,i) .. " " .. input:sub(j)
			-- replace "%s" with "1"
			input = input:gsub("%s", "1")
		end
		if input:sub( input:len() ) == "+" then
			input = input.."1"
		end
		if input:sub( input:len() ) == "-" then
			input = input.."1"
		end
	-- parse all mathematical equations into one address
		if input:match("[%-%+].") then
			local inpGmatch = input:gmatch("[%+%-]%d+")
			local i = inpGmatch()
			local operand = y + tonumber(i)
			i = inpGmatch()
			while i do
				operand = operand + tonumber(i)
				i = inpGmatch()
			end
			-- replace first occurance of "+(n)" with operand
			local i,j = input:find("[%-%+]%d+")
			input = input:sub(1,i-1) .. operand .. input:sub(j+1)
			-- get rid of other "+"s
			input = input:gsub("[%-%+]1", "")
		end
		if input:match("%+") then
			input = input:gsub("%+", y+1)
		end
		if input:match("%-") then
			input = input:gsub("%-", y-1)
		end
	-- Find and save addresses
	local k=1
	for v in input:gmatch("%d+") do
		addressBuff[k] = v
		k = k+1
	end
	local addr1 = addressBuff[ table.maxn(addressBuff)-1 ]
	local addr2 = addressBuff[ table.maxn(addressBuff) ]
	if addr1 == nil and addr2 == nil then
		if input:match(",;") ~= nil or input:match(";,") ~= nil then
			addr1 = y
			addr2 = y
		elseif input:match(",%a") ~= nil then
			addr1 = 1
			addr2 = #tLines
		elseif input:match(";%a") ~= nil then
			addr1 = y
			addr2 = #tLines
		else
			addr1 = y
			addr2 = y
		end
	end
	if addr1 == nil then addr1 = addr2 end
	return addr1, addr2, input
end

local function main()
	local input = read()
	if normal_mode == true then
		local addr1, addr2, input = parseAddr(input)

		-- Throw error if addresses are out of bounds
		if addr1 == 0 or tonumber(addr2) > #tLines then
			print("?")
			return
		end
		-- Remove addresses from input
		input = input:gsub("%d", "")
		input = input:gsub(",", "")
		input = input:gsub(";", "")
		
		-- Normal mode commands
		if input == "n" then
			for i=addr1, addr2 do
				print(i .. "   " .. tLines[i])
			end
		elseif input == "p" then
			for i=addr1, addr2 do
				print("    " .. tLines[i])
			end
		elseif input == "" then
			y = tonumber(addr2)
		--	print(y)
			print(tLines[y])
		elseif input == "q" then
			bRunning = false
		elseif input == "i" then
			normal_mode = false
			write_line = y
		elseif input == "a" then
			normal_mode = false
			write_line = y+1
		end
		y = addr2
	-- insert mode
	else
		if input ~= "." then
			table.insert(tLines, write_line, input)
			write_line = write_line+1
			unsaved = true
		else
			normal_mode = true
		end
	end
end

repeat main() until bRunning == false
