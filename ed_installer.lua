local w,h = term.getSize()
print("This installer will download cc_ed from the project's GitHub page (github.com/raninninn/cc_ed)")
print("Continue? (y/N) ")
local ans = read()
if ans:upper() == "Y" then
	print("Downloading ed")
	shell.run("wget https://raw.githubusercontent.com/raninninn/cc_ed/main/ed.lua /edTMP.lua")
	if fs.exists("/ed.lua") then
		fs.delete("/ed.lua")
	end
	fs.move("/edTMP.lua", "/ed.lua")
else
	print("Abort")
	exit()
end
print("Do you want to install file completion for cc_ed?")
print("(y/N) ")
local ans = read()
if ans:upper() == "Y" then
	local sCmpl = "local completion = require('cc.shell.completion')\nlocal complete = completion.build( {completion.file, many = true} )\nshell.setCompletionFunction('ed.lua', complete)"
	local completion = require('cc.shell.completion')
	local complete = completion.build( {completion.file, many = true} )
	shell.setCompletionFunction( 'ed.lua', complete)
	if not fs.exists("/startup") then
		fs.open("/startup", "w")
	end

	local file = fs.open("/startup", "r")
	if not file.readAll():gsub( "%s", "" ):match( sCmpl:gsub("%s", "") ) then
		local file = fs.open("/startup", "a")
		file.write(sCmpl)
		file.flush()
		file.close()
	end
end
print("Do you want to install the help file for cc_ed?")
print("(y/N) ")
local ans = read()
if ans:upper() == "Y" then
	if not fs.exists("/.help") then
		fs.makeDir("/.help")
	end
	shell.run("wget https://raw.githubusercontent.com/raninninn/cc_ed/main/help.txt /.help/edTMP.txt")
	fs.delete("/.help/ed.txt")
	fs.move("/.help/edTMP.txt", "/.help/ed.txt")
	if not help.path():match(":/.help") then
		help.setPath(help.path() .. ":/.help")
	end
	local file = fs.open("startup", "r")
	if not file.readAll():match("help.setPath(help.path()..'/.help'") then
		local file = fs.open("startup", "a")
		file.write("help.setPath(help.path()..':/.help')")
		file.flush()
		file.close()
	end
end
print("Installation completed.")
