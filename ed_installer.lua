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
print("Do you want to install the help file for cc_ed?")
print("(y/N) ")
local ans = read()
if ans:upper() == "Y" then
	if not fs.exists("/.help") then
		fs.makeDir("/.help")
	end
	shell.run("wget https://raw.githubusercontent.com/raninninn/cc_ed/main/help.txt /.help/ed.txt")
	help.setPath(help.path() .. "/.help")
	local file = fs.open("startup", "a")
	file.write("help.setPath(help.path()..':/help')")
	file.flush()
	file.close()
end
print("Installation completed.")
