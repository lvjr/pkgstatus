
------------------------------------------------------------
--> \section{Some variables and functions}
------------------------------------------------------------

local gmatch = string.gmatch
local match  = string.match
local find   = string.find
local gsub   = string.gsub

local lookup = kpse.lookup
kpse.set_program_name("kpsewhich")

local showdbg = true

local function dbgPrint(msg)
  if showdbg then print("[debug] " .. msg) end
end

local function valueExists(tab, val)
  for _, v in ipairs(tab) do
    if v == val then return true end
  end
  return false
end

local function fileRead(input)
  local f = io.open(input, "rb")
  local text
  if f then -- file exists and is readable
    text = f:read("*all")
    f:close()
    --print(#text)
    return text
  end
  -- return nil if file doesn't exists or isn't readable
end

local function fileWrite(text, output)
  -- using "wb" keeps unix eol characters
  f = io.open(output, "wb")
  f:write(text)
  f:close()
end

local function testDistribution()
  -- texlive returns "texmf-dist/web2c/updmap.cfg"
  -- miktex returns nil although there is "texmfs/install/miktex/config/updmap.cfg"
  local d = lookup("updmap.cfg")
  if d then
    return "texlive"
  else
    return "miktex"
  end
end

------------------------------------------------------------
--> \section{Including/excluding lists and package rules}
------------------------------------------------------------

local exclistobj, inclistobj = {}, {}
local clsruleobj, styruleobj = {}, {}

local function readRules()
  exclistobj = require('pkgstatus-list-exc')
  inclistobj = require('pkgstatus-list-inc')
  clsruleobj = require('pkgstatus-rule-cls')
  styruleobj = require('pkgstatus-rule-sty')
end

function applyLists(name, base, ext)
  local todo = true
  local baseext = base .. '.' .. ext
  local inclist = inclistobj[name]
  local exclist = exclistobj[name]
  if inclist then
    if valueExists(inclist, baseext) then
      dbgPrint('include ' .. name .. ' file ' .. baseext)
    else
      dbgPrint('exclude ' .. name .. ' file ' .. baseext)
      todo = false
    end
  elseif exclist then
    if valueExists(exclist, baseext) then
      dbgPrint('exclude ' .. name .. ' file ' .. baseext)
      todo = false
    else
      dbgPrint('include ' .. name .. ' file ' .. baseext)
    end
  elseif find(base, '^' .. name .. '.+') then
    -- ignore subpackages
    dbgPrint('exclude ' .. name .. ' subfile ' .. baseext)
    todo = false
  end
  return todo
end

local function applyRules(fileinfo)
  local rules --= _ENV[fileinfo.ext .. 'ruleobj']
  if fileinfo.ext == 'sty' then
    rules = styruleobj
  else
    rules = clsruleobj
  end
  --print(#list)
  for _, rule in ipairs(rules) do
    if find(fileinfo.base, rule[1]) then
      for k, v in pairs(rule[2]) do
        fileinfo[k] = v
        dbgPrint('update ' .. k .. ' = ' .. fileinfo[k])
      end
    end
  end
  return fileinfo
end

------------------------------------------------------------
--> \section{Failed and Passed Lists}
------------------------------------------------------------

local ignoreobj = {}
local failpkgs = ''

local ignorenum, failnum, passnum = 0, 0, 0

local function readIgnoreList()
  local fname = 'ignorelist.txt'
  dbgPrint('reading results from ' .. fname)
  local ignoretext = fileRead(fname)
  if ignoretext == nil then
    dbgPrint('file ' .. fname .. ' not exist')
    return
  end
  for ignorename in gmatch(ignoretext, '([^\r\n]+)') do
    --print(ignorename)
    ignorenum = ignorenum + 1
    ignoreobj[ignorename] = true
  end
  --print(ignorenum)
end

local function isIgnored(extbase)
  return ignoreobj[extbase]
end

local function countPassPkg()
  passnum = passnum + 1
end

local function recordFailPkg(extbase)
  failpkgs = failpkgs .. extbase .. '\n'
  failnum = failnum + 1
end

local function printTotalNumbers()
  print('number of ignored packages = ' .. ignorenum)
  print('number of passed packages = ' .. passnum)
  print('number of failed packages = ' .. failnum)
  return failnum
end

local function saveFailList()
  local fname = 'faillist.txt'
  if failpkgs ~= '' then
    print('saving names of failed packages to ' .. fname)
    fileWrite(failpkgs, fname)
  else
    print('all packages pass the tests')
  end
end

------------------------------------------------------------
--> \section{Compile Packages}
------------------------------------------------------------

local function compile(fileinfo)
  local base, ext, program = fileinfo.base, fileinfo.ext, fileinfo.program
  local clsname, preamble= fileinfo.clsname, fileinfo.preamble
  local baseext, extbase = base .. '.' .. ext, ext .. '-' .. base
  dbgPrint(program .. ' ' .. baseext)
  local class = '\\documentclass{' .. clsname .. '}'
  local body = '\\begin{document}TEST\\end{document}'
  local docstr = class .. preamble .. body
  local option = '--interaction=nonstopmode --output-directory=temp --jobname=' .. extbase
  local cmdstr = program .. ' ' .. option .. ' "' .. docstr .. '" 1>stdout.log 2>stderr.log'
  local result = os.execute(cmdstr)
  -- When there is an error, the return value of os.execute is 1 on Windows and 256 on Linux
  if result > 0 then
    print('------> failed ' .. baseext)
    recordFailPkg(extbase)
    local logfile = extbase .. '.log'
    if os.type == "windows" then
      os.execute('move /y temp\\' .. logfile .. ' output\\' .. logfile .. ' 1>NUL')
    else
      os.execute('mv -f temp/' .. logfile .. ' output/' .. logfile)
    end
  else
    countPassPkg()
  end
end

local function doCompilation(name, program, base, ext)
  if isIgnored(ext .. '-' .. base) then
    dbgPrint('ignore ' .. base .. '.' .. ext)
    return
  end
  if program == 'latex' or program == 'generic' then
    program = 'pdflatex'
  elseif program ~= 'xelatex' and program ~= 'lualatex' then
    -- ignore files for other formats
    dbgPrint('skip ' .. program .. ' file ' .. base .. '.' .. ext)
    return
  end
  local todo = applyLists(name, base, ext)
  if todo then
    local clsname, preamble
    if ext == 'cls' then
      clsname = base
      preamble = ''
    else -- 'sty'
      clsname = 'article'
      preamble = '\\usepackage{' .. base .. '}'
    end
    local fileinfo = {
      base = base, ext = ext, program = program,
      clsname = clsname, preamble = preamble
    }
    fileinfo = applyRules(fileinfo)
    compile(fileinfo)
  end
end

local function parseDescription(name, desc)
  --local matchstr = 'tex/(%l-latex)/[%a%d%-%./]-/([%a%d%-%.]+)%.([%a]+)\r?\n'
  local matchstr = 'tex/(%l-)/[%a%d%-%./]-/([%a%d%-%.]+)%.([%a]+)\r?\n'
  for program, base, ext in gmatch(desc, matchstr) do
    --print(program, base, ext)
    if ext == "sty" or ext == "cls" then
      --print(name, base .. "." .. ext)
      doCompilation(name, program, base, ext)
    end
  end
end

------------------------------------------------------------
--> \section{Handle TeX Live package database}
------------------------------------------------------------

local tlinspkgtext

local function tlReadPackageDB()
  local tlroot = kpse.var_value("TEXMFROOT")
  if tlroot then
    tlroot = tlroot .. "/tlpkg"
  else
    print("error in finding texmf root!")
  end
  -- this file lists all installed packages
  tlinspkgtext = fileRead(tlroot .. "/texlive.tlpdb")
  if not tlinspkgtext then
    print("error in reading texlive.tlpdb file!")
  end
end

local function tlExtractFiles(name, desc)
  -- ignore binary packages
  -- also ignore latex-dev packages
  if find(name, "%.") or find(name, "^latex%-[%a]-%-dev") then
    --print(name)
    return
  end
  -- ignore package files in doc folder
  if match(desc, "\nrunfiles .+") then
    parseDescription(name, desc)
  end
end

local function tlParsePackageDB()
  -- texlive.tlpdb might use different eol characters
  gsub(tlinspkgtext, "name (.-)\r?\n(.-)\r?\n\r?\n", tlExtractFiles)
end

------------------------------------------------------------
--> \section{Handle MiKTeX package database}
------------------------------------------------------------

local mtpkgtext

local function mtReadPackageDB()
  local mtvar = kpse.var_value("TEXMFDIST")
  if mtvar then
    -- this file lists all available packages
    mtpkgtext = fileRead(mtvar .. "/miktex/config/package-manifests.ini")
    if not mtpkgtext then
      print("error in reading packages.ini file!")
    end
  else
    print("error in finding texmf root!")
  end
end

local function mtExtractFiles(name, desc)
  -- ignore package files in source or doc folders
  -- also ignore latex-dev packages
  if find(name, "_") or find(name, "^latex%-[%a]-%-dev") then
    --print(name)
    return
  end
  parseDescription(name, desc)
end

local function mtParsePackageDB()
  -- package-manifests.ini might use different eol characters
  gsub(mtpkgtext, "%[(.-)%]\r?\n(.-)\r?\n\r?\n", mtExtractFiles)
end

------------------------------------------------------------
--> \section{Main function}
------------------------------------------------------------

local dist -- name of current tex distribution

local function main()
  if os.type == "windows" then
    os.execute('rmdir /s /q output')
    os.execute('rmdir /s /q temp')
  else
    os.execute('rm -rf output')
    os.execute('rm -rf temp')
  end
  os.execute('mkdir output')
  os.execute('mkdir temp')
  readIgnoreList()
  readRules()
  dist = testDistribution()
  dbgPrint("you are using " .. dist)
  if dist == "texlive" then
    tlReadPackageDB()
    tlParsePackageDB()
  else
    mtReadPackageDB()
    mtParsePackageDB()
  end
  saveFailList()
  return printTotalNumbers()
end

local errorlevel = main()
os.exit(errorlevel)
