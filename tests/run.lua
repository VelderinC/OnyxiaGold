-- Pure Lua runner. Lua 5.1 or later. No WoW client.
if not table.getn then
  function table.getn(t)
    return #t
  end
end

OnyxiaGold = {}

local root = arg and arg[0] or "tests/run.lua"
root = string.gsub(root, "tests/run%.lua$", "")
root = string.gsub(root, "tests\\run%.lua$", "")
if root ~= "" and string.sub(root, -1) ~= "/" and string.sub(root, -1) ~= "\\" then
  root = root .. "/"
end

local function load(path)
  local chunk, err = loadfile(root .. path)
  if not chunk then
    io.stderr:write(tostring(err) .. "\n")
    os.exit(1)
  end
  chunk()
end

load("Lots.lua")
load("Data/ItemGroups.lua")
load("Data/Recipes.lua")
load("SessionState.lua")
load("RecipeBook.lua")
load("Tests.lua")

local text, ok = OnyxiaGold.Tests:Run()
io.write(text)
io.write("\n")
if ok then
  os.exit(0)
end
os.exit(1)
