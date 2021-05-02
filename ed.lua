-- Environment
local tEnv = {
	["y"] = 1,
	["x"] = 1,
	["bRunning"] = true,
	["mode"] = "normal",
	["write_line"] = 0,
	["unsaved"] = false,
	["change"] = false,
	["syntaxHL"] = false,
	["last_error"] = 0,
	["bPrint_error"] = false,
}
-- Bookmarks
local tBookms = {}
-- Get file to edit
local tArgs = { ... }

local sPath
if tArgs[1] then
	sPath = shell.resolve(tArgs[1])
	-- Error checking
	local bReadOnly = fs.isReadOnly(sPath)
	if fs.exists(sPath) and fs.isDir(sPath) then
		tEnv.last_error = sPath .. ": Is a directory"
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
    commentColour = colours.grey
    stringColour = colours.white
end

local function ed_error(error)
	print("?")
	if tEnv.bPrint_error == true then
		print(error)
	end
	tEnv.last_error = error
end

local function load(_sPath)
    tLines = {}
    if _sPath and fs.exists(_sPath) and not fs.isDir(_sPath) then
        local file = io.open(_sPath, "r")
        local sLine = file:read()
        while sLine do
            table.insert(tLines, sLine)
            sLine = file:read()
        end
        file:close()
	else
		tEnv.last_error = "Cannot read input file"
	end

    if #tLines == 0 then
        table.insert(tLines, "")
    end
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
			ed_error("Cannot open output file")
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

local function split(s, delimiter)
	local result = {}
	for match in (s..delimiter):gmatch("(.-)"..delimiter) do
		table.insert(result, match)
	end
	return result
end

local function parseAddr( input )
	local addressBuff = {}
	-- Error if `+` or `-` is before 'x
		if input:match("%+'%l") or input:match("%-'%l") then
			tEnv.mode = "none"
			return 0, tEnv.y
		end
	-- Replace all fullstops with current address
		input = input:gsub("%.", tEnv["y"])
	-- Replace all dollars with the end of the buffer
		input = input:gsub("%$", #tLines)
	-- Replace all 'x with the respective bookmark
		while input:match("'%l") do 
			local sMark = input:match("'%l")
			local mark = sMark:sub(2)
			if tBookms[mark] then
				input = input:gsub(sMark, tBookms[mark])
			else
				tEnv.mode = "none"
				return 0, tEnv.y
			end
		end
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
			local sum1 = input:match("%d+[%+%-]")
			sum1 = sum1:sub(1, string.len(sum1)-1)
			tEnv.y = sum1
			local i = inpGmatch()
			local operand = tEnv["y"] + tonumber(i)
			i = inpGmatch()
			while i do
				operand = operand + tonumber(i)
				i = inpGmatch()
			end
			-- replace sum1 with nothing
			input = input:sub( string.len(sum1)+1 )
			-- replace first occurance of "+(n)" with operand
			local i,j = input:find("[%-%+]%d+")
			input = input:sub(1,i-1) .. operand .. input:sub(j+1)
			-- get rid of other "+"s
			input = input:gsub("[%-%+]1", "")
		end
		if input:match("%+") then
			input = input:gsub("%+", tEnv["y"]+1)
		end
		if input:match("%-") then
			input = input:gsub("%-", tEnv["y"]-1)
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
			addr1 = tEnv["y"]
			addr2 = tEnv["y"]
		elseif input:match(",%a") ~= nil then
			addr1 = 1
			addr2 = #tLines
		elseif input:match(";%a") ~= nil then
			addr1 = tEnv["y"]
			addr2 = #tLines
		else
			addr1 = tEnv["y"]
			addr2 = tEnv["y"]
		end
	end
	if addr1 == nil then addr1 = addr2 end
	return addr1, addr2, input
end


--Main program
term.setBackgroundColour(bgColour)
term.clear()
term.setCursorPos(tEnv.x, tEnv.y)
term.setCursorBlink(true)

if tEnv.last_error ~= 0 then print(tEnv.last_error) end
load(sPath)

local function main()
	-- reset mode after error run
	if tEnv.mode == "none" then
		tEnv.mode = "normal"
	end

	local input = read()
	if tEnv.mode == "normal" then
		local addr1, addr2, input = parseAddr(input)
		-- Throw error if addresses are out of bounds
		if addr1 == 0 or tonumber(addr2) > #tLines then
			ed_error("Invalid address")
			return
		end
		-- Remove addresses from input
		input = input:gsub("%d", "")
		input = input:gsub(",", "")
		input = input:gsub(";", "")
		
		-- Normal mode commands
		if input == "n" then
			for i=addr1, addr2 do
				if tEnv.syntaxHL == true then
					if string.len(tLines[i]) > 0 then
						write(i .. "   ") writeHighlighted(tLines[i]) write("\n")
					else print(i)
					end
				else print(i .. "   ".. tLines[i])
				end
			end
		elseif input == "p" then
			for i=addr1, addr2 do
				if tEnv.syntaxHL == true then
					if string.len(tLines[i]) > 0 then
						writeHighlighted(tLines[i]) write("\n")
					else print(i) end
				else print(tLines[i])
				end
			end
		elseif input == "" then
			tEnv["y"] = tonumber(addr2)
			print(tLines[tEnv["y"]])
		elseif input == "Q" then
			tEnv.bRunning = false
		elseif input == "d" then
			for i=addr1, addr2 do
				table.remove(tLines, i)
			end
		elseif input == "i" then
			tEnv.mode = "insert"
			tEnv.write_line = addr2
		elseif input == "a" then
			tEnv.mode = "insert"
			tEnv.write_line = addr2+1
		elseif input == "c" then
			tEnv.mode = "insert"
			tEnv.write_line = addr2
			tEnv.change = true
		elseif input:match("w.-") then
			local input = string.sub( input:gsub("%s", ""), 2)
			local sPath = sPath
			if string.len(input) > 0 then
				sPath = shell.resolve(input)
			end
			if sPath then
				save(sPath)
				tEnv.unsaved = false
			else ed_error("No current filename") end
		elseif input:match("set") then
			-- find argument
			local arg = input:gsub("set", "")
			arg = arg:gsub("%s+", "")
			-- split at "="
			local parts = split(arg, "=")
			local partsLen = #parts
			if partsLen > 1 then
				local key = parts[partsLen-1]
				local value = parts[partsLen]
				if tEnv[key] ~= nil then
					if value == "true" then
						value = true
					elseif value == "false" then
						value = false
					end
					tEnv[key] = value
				else
					print(tEnv.syntaxHL)
					ed_error(key..": No such value")
				end
			else
				ed_error("Not enough arguments")
			end
		elseif input:match("H") then
			if tEnv.bPrint_error == false then
				tEnv.bPrint_error = true
				print(tEnv.last_error)
			else tEnv.bPrint_error = false end
		elseif input:match("k%l?") then
			local suffix = input:sub(2)
			if string.len(input) ~= 2 then
				ed_error("Invalid command suffix")
			else
				tBookms[suffix] = addr2
			end
		end

		tEnv["y"] = addr2
	-- insert mode
	elseif tEnv.mode == "insert" then
		if input ~= "." and tEnv.change == false then
			table.insert(tLines, tEnv.write_line, input)
			tEnv.write_line = tEnv.write_line+1
			tEnv.unsaved = true
		elseif input ~= "." and tEnv.change == true then
			tLines[tonumber(tEnv.write_line)] = input
			tEnv.write_line = tEnv.write_line+1
			tEnv.unsaved = true
		elseif input == "." then
			tEnv.mode = "normal"
			tEnv.change = false
		end
	end
end

repeat main() until tEnv.bRunning == false
