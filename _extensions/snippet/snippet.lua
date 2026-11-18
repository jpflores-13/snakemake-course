--[[
snippet: show real pipeline code in a page, pulled from the file itself.

  {{< snippet repo="microcpipe" file="workflows/MicroCPipe.snakefile" rule="dedup" >}}
  {{< snippet repo="ttpipe" file="workflows/rules/processing.smk" rule="star_align" >}}
  {{< snippet repo="regpipe" file="workflows/rules/common.smk" def="get_control" >}}
  {{< snippet repo="chromsimpipe" file="workflows/ChromSimPipe.snakefile" checkpoint="name" >}}
  {{< snippet repo="stopB" file="Snakefile" lines="10-40" >}}

Arguments
  repo      microcpipe | ttpipe | chromsimpipe  (git submodules under pipelines/)
            regpipe (course-pipeline/) | stopA | stopB | stopC | stopD (stopping-points/stopX/)
  file      path inside that repo
  rule      a rule (or checkpoint / def) name: from `rule NAME:` to the end of its block
  def       a Python function name
  checkpoint a checkpoint name
  lines     "10-40", "10-" or "10" instead of a name
  lang      override the code language (default: from the file extension)
  comments  "false" to leave out the comment lines directly above a rule
  filename  override the label shown above the block (default: the repo path)

Missing repos, files or rules render a visible warning box (and a render
warning) instead of stopping the render.
]]

local REPOS = {
  microcpipe   = { dir = "pipelines/microcpipe",   github = "MicroCPipe" },
  ttpipe       = { dir = "pipelines/ttpipe",       github = "TTpipe" },
  chromsimpipe = { dir = "pipelines/chromsimpipe", github = "ChromSimPipe" },
  regpipe      = { dir = "course-pipeline",          course = true },
  stopA        = { dir = "stopping-points/stopA",    course = true },
  stopB        = { dir = "stopping-points/stopB",    course = true },
  stopC        = { dir = "stopping-points/stopC",    course = true },
  stopD        = { dir = "stopping-points/stopD",    course = true },
}
local GITHUB_USER = "jpflores-13"
local COURSE_REPO = "https://github.com/jpflores-13/snakemake-course/blob/main/"

local sha_cache = {}

-- Quarto adds the filename bar while parsing the document, before shortcodes
-- run, so build the same markup it uses (DecoratedCodeBlock html renderer).
local function with_filename(code, filename)
  if not filename or not quarto.doc.is_format("html") then return code end
  local bar = pandoc.Div({ pandoc.Plain({
    pandoc.RawInline("html", "<pre>"),
    pandoc.Strong({ pandoc.Str(filename) }),
    pandoc.RawInline("html", "</pre>"),
  }) }, pandoc.Attr("", { "code-with-filename-file" }))
  return pandoc.Div({ bar, code }, pandoc.Attr("", { "code-with-filename" }))
end

local function str(v)
  if v == nil then return nil end
  local s = pandoc.utils.stringify(v)
  if s == "" then return nil end
  return s
end

local function project_dir()
  if quarto.project and quarto.project.directory then
    return quarto.project.directory
  end
  return pandoc.system.get_working_directory()
end

local function warn_block(msg)
  quarto.log.warning("snippet: " .. msg)
  return quarto.Callout({
    type = "warning",
    title = "Snippet not found",
    content = { pandoc.Para({ pandoc.Str(msg) }) },
    appearance = "simple",
  })
end

local function read_lines(path)
  local fh = io.open(path, "r")
  if not fh then return nil end
  local lines = {}
  for line in fh:lines() do
    lines[#lines + 1] = (line:gsub("\r$", ""))
  end
  fh:close()
  return lines
end

local function pinned_sha(dir)
  if sha_cache[dir] ~= nil then return sha_cache[dir] end
  local sha = false
  local p = io.popen('git -C "' .. dir .. '" rev-parse HEAD 2>/dev/null')
  if p then
    local out = p:read("*l")
    p:close()
    if out and out:match("^%x+$") and #out == 40 then sha = out end
  end
  sha_cache[dir] = sha
  return sha
end

local function lang_for(file)
  local base = file:match("([^/]+)$") or file
  local ext = base:match("%.([^.]+)$")
  ext = ext and ext:lower() or ""
  if base == "Snakefile" or ext == "snakefile" or ext == "smk" or ext == "py" then return "python" end
  if ext == "yml" or ext == "yaml" then return "yaml" end
  if ext == "sh" or ext == "bash" then return "bash" end
  if ext == "r" then return "r" end
  if ext == "json" then return "json" end
  if ext == "toml" then return "toml" end
  if ext == "tsv" or ext == "txt" or ext == "csv" then return "default" end
  return "default"
end

local function indent_of(line)
  local ws = line:match("^(%s*)")
  return #(ws:gsub("\t", "    "))
end

local function is_blank(line) return line:match("^%s*$") ~= nil end

-- count triple quotes on a line (very small tokenizer: enough for shell: blocks)
local function count_triples(line)
  local n = 0
  for _ in line:gmatch('"""') do n = n + 1 end
  for _ in line:gmatch("'''") do n = n + 1 end
  return n
end

local function escape_pattern(s)
  return (s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

-- Find `rule NAME:`, `checkpoint NAME:` or `def NAME(`; return start, stop (1-based, inclusive).
local function find_block(lines, name, kinds, with_comments)
  local esc = escape_pattern(name)
  local start
  for _, kind in ipairs(kinds) do
    for i, line in ipairs(lines) do
      local pat
      if kind == "def" then
        pat = "^%s*def%s+" .. esc .. "%s*%("
      else
        pat = "^%s*" .. kind .. "%s+" .. esc .. "%s*:"
      end
      if line:match(pat) then start = i; break end
    end
    if start then break end
  end
  if not start then return nil end
  local base = indent_of(lines[start])
  local stop = start
  local in_string = (count_triples(lines[start]) % 2) == 1
  for j = start + 1, #lines do
    local line = lines[j]
    if in_string then
      stop = j
      if count_triples(line) % 2 == 1 then in_string = false end
    elseif is_blank(line) then
      -- blank lines belong to the block only if more body follows
    elseif indent_of(line) <= base then
      break
    else
      stop = j
      if count_triples(line) % 2 == 1 then in_string = true end
    end
  end
  local first = start
  if with_comments then
    local k = start - 1
    while k >= 1 and lines[k]:match("^%s*#") and indent_of(lines[k]) == base do
      first = k
      k = k - 1
    end
  end
  return first, stop
end

local function parse_lines(spec, n)
  local a, b = spec:match("^%s*(%d+)%s*%-%s*(%d*)%s*$")
  if not a then
    a = spec:match("^%s*(%d+)%s*$")
    b = a
  end
  if not a then return nil end
  a = tonumber(a)
  b = (b == nil or b == "") and n or tonumber(b)
  if a < 1 then a = 1 end
  if b > n then b = n end
  if a > b then return nil end
  return a, b
end

local function dedent(chunk)
  local min
  for _, line in ipairs(chunk) do
    if not is_blank(line) then
      local ind = #line:match("^(%s*)")
      if not min or ind < min then min = ind end
    end
  end
  min = min or 0
  local out = {}
  for i, line in ipairs(chunk) do
    out[i] = is_blank(line) and "" or line:sub(min + 1)
  end
  while #out > 0 and out[#out] == "" do table.remove(out) end
  return out
end

local function snippet(args, kwargs, meta)
  local repo = str(kwargs["repo"])
  local file = str(kwargs["file"])
  if not repo or not file then
    return warn_block("snippet needs repo= and file= (got repo=" .. tostring(repo) .. ", file=" .. tostring(file) .. ")")
  end
  local info = REPOS[repo]
  if not info then
    return warn_block("unknown repo '" .. repo .. "' (use microcpipe, ttpipe, chromsimpipe, regpipe, stopA-stopD)")
  end
  local root = project_dir()
  local dir = root .. "/" .. info.dir
  local path = dir .. "/" .. file
  local lines = read_lines(path)
  if not lines then
    return warn_block(info.dir .. "/" .. file .. " does not exist (yet)")
  end

  local first, last
  local name = str(kwargs["rule"]) or str(kwargs["def"]) or str(kwargs["checkpoint"])
  local with_comments = str(kwargs["comments"]) ~= "false"
  if str(kwargs["lines"]) then
    first, last = parse_lines(str(kwargs["lines"]), #lines)
    if not first then
      return warn_block("lines=\"" .. str(kwargs["lines"]) .. "\" is outside " .. file .. " (" .. #lines .. " lines)")
    end
  elseif name then
    local kinds
    if str(kwargs["def"]) then kinds = { "def", "rule", "checkpoint" }
    elseif str(kwargs["checkpoint"]) then kinds = { "checkpoint", "rule", "def" }
    else kinds = { "rule", "checkpoint", "def" } end
    first, last = find_block(lines, name, kinds, with_comments)
    if not first then
      return warn_block("no rule, checkpoint or def named '" .. name .. "' in " .. info.dir .. "/" .. file)
    end
  else
    first, last = 1, #lines
  end

  local chunk = {}
  for i = first, last do chunk[#chunk + 1] = lines[i] end
  chunk = dedent(chunk)
  -- trailing blank lines were trimmed: move `last` to the last line shown
  last = first + #chunk - 1

  local lang = str(kwargs["lang"]) or lang_for(file)
  local label = str(kwargs["filename"]) or file
  local code = with_filename(pandoc.CodeBlock(table.concat(chunk, "\n"), pandoc.Attr("", { lang })), label)

  local url
  if info.github then
    local sha = pinned_sha(dir)
    local ref = sha or "main"
    url = "https://github.com/" .. GITHUB_USER .. "/" .. info.github .. "/blob/" .. ref .. "/" .. file
      .. "#L" .. first .. "-L" .. last
  elseif info.course then
    url = COURSE_REPO .. info.dir .. "/" .. file .. "#L" .. first .. "-L" .. last
  end

  local blocks = { code }
  if url then
    local where = info.github and (info.github .. ", lines " .. first .. "-" .. last)
      or (info.dir .. ", lines " .. first .. "-" .. last)
    local link_text = info.github and "view on GitHub" or "view in the course repository"
    blocks[#blocks + 1] = pandoc.Div(
      { pandoc.Plain({
          pandoc.Span({ pandoc.Str(where) }, pandoc.Attr("", { "snippet-where" })),
          pandoc.Space(),
          pandoc.Link({ pandoc.Str(link_text) }, url, "", pandoc.Attr("", { "snippet-link" })),
        }) },
      pandoc.Attr("", { "snippet-source" }))
  end
  return pandoc.Div(blocks, pandoc.Attr("", { "snippet" }, { { "data-repo", repo } }))
end

return {
  ["snippet"] = snippet,
}
