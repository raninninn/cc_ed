--
-- cc_ed
-- made by Raninninn
--


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
  ["last_cmd"] = false,
  ["implicitAddr"] = false,
	["lastS"] = {},
	["lastShellCmd"] = {},
	["cutBuffer"] = {},
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

local function writeFile(_sPath, _addr1, _addr2, _mode)
  -- Create intervening folder
  local sDir = _sPath:sub(1, _sPath:len() - fs.getName(_sPath):len())
  if not fs.exists(sDir) then
    fs.makeDir(sDir)
  end

  -- Save
  local file, fileerr
  local function innerWrite()
    file, fileerr = fs.open(_sPath, _mode)
    if file then
    	for i = _addr1, _addr2 do
        file.write(tLines[i] .. "\n")
      end
    else
			ed_error("Cannot open output file")
    end
  end

  local ok, err = pcall(innerWrite)
  if file then
    file.flush()
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

local function splitAddr( input )
	local splitter = 0
	local input = input.."a"
	-- find first occurance of a letter or = or ! that isn't part of regex, if it is lower case and has `'` before it, go to next occurance
	while input:find("[%a=!]") do
		local mbSplitter = input:find("[%a=!]")
		local i,j = input:find("%b//")
		local ii, jj = input:find("%b??")
		if i == nil or i ~= nil and ii ~= nil and i < ii then
			i = ii
			j = jj
		end
		if i == nil or j == nil or mbSplitter < i or mbSplitter > j then
			if input:sub(mbSplitter-1, mbSplitter-1) ~= "'" or string.match(input:sub(mbSplitter, mbSplitter), "%u") then
				splitter = splitter + mbSplitter
				break
			else input = input:sub(mbSplitter+1)
			splitter = splitter + mbSplitter
			end
		else
			if mbSplitter < j then
				input = input:sub(j+1)
				splitter = splitter + j
			else
				input = input:sub(mbSplitter)
				splitter = splitter + mbSplitter
			end
		end
	end
	if splitter == 0 then
		splitter = 1
	end
	return splitter
end

local function findAddr( input )
	local addressBuff = {}
	local splitter = splitAddr( input )
	local addr = input:sub(1, splitter-1)

  tEnv.implicitAddr = false

	if input:len() == 1 and input:match("[%d,%.;]") then
		addr = input
	end
	-- Error if more than 2 addresses are given
	if addr:match("[,;].+[,;]") then
		return 0, tEnv.y
	end
	-- Error if `+` or `-` is before `'x` or `/`
	if addr:match("[%+%-]'%l") or input:match("[%+%-][%?/]") then
    -- check we're not inside of regex
    addrCpy = addr
    while addrCpy:match("[%+%-]'%l") or addrCpy:match("[%+%-][%?/]") do
      local regStart, regEnd = 0, 0
      local regStart, regEnd = addrCpy:find("[/%?][^/%?]+[/%?]")
      local offender1Start, offender1End = addrCpy:find("[%+%-]'%l")
      local offender2Start, offender2End = addrCpy:find("[%+%-][/%?]")
      local offenderStart, offenderEnd = 0, 0

      if offender1Start and offender2Start and offender1Start < offender2Start then
        offenderStart = offender1Start
        offenderEnd = offender1End
      elseif offender1Start and offender2Start and offender1Start > offender2Start then
        offenderStart = offender2Start
        offenderEnd = offender2End
      else
        if offender1End and offender2End and offender1End > offender2End then
          offenderStart = offender1Start
        	offenderEnd = offender1End
        else
        	if offender2Start then
            offenderStart = offender2Start
            offenderEnd = offender2End
          else
            offenderStart = offender1Start
            offenderEnd = offender1End
          end
        end
      end
      if offenderStart < regStart or offenderEnd > regEnd then
        tEnv.mode = "none"
        return 0, tEnv.y
      end
      addrCpy = addrCpy:sub(regEnd)
    end
	end
	-- Replace all Regex with their respective lines
	if addr:match("/.+/") then
		local regStart, regEnd = addr:find("/.+/")
		local regex = addr:sub(regStart+1, regEnd-1)
		local foundMatch = false
		for i=tEnv.y, #tLines do
			if tLines[i]:match(regex) then
				addr = addr:sub(0, regStart-1) .. i .. addr:sub(regEnd+1)
				foundMatch = true
				break
			end
		end
		if foundMatch == false then
			for i=1, tEnv.y-1 do
				if tLines[i]:match(regex) then
					addr = addr:sub(0, regStart-1) .. i .. addr:sub(regEnd+1)
					foundMatch = true
					break
				end
			end
		end
		if foundMatch == false then
			return -1, tEnv.y
		end
	end
	if addr:match("%?.+%?") then
		local regStart, regEnd = addr:find("%?.+%?")
		local regex = addr:sub(regStart+1, regEnd-1)
		local foundMatch = false
		for i=tEnv.y, 1, -1 do
			if tLines[i]:match(regex) then
				addr = addr:sub(0, regStart-1) .. i .. addr:sub(regEnd+1)
				foundMatch = true
				break
			end
		end
		if foundMatch == false then
			for i=#tLines, tEnv.y+1, -1 do
				if tLines[i]:match(regex) then
					addr = addr:sub(0, regStart-1) .. i .. addr:sub(regEnd+1)
					foundMatch = true
					break
				end
			end
		end
		if foundMatch == false then
			return -1, tEnv.y
		end
	end
	-- strip all spaces from `addr`
	addr = addr:gsub("%s", "")
	-- Replace all fullstops with current address
	addr = addr:gsub("%.", tEnv.y)
	-- replace all dollars with end of buffer
	addr = addr:gsub("%$", #tLines)
	-- Replace all bookmarks
	while addr:match("'%l") do
		local sMark = addr:match("'%l")
		local mark = sMark:sub(2)
		if tBookms[mark] then
			addr = addr:gsub(sMark, tBookms[mark])
		else
			tEnv.mode = "none"
			return 0, tEnv.y
		end
	end
	-- Replace all "+%D" with "+1"
	while addr:match("[%+%-]%D") do
		-- Insert space between "+" and "%D"
		local i,j = addr:find("[%+%-][%D]")
		addr = addr:sub(1,i) .. " " .. addr:sub(j)
		-- replace "%s" with "1"
		addr = addr:gsub("%s", "1")
	end
	if addr:sub( addr:len() ) == "+" then
		addr = addr.."1"
	end
	if addr:sub( addr:len() ) == "-" then
		addr = addr.."1"
	end
	if addr:sub(1,1):match("[%+%-]") then
		addr = tEnv.y..addr
	end
	-- parse all mathematical equations into one address
	if addr:match("[%-%+].") then
		local addrGmatch = addr:gmatch("[%+%-]%d+")
		local sum1 = addr:match("%d[%+%-]")
		sum1 = sum1:sub(1, string.len(sum1)-1)
		tEnv.y = sum1
		local i = addrGmatch()
		local operand = tEnv.y + tonumber(i)
		i = addrGmatch()
		while i do
			operand = operand + tonumber(i)
			i = addrGmatch()
		end
		-- replace sum1 with nothing
		addr = addr:sub( string.len(sum1)+1 )
		-- replace first occurance of "+(n)" with operand
		local i,j = addr:find("[%-%+]%d+")
		addr = addr:sub(1,i-1) .. operand .. addr:sub(j+1)
		-- get rid of other "+"s
		addr = addr:gsub("[%+%-]1", "")
	end
	if addr:match("%+") then
		addr = addr:gsub("%+", tEnv["y"]+1)
	end
	if addr:match("%-") then
		addr = addr:gsub("%-", tEnv["y"]-1)
	end
	-- find and save addresses
	local k=1
	for v in addr:gmatch("%d+") do
		addressBuff[k] = v
		k = k+1
	end
	local addr1 = addressBuff[ table.maxn(addressBuff)-1 ]
	local addr2 = addressBuff[ table.maxn(addressBuff) ]
	if addr1 == nil and addr2 == nil then
		if addr:match(",;") or addr:match(";,") ~= nil then
			addr1 = tEnv.y
			addr2 = tEnv.y
		elseif addr:match(",") ~= nil then
			addr1 = 1
			addr2 = #tLines
		elseif addr:match(";") ~= nil then
			addr1 = tEnv.y
			addr2 = #tLines
		elseif input ~= "" then
      tEnv.implicitAddr = true
			addr1 = tEnv.y
			addr2 = tEnv.y
		end
	end
	if addr1 == nil then addr1 = addr2 end
	return addr1, addr2, splitter
end



--Main program
term.setBackgroundColour(bgColour)
term.clear()
term.setCursorPos(tEnv.x, tEnv.y)
term.setCursorBlink(true)
local normCmds = {
	["n"] = function(addr1, addr2)
				for i=addr1, addr2 do
					if tEnv.syntaxHL == true then
						if string.len(tLines[i]) > 0 then
							write(i .. "   ") writeHighlighted(tLines[i]) write("\n")
						else print(i)
						end
					else print(i .. "   " .. tLines[i])
					end
				end
			end,
	["p"] = function(addr1, addr2)
				for i=addr1, addr2 do
					if tEnv.syntaxHL == true then
						if string.len(tLines[i]) > 0 then
							writeHighlighted(tLines[i]) write("\n")
						else print(i) end
					else print(tLines[i])
					end
				end
			end,
	["Q"] = function() tEnv.bRunning = false end,
  ["q"] = function()
        if tEnv.unsaved == true then
          if tEnv.last_cmd == "q" then
            tEnv.bRunning = false
          else
            ed_error("Warning: buffer modified")
          end
        else tEnv.bRunning = false end
      end,
	["d"] = function(addr1, addr2)
				tEnv.cutBuffer = {}
				local ii = 1
				for i=addr1, addr2 do
					tEnv.cutBuffer[ii] = tLines[addr1]
					table.remove(tLines, addr1)
					tEnv.unsaved = true
					ii = ii + 1
				end
				if #tLines == 0 then
					tLines[1] = ""
				end
			end,
	["i"] = function(addr1, addr2) tEnv.mode = "insert" tEnv.write_line = addr2 end,
	["a"] = function(addr1, addr2) tEnv.mode = "insert" tEnv.write_line = addr2+1 end,
	["c"] = function(addr1, addr2) tEnv.mode = "insert" tEnv.write_line = addr2 tEnv.change = true end,
	["H"] = function()
				if tEnv.bPrint_error == false then
					tEnv.bPrint_error = true print(tEnv.last_error)
				else tEnv.bPrint_error = false end
			end,
	["h"] = function()
				print(tEnv.last_error)
			end,
	["="] = function() print(tEnv.y) end,
	["j"] = function(addr1, addr2)
				local addr1, addr2 = tonumber(addr1), tonumber(addr2)
				if addr1 ~= addr2 then
					tLines[addr1] = tLines[ addr1 ]..tLines[ addr2 ]
					table.remove(tLines, addr2)
					tEnv.y = addr1
				end
			end,
	["y"] = function(addr1, addr2)
				local addr1, addr2 = tonumber(addr1), tonumber(addr2)
				tEnv.cutBuffer = {}
				for i = addr1, addr2 do
					table.insert(tEnv.cutBuffer, tLines[i])
				end
			end,
	["x"] = function(addr1)
				local addr1 = tonumber(addr1)
				for i = 1, #tEnv.cutBuffer do
					table.insert(tLines, addr1, tEnv.cutBuffer[i])
					addr1 = addr1 + 1
				end
			end,
}


if tEnv.last_error ~= 0 then print(tEnv.last_error) end
load(sPath)

local function main()
	-- reset mode after error run
	if tEnv.mode == "none" then
		tEnv.mode = "normal"
	end
	local input = read()
	if tEnv.mode == "normal" then
		local addr1, addr2, splitter = findAddr(input)
		-- Throw error if addresses are out of bounds
		if addr1 ~= nil then
			if tonumber(addr1) == 0 or tonumber(addr2) > #tLines then
				ed_error("Invalid address")
				return
			end
		end
		-- Throw error if no match found for regex
		if addr1 == -1 then
			ed_error("No match")
			return
		end
		-- Remove addresses from input
		input = input:sub(splitter)

		-- Normal mode commands
		if input == "" and addr2 then
			tEnv["y"] = tonumber(addr2)
			print(tLines[tEnv["y"]])
		elseif input == "" and addr1 == nil then
      print(tEnv.y)
      print(type(tEnv.y).." "..type(#tLines))
			if tEnv.y < #tLines then
				tEnv.y = tEnv.y + 1
				print(tLines[tEnv.y])
			else
				ed_error("Invalid address")
			end
		elseif input:sub(1,1) == "!" then
			input = input:sub(2)
			-- replace all ! with last shell command
			if input:match("!") then
				input = input:gsub("!", tEnv.lastShellCmd)
				print(input)
			end
			-- replace all unescaped % with default file name
			local start = 0
			while input:find("%%", start+1) do
				start = input:find("%%", start+1)
				if input:sub(start-1, start-1) ~= "\\" then
					input = input:sub(0, start-1) .. sPath .. input:sub(start+1)
					print(input)
				end
			end
			-- execute
			shell.run(input)
			-- set executed shell command as last shell command
			tEnv.lastShellCmd = input
			print("!")
		elseif input:match("w.-") then
            if input:sub(1,1) ~= "w" then
                ed_error("Unknown command")
                return
            end
            if tEnv.implicitAddr then
                addr1 = 1
                addr2 = #tLines
            end
            -- wq
            local quitAfter = false
            if input:sub(2,2) == "q" then
                quitAfter = true
            end
            local input = input
            -- find filename
            if quitAfter == false then
                input = input:gsub("%s", ""):sub(2)
            else
                input = input:gsub("%s", ""):sub(3)
            end
			local sPath = sPath
			if string.len(input) > 0 then
				sPath = shell.resolve(input)
			end
			if sPath then
				writeFile(sPath, addr1, addr2, "w")
                if addr1 == 1 and addr2 == #tLines then
                    tEnv.unsaved = false
                end
			else ed_error("No current filename") end
            if quitAfter then
                tEnv.bRunning = false
            end
        elseif input:match("W.-") then
            if input:sub(1,1) ~= "W" then
                ed_error("Unknown command")
                return
            end
            if tEnv.implicitAddr then
                addr1 = 1
                addr2 = #tLines
            end
            -- find filename
            local input = input:gsub("%s", ""):sub(2)
            local sPath = sPath
            if string.len(input) > 0 then
                sPath = shell.resolve(input)
            end
            if sPath then
                writeFile(sPath, addr1, addr2, "a")
                if addr1 == 1 and addr2 == #tLines then
                    tEnv.unsaved = false
                end
            end
		elseif input:match("set") then
            if input:sub(1,3) ~= "set" then
                ed_error("Unknown command")
                return
            end
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
		elseif input:match("k%l?") then
      if not input:sub(1,2):match("'%l") then
        ed_error("Unknown command")
        return
      end
			local suffix = input:sub(2)
			if string.len(input) ~= 2 then
				ed_error("Invalid command suffix")
			else
				tBookms[suffix] = addr2
			end
		elseif input:match("s") then
			if input:sub(1,1) ~= "s" then
				ed_error("Unknown command")
				return
			end

			local comList = ""
			local cTlines = {table.unpack(tLines)}

			local function doSuffices(_comList, _regex)
				local comListLen = string.len(_comList)
				for i=1, comListLen do
					local suffix = _comList:sub(i, i)
					if suffix == "n" then
						local lastMatch = 0
						for i = addr1, addr2 do
							if cTlines[i]:match(_regex) then
								lastMatch = i
							end
						end
						if lastMatch ~= 0 then
							normCmds["n"](lastMatch, lastMatch)
						end
					elseif suffix == "p" then
						local lastMatch = 0
						for i=addr1, addr2 do
							if cTlines[i]:match(_regex) then
								lastMatch = i
							end
						end
						if lastMatch ~= 0 then
							normCmds["p"](lastMatch, lastMatch)
						end
					elseif suffix == "l" then
						local lastMatch = 0
						for i=addr1, addr2 do
							if cTlines[i]:match(_regex) then
								lastMatch = i
							end
						end
						if lastMatch ~= 0 then
							normCmds["l"](lastMatch, lastMatch)
						end
					end
				end
			end

			local function doRepl(regex, repl, count)
				local cCount = 1
				for i = addr1, addr2 do
					if count ~= "all" then
						count = tonumber(count)
						local sLine = tLines[i]
						local cPos = 0
						while sLine:match(regex) do
							local regFindS, regFindE = sLine:find(regex)
							if cCount == count then
								tLines[i] = tLines[i]:sub(1,cPos + regFindS-1) .. repl .. tLines[i]:sub(cPos + regFindE+1)
								break
							else
								sLine = sLine:sub(regFindE+1)
								cPos = regFindE
							end
							cCount = cCount + 1
						end
						if cCount == count then
							break
						end
					else
						tLines[i] = tLines[i]:gsub(regex, repl)
					end
				end
				tEnv.unsaved = true
			end

			local function findCount(input)
				local count = input:match("%d+")
				if input:match("g") then
					count = "all"
				end
				if count == nil then
					count = 1
				end
				return count
			end

	    if input:match("s%?.+%?.*%?.*") or input:match("s/.+/.*/.*") then
	    	local regex = input:match("[/%?][^/%?]+[/%?]")
	      if regex then
	      	-- add % in front of character classes to prohibit regex confusion
	        cleanRegex = regex:gsub("%^", "%%^"):gsub("%$", "%%$"):gsub("%%", "%%%%")
	        cleanRegex = cleanRegex:gsub("%+", "%%+"):gsub("%-", "%%-"):gsub("%?", "%%?")
	        cleanRegex = cleanRegex:gsub("%.", "%%."):gsub("%(", "%%("):gsub("%)", "%%)"):gsub("%[", "%%["):gsub("%]", "%%]"):gsub("%*", "%%*")
					-- find regex
	        local regStart, regEnd = input:find(cleanRegex)
	        regStart = regStart + 1
	        regEnd = regEnd - 1
	        regex = input:sub(regStart, regEnd)
	        input = input:sub(regEnd+1)
					-- find repl
	        local repl = input:match("[/%?][^/%?]*[/%?]")
	        local replStart, replEnd = input:find(repl)
	        replStart = replStart + 1
	        replEnd = replEnd - 1
	        if repl:len() > 2 then
	          repl = input:sub(replStart, replEnd)
	        else
	          repl = ""
	        end
	        input = input:sub(replEnd+2)

	        -- determine number of repetitions
					local count = findCount(input)

	        -- strip count from command list
	        local cleanInput = input:gsub("[%dg]", "")
					if cleanInput:len() > 0 then
						comList = cleanInput
					end
					-- save regex and repl for later
					tEnv.lastS.regex = regex
					tEnv.lastS.repl = repl
	        -- replacing
					doRepl(regex, repl, count)
	        -- loop over command list
					doSuffices(comList, regex)

    		end
				-- repeat last replacement
				else
					local count = findCount(input)
					local cleanInput = input:gsub("[%dg]", "")
					if cleanInput:len() > 0 then
						comList = cleanInput:sub(2)
					end
					if tEnv.lastS.regex == nil or tEnv.lastS.repl == nil then
						ed_error("No previous substitution")
						return
					end
					doRepl(tEnv.lastS.regex, tEnv.lastS.repl, count)
					doSuffices(comList, tEnv.lastS.regex)
				end
		else
			if normCmds[input] == nil then
				ed_error("Unknown command")
			else
				normCmds[input](addr1, addr2)
			end
		end
		if addr2 ~= nil then
			tEnv["y"] = addr2
		end
  -- update last_cmd
  tEnv["last_cmd"] = input

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
